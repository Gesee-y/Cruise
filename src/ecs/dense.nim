#######################################################################################################################################
###################################################### DENSE ECS LOGICS ###############################################################
#######################################################################################################################################

proc createPartition(table: var ECSWorld, arch: ArchetypeNode): TablePartition =
  check(not arch.isNil, "ArchetypeNode must not be nil")
  if arch.partition.isNil:
    var partition: TablePartition
    new(partition)
    partition.components = cast[seq[int]](arch.componentIds)
    arch.partition = partition
  return arch.partition

proc allocateNewBlocks(table: var ECSWorld, count: int, res: var seq[(uint, Range)], 
  partition: var TablePartition, components: seq[int]): seq[(uint, Range)] =
  
  check(count >= 0, "Allocation count cannot be negative")
  var n = count
  let s = n div DEFAULT_BLK_SIZE
  var bc = table.blockCount
  let pl = partition.zones.len
  
  partition.zones.setLen(pl + s + 1)
  upsize(table, s + 1)

  for i in 0..s:
    var trange: TableRange
    let e = min(n, DEFAULT_BLK_SIZE)
    
    res.add((bc.uint, Range(s:0, e:e)))
    trange.r.s = 0
    trange.r.e = e
    trange.block_idx = bc
    partition.zones[pl+i] = trange
    
    if n >= DEFAULT_BLK_SIZE:
      partition.fill_index += 1

    for id in components:
      check(id < table.registry.entries.len, "Component ID out of registry bounds")
      var entry = table.registry.entries[id]
      entry.newBlockAtOp(entry.rawPointer, bc)

    table.blockCount += 1
    n -= DEFAULT_BLK_SIZE
    inc bc

  table.handles.setLen((table.blockCount + 1) * DEFAULT_BLK_SIZE)
  return res

proc allocateEntities(table: var ECSWorld, n: int, archNode: ArchetypeNode, components: seq[int]): seq[(uint, Range)] =
  check(not archNode.isNil, "ArchetypeNode is nil during entity allocation")
  var res: seq[(uint, Range)]

  if archNode.partition.isNil:
    var partition: TablePartition
    new(partition)
    partition.components = components
    archNode.partition = partition
    return allocateNewBlocks(table, n, res, partition, components)

  var m = n
  var partition = archNode.partition

  while m > 0 and partition.fill_index < partition.zones.len:
    let id = partition.zones[partition.fill_index].block_idx
    let e = partition.zones[partition.fill_index].r.e
    let r = min(e + m, DEFAULT_BLK_SIZE)

    partition.zones[partition.fill_index].r.e = r
    res.add((id.uint, Range(s:e, e:r)))
    
    if r >= DEFAULT_BLK_SIZE:
      partition.fill_index += 1

    m -= r - e

  if m > 0:
    discard allocateNewBlocks(table, m, res, partition, components)

  return res

proc allocateEntities(table: var ECSWorld, n: int, arch: ArchetypeMask, components: seq[int]): seq[(uint, Range)] =
  var archNode = table.archGraph.findArchetypeFast(arch)
  return allocateEntities(table, n, archNode, components)

proc allocateEntities(table: var ECSWorld, n: int, arch: ArchetypeMask): seq[(uint, Range)] =
  allocateEntities(table, n, arch, getComponentsFromSig(arch))

proc allocateEntity(table: var ECSWorld, arch: ArchetypeMask, components: seq[int]): (uint, int, uint16) =
  var archNode = table.archGraph.findArchetypeFast(arch)
  check(not archNode.isNil, "ArchetypeNode not found")

  if archNode.partition.isNil:
    var partition: TablePartition
    new(partition)
    partition.components = components
    archNode.partition = partition
  
  var partition = archNode.partition
  var fill_index = partition.fill_index

  if fill_index >= partition.zones.len:
    partition.zones.setLen(fill_index + 1)
    upsize(table, 1)

    for id in components:
      check(id < table.registry.entries.len, "Invalid component ID")
      var entry = table.registry.entries[id]
      entry.newBlockAtOp(entry.rawPointer, table.blockCount)

    partition.zones[fill_index].block_idx = table.blockCount
    table.blockCount += 1
    table.handles.setLen((table.blockCount + 1) * DEFAULT_BLK_SIZE)

  var zone = addr partition.zones[fill_index]
  let id = zone.block_idx
  let e = zone.r.e

  zone.r.e += 1
    
  if isFull(partition.zones[fill_index]):
    partition.fill_index += 1

  return (id.uint, e, archNode.id)

proc deleteRow(table: var ECSWorld, i: uint, arch: uint16): uint =
  check(arch.int < table.archGraph.nodes.len, "Archetype ID out of bounds")
  let archNode = table.archGraph.nodes[arch]
  let partition = archNode.partition
  
  check(not partition.isNil, "Attempting to delete from nil partition")

  if partition.zones.len <= partition.fill_index or isEmpty(partition.zones[partition.fill_index]):
    partition.fill_index -= 1

  check(partition.fill_index >= 0, "Partition index underflow during deletion")
  var zone = addr partition.zones[partition.fill_index]

  let last = zone.r.e - 1
  let bid = zone.block_idx.uint
  let lid = makeId(last, bid)

  if lid != i:
    for id in partition.components:
      var entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, i, lid)

  zone.r.e -= 1
  return last.uint + bid * DEFAULT_BLK_SIZE

proc changePartition(table: var ECSWorld, i: uint, oldArch: uint16, newArch: ArchetypeNode): (int, uint, uint) =
  check(oldArch.int < table.archGraph.nodes.len, "Old archetype ID out of bounds")
  check(not newArch.isNil, "Target ArchetypeNode is nil")
  
  var oldPartition = table.archGraph.nodes[oldArch].partition
  var newPartition = createPartition(table, newArch)
  var oldComponents = oldPartition.components
  var newComponents = newPartition.components

  if oldPartition.zones.len <= oldPartition.fill_index or isEmpty(oldPartition.zones[oldPartition.fill_index]):
    oldPartition.fill_index -= 1

  check(oldPartition.fill_index >= 0, "Source partition underflow during move")
  var oldZone = addr oldPartition.zones[oldPartition.fill_index]
  let last = oldZone.r.e - 1
  let blast = oldZone.block_idx

  oldZone.r.e -= 1

  if newPartition.zones.len <= newPartition.fill_index:
    let fi = newPartition.fill_index
    newPartition.zones.setLen(fi + 1)
    let bc = table.blockCount
    var nZone = addr newPartition.zones[fi]
    nZone.block_idx = bc
    nZone.r.s = 0
    nZone.r.e = 0
    for id in newPartition.components:
      var entry = table.registry.entries[id]
      entry.resizeOp(entry.rawPointer, table.blockCount + 1)
      entry.newBlockAtOp(entry.rawPointer, table.blockCount)

    table.blockCount += 1
    table.entities.setLen((table.blockCount + 1) * DEFAULT_BLK_SIZE)

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

  return (last + blast * DEFAULT_BLK_SIZE, new_id, bid)

proc changePartition(table: var ECSWorld, ids: var openArray[DenseHandle], oldArch: uint16, newArch: ArchetypeNode) =
  check(ids.len > 0, "Batch change with empty handles")
  var oldPartition = table.archGraph.nodes[oldArch].partition
  var newPartition = createPartition(table, newArch)
  var oldComponents = oldPartition.components
  var newComponents = newPartition.components

  if oldPartition.zones.len <= oldPartition.fill_index:
    oldPartition.fill_index -= 1

  var m = ids.len
  var ofil = oldPartition.fill_index
  var toSwap = newSeqofCap[uint](m)
  var toAdd = newSeqofCap[uint](m)
  
  while toSwap.len < ids.len:
    check(ofil >= 0, "Source partition underflow during batch move")
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
      newPartition.zones.setLen(nfil + 1)
      newPartition.zones[nfil].block_idx = table.blockCount

      for id in newPartition.components:
        var entry = table.registry.entries[id]
        entry.resizeOp(entry.rawPointer, table.blockCount + 1)
        entry.newBlockAtOp(entry.rawPointer, table.blockCount)

      table.blockCount += 1
      table.handles.setLen((table.blockCount + 1) * DEFAULT_BLK_SIZE)

    var zone = addr newPartition.zones[nfil]
    let r = zone.r.e..<min(zone.r.e + m, DEFAULT_BLK_SIZE)
    zone.r.e = r.b + 1
    let bid = zone.block_idx.uint

    nfil += 1 * (r.b == DEFAULT_BLK_SIZE - 1).int

    for i in r:
      toAdd.add((bid shl BLK_SHIFT) or i.uint)

    m -= r.b - r.a + 1

  newPartition.fill_index = nfil

  # Final safety check before raw pointer operations
  for h in ids: 
    check(not h.obj.isNil, "DenseHandle contains nil entity pointer.")
    check(h.gen == table.generations[h.obj.widx], "DenseHandle contains stale handles.")

  if oldComponents.len < newComponents.len:
    for id in oldComponents:
      var entry = table.registry.entries[id]
      var ents = addr table.handles
      entry.overrideValsBatchOp(entry.rawPointer, newArch.id, ents, ids, toSwap, toAdd)
  else:
    for id in newComponents:
      var entry = table.registry.entries[id]
      var ents = addr table.handles
      entry.overrideValsBatchOp(entry.rawPointer, newArch.id, ents, ids, toSwap, toAdd)