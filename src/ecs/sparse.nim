#######################################################################################################################################
######################################################## SPARSE ECS LOGICS ############################################################
#######################################################################################################################################

proc activateComponentsSparse(table: var ECSWorld, i:int|uint, components:openArray[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.activateSparseBitOp(entry.rawPointer, i.uint)

template activateComponentsSparse(table: var ECSWorld, idxs:openArray, components:openArray[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.activateSparseBitBatchOp(entry.rawPointer, idxs)

proc deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:openArray[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.deactivateSparseBitOp(entry.rawPointer, i.uint)

proc deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:ArchetypeMask) =
  for m in components:
    var mask = m

    while mask != 0:
      let id = countTrailingZeroBits(mask)
      var entry = table.registry.entries[id]
      entry.deactivateSparseBitOp(entry.rawPointer, i.uint)
      mask = mask and (mask - 1)

proc overrideComponents(table: var ECSWorld, i,j:int|uint, components:ArchetypeMask) =
  for m in components:
    var mask = m

    while mask != 0:
      let id = countTrailingZeroBits(mask)
      var entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, i.uint, j.makeID)
      mask = mask and (mask - 1)

template deactivateComponentsSparse(table: var ECSWorld, idxs:openArray, components:openArray[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.deactivateSparseBitBatchOp(entry.rawPointer, idxs)

proc allocateSparseEntities(table: var ECSWorld, count:int, components:openArray[int]):seq[Range] =
  var res:seq[Range]
  var toActivate:seq[uint]
  var n = count
  var free_cursor = table.free_list.len-1
  let S = sizeof(uint)*8

  while n > 0 and free_cursor >= 0:
    let i = table.free_list[free_cursor].toIdx
    res.add(Range(s:i.int,e:i.int+1))
    toActivate.add(i)

    free_cursor -= 1
    n -= 1

  activateComponentsSparse(table, toActivate, components)
  table.free_list.setLen(free_cursor+1)
  if free_cursor >= 0: return res

  var masks:seq[uint]

  while n > 0:
    let toAdd = min(n, S)
    let m = table.max_index
    res.add(Range(s:m,e:m+toAdd))
    n -= S
    var mask = (1.uint shl toAdd) - (1 + (toAdd==S).uint)

    table.max_index += S
    if n <= 0:
      for i in m..<m+(S-toAdd):
        table.free_list.add(i.uint)

    masks.add(mask)

  for id in components:
    var entry = table.registry.entries[id]
    entry.newSparseBlocksOp(entry.rawPointer, masks)

  table.sparse_gens.setLen(table.max_index)

  return res

proc allocateSparseEntity(table: var ECSWorld, components:openArray[int]):uint = 
  if table.free_list.len > 0:
    return table.free_list.pop()

  let S = sizeof(uint)*8
  for id in components:
    var entry = table.registry.entries[id]
    entry.newSparseBlockOp(entry.rawPointer, table.max_index, 1.uint)

  for i in table.max_index+1..<table.max_index+S:
    table.free_list.add(i.uint)

  let id = table.max_index
  table.max_index += S
  table.sparse_gens.setLen(table.max_index)

  return id.uint

proc deleteSparseRow(table: var ECSWorld, i:uint, components:ArchetypeMask) =
  table.free_list.add(i)
  deactivateComponentsSparse(table, i, components)
