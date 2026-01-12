#######################################################################################################################################
######################################################## SPARSE ECS LOGICS ############################################################
#######################################################################################################################################

template activateComponentsSparse(table: var ECSWorld, i:int|uint, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.activateSparseBitOp(entry.rawPointer, i.uint)

template activateComponentsSparse(table: var ECSWorld, idxs:openArray, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.activateSparseBitBatchOp(entry.rawPointer, idxs)

template deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.deactivateSparseBitOp(entry.rawPointer, i.uint)

template deactivateComponentsSparse(table: var ECSWorld, idxs:openArray, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.deactivateSparseBitBatchOp(entry.rawPointer, idxs)

proc allocateSparseEntities(table: var ECSWorld, count:int, components:seq[int]):seq[Range] =
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

  while n > 0:
    let toAdd = min(n, S)
    let m = table.max_index
    res.add(Range(s:m,e:m+toAdd))
    n -= S

    for id in components:
      let m = (1.uint shl toAdd) - 1
      var entry = table.registry.entries[id]
      entry.newSparseBlockOp(entry.rawPointer, table.max_index, m)

    table.max_index += toAdd
    if n <= 0:
      for i in m..<m+(S-toAdd):
        table.free_list.add(makeId(i))

  return res

proc allocateSparseEntity(table: var ECSWorld, components:seq[int]):uint = 
  if table.free_list.len > 0:
    return table.free_list.pop()

  let S = sizeof(uint)*8
  for id in components:
    var entry = table.registry.entries[id]
    entry.newSparseBlockOp(entry.rawPointer, table.max_index, 1.uint)

  for i in table.max_index+1..<table.max_index+S:
    table.free_list.add(makeId(i))

  let id = table.max_index
  table.max_index += S

  return id

proc deleteSparseRow(table: var ECSWorld, i:uint, components:seq[int]) =
  table.free_list.add(i)
  deactivateComponentsSparse(table, i, components)
