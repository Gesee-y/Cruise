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

  ## The compiled representation of a query.
  ## It translates a list of component constraints into efficient bitmasks
  ## that can be rapidly compared against archetype masks.
  QuerySignature = object
    components: seq[QueryComponent] ## The raw list of components in the query (stores Modified info here).
    includeMask: ArchetypeMask      ## Bitmask representing all required components (OR'ed together).
    excludeMask: ArchetypeMask      ## Bitmask representing all forbidden components (OR'ed together).
    modified: seq[int]
    notModified: seq[int]

  ## A cached result object for Dense queries.
  ## Stores the partitions (memory blocks) that matched the query signature,
  ## allowing for efficient re-iteration without re-checking archetype masks.
  DenseQueryResult = object
    part: seq[TablePartition] ## Sequence of matching table partitions.

  ## A cached result object for Sparse queries.
  ## Stores the calculated bitmasks representing the matching entities.
  sparseQueryResult = object
    rmask: seq[uint]  ## High-level mask indicating which chunks contain at least one matching entity.
    chunks: seq[uint] ## Low-level masks for each chunk, indicating specific entities within that chunk.

####################################################################################################################################################
################################################################### MASK ITERATOR ##################################################################
####################################################################################################################################################

## Low-level iterator to traverse set bits in an unsigned integer bitmask.
##
## This uses the "Brian Kernighan's algorithm" approach (`m & (m-1)`), which efficiently
## jumps to the next set bit.
##
## @param it: The bitmask (uint) to iterate over.
## @return: The index (int) of each set bit found.
iterator maskIter(it: uint): int =
  var m = it
  while m != 0:
    yield countTrailingZeroBits(m)
    m = m and (m-1)

####################################################################################################################################################
################################################################### QUERY BUILDER ##################################################################
####################################################################################################################################################

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
proc buildQuerySignature(world: ECSWorld, components: seq[QueryComponent]): QuerySignature =
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

## Checks if an Archetype's mask matches a given Query Signature.
##
## @param sig: The `QuerySignature` to test against.
## @param arch: The `ArchetypeMask` of the archetype being tested.
## @return: True if the archetype matches the query, False otherwise.
proc matchesArchetype(sig: QuerySignature, arch: ArchetypeMask): bool =
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

## Iterates over entities matching the query in Dense storage.
##
## This iterator scans the archetype graph. For every matching archetype, it yields
## the memory blocks (zones) containing the entities.
##
## @param world: The `ECSWorld` to query.
## @param sig: The `QuerySignature` defining the filter.
## @yield: A tuple containing:
##         - `int`: The Block Index (identifying the memory chunk).
##         - `HSlice[int, int]`: A slice representing the range of valid entity indices within that block.
iterator denseQuery*(world: ECSWorld, sig: QuerySignature): (int, HSlice[int, int], seq[uint]) =
  ## Iterate through all partitions that match the query signature
  ## Returns block index and range for each matching zone
  
  for archNode in world.archGraph.nodes:
    let arch = archNode.mask
    # Skip archetypes that don't match the query.
    if not matchesArchetype(sig, arch):
      continue
    
    if not archNode.partition.isNil:
      if sig.modified.len == 0 and sig.notModified.len == 0:
        # Iterate through filled zones in this partition.
        for zone in archNode.partition.zones:
          yield (zone.block_idx, zone.r.s..<zone.r.e, @[])
      else:
        let mlen = sig.modified.len
        let nmlen = sig.notModified.len
        let maskCount = ((DEFAULT_BLK_SIZE-1) shr 6) + 1
        let modDef = newSeq[uint](maskCount)
        let res = newSeq[uint](maskCount)
        let nmodDef = newSeq[uint](maskCount)
        
        for i in 0..<maskCount:
          modDef[i] = 0'u-1
          res[i] = 0'u-1

        for zone in archNode.partition.zones:
          for i in 0..<max(mlen, nmlen):
            let incl = if i < mlen: world.registry.entries[sig.modified[i]].getChangeMaskop(zone.block_idx) else: modDef
            let excl = if i < nmlen: world.registry.entries[sig.noModified[i]].getChangeMaskop(zone.block_idx) else: nmodDef

            for i in 0..<maskCount:
              res[i] = (res[i] and incl[i]) and not excl[i]

          yield (zone.block_idx, zone.r.s..<zone.r.e, res)

## Computes and caches the result of a Dense query.
##
## Useful if you need to iterate over the results multiple times, as it avoids
## re-scanning the archetype graph on subsequent iterations.
##
## @param world: The `ECSWorld` to query.
## @param sig: The `QuerySignature` defining the filter.
## @return: A `DenseQueryResult` containing the matching partitions.
proc denseQueryCache*(world: ECSWorld, sig: QuerySignature): DenseQueryResult =
  ## Iterate through all partitions that match the query signature
  ## Returns block index and range for each matching zone
  
  for archNode in world.archGraph.nodes:
    let arch = archNode.mask
    if not matchesArchetype(sig, arch):
      continue
    
    if not archNode.partition.isNil: 
      result.part.add(archNode.partition)

## Iterator for the cached `DenseQueryResult`.
##
## @param qr: The `DenseQueryResult` to iterate over.
## @yield: A tuple containing:
##         - `int`: The Block Index.
##         - `HSlice[int, int]`: The range of entity indices.
iterator items*(qr:DenseQueryResult):(int, HSlice[int, int]) =
  for partition in qr.part:
    for zone in partition.zones:
      yield (zone.block_idx, zone.r.s..<zone.r.e)

## Counts the total number of entities matching a query in Dense storage.
##
## @param world: The `ECSWorld` to query.
## @param sig: The `QuerySignature` defining the filter.
## @return: The total count of matching entities.
proc denseQueryCount*(world: ECSWorld, sig: QuerySignature): int =
  ## Count total entities matching the dense query
  result = 0
  
  for archNode in world.archGraph.nodes:
    let arch = archNode.mask
    if not matchesArchetype(sig, arch):
      continue
    
    let partition = archNode.partition

    if not partition.isNil:
      for zoneIdx in 0..partition.fill_index:
        if zoneIdx >= partition.zones.len:
          break
        
        let zone = partition.zones[zoneIdx]
        if not isEmpty(zone):
          result += zone.r.e - zone.r.s

####################################################################################################################################################
################################################################### SPARSE QUERIES #################################################################
####################################################################################################################################################

## Helper: Retrieves the existence masks for a list of components in Sparse storage.
##
## @param world: The `ECSWorld`.
## @param componentIds: Sequence of Component IDs to look up.
## @return: A sequence of sparse masks (sequences of uint), one per component ID.
proc getSparseMasks(world: ECSWorld, componentIds: seq[int]): seq[seq[uint]] =
  ## Get sparse masks for each component
  result = newSeq[seq[uint]](componentIds.len)
  
  for i, compId in componentIds:
    let entry = world.registry.entries[compId]
    result[i] = entry.getSparseMaskOp(entry.rawPointer)

## Helper: Performs a bitwise AND operation across multiple sparse masks.
##
## This intersection finds which entities/chunks exist in all provided masks.
##
## @param masks: A sequence of sparse masks (sequences of uint).
## @return: A single resulting mask representing the intersection.
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

## Helper: Filters a base mask by removing bits defined in exclusion masks.
##
## @param baseMask: The mask to filter (modified in place).
## @param excludeMasks: A sequence of masks containing bits to clear.
proc filterExcludedMasks(baseMask: var seq[uint], excludeMasks: seq[seq[uint]]) =
  ## Remove excluded components from base mask
  for excludeSeq in excludeMasks:
    let minLen = min(baseMask.len, excludeSeq.len)
    
    for i in 0..<minLen:
      baseMask[i] = baseMask[i] and not excludeSeq[i]

proc getChangeMask(world: ECSWorld, modif, nmodif:seq[int], blk:int):uint =
  let mlen = sig.modified.len
  let nmlen = sig.notModified.len
  let maskCount = 1
  let modDef = 0'u - 1
  let res = 0'u - 1
  let nmodDef = 0'u

  for i in 0..<max(mlen, nmlen):
    let incl = if i < mlen: world.registry.entries[modif[i]].getSparseChangeMaskop(blk)[0] else: modDef
    let excl = if i < nmlen: world.registry.entries[nmodif[i]].getSparseChangeMaskop(blk)[0] else: nmodDef

    for i in 0..<maskCount:
      res = (res and incl) and not excl

  return res

## Iterates over entities matching the query in Sparse storage.
##
## Logic:
## 1. Compute the intersection of all "included" component masks.
## 2. Remove any bits found in "excluded" component masks.
## 3. Iterate through the resulting chunks, yielding the chunk index and the specific entity mask.
##
## @param world: The `ECSWorld` to query.
## @param sig: The `QuerySignature` defining the filter.
## @yield: A tuple containing:
##         - `int`: The Chunk Index.
##         - `uint`: A bitmask where set bits indicate valid entity indices within that chunk.
iterator sparseQuery*(world: ECSWorld, sig: QuerySignature): (int, uint) =
  ## Iterate through sparse entities matching the query
  ## Returns chunk index and mask iterator for each matching chunk
  
  var includeIds: seq[int]
  var excludeIds: seq[int]
  
  for comp in sig.components:
    case comp.op
    of qInclude: includeIds.add(comp.id)
    of qExclude: excludeIds.add(comp.id)
    
  if includeIds.len > 0:
  
    # Get sparse masks for included components
    let includeMasks = getSparseMasks(world, includeIds)
  
    # AND all included masks (intersection)
    var resultMask = andMasks(includeMasks)
  
    # Filter out excluded components (difference)
    if excludeIds.len > 0:
      let excludeMasks = getSparseMasks(world, excludeIds)
      filterExcludedMasks(resultMask, excludeMasks)
  
    # Iterate through chunks with entities
    let S = sizeof(uint)*8
    
    if sig.modified.len == 0 and sig.notModified.len == 0:
      for i in 0..<resultMask.len:
        var m = resultMask[i]
        
        while m != 0:
          let chunkIdx = i*S + countTrailingZeroBits(m)
          var chunkMask = (1'u shl S-1) - 1'u # Initialize mask to all 1s (all entities in chunk)
          m = m and (m-1) # Clear the lowest set bit to move to next

          # Refine the mask by ensuring the entity actually has ALL included components
          for compId in includeIds:
            let entry = world.registry.entries[compId]
            let entityMask = entry.getSparseChunkMaskOp(entry.rawPointer, chunkIdx)
            chunkMask = chunkMask and entityMask

          yield (chunkIdx, chunkMask)
    else:
      for i in 0..<resultMask.len:
        var m = resultMask[i]
        
        while m != 0:
          let chunkIdx = i*S + countTrailingZeroBits(m)
          var chunkMask = (1'u shl S-1) - 1'u # Initialize mask to all 1s (all entities in chunk)
          let changeMask = getChangeMask(world, sig.modified, sig.notModified, chunkIdx)
          m = m and (m-1) # Clear the lowest set bit to move to next

          # Refine the mask by ensuring the entity actually has ALL included components
          for compId in includeIds:
            let entry = world.registry.entries[compId]
            let entityMask = entry.getSparseChunkMaskOp(entry.rawPointer, chunkIdx)
            chunkMask = chunkMask and entityMask

          let res = chunkMask and changeMask

          if res != 0: yield (chunkIdx, res)

## Computes and caches the result of a Sparse query.
##
## @param world: The `ECSWorld` to query.
## @param sig: The `QuerySignature` defining the filter.
## @return: A `sparseQueryResult` containing the calculated masks.
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

## Iterator for the cached `sparseQueryResult`.
##
## @param sr: The `sparseQueryResult` to iterate over.
## @yield: A tuple containing:
##         - `int`: The Chunk Index.
##         - `uint`: The bitmask of valid entities within the chunk.
iterator items*(sr:sparseQueryResult):(int, uint) =
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

## Counts the total number of entities matching a query in Sparse storage.
##
## @param world: The `ECSWorld` to query.
## @param sig: The `QuerySignature` defining the filter.
## @return: The total count of matching entities.
proc sparseQueryCount*(world: ECSWorld, sig: QuerySignature): int =
  ## Count total entities matching the sparse query
  result = 0
  
  for _,mask in sparseQuery(world, sig):
    for _ in mask.maskIter:
      result += 1

####################################################################################################################################################
################################################################### QUERY SYNTAX ###################################################################
####################################################################################################################################################

# Helper procs for building queries

## Creates a `QueryComponent` that requires a specific component.
proc includeComp*(componentId: int): QueryComponent =
  QueryComponent(id: componentId, op: qInclude)

## Creates a `QueryComponent` that forbids a specific component.
proc excludeComp*(componentId: int): QueryComponent =
  QueryComponent(id: componentId, op: qExclude)

## Creates a `QueryComponent` that requires a component to be modified.
proc modifiedComp*(componentId: int): QueryComponent =
  QueryComponent(id: componentId, op: qModified)

## Creates a `QueryComponent` that requires a component to be not modified.
proc notModifiedComp*(componentId: int): QueryComponent =
  QueryComponent(id: componentId, op: qNotModified)

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
macro query*(world: untyped, expr: untyped): untyped =
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