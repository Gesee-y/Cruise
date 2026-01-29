#######################################################################################################################################
######################################################## SPARSE ECS LOGICS ############################################################
#######################################################################################################################################

## Activates a set of components for a single sparse entity index.
## This marks the entity as owning those components without allocating dense storage.
proc activateComponentsSparse(table: var ECSWorld, i:int|uint, components:openArray[int]) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.activateSparseBitOp(entry.rawPointer, i.uint)

## Batch version of sparse activation.
## Efficiently activates the same set of components for multiple entity indices.
template activateComponentsSparse(table: var ECSWorld, idxs:openArray, components:openArray[int]) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.activateSparseBitBatchOp(entry.rawPointer, idxs)

## Deactivates a set of components for a single sparse entity index.
## This does NOT reclaim entity IDs, only clears component ownership.
proc deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:openArray[int]) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.deactivateSparseBitOp(entry.rawPointer, i.uint)

## Deactivates components described by an archetype mask.
## Uses bit iteration for fast traversal of active component IDs.
proc deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:ArchetypeMask) =
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
proc overrideComponents(table: var ECSWorld, i,j:int|uint, components:ArchetypeMask) =
  for m in components:
    var mask = m
    while mask != 0:
      let id = countTrailingZeroBits(mask)
      let entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, i.uint, j.makeID)
      mask = mask and (mask - 1)

## Batch deactivation of sparse components for multiple entity indices.
template deactivateComponentsSparse(table: var ECSWorld, idxs:openArray, components:openArray[int]) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.deactivateSparseBitBatchOp(entry.rawPointer, idxs)

## Allocates multiple sparse entities at once.
## Reuses entity IDs from the free list when possible, otherwise grows
## the sparse storage in block-sized chunks.
##
## Returns ranges describing the allocated entity indices.
proc allocateSparseEntities(table: var ECSWorld, count:int, components:openArray[int]):seq[Range] =
  var res: seq[Range]
  var toActivate: seq[uint]
  var n = count
  var free_cursor = table.free_list.len - 1
  let S = sizeof(uint) * 8

  ## Reuse free entity slots first
  while n > 0 and free_cursor >= 0:
    let i = table.free_list[free_cursor].toIdx
    res.add(Range(s: i.int, e: i.int + 1))
    toActivate.add(i)
    free_cursor -= 1
    n -= 1

  activateComponentsSparse(table, toActivate, components)
  table.free_list.setLen(free_cursor + 1)
  if free_cursor >= 0:
    return res

  ## Allocate new sparse blocks if free slots are exhausted
  var masks: seq[uint]
  let baseOffset = table.max_index

  while n > 0:
    let toAdd = min(n, S)
    let m = table.max_index
    let r = m ..< m + toAdd
    res.add(Range(s: m, e: m + toAdd))

    ## Activate components for newly created entities
    for i in r:
      table.activateComponentsSparse(i, components)

    n -= S
    var mask = (1.uint shl toAdd) - (1 + (toAdd == S).uint)

    table.max_index += S

    ## Remaining slots in the block are pushed to the free list
    if n <= 0:
      for i in m ..< m + (S - toAdd):
        table.free_list.add(i.uint)

    masks.add(mask)

  ## Notify each component to materialize new sparse blocks
  for id in components:
    let entry = table.registry.entries[id]
    entry.newSparseBlocksOp(entry.rawPointer, baseOffset, masks)

  table.sparse_gens.setLen(table.max_index)
  return res

## Allocates a single sparse entity.
## Grows sparse storage if no free IDs are available.
proc allocateSparseEntity(table: var ECSWorld, components:openArray[int]):uint = 
  if table.free_list.len > 0:
    let id = table.free_list.pop()
    activateComponentsSparse(table, id, components)
    return id

  let S = sizeof(uint) * 8

  ## Allocate a new sparse block for each component
  for id in components:
    let entry = table.registry.entries[id]
    entry.newSparseBlockOp(entry.rawPointer, table.max_index, 1.uint)

  ## Push remaining slots of the block into the free list
  let diff = (table.max_index + S) - table.max_index
  let base = table.free_list.len
  table.free_list.setLen(base+diff)
  for i in table.max_index+1..<table.max_index + S:
    table.free_list[base+i] = i.uint

  let id = table.max_index
  table.max_index += S
  table.sparse_gens.setLen(table.max_index)

  return id.uint

## Deletes a sparse entity row.
## The entity ID is recycled and all components are deactivated.
proc deleteSparseRow(table: var ECSWorld, i:uint, components:ArchetypeMask) =
  table.free_list.add(i)
  deactivateComponentsSparse(table, i, components)
