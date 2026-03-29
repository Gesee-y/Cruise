#######################################################################################################################################
###################################################### DENSE ECS LOGICS ###############################################################
#######################################################################################################################################

## Ensures that an archetype has an associated table partition.
## If none exists, a new partition is created and attached to the archetype node.
proc createPartition(table: var ECSWorld, arch: ArchetypeNode): TablePartition =
  check(not arch.isNil, "ArchetypeNode must not be nil")
  if arch.partition.isNil:
    var partition: TablePartition
    new(partition)
    partition.components = cast[seq[int]](arch.componentIds)
    arch.partition = partition
  return arch.partition

## Allocates new dense blocks for a partition.
## Each block corresponds to DEFAULT_BLK_SIZE contiguous entity slots.
##
## The resulting ranges describe which block indices and offsets were allocated.
proc allocateNewBlocks(
  table: var ECSWorld,
  count: int,
  res: var seq[(uint, Range)],
  current: int,
  partition: var TablePartition
) =
  
  check(count >= 0, "Allocation count cannot be negative")
  var n = count
  let s = n div DEFAULT_BLK_SIZE
  var bc = table.blockCount
  let pl = partition.zones.len
  var c = current
  
  partition.zones.setLen(pl + s + 1)

  for i in 0..s:
    var trange: TableRange
    let e = min(n, DEFAULT_BLK_SIZE)
    
    ## Register allocated range
    res[c] = ((bc.uint, Range(s: 0, e: e)))
    trange.r.s = 0
    trange.r.e = e
    trange.block_idx = bc
    partition.zones[pl + i] = trange
    
    ## Advance fill index if the block is fully occupied
    if n >= DEFAULT_BLK_SIZE:
      partition.fill_index += 1

    ## Materialize the new block for each component in the partition
    for id in partition.components:
      check(id < table.registry.entries.len, "Component ID out of registry bounds")
      let entry = table.registry.entries[id]
      entry.newBlockAtOp(entry.rawPointer, bc)

    table.blockCount += 1
    n -= DEFAULT_BLK_SIZE
    inc bc
    inc c

  table.handles.setLen((table.blockCount + 1) * DEFAULT_BLK_SIZE)

## Allocates `n` entities for a given archetype node.
## Reuses partially-filled blocks before allocating new ones.
proc allocateEntities(
  table: var ECSWorld,
  n: int,
  archNode: ArchetypeNode
): seq[(uint, Range)] =
  check(not archNode.isNil, "ArchetypeNode is nil during entity allocation")
  var res = newSeq[(uint, Range)](n div DEFAULT_BLK_SIZE + 1)

  ## First allocation for this archetype
  if archNode.partition.isNil:
    var partition = createPartition(table, archNode)
    allocateNewBlocks(table, n, res, 0, partition)
    return res

  var m = n
  var partition = archNode.partition
  var current = 0

  ## Fill existing blocks
  while m > 0 and partition.fill_index < partition.zones.len:
    let id = partition.zones[partition.fill_index].block_idx
    let e = partition.zones[partition.fill_index].r.e
    let r = min(e + m, DEFAULT_BLK_SIZE)

    partition.zones[partition.fill_index].r.e = r
    res[current] = ((id.uint, Range(s: e, e: r)))
    
    if r >= DEFAULT_BLK_SIZE:
      partition.fill_index += 1

    m -= r - e
    current += 1

  ## Allocate new blocks if necessary
  if m > 0:
    allocateNewBlocks(table, m, res, current, partition)

  return res

## Allocates multiple entities using an archetype mask.
## Fast-path through archetype graph lookup.
proc allocateEntities(
  table: var ECSWorld,
  n: int,
  arch: ArchetypeMask
): seq[(uint, Range)] =
  let archNode = table.archGraph.findArchetypeFast(arch)
  return allocateEntities(table, n, archNode)

## Allocates a single dense entity and returns:
## (block index, offset inside block, archetype id)
template allocateEntity(
  table: var ECSWorld,
  archNode: var ArchetypeNode
): (uint, int, uint16) =

  var partition = createPartition(table, archNode)
  var fill_index = partition.fill_index

  ## Allocate a new block if required
  if fill_index >= partition.zones.len:
    partition.zones.setLen(fill_index + 1)

    for id in partition.components:
      check(id < table.registry.entries.len, "Invalid component ID")
      let entry = table.registry.entries[id]
      entry.newBlockAtOp(entry.rawPointer, table.blockCount)

    partition.zones[fill_index].block_idx = table.blockCount
    table.blockCount += 1
    table.handles.setLen((table.blockCount + 1) * DEFAULT_BLK_SIZE)

  var zone = addr partition.zones[fill_index]
  let id = zone.block_idx
  let e = zone.r.e

  zone.r.e += 1
    
  if isFull(zone):
    partition.fill_index += 1

  (id.uint, e, archNode.id)

## Allocates a single dense entity and returns:
## (block index, offset inside block, archetype id)
proc allocateEntity(
  table: var ECSWorld,
  arch: ArchetypeMask
): (uint, int, uint16) =
  var archNode = table.archGraph.findArchetypeFast(arch)
  check(not archNode.isNil, "ArchetypeNode not found")

  return allocateEntity(table, archNode)

## Deletes a dense entity row.
## Performs swap-remove within the archetype partition.
template deleteRow(table: var ECSWorld, i: uint, arch: uint16): uint =
  check(arch.int < table.archGraph.nodes.len, "Archetype ID out of bounds")
  let partition = addr table.archGraph.nodes[arch].partition
  
  if partition.zones.len <= partition.fill_index or
     isEmpty(addr partition.zones[partition.fill_index]):
    partition.fill_index -= 1

  let zone = addr partition.zones[partition.fill_index]

  let last = zone.r.e - 1
  let bid = zone.block_idx.uint
  let lid = makeId(last, bid)

  ## Move last entity into the deleted slot
  if lid != i:
    for id in partition.components:
      let entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, i, lid)

  zone.r.e -= 1
  last.uint + bid * DEFAULT_BLK_SIZE

## Moves a single entity from one archetype partition to another.
## Returns:
## (old swapped entity id, new offset, new block id)
template changePartition(
  table: var ECSWorld,
  i: uint,
  oldArch: uint16,
  newArch: ArchetypeNode
): (int, uint, uint) =
  check(oldArch.int < table.archGraph.nodes.len, "Old archetype ID out of bounds")
  check(not newArch.isNil, "Target ArchetypeNode is nil")
  
  let oldPartition = addr table.archGraph.nodes[oldArch].partition
  let newPartition = createPartition(table, newArch)
  let oldComponents = addr oldPartition.components

  ## Remove entity from old partition
  if oldPartition.zones.len <= oldPartition.fill_index or
     isEmpty(oldPartition.zones[oldPartition.fill_index]):
    oldPartition.fill_index -= 1

  check(oldPartition.fill_index >= 0, "Source partition underflow during move")
  let oldZone = addr oldPartition.zones[oldPartition.fill_index]
  let last = oldZone.r.e - 1
  let blast = oldZone.block_idx

  oldZone.r.e -= 1

  ## Ensure destination has space
  if newPartition.zones.len <= newPartition.fill_index:
    let fi = newPartition.fill_index
    newPartition.zones.setLen(fi + 1)
    let bc = table.blockCount
    let nZone = addr newPartition.zones[fi]
    nZone.block_idx = bc
    nZone.r.s = 0
    nZone.r.e = 0

    for id in newPartition.components:
      let entry = table.registry.entries[id]
      entry.newBlockAtOp(entry.rawPointer, table.blockCount)

    table.blockCount += 1
    table.handles.setLen((table.blockCount) * DEFAULT_BLK_SIZE)

  let newZone = addr newPartition.zones[newPartition.fill_index]
  let new_id = newZone.r.e.uint
  let bid = newZone.block_idx.uint

  ## Copy only components common to both old and new archetypes
  let oldNode = addr table.archGraph.nodes[oldArch]
  let oldMask = addr oldNode.mask
  let newMask = addr newArch.mask
  let intersection = oldMask and newMask
  let destBase = (bid shl BLK_SHIFT) or new_id

  if intersection == oldMask:
    # Fast Path: New archetype contains all old components (e.g. addComponent)
    for id in oldNode.componentIds:
      let entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, destBase, i.uint)
  elif intersection == newMask:
    # Fast Path: Old archetype contains all new components (e.g. removeComponent)
    for id in newArch.componentIds:
      let entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, destBase, i.uint)
  else:
    # Slow Path: Partial intersection (unlikely for direct edges)
    for id in oldNode.componentIds:
      if newMask.hasComponent(id):
        let entry = table.registry.entries[id]
        entry.overrideValsOp(entry.rawPointer, destBase, i.uint)

  ## Fix swap-remove in source partition
  if (i and BLK_MASK).int != last:
    for id in oldNode.componentIds:
      let entry = table.registry.entries[id]
      entry.overrideValsOp(
        entry.rawPointer,
        i.uint,
        (blast.uint shl BLK_SHIFT) or last.uint
      )
  
  newZone.r.e += 1
  if isFull(newZone):
    newPartition.fill_index += 1

  (last + blast * DEFAULT_BLK_SIZE, new_id, bid)

## Batch archetype migration for dense entities.
## Moves multiple entities while minimizing component copies.
template changePartition(
  table: var ECSWorld,
  ids: var openArray[DenseHandle],
  oldArch: uint16,
  newArch: ArchetypeNode
):(seq[uint], seq[uint]) =
  check(ids.len > 0, "Batch change with empty handles")

  let oldPartition = table.archGraph.nodes[oldArch].partition
  let newPartition = createPartition(table, newArch)

  if oldPartition.zones.len <= oldPartition.fill_index:
    oldPartition.fill_index -= 1

  var m = ids.len
  var ofil = oldPartition.fill_index
  var c = 0
  var toSwap = newSeq[uint](m)
  var toAdd  = newSeq[uint](m)
  
  ## Collect entities to remove from old partition
  while toSwap.len < ids.len:
    check(ofil >= 0, "Source partition underflow during batch move")
    let zone = addr oldPartition.zones[ofil]
    let r = max(0, zone.r.e - m) ..< zone.r.e
    let bid = zone.block_idx.uint

    m -= r.b - r.a + 1

    for i in r:
      toSwap[c] = ((bid shl BLK_SHIFT) or i.uint)
      inc c

    zone.r.e = r.a
    ofil -= 1 * (r.a == 0 and toSwap.len < ids.len).int

  oldPartition.fill_index = ofil

  ## Allocate destination slots
  var nfil = newPartition.fill_index
  m = ids.len
  c = 0

  while toAdd.len < ids.len:
    if nfil >= newPartition.zones.len:
      newPartition.zones.setLen(nfil + 1)
      newPartition.zones[nfil].block_idx = table.blockCount

      for id in newPartition.components:
        let entry = table.registry.entries[id]
        entry.newBlockAtOp(entry.rawPointer, table.blockCount)

      table.blockCount += 1
      table.handles.setLen((table.blockCount + 1) * DEFAULT_BLK_SIZE)

    let zone = addr newPartition.zones[nfil]
    let r = zone.r.e ..< min(zone.r.e + m, DEFAULT_BLK_SIZE)
    zone.r.e = r.b + 1
    let bid = zone.block_idx.uint

    nfil += 1 * (r.b == DEFAULT_BLK_SIZE - 1).int

    for i in r:
      toAdd[c] = ((bid shl BLK_SHIFT) or i.uint)
      inc c

    m -= r.b - r.a + 1

  newPartition.fill_index = nfil

  ## Safety checks before raw pointer operations
  for h in ids:
    check(not h.obj.isNil, "DenseHandle contains nil entity pointer.")
    check(h.gen == table.generations[h.obj.widx], "DenseHandle contains stale handle.")

  ## Perform batched component migration (only common components)
  let oldMask = addr table.archGraph.nodes[oldArch].mask
  let commonMask = oldMask and (addr newArch.mask)
  let commonComponents = commonMask.getComponents()
  for id in commonComponents:
    let entry = table.registry.entries[id]
    let ents = addr table.handles
    entry.overrideValsBatchOp(entry.rawPointer, newArch.id, ents, ids, toSwap, toAdd)

  for i in 0..<ids.len:
    var e = ids[i].obj
    let s = toSwap[i]
    let a = toAdd[i]
    
    table.handles[a.toIdx] = e
    table.handles[e.id.toIdx] = table.handles[s.toIdx]
    table.handles[s.toIdx].id = e.id

    e.id = a
    e.archetypeId = newArch.id

  (toSwap, toAdd)
