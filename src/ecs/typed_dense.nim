## Internal typed swap-remove inside a single archetype partition.
##
## Everything that `deleteRow` does, but component copies are unrolled at
## compile time from `S` — the static mask already on the handle — so there is
## no `partition.components` iteration and no `overrideValsOp` vtable call.
##
## `i`   — packed entity ID (block<<ID_SHIFT | offset) of the slot to free.
## Returns the flat index of the last slot that was swapped in (identical
## contract to the untyped `deleteRow`).
##
## Not public — called only by `tDeleteEntity` and `tChangePartitionD`.
macro deleteRow(
    table: ECSWorld,
    S: static ArchetypeMask,
    i:     uint32,
): uint =
  ## Derive the component ID list from S at compile time.
  let compIds = S.getComponents()   ## seq[int], evaluated at macro expansion
  let arch = ARCHETYPE_ID_REGISTRY[S]

  ## Emit one typed overrideVals per component in S.
  var swapCode = newNimNode(nnkStmtList)
  for cid in compIds:
    ## We need the NimNode for the type, not the integer.
    ## `ID_TO_COMPONENT` maps compile-time IDs → NimNode (populated by toComponentId).
    let cNode = ID_TO_COMPONENT[cid]
    swapCode.add quote("@") do:
      block:
        var fr = castTo(`@table`.registry.entries[`@cid`].rawPointer, `@cNode`, DEFAULT_BLK_SIZE)
        fr.overrideVals(i, lid)   ## `lid` bound in the outer quote below

  return quote("@") do:
    block:
      check(`@arch`.int < `@table`.archGraph.nodes.len,
        "tDeleteRow: archetypeId=" & $`@arch` & " out of bounds.")
      let partition = `@table`.archGraph.nodes[`@arch`].partition
      check(not partition.isNil,
        "tDeleteRow: archetype " & $`@arch` & " has no partition.")

      if partition.zones.len <= partition.fill_index or
          isEmpty(addr partition.zones[partition.fill_index]):
        check(partition.fill_index > 0,
          "tDeleteRow: fill_index would underflow for archetype " & $`@arch` & ".")
        partition.fill_index -= 1

      let zone = addr partition.zones[partition.fill_index]
      check(zone.r.e > 0,
        "tDeleteRow: active zone is empty for archetype " & $`@arch` & ".")

      let last = zone.r.e - 1
      let bid  = zone.block_idx.uint
      let lid  = makeId(bid, last)   ## packed ID of the last live slot

      if lid != `@i`:
        `@swapCode`

      zone.r.e -= 1
      last.uint + bid * DEFAULT_BLK_SIZE

####################################################################################################################################################
################################################ TYPED DENSE changePartition (single) ##############################################################
####################################################################################################################################################

## Internal fully-typed single-entity partition migration.
##
## `OldS` and `NewS` are the static masks of the source and destination
## archetypes respectively — both known at the call site without the user
## ever spelling them out.  The macro derives from them:
##
##   • oldComps  = OldS.getComponents()   → swap-remove loop
##   • newComps  = NewS.getComponents()   → newBlockAt loop
##   • shared    = OldS ∩ NewS            → data-copy loop
##
## Returns `(lastFlatIdx, newOffset, newBlockId)`.
macro ChangePartition(
    table:   ECSWorld,
    OldS: static ArchetypeMask,
    NewS: static ArchetypeMask,
    i:       uint32,
): (int, uint, uint) =

  let oldArch = ARCHETYPE_ID_REGISTRY[OldS]
  let newArch = ARCHETYPE_ID_REGISTRY[NewS]
  let oldIds    = OldS.getComponents()
  let newIds    = NewS.getComponents()
  let sharedIds = block:
    var s: seq[int]
    for id in oldIds:
      if NewS.hasComponent(id): s.add id
    s

  var copyCode = newNimNode(nnkStmtList)
  for cid in sharedIds:
    let cNode = ID_TO_COMPONENT[cid]
    copyCode.add quote("@") do:
      block:
        var fr = castTo(`@table`.registry.entries[`@cid`].rawPointer, `@cNode`, DEFAULT_BLK_SIZE)
        fr.overrideVals(destBase, `@i`)

  var swapCode = newNimNode(nnkStmtList)
  for cid in oldIds:
    let cNode = ID_TO_COMPONENT[cid]
    swapCode.add quote("@") do:
      block:
        var fr = castTo(`@table`.registry.entries[`@cid`].rawPointer, `@cNode`, DEFAULT_BLK_SIZE)
        fr.overrideVals(`@i`, makeId(blast, last))

  var newBlockCode = newNimNode(nnkStmtList)
  for cid in newIds:
    if not OldS.hasComponent(cid):
      let cNode = ID_TO_COMPONENT[cid]
      newBlockCode.add quote("@") do:
        block:
          var fr = castTo(`@table`.registry.entries[`@cid`].rawPointer, `@cNode`, DEFAULT_BLK_SIZE)
          fr.newBlockAt(`@table`.blockCount)

  return quote("@") do:
    block:
      check(`@oldArch`.int < `@table`.archGraph.nodes.len,
        "tChangePartition: source archetypeId=" & $`@oldArch` & " out of bounds.")

      let oldPartition = `@table`.archGraph.nodes[`@oldArch`].partition
      check(not oldPartition.isNil,
        "tChangePartition: source archetype " & $`@oldArch` & " has no partition.")
      let newPartition = createPartition(`@table`, `@newArch`)

      if oldPartition.zones.len <= oldPartition.fill_index or
          isEmpty(oldPartition.zones[oldPartition.fill_index]):
        check(oldPartition.fill_index > 0,
          "tChangePartition: source fill_index would underflow.")
        oldPartition.fill_index -= 1

      let oldZone = addr oldPartition.zones[oldPartition.fill_index]
      let last    = oldZone.r.e - 1
      let blast   = oldZone.block_idx
      oldZone.r.e -= 1

      if newPartition.zones.len <= newPartition.fill_index:
        let fi = newPartition.fill_index
        newPartition.zones.setLen(fi + 1)
        let nz = addr newPartition.zones[fi]
        nz.block_idx = `@table`.blockCount
        nz.r.s = 0
        nz.r.e = 0
        `@newBlockCode`
        `@table`.blockCount += 1
        `@table`.handles.setLen(`@table`.blockCount * DEFAULT_BLK_SIZE)

      let newZone  = addr newPartition.zones[newPartition.fill_index]
      let new_id   = newZone.r.e.uint
      let bid      = newZone.block_idx.uint
      let destBase = makeId(bid, new_id)

      `@copyCode`

      if (`@i` and ID_MASK.uint32) != last.uint32:
        `@swapCode`

      newZone.r.e += 1
      if isFull(newZone):
        newPartition.fill_index += 1

      (last + blast * DEFAULT_BLK_SIZE, new_id, bid)

macro ChangePartition[OldS: static ArchetypeMask](
    table:   ECSWorld,
    ents:    openArray[TDHandle[OldS]],
    NewS: static ArchetypeMask,
    oldArch: uint16,
    newArch: uint16
): (seq[uint32], seq[uint32], seq[uint32]) =
 
  let oldIds    = OldS.getComponents()
  let newIds    = NewS.getComponents()
  let sharedIds = block:
    var s: seq[int]
    for id in oldIds:
      if NewS.hasComponent(id): s.add id
    s
 
  var newBlockCode = newNimNode(nnkStmtList)
  for cid in newIds:
    if not OldS.hasComponent(cid):
      let cNode = ID_TO_COMPONENT[cid]
      newBlockCode.add quote("@") do:
        block:
          var fr = castTo(`@table`.registry.entries[`@cid`].rawPointer, `@cNode`, DEFAULT_BLK_SIZE)
          fr.newBlockAt(`@table`.blockCount)
 
  var batchCopyCode = newNimNode(nnkStmtList)
  for cid in sharedIds:
    let cNode = ID_TO_COMPONENT[cid]
    batchCopyCode.add quote("@") do:
      block:
        var fr = castTo(`@table`.registry.entries[`@cid`].rawPointer, `@cNode`, DEFAULT_BLK_SIZE)
        fr.overrideValsBatch(eids, toSwap, toAdd)
 
  return quote("@") do:
    block:
      check(`@ents`.len > 0, "tChangePartitionBatchD: empty entity batch.")
 
      let oldPartition = `@table`.archGraph.nodes[`@oldArch`].partition
      check(not oldPartition.isNil,
        "tChangePartitionBatchD: source archetype " & $`@oldArch` & " has no partition.")
      let newPartition = createPartition(`@table`, `@newArch`)
 
      var toSwap = newSeq[uint32](`@ents`.len)
      var m      = `@ents`.len
      var ofil   = oldPartition.fill_index
 
      if oldPartition.zones.len <= ofil or isEmpty(addr oldPartition.zones[ofil]):
        check(ofil > 0,
          "tChangePartitionBatchD: source partition underflow — batch larger than partition.")
        ofil -= 1
 
      var c = 0
      while c < `@ents`.len:
        check(ofil >= 0,
          "tChangePartitionBatchD: source partition exhausted before batch complete.")
        let zone = addr oldPartition.zones[ofil]
        let lo   = max(0, zone.r.e - m)
        let bid  = zone.block_idx.uint
 
        for i in lo..<zone.r.e:
          toSwap[c] = makeId(bid, i)
          inc c
 
        m -= zone.r.e - lo
        zone.r.e = lo
        if m > 0: ofil -= 1
 
      oldPartition.fill_index = ofil
 
      var toAdd = newSeq[uint32](`@ents`.len)
      var nfil  = newPartition.fill_index
      m = `@ents`.len
      c = 0
 
      while c < `@ents`.len:
        if nfil >= newPartition.zones.len:
          newPartition.zones.setLen(nfil + 1)
          newPartition.zones[nfil].block_idx = `@table`.blockCount
          newPartition.zones[nfil].r.s = 0
          newPartition.zones[nfil].r.e = 0
          `@newBlockCode`
          `@table`.blockCount += 1
          `@table`.handles.setLen((`@table`.blockCount + 1) * DEFAULT_BLK_SIZE)
 
        let zone = addr newPartition.zones[nfil]
        let lo   = zone.r.e
        let hi   = min(lo + m, DEFAULT_BLK_SIZE)
        let bid  = zone.block_idx.uint
 
        for i in lo..<hi:
          toAdd[c] = makeId(bid, i)
          inc c
 
        m -= hi - lo
        zone.r.e = hi
        if hi == DEFAULT_BLK_SIZE: nfil += 1
 
      newPartition.fill_index = nfil
 
      var eids = newSeq[uint32](`@ents`.len)
 
      for idx in 0..<`@ents`.len:
        let h  = `@ents`[idx]
        check(not h.obj.isNil,   "tChangePartitionBatchD: nil entity pointer.")
        check(h.gen == `@table`.generations[h.widx],
          "tChangePartitionBatchD: stale handle (widx=" & $h.widx & ").")
 
        let e     = h.obj
        let swap  = toSwap[idx]
        let add   = toAdd[idx]
 
        eids[idx] = e.id
 
        `@table`.handles[add.toIdx]  = h.widx
        `@table`.handles[e.id.toIdx] = `@table`.handles[swap.toIdx]
        `@table`.entities[`@table`.handles[swap.toIdx]].id = e.id
 
        e.id          = add
        e.archetypeId = `@newArch`
 
      `@batchCopyCode`
 
      (eids, toSwap, toAdd)