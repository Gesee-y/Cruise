####################################################################################################################################################
############################################################### QUERIES ##########################################################################
####################################################################################################################################################

## Defines the operation type for a query component filter.
type
  QueryOp = enum
    qInclude     ## Specifies that the component must be present in the archetype.
    qExclude     ## Specifies that the component must be absent from the archetype.
    qModified    ## Specifies that the component must be present and modified (State tracking).
    qNotModified ## Specifies that the component must be present and NOT modified (State tracking).

  ## Represents a single component constraint within a query.
  ## It binds a Component ID to an operation (Include, Exclude, Modified, etc.).
  QueryComponent = object
    id: int   ## The ID of the component to filter by.
    op: QueryOp ## The operation.
  
  ## Represent an independent filter that can be used narrow queries
  QueryFilter* = object

    # Dense Query
    dLayer:HibitsetType

    # Sparse Query
    sLayer:HibitsetType

  ## The compiled representation of a query.
  ## It translates a list of component constraints into efficient bitmasks
  ## that can be rapidly compared against archetype masks.
  QuerySignature* = object
    components: seq[QueryComponent] ## The raw list of components in the query (stores Modified info here).
    includeMask: ArchetypeMask      ## Bitmask representing all required components (OR'ed together).
    excludeMask: ArchetypeMask      ## Bitmask representing all forbidden components (OR'ed together).
    modified: seq[int]
    notModified: seq[int]
    filters:seq[QueryFilter]

  ## A cached result object for Dense queries.
  ## Stores the partitions (memory blocks) that matched the query signature,
  ## allowing for efficient re-iteration without re-checking archetype masks.
  DenseQueryResult* = object
    part*: seq[TablePartition] ## Sequence of matching table partitions.

  ## Iterator for dense queries.
  DenseIterator* = object
    r:HSlice[int, int]
    m:ptr seq[uint]
    masked:bool

  ## A cached result object for Sparse queries.
  ## Stores the calculated bitmasks representing the matching entities.
  sparseQueryResult* = object
    rmask*: seq[uint]  ## High-level mask indicating which chunks contain at least one matching entity.
    chunks*: seq[uint] ## Low-level masks for each chunk, indicating specific entities within that chunk.

  ## Iterator obtained from sparse queries.
  SparseIterator* = object
    m:uint

####################################################################################################################################################
################################################################### MASK ITERATOR ##################################################################
####################################################################################################################################################

proc `and`*(a, b: QueryFilter): QueryFilter =
  result.dLayer = a.dLayer and b.dLayer
  result.sLayer = a.sLayer and b.sLayer

proc `or`*(a, b: QueryFilter): QueryFilter =
  result.dLayer = a.dLayer or b.dLayer
  result.sLayer = a.sLayer or b.sLayer

proc `xor`*(a, b: QueryFilter): QueryFilter =
  result.dLayer = a.dLayer xor b.dLayer
  result.sLayer = a.sLayer xor b.sLayer

proc `not`*(a: QueryFilter): QueryFilter =
  result.dLayer = not a.dLayer 
  result.sLayer = not a.sLayer

proc dGet*(qf: QueryFilter, id: uint): bool =
  ## Returns 1 if the ID is present in the dense filter, 0 otherwise
  qf.dLayer.get(id.int)

proc dSet*(qf: var QueryFilter, id: uint) =
  ## Sets an ID in the dense filter
  qf.dLayer.set(id.int)

proc dUnset*(qf: var QueryFilter, id: uint) =
  ## Unsets an ID from the dense filter
  qf.dLayer.unset(id.int)

proc sGet*(qf: QueryFilter, id: int | uint): bool =
  ## Sparse membership check
  qf.sLayer.get(id.int)

proc sSet*(qf: var QueryFilter, id: int | uint) =
  ## Insert into sparse filter
  qf.sLayer.set(id.int)

proc sUnset*(qf: var QueryFilter, id: int | uint) =
  ## Remove from sparse filter
  qf.sLayer.unset(id.int)

iterator maskIter(it: uint): int =
  ## Low-level iterator to traverse set bits in an unsigned integer bitmask.
  ##
  ## This uses the "Brian Kernighan's algorithm" approach (`m & (m-1)`), which efficiently
  ## jumps to the next set bit.
  ##
  ## @param it: The bitmask (uint) to iterate over.
  ## @return: The index (int) of each set bit found.

  var m = it
  while m != 0:
    yield countTrailingZeroBits(m)
    m = m and (m-1)
iterator maskIter(it: (HSlice[int,int],seq[uint])): int =
  var current = 0
  var i = 0
  let S = sizeof(uint)*8

  while i < it[1].len and current <= it[0].b:
    var m = it[1][i]
    
    while m != 0:
      current = i*S + countTrailingZeroBits(m)
      m = m and (m-1)
      if current > it[0].b: break
      yield current

    i += 1

proc count*(it:DenseIterator|SparseIterator):int =
  var res = 0
  for i in it:
    res += 1

  return res

iterator items*(it: DenseIterator): int =
  ## Iterate a `DenseIterator` obtained from a query
  ## 
  ## It return the index of the matching entity in a given block.

  if it.masked:
    for i in (it.r, it.m[]).maskIter:
      yield i
  else:
    for i in it.r:
      yield i

iterator items*(it: SparseIterator): int =
  ## Iterate a `SparseIterator` obtained from a sparse query.
  ## 
  ## It return the index of the matching entities in a given block.

  for i in it.m.maskIter:
    yield i

####################################################################################################################################################
################################################################### QUERY BUILDER ##################################################################
####################################################################################################################################################

proc buildQuerySignature(world: ECSWorld, components: seq[QueryComponent]): QuerySignature =
  ## Constructs a `QuerySignature` from a list of component constraints.
  ##
  ## This function calculates the aggregate `includeMask` and `excludeMask` from the
  ## individual `QueryComponent` objects.
  ## Note: Processing logic for qModified/qNotModified is not implemented here per request,
  ## only the ID is cached in the components sequence.
  ##
  ## @param world: The `ECSWorld` (used for context or future expansion).
  ## @param components: A sequence of `QueryComponent` objects defining the filter.
  ## @return: A fully constructed `QuerySignature`.

  result.components = components
  
  for comp in components:
    # Calculate which layer (word) in the mask array and which bit within that word.
    let layer = comp.id div (sizeof(uint) * 8)
    let bitPos = comp.id mod (sizeof(uint) * 8)
    
    if layer < MAX_COMPONENT_LAYER:
      case comp.op
      of qInclude:
        # Set the bit in the include mask.
        result.includeMask[layer] = result.includeMask[layer] or (1.uint shl bitPos)
      of qExclude:
        # Set the bit in the exclude mask.
        result.excludeMask[layer] = result.excludeMask[layer] or (1.uint shl bitPos)
      of qModified, qNotModified:
        if comp.op == qModified:
          result.modified.add(comp.id)
        else:
          result.notModified.add(comp.id)
        # For archetype matching, a Modified component implies the component must exist (Include).
        # However, we only cache the info here as requested.
        # If you need the entity to exist to be checked for modification:
        result.includeMask[layer] = result.includeMask[layer] or (1.uint shl bitPos)

proc addFilter(qs: var QuerySignature, qf:QueryFilter) =
  ## Adds a new filter to the query
  qs.filters.add(qf)

proc matchesArchetype(sig: QuerySignature, arch: ArchetypeMask): bool =
  ## Checks if an Archetype's mask matches a given Query Signature.
  ##
  ## @param sig: The `QuerySignature` to test against.
  ## @param arch: The `ArchetypeMask` of the archetype being tested.
  ## @return: True if the archetype matches the query, False otherwise.

  # Check if all included components are present.
  # (A & B) == B ensures B is a subset of A.
  if (sig.includeMask and arch) != sig.includeMask:
    return false

  # Check if any excluded components are present.
  # (A & ~B) == A ensures A and B do not overlap.
  if (arch and not sig.excludeMask) != arch:
    return false
  
  return true

####################################################################################################################################################
################################################################### DENSE QUERIES ##################################################################
####################################################################################################################################################

iterator denseQuery*(world: ECSWorld, sig: QuerySignature): (int, DenseIterator) =
  ## Iterate through all partitions that match the query signature
  ## Returns block index and range for each matching zone
  
  for archNode in world.archGraph.nodes:
    let arch = archNode.mask
    # Skip archetypes that don't match the query.
    if not matchesArchetype(sig, arch):
      continue
    
    if not archNode.partition.isNil:
      let mlen = sig.modified.len
      let nmlen = sig.notModified.len
      let maskCount = ((DEFAULT_BLK_SIZE-1) shr 6) + 1
      var modDef = newSeq[uint](maskCount)
      var res = newSeq[uint](maskCount)
      let nmodDef = newSeq[uint](maskCount)
      
      for i in 0..<maskCount:
        modDef[i] = 0'u-1
        res[i] = 0'u-1

      for zone in archNode.partition.zones:
        var masked = false
        for i in 0..<max(mlen, nmlen):
          masked = true
          if i < mlen: 
            let incl = world.registry.entries[sig.modified[i]].getChangeMaskOp(world.registry.entries[sig.modified[i]].rawPointer, zone.block_idx)
            for j in 0..<maskCount:
              res[j] = res[j] and incl[j]

          if i < nmlen: 
            let excl = world.registry.entries[sig.notModified[i]].getChangeMaskOp(world.registry.entries[sig.notModified[i]].rawPointer, zone.block_idx)
            for j in 0..<maskCount:
              res[j] = res[j] and not excl[j]

        for qf in sig.filters:
          masked = true
          if zone.block_idx >= qf.dLayer.maxLen:
            for i in 0..<res.len:
              res[i] = 0'u
          else:
            for i in 0..<res.len:
              res[i] = res[i] and qf.dLayer.getL0(zone.block_idx*sizeof(uint)*8 + i)
        
        yield (zone.block_idx, DenseIterator(r:zone.r.s..<zone.r.e, m:addr res, masked:masked))

proc denseQueryCache*(world: ECSWorld, sig: QuerySignature): DenseQueryResult =
  ## Computes and caches the result of a Dense query.
  ##
  ## Useful if you need to iterate over the results multiple times, as it avoids
  ## re-scanning the archetype graph on subsequent iterations.
  ##
  ## @param world: The `ECSWorld` to query.
  ## @param sig: The `QuerySignature` defining the filter.
  ## @return: A `DenseQueryResult` containing the matching partitions.

  for archNode in world.archGraph.nodes:
    let arch = archNode.mask
    if not matchesArchetype(sig, arch):
      continue
    
    if not archNode.partition.isNil: 
      result.part.add(archNode.partition)

iterator items*(qr:DenseQueryResult):(int, HSlice[int, int]) =
  ## Iterator for the cached `DenseQueryResult`.
  ##
  ## @param qr: The `DenseQueryResult` to iterate over.
  ## @yield: A tuple containing:
  ##         - `int`: The Block Index.
  ##         - `HSlice[int, int]`: The range of entity indices.

  for partition in qr.part:
    for zone in partition.zones:
      yield (zone.block_idx, zone.r.s..<zone.r.e)

proc denseQueryCount*(world: ECSWorld, sig: QuerySignature): int =
  ## Count total entities matching the dense query
  result = 0
  
  for bid, r in world.denseQuery(sig):
    result += r.count

####################################################################################################################################################
################################################################### SPARSE QUERIES #################################################################
####################################################################################################################################################

proc getSparseMasks(world: ECSWorld, componentIds: seq[int]): seq[seq[uint]] =
  ## Get sparse masks for each component
  result = newSeq[seq[uint]](componentIds.len)
  
  for i, compId in componentIds:
    let entry = world.registry.entries[compId]
    #result[i] = entry.getSparseMaskOp(entry.rawPointer)

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

proc getChangeMask(world: ECSWorld, sig:QuerySignature, modif, nmodif:seq[int], blk:int):HibitsetType =
  let mlen = sig.modified.len
  let nmlen = sig.notModified.len
  let maskCount = 1
  var modDef = 0'u - 1
  var res:HibitsetType
  let nmodDef = 0'u

  for i in 0..<max(mlen, nmlen):
    if i < mlen: 
      let modEntry = world.registry.entries[sig.modified[i]]
      let incl = modEntry.getSparseChangeMaskOp(modentry.rawPointer)
      res = res and incl[]
    if i < nmlen: 
      let nmodEntry = world.registry.entries[sig.notModified[i]]
      let excl = nmodEntry.getSparseChangeMaskop(nmodentry.rawPointer)
      res = res and not excl[]

  return res

iterator sparseQuery*(world: ECSWorld, sig: QuerySignature): (int, SparseIterator) =
  ## Iterate through sparse entities matching the query
  ## Returns chunk index and mask iterator for each matching chunk
  
  var includeIds: seq[int]
  var excludeIds: seq[int]
  
  for comp in sig.components:
    case comp.op
    of qInclude, qModified, qNotModified: includeIds.add(comp.id)
    of qExclude: excludeIds.add(comp.id)
    
  if includeIds.len > 0:  
    # Iterate through chunks with entities
    let S = sizeof(uint)*8
    let entry = world.registry.entries[includeIds[0]]
    var res = entry.getSparseMaskOp(entry.rawPointer)[]
        
    for compId in includeIds[1..^1]:
      let entry = world.registry.entries[compId]
      res = res and entry.getSparseMaskOp(entry.rawPointer)[]

    for compId in excludeIds:
      let entry = world.registry.entries[compId]
      res = res and not entry.getSparseMaskOp(entry.rawPointer)[]

    for compId in sig.modified:
      let entry = world.registry.entries[compId]
      res = res and entry.getSparseChangeMaskop(entry.rawPointer)[]

    for compId in sig.notModified:
      let entry = world.registry.entries[compId]
      res = res and not entry.getSparseChangeMaskOp(entry.rawPointer)[]

    for qf in sig.filters:
      res = res and qf.sLayer

    for chunkIdx in res.blkIter:
      yield (chunkIdx, SparseIterator(m:res.getL0(chunkIdx)))

proc sparseQueryCache*(world: ECSWorld, sig: QuerySignature): sparseQueryResult =
  ## Iterate through sparse entities matching the query
  ## Returns chunk index and mask iterator for each matching chunk
  
  var includeIds: seq[int]
  var excludeIds: seq[int]
  
  for comp in sig.components:
    if comp.op == qInclude:
      includeIds.add(comp.id)
    elif comp.op == qExclude:
      excludeIds.add(comp.id)
    # Note: qModified and qNotModified are cached but not processed in this implementation
  
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
    let S = sizeof(uint)*8
    var chk = newSeq[uint]()
    for i in 0..<resultMask.len:
      var m = resultMask[i]
      
      while m != 0:
        let chunkIdx = i*S + countTrailingZeroBits(m)
        var chunkMask = (1'u shl S-1) - 1'u
        m = m and (m-1)

        for compId in includeIds:
          let entry = world.registry.entries[compId]
          let entityMask = entry.getSparseChunkMaskOp(entry.rawPointer, chunkIdx)
          chunkMask = chunkMask and entityMask

        chk.add(chunkMask)

    result.rmask = resultMask
    result.chunks = chk

iterator items*(sr:sparseQueryResult):(int, uint) =
  ## Iterator for the cached `sparseQueryResult`.
  ##
  ## @param sr: The `sparseQueryResult` to iterate over.
  ## @yield: A tuple containing:
  ##         - `int`: The Chunk Index.
  ##         - `uint`: The bitmask of valid entities within the chunk.

  var c = 0
  let S = sizeof(uint)*8
  for i in 0..<sr.rmask.len:
    var m = sr.rmask[i]
      
    while m != 0:
      let chunkIdx = i*S + countTrailingZeroBits(m)
      var chunkMask = sr.chunks[c]
      m = m and (m-1)

      yield (chunkIdx, chunkMask)
      c += 1

proc sparseQueryCount*(world: ECSWorld, sig: QuerySignature): int =
  ## Count total entities matching the sparse query
  result = 0
  
  for _,mask in sparseQuery(world, sig):
    for _ in mask:
      result += 1

####################################################################################################################################################
################################################################### QUERY SYNTAX ###################################################################
####################################################################################################################################################

# Helper procs for building queries

proc includeComp*(componentId: int): QueryComponent =
  ## Creates a `QueryComponent` that requires a specific component.
  QueryComponent(id: componentId, op: qInclude)

proc excludeComp*(componentId: int): QueryComponent =
  ## Creates a `QueryComponent` that forbids a specific component.
  QueryComponent(id: componentId, op: qExclude)

proc modifiedComp*(componentId: int): QueryComponent =
  ## Creates a `QueryComponent` that requires a component to be modified.
  QueryComponent(id: componentId, op: qModified)

proc notModifiedComp*(componentId: int): QueryComponent =
  ## Creates a `QueryComponent` that requires a component to be not modified.
  QueryComponent(id: componentId, op: qNotModified)

macro query*(world: untyped, expr: untyped): untyped =
  ## Macro for Domain Specific Language (DSL) query syntax.
  ##
  ## Allows writing queries using `and`, `not`, and `Modified[]` operators, e.g.:
  ## `query(world, Position and Modified[Velocity] and not Dead)`
  ##
  ## The macro parses the Abstract Syntax Tree (AST) of the expression and converts
  ## the identifiers (types) into their Component IDs using the world's registry.
  ##
  ## @param world: The `ECSWorld` instance.
  ## @param expr: The query expression (e.g., `Pos and Modified[Vel]`).
  ## @return: A `QuerySignature` ready for use in query functions.

  var components = newSeq[NimNode]()
  
  proc processExpr(world: NimNode, node: NimNode) =
    case node.kind
      of nnkInfix:
        if node[0].strVal == "and":
          # Recursively process left and right operands of 'and'
          processExpr(world, node[1])
          processExpr(world, node[2])
        else:
          error("Unsupported operator in query: " & node[0].strVal)
      
      of nnkPrefix:
        if node[0].strVal == "not":
          let operand = node[1]
          
          # Check if the operand is Modified[Type]
          if operand.kind == nnkBracketExpr and operand[0].eqIdent("Modified"):
            # not Modified[Type]
            let compNode = operand[1] # The Type inside []
            components.add(quote("@") do:
              notModifiedComp(getComponentId(`@world`, `@compNode`))
            )
          elif operand.kind in {nnkIdent, nnkSym}:
            # not Type
            components.add(quote("@") do:
              excludeComp(getComponentId(`@world`, `@operand`))
            )
          else:
            error("Unsupported operand for 'not': " & $operand.kind)
        else:
          error("Unsupported prefix operator in query: " & node[0].strVal)
      
      of nnkBracketExpr:
        # Check for Modified[Type]
        if node[0].eqIdent("Modified"):
          let compNode = node[1] # The Type inside []
          components.add(quote("@") do:
            modifiedComp(getComponentId(`@world`, `@compNode`))
          )
        else:
          error("Unsupported bracket syntax in query. Only Modified[Type] is supported.")
      
      of nnkIdent, nnkSym:
        # Process a raw type identifier (Implies 'include')
        components.add(quote("@") do:
          includeComp(getComponentId(`@world`, `@node`))
        )
      
      else:
        error("Unsupported node kind in query: " & $node.kind)
  
  processExpr(world, expr)
  
  # Construct the sequence of QueryComponents
  let componentsSeq = newNimNode(nnkBracket)
  for comp in components:
    componentsSeq.add(comp)
  
  # Return the call to buildQuerySignature
  result = quote do:
    buildQuerySignature(`world`, @`componentsSeq`)

#####################################################################################################################################
####################################################### Query and Entity ############################################################
#####################################################################################################################################

proc get*(qf: QueryFilter, d: DenseHandle): bool =
  ## Dense handle membership check
  qf.dGet(d.obj.id)

proc get*(qf: QueryFilter, s: SparseHandle): bool =
  ## Sparse handle membership check
  qf.sGet(s.id)

proc set*(qf: var QueryFilter, d: DenseHandle) =
  ## Insert dense handle into query filter
  qf.dSet(d.obj.id)

proc set*(qf: var QueryFilter, s: SparseHandle) =
  ## Insert sparse handle into query filter
  qf.sSet(s.id)

proc unset*(qf: var QueryFilter, d: DenseHandle) =
  ## Remove dense handle from query filter
  qf.dUnset(d.obj.id)

proc unset*(qf: var QueryFilter, s: SparseHandle) =
  ## Remove sparse handle from query filter
  qf.sUnset(s.id)
