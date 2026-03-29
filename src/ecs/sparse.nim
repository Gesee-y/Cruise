#######################################################################################################################################
######################################################## SPARSE ECS LOGICS ############################################################
#######################################################################################################################################

## Activates a set of components for a single sparse entity index.
## This marks the entity as owning those components without allocating dense storage.
template activateComponentsSparse(table: var ECSWorld, i:int|uint, components:untyped) =
  for id in components:
    let entry = addr table.registry.entries[id]
    entry.activateSparseBitOp(entry.rawPointer, i.uint)

## Batch version of sparse activation.
## Efficiently activates the same set of components for multiple entity indices.
template activateComponentsSparse(table: var ECSWorld, idxs:openArray, components:untyped) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.activateSparseBitBatchOp(entry.rawPointer, idxs)

## Deactivates a set of components for a single sparse entity index.
## This does NOT reclaim entity IDs, only clears component ownership.
template deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:untyped) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.deactivateSparseBitOp(entry.rawPointer, i.uint)

## Deactivates components described by an archetype mask.
## Uses bit iteration for fast traversal of active component IDs.
template deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:ArchetypeMask) =
  for m in components:
    var mask = m
    while mask != 0:
      let id = countTrailingZeroBits(mask)
      let entry = table.registry.entries[id]
      entry.deactivateSparseBitOp(entry.rawPointer, i.uint)
      mask = mask and (mask - 1)

## Overrides component values from entity j into entity i
## for all components present in the archetype mask.
## Used during entity migration or structural transformations.
template overrideComponents(table: var ECSWorld, i,j:int|uint, components:ArchetypeMask) =
  for m in components:
    var mask = m
    while mask != 0:
      let id = countTrailingZeroBits(mask)
      let entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, i.uint, j.makeID)
      mask = mask and (mask - 1)

## Batch deactivation of sparse components for multiple entity indices.
template deactivateComponentsSparse(table: var ECSWorld, idxs:openArray, components:untyped) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.deactivateSparseBitBatchOp(entry.rawPointer, idxs)

## Allocates multiple sparse entities at once.
## Reuses entity IDs from the free list when possible, otherwise grows
## the sparse storage in block-sized chunks.
##
## Returns ranges describing the allocated entity indices.
template allocateSparseEntities(table: var ECSWorld, count:untyped, components:untyped):seq[Range] =
  var res = newSeqOfCap[Range](count shr BIT_DIVIDER)
  var free_cursor = table.free_list.len - 1
  var toActivate = newSeq[uint](free_cursor+1)
  var n = count
  var c = 0

  ## Reuse free entity slots first
  while n > 0 and free_cursor >= 0:
    let i = table.free_list[free_cursor].toIdx
    res.add(Range(s: i.int, e: i.int + 1))
    toActivate[c] = i
    dec free_cursor
    dec n
    inc c

  activateComponentsSparse(table, toActivate, components)

  ## To be activated after also collecting new IDs
  # Removed early return and early activation

  ## Allocate new sparse blocks if free slots are exhausted
  var masks: seq[uint]
  let baseOffset = table.max_index

  while n > 0:
    let toAdd = min(n, UINT_BITS)
    let m = table.max_index
    let r = m ..< m + toAdd
    res.add(Range(s: m, e: m + toAdd))

    n -= UINT_BITS
    var mask = (1.uint shl toAdd) - (1 + (toAdd == UINT_BITS).uint)

    table.max_index += UINT_BITS

    ## Remaining slots in the block are pushed to the free list
    if n <= 0:
      let start = m + toAdd
      let count = UINT_BITS - toAdd
      if count > 0:
        let curLen = table.free_list.len
        table.free_list.setLen(curLen + count)
        for i in 0..<count:
          table.free_list[curLen + i] = (start + i).uint

    masks.add(mask)

  ## Update table state
  table.free_list.setLen(free_cursor + 1)

  ## Notify each component to materialize new sparse blocks
  for id in components:
    let entry = table.registry.entries[id]
    entry.newSparseBlocksOp(entry.rawPointer, baseOffset, masks)

  table.sparse_gens.setLen(table.max_index)
  res

## Allocates a single sparse entity.
## Grows sparse storage if no free IDs are available.
template allocateSparseEntity(table: var ECSWorld, components:untyped):uint = 
  if table.free_list.len > 0:
    let id = table.free_list.pop()
    activateComponentsSparse(table, id, components)
    id
  else:
    ## Allocate a new sparse block for each component
    for id in components:
      let entry = table.registry.entries[id]
      entry.newSparseBlockOp(entry.rawPointer, table.max_index, 1.uint)

    ## Push remaining slots of the block into the free list
    let count = UINT_BITS - 1
    let curLen = table.free_list.len
    table.free_list.setLen(curLen + count)
    for i in 0..<count:
      table.free_list[curLen + i] = (table.max_index + 1 + i).uint

    let id = table.max_index
    table.max_index += UINT_BITS
    table.sparse_gens.setLen(table.max_index)

    id.uint

## Deletes a sparse entity row.
## The entity ID is recycled and all components are deactivated.
template deleteSparseRow(table: var ECSWorld, i:uint, components:untyped) =
  table.free_list.add(i)
  deactivateComponentsSparse(table, i, components)
