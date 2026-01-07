####################################################################################################################################################
############################################################### QUERIES ##########################################################################
####################################################################################################################################################

type
  QueryOp = enum
    qInclude, qExclude
  
  QueryComponent = object
    id: int
    op: QueryOp
  
  QuerySignature = object
    components: seq[QueryComponent]
    includeMask: ArchetypeMask
    excludeMask: ArchetypeMask

####################################################################################################################################################
################################################################### MASK ITERATOR ##################################################################
####################################################################################################################################################

iterator maskIter(it: uint): int =
  var m = it
  while m != 0:
    yield countTrailingZeroBits(m)
    m = m and (m-1)

####################################################################################################################################################
################################################################### QUERY BUILDER ##################################################################
####################################################################################################################################################

proc buildQuerySignature(world: ECSWorld, components: seq[QueryComponent]): QuerySignature =
  result.components = components
  
  for comp in components:
    let layer = comp.id div (sizeof(uint) * 8)
    let bitPos = comp.id mod (sizeof(uint) * 8)
    
    if layer < MAX_COMPONENT_LAYER:
      if comp.op == qInclude:
        result.includeMask[layer] = result.includeMask[layer] or (1.uint shl bitPos)
      else:
        result.excludeMask[layer] = result.excludeMask[layer] or (1.uint shl bitPos)

proc matchesArchetype(sig: QuerySignature, arch: ArchetypeMask): bool =
  for i in 0..<MAX_COMPONENT_LAYER:
    # Check if all included components are present
    if (sig.includeMask[i] and arch[i]) != sig.includeMask[i]:
      return false
    
    # Check if no excluded components are present
    if (sig.excludeMask[i] and arch[i]) != 0:
      return false
  
  return true

####################################################################################################################################################
################################################################### DENSE QUERIES ##################################################################
####################################################################################################################################################

iterator denseQuery(world: ECSWorld, sig: QuerySignature): (int, HSlice[int, int]) =
  ## Iterate through all partitions that match the query signature
  ## Returns block index and range for each matching zone
  
  for arch, partition in world.archetypes.pairs:
    if not matchesArchetype(sig, arch):
      continue
    
    # Iterate through filled zones in this partition
    for zoneIdx in 0..partition.fill_index:
      if zoneIdx >= partition.zones.len:
        break
      
      let zone = partition.zones[zoneIdx]
      if not isEmpty(zone):
        yield (zone.block_idx, zone.r.s..<zone.r.e)

proc denseQueryCount(world: ECSWorld, sig: QuerySignature): int =
  ## Count total entities matching the dense query
  result = 0
  
  for arch, partition in world.archetypes.pairs:
    if not matchesArchetype(sig, arch):
      continue
    
    for zoneIdx in 0..partition.fill_index:
      if zoneIdx >= partition.zones.len:
        break
      
      let zone = partition.zones[zoneIdx]
      if not isEmpty(zone):
        result += zone.r.e - zone.r.s

####################################################################################################################################################
################################################################### SPARSE QUERIES #################################################################
####################################################################################################################################################

proc getSparseMasks(world: ECSWorld, componentIds: seq[int]): seq[seq[uint]] =
  ## Get sparse masks for each component
  result = newSeq[seq[uint]](componentIds.len)
  
  for i, compId in componentIds:
    let entry = world.registry.entries[compId]
    result[i] = entry.getSparseMaskOp(entry.rawPointer)

proc andMasks(masks: seq[seq[uint]]): seq[uint] =
  ## Perform AND operation on all sparse masks
  if masks.len == 0:
    return @[]
  
  result = masks[0]
  
  for i in 1..<masks.len:
    let minLen = min(result.len, masks[i].len)
    result.setLen(minLen)
    
    for j in 0..<minLen:
      result[j] = result[j] and masks[i][j]

proc filterExcludedMasks(baseMask: var seq[uint], excludeMasks: seq[seq[uint]]) =
  ## Remove excluded components from base mask
  for excludeSeq in excludeMasks:
    let minLen = min(baseMask.len, excludeSeq.len)
    
    for i in 0..<minLen:
      baseMask[i] = baseMask[i] and not excludeSeq[i]

iterator sparseQuery(world: ECSWorld, sig: QuerySignature): (int, uint) =
  ## Iterate through sparse entities matching the query
  ## Returns chunk index and mask iterator for each matching chunk
  
  var includeIds: seq[int]
  var excludeIds: seq[int]
  
  for comp in sig.components:
    if comp.op == qInclude:
      includeIds.add(comp.id)
    else:
      excludeIds.add(comp.id)
  
  if includeIds.len > 0:
  
    # Get sparse masks for included components
    let includeMasks = getSparseMasks(world, includeIds)
  
    # AND all included masks
    var resultMask = andMasks(includeMasks)
  
    # Filter out excluded components
    if excludeIds.len > 0:
      let excludeMasks = getSparseMasks(world, excludeIds)
      filterExcludedMasks(resultMask, excludeMasks)
  
    # Iterate through chunks with entities
    for i in 0..<resultMask.len:
      var m = resultMask[i]
      
      while m != 0:
        let chunkIdx = countTrailingZeroBits(m)
        var chunkMask = (1'u shl (sizeof(uint)*8)-1) - 1'u
        m = m and (m-1)

        for compId in includeIds:
          let entry = world.registry.entries[compId]
          let entityMask = entry.getSparseChunkMaskOp(entry.rawPointer, chunkIdx)
          chunkMask = chunkMask and entityMask

        yield (chunkIdx, chunkMask)

proc sparseQueryCount(world: ECSWorld, sig: QuerySignature): int =
  ## Count total entities matching the sparse query
  result = 0
  
  for _,mask in sparseQuery(world, sig):
    for _ in mask.maskIter:
      result += 1

####################################################################################################################################################
################################################################### QUERY SYNTAX ###################################################################
####################################################################################################################################################

# Helper procs for building queries
proc includeComp*(componentId: int): QueryComponent =
  QueryComponent(id: componentId, op: qInclude)

proc excludeComp*(componentId: int): QueryComponent =
  QueryComponent(id: componentId, op: qExclude)

# Macro for query syntax: query(world, Pos and Vel and not Acc)
macro query*(world: untyped, expr: untyped): untyped =
  var components = newSeq[NimNode]()
  
  proc processExpr(world,node: NimNode) =
    case node.kind:
      of nnkInfix:
        if node[0].strVal == "and":
          processExpr(world,node[1])
          processExpr(world,node[2])
        else:
          error("Unsupported operator in query: " & node[0].strVal)
      
      of nnkPrefix:
        if node[0].strVal == "not":
          let compNode = node[1]
          components.add(quote("@") do:
            excludeComp(getComponentId(`@world`, `@compNode`))
          )
        else:
          error("Unsupported prefix operator in query: " & node[0].strVal)
      
      of nnkIdent, nnkSym:
        components.add(quote("@") do:
          includeComp(getComponentId(`@world`, `@node`))
        )
      
      else:
        error("Unsupported node kind in query: " & $node.kind)
  
  processExpr(world,expr)
  
  let componentsSeq = newNimNode(nnkBracket)
  for comp in components:
    componentsSeq.add(comp)
  
  result = quote do:
    buildQuerySignature(`world`, @`componentsSeq`)