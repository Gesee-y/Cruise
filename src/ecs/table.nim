####################################################################################################################################################
######################################################################## ECS TABLE #################################################################
####################################################################################################################################################

import tables, bitops
include "fragment.nim"
include "registry.nim"

const
  MAX_COMPONENT_LAYER = 4

type 
  Range = object
    s,e:int

  ArchetypeMask = array[MAX_COMPONENT_LAYER, uint]

  TableColumn[N:static int,T,B] = ref object
    components:SoAFragmentArray[N,T,B]
    mask:seq[uint]

  TableRange = object
    r:Range
    block_idx:int

  TablePartition = ref object
    zones:seq[TableRange]
    components:seq[int]
    fill_index:int

  ECSWorld = object
    registry:ComponentRegistry
    archetypes:Table[ArchetypeMask, TablePartition]
    pooltype:Table[string, int]
    free_list:seq[int]
    max_index:int
    block_count:int

template newTableColumn[N,T,B](f:SoAFragmentArray[N,T,B]):untyped =
  var m = newSeq[uint]()

  for i in 0..<f.blocks.len:
    let idx = i div sizeof(uint)
    let bitpos = i mod sizeof(uint)
    if idx >= m.len:
      m.add(0.uint)

    if not f.blocks[i].isNil:
      m[idx] = m[idx] or (1 shl bitpos)
  
  var res = TableColumn[N,T,B](components:f, mask:m)
  res

include "mask.nim"

####################################################################################################################################################
####################################################################### OPERATIONS #################################################################
####################################################################################################################################################

proc isEmpty(t:TableRange):bool = t.r.s == t.r.e

proc resize(world: var ECSWorld, n:int) =
  for entry in world.registry.entries:
    entry.resizeOp(entry.rawPointer, n)

proc upsize(world: var ECSWorld, n:int) =
  for entry in world.registry.entries:
    entry.resizeOp(entry.rawPointer, world.blockCount + n)

proc blockCount(world: ECSWorld):int =
  return world.blockCount

proc getComponentsFromSig(table: ECSWorld, sig:ArchetypeMask):seq[int] =
  var res:seq[int]
  var cnt = 0
  for i in 0..<sig.len:
    var s = sig[i]
    while s != 0:
      cnt += countTrailingZeroBits(s)
      res.add(cnt)
      s = s and not (1.uint shl cnt)

  return res

proc createPartition(table: var ECSWorld, arch:ArchetypeMask):TablePartition =
  if not table.archetypes.haskey(arch):
    var partition:TablePartition
    new(partition)
    partition.components = getComponentsFromSig(table, arch)
    table.archetypes[arch] = partition

  return table.archetypes[arch]

proc allocateNewBlocks(table: var ECSWorld, count:int, res: var seq[Range], 
  partition:var TablePartition, arch:ArchetypeMask, components:varargs[int]) =
  
  var n = count
  let s = n div DEFAULT_BLK_SIZE
  var bc = table.blockCount()
  
  partition.zones.setLen(s+1)
  table.archetypes[arch] = partition
  upsize(table, s+1)

  for i in 0..<s:
    var trange:TableRange
    let s = DEFAULT_BLK_SIZE*bc
    let e = s+min(n, DEFAULT_BLK_SIZE)
    
    res.add(Range(s:s,e:e))
    trange.r.s = s
    trange.r.e = e
    trange.block_idx = bc
    partition.zones[i] = trange
    partition.fill_index += 1

    for id in components:
      var entry = table.registry.entries[id]
      entry.newBlockAtOp(entry.rawPointer, bc)

    table.blockCount += 1

    n -= DEFAULT_BLK_SIZE
    inc bc
  

proc allocateEntities(table: var ECSWorld, n:int, arch:ArchetypeMask, components:seq[int]):seq[Range] =
  var res:seq[Range]
  if n < 1: return res
  
  if not table.archetypes.haskey(arch):
    var partition:TablePartition
    new(partition)
    partition.components = getComponentsFromSig(table, arch)
    allocateNewBlocks(table, n, res, partition, arch, components)

    return res

  var m = n
  var partition = table.archetypes[arch]
  while m > 0 and partition.fill_index < table.blockCount():
    let id = partition.zones[partition.fill_index].block_idx
    let e = partition.zones[partition.fill_index].r.e
    let r = DEFAULT_BLK_SIZE*id - e
    partition.zones[partition.fill_index].r.e += min(m, r)
    
    res.add(Range(s:e,e:e+r))
    m -= r
    partition.fill_index += 1

  if m > 0:
    allocateNewBlocks(table, m, res, partition, arch, components)

  return res

proc allocateEntity(table: var ECSWorld, arch:ArchetypeMask, components:seq[int]):int = allocateEntities(table, 1, arch, components)[0].e-1

proc activateComponents(table: var ECSWorld, i:int, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.activateBitOp(entry.rawPointer, i)

proc deactivateComponents(table: var ECSWorld, i:int, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.deactivateBitOp(entry.rawPointer, i)

proc allocateSparseEntities(table: var ECSWorld, count:int):seq[Range] =
  var res:seq[Range]
  var n = count
  var free_cursor = table.free_list.len-1

  while n > 0 and free_cursor >= 0:
    let i = table.free_list[free_cursor]
    res.add(Range(s:i,e:i+1))
    free_cursor -= 1
    n -= 1

  table.free_list.setLen(free_cursor+1)

  while n > 0:
    let toAdd = min(n, sizeof(uint)*8)
    res.add(Range(s:table.max_index,e:table.max_index+toAdd+1))
    table.max_index += toAdd
    n -= sizeof(uint)*8

  return res

proc allocateSparseEntity(table: var ECSWorld):int = allocateSparseEntities(table, 1)[0].e-1

proc deleteRow(table: var ECSWorld, i:int, arch:ArchetypeMask):int =
  let partition = table.archetypes[arch]
  if isEmpty(partition.zones[partition.fill_index]):
    partition.fill_index -= 1

  let last = partition.zones[partition.fill_index].r.e
  for id in partition.components:
    var entry = table.registry.entries[id]
    entry.overrideValsOp(entry.rawPointer, i, last)

  partition.zones[partition.fill_index].r.e -= 1

  return last

proc deleteSparseRow(table: var ECSWorld, i:int, components:seq[int]) =
  table.free_list.add(i)
  deactivateComponents(table, i, components)
  
proc changePartition(table: var ECSWorld, i:int, oldArch:ArchetypeMask, newArch:ArchetypeMask) =
  var oldPartition = table.archetypes[oldArch]

  var newPartition = createPartition(table, newArch)
  var oldComponents = oldPartition.components
  var newComponents = newPartition.components

  if isempty(oldPartition.zones[oldPartition.fill_index]):
    oldPartition.fill_index -= 1

  let last = oldPartition.zones[oldPartition.fill_index].r.e-1

  for id in oldComponents:
    var entry = table.registry.entries[id]
    entry.overrideValsOp(entry.rawPointer, i, last)

  oldPartition.zones[oldPartition.fill_index].r.e -= 1

  if newPartition.zones.len == 0:
    newPartition.zones.setLen(1)
    for id in newPartition.components:
      var entry = table.registry.entries[id]
      entry.newBlockOp(entry.rawPointer, table.max_index)

