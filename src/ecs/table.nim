####################################################################################################################################################
######################################################################## ECS TABLE #################################################################
####################################################################################################################################################

import tables, bitops, typetraits, hashes

const
  MAX_COMPONENT_LAYER = 4

type 
  Range = object
    s,e:int

  ArchetypeMask = array[MAX_COMPONENT_LAYER, uint]

include "fragment.nim"
include "entity.nim"
include "registry.nim"
include "mask.nim"

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

include "archetypes.nim"

type
  ECSWorld = ref object
    registry:ComponentRegistry
    entities:seq[Entity]
    sparse_entities:seq[Entity]
    archetypes:Table[ArchetypeMask, TablePartition]
    archGraph:ArchetypeGraph
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

proc newECSWorld(max_entities:int=1000000):ECSWorld =
  var w:ECSWorld
  new(w)
  new(w.registry)
  w.archGraph = initArchetypeGraph()
  w.entities = newSeqofCap[Entity](max_entities)

  return w

####################################################################################################################################################
####################################################################### OPERATIONS #################################################################
####################################################################################################################################################

proc isEmpty(t:TableRange):bool = t.r.s == t.r.e
proc isFull(t:TableRange):bool = t.r.e - t.r.s == DEFAULT_BLK_SIZE

proc getComponentId(world:ECSWorld, t:typedesc):int =
  return world.registry.cmap[$t]

proc getArchetype(w:ECSWorld, e:SomeEntity):ArchetypeNode =
  return w.archGraph.nodes[e.archetypeId]

proc makeId(info:(uint, Range)):uint =
  return ((info[0]).uint shl 32) or ((info[1].e-1) mod DEFAULT_BLK_SIZE).uint

proc makeId(i:int):uint =
  let bid = i div DEFAULT_BLK_SIZE
  let idx = i mod DEFAULT_BLK_SIZE

  return (bid.uint shl BLK_SHIFT) or idx.uint

proc registerComponent[T](world:var ECSWorld, t:typedesc[T]):int =
  registerComponent(world.registry, T)

template get[T](world:ECSWorld,t:typedesc[T]):untyped =
  let id = world.getComponentId(t)
  getValue[T](world.registry.entries[id])

template get[T](world:ECSWorld, t:typedesc[T], i:untyped):untyped =
  let id = world.getComponentId(t)
  getValue[T](world.registry.entries[id])[i]

proc resize(world: var ECSWorld, n:int) =
  for entry in world.registry.entries:
    entry.resizeOp(entry.rawPointer, n)

proc upsize(world: var ECSWorld, n:int) =
  for entry in world.registry.entries:
    entry.resizeOp(entry.rawPointer, world.blockCount + n)

proc getComponentsFromSig(sig:ArchetypeMask):seq[int] =
  var res:seq[int]
  for i in 0..<sig.len:
    var s = sig[i]
    while s != 0:
      res.add(countTrailingZeroBits(s))
      s = s and (s-1)

  return res

proc createPartition(table: var ECSWorld, arch:ArchetypeMask):TablePartition =
  if not table.archetypes.haskey(arch):
    var partition:TablePartition
    new(partition)
    partition.components = getComponentsFromSig(arch)
    table.archetypes[arch] = partition

  return table.archetypes[arch]

proc createPartition(table: var ECSWorld, arch:ArchetypeNode):TablePartition =
  if arch.partition.isNil:
    var partition:TablePartition
    new(partition)
    partition.components = cast[seq[int]](arch.componentIds)
    arch.partition = partition

  return arch.partition

proc allocateNewBlocks(table: var ECSWorld, count:int, res: var seq[(uint, Range)], 
  partition:var TablePartition, arch:ArchetypeMask, components:seq[int]):seq[(uint, Range)] =
  
  var n = count
  let s = n div DEFAULT_BLK_SIZE
  var bc = table.blockCount
  let pl = partition.zones.len
  
  partition.zones.setLen(pl + s+1)
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

  table.entities.setLen((table.blockCount+1)*DEFAULT_BLK_SIZE)

  return res

proc allocateEntities(table: var ECSWorld, n:int, arch:ArchetypeMask, components:seq[int]):seq[(uint, Range)] =
  var res:seq[(uint, Range)]
  var archNode = table.archGraph.findArchetypeFast(arch)

  if archNode.partition.isNil:
    var partition:TablePartition
    new(partition)
    partition.components = components
    archNode.partition = partition

    return allocateNewBlocks(table, n, res, partition, arch, components)

  var m = n
  var partition = archNode.partition

  while m > 0 and partition.fill_index < partition.zones.len:
    let id = partition.zones[partition.fill_index].block_idx
    let e = partition.zones[partition.fill_index].r.e
    let r = min(m, DEFAULT_BLK_SIZE)

    partition.zones[partition.fill_index].r.e += r
    res.add((id.uint, Range(s:e,e:e+r)))
    
    if e+r >= DEFAULT_BLK_SIZE:
      partition.fill_index += 1

    m -= r

  if m > 0:
    var r = allocateNewBlocks(table, m, res, partition, arch, components)
    for i in r:
      res.add(i)

  return res

proc allocateEntities(table: var ECSWorld, n:int, arch:ArchetypeMask):seq[(uint, Range)] =
  allocateEntities(table, n, arch, getComponentsFromSig(arch))

proc allocateEntity(table: var ECSWorld, arch:ArchetypeMask, components:seq[int]):(uint, int, uint16) =
  var partition:TablePartition
  var archNode = table.archGraph.findArchetypeFast(arch)

  if archNode.partition.isNil:
    new(partition)
    partition.components = components
    archNode.partition = partition
  
  partition = archNode.partition
  
  var fill_index = partition.fill_index

  if fill_index >= partition.zones.len:
    partition.zones.setLen(fill_index+1)
    upsize(table, 1)

    for id in components:
      var entry = table.registry.entries[id]
      entry.newBlockAtOp(entry.rawPointer, table.blockCount)

    partition.zones[fill_index].block_idx = table.blockCount
    table.blockCount += 1

    table.entities.setLen((table.blockCount+1)*DEFAULT_BLK_SIZE)

  var zone = addr partition.zones[fill_index]
  let id = zone.block_idx
  let e = zone.r.e

  zone.r.e += 1
    
  if isFull(partition.zones[fill_index]):
    partition.fill_index += 1

  return (id.uint, e, archNode.id)

proc allocateEntity(table: var ECSWorld, n:int, arch:ArchetypeMask):(uint, int, uint16) =
  allocateEntity(table, arch, getComponentsFromSig(arch))

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
  let S = sizeof(uint)*8

  while n > 0 and free_cursor >= 0:
    let i = table.free_list[free_cursor]
    res.add(Range(s:i.int,e:i.int+1))
    
    activateComponentsSparse(table, i, components)

    free_cursor -= 1
    n -= 1


  table.free_list.setLen(free_cursor+1)

  while n > 0:
    let toAdd = min(n, S)
    res.add(Range(s:0,e:toAdd))
    n -= S

    for id in components:
      let m = (1.uint shl (S)) - 1
      var entry = table.registry.entries[id]
      entry.newSparseBlockOp(entry.rawPointer, table.max_index, m)

    table.max_index += toAdd

  return res

proc allocateSparseEntity(table: var ECSWorld, components:seq[int]):int = allocateSparseEntities(table, 1, components)[0].e-1

proc deleteRow(table: var ECSWorld, i:int, arch:uint16):uint =
  let archNode = table.archGraph.nodes[arch]
  let partition = archNode.partition
  if partition.zones.len <= partition.fill_index:
    partition.fill_index -= 1

  var zone = addr partition.zones[partition.fill_index]

  let last = zone.r.e-1
  let bid = zone.block_idx.uint

  if last != i:
    for id in partition.components:
      var entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, makeId(i), makeId(last))

  zone.r.e -= 1

  return last.uint+bid*DEFAULT_BLK_SIZE

proc deleteRow(table: var ECSWorld, i:int, arch:ArchetypeMask):uint =
  let archNode = table.archGraph.findArchetypeFast(arch)
  return deleteRow(table, i, archNode.id)

proc deleteSparseRow(table: var ECSWorld, i:uint, components:seq[int]) =
  table.free_list.add(i)
  deactivateComponentsSparse(table, i, components)
  
proc changePartition(table: var ECSWorld, i:int|uint, oldArch:uint16, newArch:ArchetypeNode):(int, uint, uint) =
  var oldPartition = table.archGraph.nodes[oldArch].partition
  var newPartition = createPartition(table, newArch)
  var oldComponents = oldPartition.components
  var newComponents = newPartition.components

  if oldPartition.zones.len <= oldPartition.fill_index or isEmpty(oldPartition.zones[oldPartition.fill_index]):
    oldPartition.fill_index -= 1

  var oldZone = addr oldPartition.zones[oldPartition.fill_index]
  let last = oldZone.r.e-1
  let blast = oldZone.block_idx

  oldZone.r.e -= 1

  if newPartition.zones.len <= newPartition.fill_index:
    let fi = newPartition.fill_index
    newPartition.zones.setLen(fi+1)
    let bc = table.blockCount
    var nZone = addr newPartition.zones[fi]
    nZone.block_idx = bc
    nZone.r.s = 0
    nZone.r.e = 0
    for id in newPartition.components:
      var entry = table.registry.entries[id]
      entry.resizeOp(entry.rawPointer, table.blockCount+1)
      entry.newBlockAtOp(entry.rawPointer, table.blockCount)

    table.blockCount += 1
  
    table.entities.setLen((table.blockCount+1)*DEFAULT_BLK_SIZE)

  var newZone = addr newPartition.zones[newPartition.fill_index]
  let new_id = (newZone.r.e mod DEFAULT_BLK_SIZE).uint
  let bid = newZone.block_idx.uint

  if oldComponents.len < newComponents.len:
    for id in oldComponents:
      var entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, (bid shl BLK_SHIFT) or new_id, i.uint)
  else:
    for id in newComponents:
      var entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, (bid shl BLK_SHIFT) or new_id, i.uint)

  if (i and BLK_MASK).int != last:
    for id in oldComponents:
      var entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, i.uint, (blast.uint shl BLK_SHIFT) or last.uint)
  
  newZone.r.e += 1
  if isFull(newZone[]):
    newPartition.fill_index += 1

  return (last + blast*DEFAULT_BLK_SIZE, new_id, bid)

proc changePartition(table: var ECSWorld, ids:var openArray[ptr Entity], oldArch:uint16, newArch:ArchetypeNode) =
  var oldPartition = table.archGraph.nodes[oldArch].partition
  var newPartition = createPartition(table, newArch)
  var oldComponents = oldPartition.components
  var newComponents = newPartition.components

  if oldPartition.zones.len <= oldPartition.fill_index:
    oldPartition.fill_index -= 1

  var m = ids.len
  var ofil = oldPartition.fill_index
  var toSwap, toAdd:seq[uint]
  
  while toSwap.len < ids.len:
    let zone = addr oldPartition.zones[ofil]
    let r = max(0, zone.r.e - m)..<zone.r.e
    let bid = zone.block_idx.uint

    m -= r.b - r.a + 1

    for i in r:
      toSwap.add((bid shl BLK_SHIFT) or i.uint)

    zone.r.e = r.a
    ofil -= 1 * (r.a == 0 and toSwap.len < ids.len).int

  oldPartition.fill_index = ofil

  var nfil = newPartition.fill_index
  m = ids.len
  while toAdd.len < ids.len:
    if nfil >= newPartition.zones.len:
      newPartition.zones.setLen(nfil+1)
      newPartition.zones[nfil].block_idx = table.blockCount

      for id in newPartition.components:
        var entry = table.registry.entries[id]
        entry.resizeOp(entry.rawPointer, table.blockCount+1)
        entry.newBlockAtOp(entry.rawPointer, table.blockCount)

      table.blockCount += 1
      table.entities.setLen((table.blockCount+1)*DEFAULT_BLK_SIZE)

    var zone = addr newPartition.zones[nfil]
    let r = zone.r.e..<min(zone.r.e+m,DEFAULT_BLK_SIZE)
    zone.r.e = r.b+1
    let bid = zone.block_idx.uint

    nfil += 1*(r.b == DEFAULT_BLK_SIZE-1).int

    for i in r:
      toAdd.add((bid shl BLK_SHIFT) or i.uint)

    m -= r.b - r.a + 1

  newPartition.fill_index = nfil

  if oldComponents.len < newComponents.len:
    for id in oldComponents:
      var entry = table.registry.entries[id]
      var ents = addr table.entities
      entry.overrideValsBatchOp(entry.rawPointer, newArch.id, ents, ids, toSwap, toAdd)
  else:
    for id in newComponents:
      var entry = table.registry.entries[id]
      var ents = addr table.entities
      entry.overrideValsBatchOp(entry.rawPointer, newArch.id, ents, ids, toSwap, toAdd)

include "query.nim"
include "operations.nim"