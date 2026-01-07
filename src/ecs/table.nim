####################################################################################################################################################
######################################################################## ECS TABLE #################################################################
####################################################################################################################################################

import tables, bitops, typetraits

const
  MAX_COMPONENT_LAYER = 4

type 
  Range = object
    s,e:int

  ArchetypeMask = array[MAX_COMPONENT_LAYER, uint]

include "fragment.nim"
include "registry.nim"
include "entity.nim"

type
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
    entities:seq[Entity]
    sparse_entities:seq[Entity]
    archetypes:Table[ArchetypeMask, TablePartition]
    pooltype:Table[string, int]
    free_list:seq[uint]
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

proc makeId(info:(uint, Range)):uint =
  return ((info[0]).uint shl 32) or ((info[1].e-1) mod DEFAULT_BLK_SIZE).uint

proc makeId(i:int):uint =
  let bid = i div DEFAULT_BLK_SIZE
  let idx = i mod DEFAULT_BLK_SIZE

  return (bid.uint shl BLK_SHIFT) or idx.uint

proc resize(world: var ECSWorld, n:int) =
  world.max_index = DEFAULT_BLK_SIZE*n
  for entry in world.registry.entries:
    entry.resizeOp(entry.rawPointer, n)

  world.entities.setLen(world.max_index)

proc upsize(world: var ECSWorld, n:int) =
  world.max_index += DEFAULT_BLK_SIZE*n
  for entry in world.registry.entries:
    entry.resizeOp(entry.rawPointer, world.blockCount + n)

  world.entities.setLen(world.max_index)

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

proc allocateNewBlocks(table: var ECSWorld, count:int, res: var seq[(uint, Range)], 
  partition:var TablePartition, arch:ArchetypeMask, components:varargs[int]):seq[(uint, Range)] =
  
  var n = count
  let s = n div DEFAULT_BLK_SIZE
  var bc = table.blockCount()
  let pl = partition.zones.len
  
  partition.zones.setLen(pl + s+1)
  table.archetypes[arch] = partition
  upsize(table, s+1)

  for i in 0..s:
    var trange:TableRange
    let e = min(n, DEFAULT_BLK_SIZE)
    
    res.add((bc.uint, Range(s:0,e:e)))
    trange.r.s = 0
    trange.r.e = e
    trange.block_idx = bc
    partition.zones[pl+i] = trange
    if n >= DEFAULT_BLK_SIZE:
      partition.fill_index += 1

    for id in components:
      var entry = table.registry.entries[id]
      entry.newBlockAtOp(entry.rawPointer, bc)

    table.blockCount += 1

    n -= DEFAULT_BLK_SIZE
    inc bc

  return res

proc allocateEntities(table: var ECSWorld, n:int, arch:ArchetypeMask, components:seq[int]):seq[(uint, Range)] =
  var res:seq[(uint, Range)]
  if n < 1: return res
  
  if not table.archetypes.haskey(arch):
    var partition:TablePartition
    new(partition)
    partition.components = getComponentsFromSig(table, arch)

    return allocateNewBlocks(table, n, res, partition, arch, components)

  var m = n
  var partition = table.archetypes[arch]

  while m > 0 and partition.fill_index < partition.zones.len:
    let id = partition.zones[partition.fill_index].block_idx
    let e = partition.zones[partition.fill_index].r.e
    let r = DEFAULT_BLK_SIZE*(id+1) - e

    partition.zones[partition.fill_index].r.e += min(m, r)
    res.add((id.uint, Range(s:e,e:e+min(m, r))))
    
    if m >= r:
      partition.fill_index += 1

    m -= r

  if m > 0:
    var r = allocateNewBlocks(table, m, res, partition, arch, components)
    for i in r:
      res.add(i)

  return res

proc allocateEntity(table: var ECSWorld, arch:ArchetypeMask, components:seq[int]):(uint, Range) = allocateEntities(table, 1, arch, components)[0]

template activateComponents(table: var ECSWorld, i:int|uint, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.activateBitOp(entry.rawPointer, i.int)

template deactivateComponents(table: var ECSWorld, i:int|uint, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.deactivateBitOp(entry.rawPointer, i.int)

template activateComponentsSparse(table: var ECSWorld, i:int|uint, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.activateSparseBitOp(entry.rawPointer, i.uint)

template deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:seq[int]) =
  for id in components:
    var entry = table.registry.entries[id]
    entry.deactivateSparseBitOp(entry.rawPointer, i.uint)

proc allocateSparseEntities(table: var ECSWorld, count:int, components:seq[int]):seq[Range] =
  var res:seq[Range]
  var n = count
  var free_cursor = table.free_list.len-1

  while n > 0 and free_cursor >= 0:
    let i = table.free_list[free_cursor]
    res.add(Range(s:i.int,e:i.int+1))
    
    activateComponentsSparse(table, i, components)

    free_cursor -= 1
    n -= 1


  table.free_list.setLen(free_cursor+1)

  while n > 0:
    let toAdd = min(n, sizeof(uint)*8)
    res.add(Range(s:0,e:toAdd))
    table.max_index += toAdd
    n -= sizeof(uint)*8

    for id in components:
      let m = (1.uint shl (toAdd+1)) - 1
      var entry = table.registry.entries[id]
      entry.newSparseBlockOp(entry.rawPointer, table.max_index+1, m)

  return res

proc allocateSparseEntity(table: var ECSWorld, components:seq[int]):int = allocateSparseEntities(table, 1, components)[0].e-1

proc deleteRow(table: var ECSWorld, i:int, arch:ArchetypeMask):uint =
  let partition = table.archetypes[arch]
  if partition.zones.len <= partition.fill_index:
    partition.fill_index -= 1

  let last = partition.zones[partition.fill_index].r.e-1
  for id in partition.components:
    var entry = table.registry.entries[id]
    entry.overrideValsOp(entry.rawPointer, makeId(i), makeId(last))

  partition.zones[partition.fill_index].r.e -= 1

  return last.uint

proc deleteSparseRow(table: var ECSWorld, i:uint, components:seq[int]) =
  table.free_list.add(i)
  deactivateComponentsSparse(table, i, components)
  
proc changePartition(table: var ECSWorld, i:int, oldArch:ArchetypeMask, newArch:ArchetypeMask):(uint, uint, uint) =
  var oldPartition = table.archetypes[oldArch]

  var newPartition = createPartition(table, newArch)
  var oldComponents = oldPartition.components
  var newComponents = newPartition.components

  if isempty(oldPartition.zones[oldPartition.fill_index]):
    oldPartition.fill_index -= 1

  let last = oldPartition.zones[oldPartition.fill_index].r.e-1

  oldPartition.zones[oldPartition.fill_index].r.e -= 1

  if newPartition.zones.len == 0:
    newPartition.zones.setLen(1)
    newPartition.zones[0].block_idx = table.blockCount
    newPartition.zones[0].r.s = table.max_index
    newPartition.zones[0].r.e = table.max_index-1
    for id in newPartition.components:
      var entry = table.registry.entries[id]
      entry.resizeOp(entry.rawPointer, table.blockCount+1)
      entry.newBlockAtOp(entry.rawPointer, table.blockCount)

  let new_id = (newPartition.zones[newPartition.fill_index].r.e mod DEFAULT_BLK_SIZE).uint
  let bid = newPartition.zones[newPartition.fill_index].block_idx.uint

  if oldComponents.len < newComponents.len:
    for id in oldComponents:
      var entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, (bid shl BLK_SHIFT) or new_id, i.uint)
  else:
    for id in newComponents:
      var entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, (bid shl BLK_SHIFT) or new_id, i.uint)

  for id in oldComponents:
    var entry = table.registry.entries[id]
    entry.overrideValsOp(entry.rawPointer, i.uint, last.uint)

  return (last.uint, new_id, bid)



include "operations.nim"