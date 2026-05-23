

macro createTEntity*(world: ECSWorld, comps: varargs[typed]): untyped =
  ## Determine mask and archetype ID at compile time.
  var ids: seq[int]
  for c in comps:
    ids.add getComponentIdFromRegistry(c)
    for req in getRequiredComps(getComponentIdFromRegistry(c)):
      if req notin ids: ids.add req

  let (mask, archIdCT) = toArchetypeIDC(ids)

  ## Build component-registration stmts.
  var regis = newNimNode(nnkStmtList)
  for c in comps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  ## Emit typed handle with the mask baked in as a type parameter.
  return quote("@") do:
    block:
      `@regis`
      ## Arch ID is a compile-time constant; no graph walk at runtime.
      const arch: uint16 = `@archIdCT`

      let pid = getStableEntity(`@world`)
      let (bid, id) = allocateEntity(`@world`, arch, `@comps`)
      let idx = id.uint mod DEFAULT_BLK_SIZE + bid * DEFAULT_BLK_SIZE

      var e = addr `@world`.entities[pid]
      `@world`.handles[idx] = pid
      e.id = makeId(bid, id)
      e.archetypeId = arch

      ## Return a TDHandle with the mask encoded in the type.
      TDHandle[`@mask`](
        world: `@world`,
        widx:  pid,
        gen:   `@world`.generations[pid]
      )

## Create `n` dense entities with a statically known archetype.  Returns
## `seq[TDHandle[S]]`.  Batch-allocation logic is identical to `createEntities`
## but the archetype lookup is a compile-time constant.
macro createTEntities*(world: ECSWorld, n: typed, comps: varargs[typed]): untyped =
  var ids: seq[int]
  for c in comps:
    ids.add getComponentIdFromRegistry(c)
    for req in getRequiredComps(getComponentIdFromRegistry(c)):
      if req notin ids: ids.add req

  let (mask, archIdCT) = toArchetypeIDC(ids)

  var regis = newNimNode(nnkStmtList)
  for c in comps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  return quote("@") do:
    block:
      `@regis`
      const arch: uint16 = `@archIdCT`

      var rest = newSeq[TDHandle[`@mask`]](`@n`)
      let pids = getStableEntities(`@world`, `@n`)
      let res  = allocateEntities(`@world`, `@n`, arch, `@comps`)
      var current = 0

      for (bid, r) in res:
        for id in r.s..<r.e:
          let pid = pids[current]
          let idx = id.uint mod DEFAULT_BLK_SIZE + bid * DEFAULT_BLK_SIZE
          var e = addr `@world`.entities[pid]
          `@world`.handles[idx] = pid
          e.id = makeId(bid, id)
          e.archetypeId = arch
          rest[current] = TDHandle[`@mask`](
            world: `@world`,
            widx:  pid,
            gen:   `@world`.generations[pid]
          )
          inc current

      rest

####################################################################################################################################################
########################################################## TYPED SPARSE CREATION ###################################################################
####################################################################################################################################################

## Create a single sparse entity with a statically known archetype.
macro createTSparseEntity*(world: ECSWorld, comps: varargs[typed]): untyped =
  var ids: seq[int]
  for c in comps:
    ids.add getComponentIdFromRegistry(c)
    for req in getRequiredComps(getComponentIdFromRegistry(c)):
      if req notin ids: ids.add req

  let (mask, archIdCT) = toArchetypeIDC(ids)

  var regis = newNimNode(nnkStmtList)
  for c in comps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  ## Typed activation: one `castTo` per component, no vtable.
  var activateCode = newNimNode(nnkStmtList)
  for c in comps:
    activateCode.add quote("@") do:
      block:
        let rawp = `@world`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(sid)

  return quote("@") do:
    block:
      `@regis`
      const arch: uint16 = `@archIdCT`
      let sid = allocateSparseEntity(`@world`)          ## raw uint id
      let gen = `@world`.sparse_gens[sid].uint32
      `@activateCode`
      TSHandle[`@mask`](id: sid.uint32, meta: (arch.uint32 shl 16) or gen)

## Create `n` sparse entities with a statically known archetype.
macro createTSparseEntities*(world: ECSWorld, n: typed, comps: varargs[typed]): untyped =
  var ids: seq[int]
  for c in comps:
    ids.add getComponentIdFromRegistry(c)
    for req in getRequiredComps(getComponentIdFromRegistry(c)):
      if req notin ids: ids.add req

  let (mask, archIdCT) = toArchetypeIDC(ids)

  var regis = newNimNode(nnkStmtList)
  for c in comps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  ## Batch-typed activation: one castTo per component, one pass per component.
  var activateBatchCode = newNimNode(nnkStmtList)
  for c in comps:
    activateBatchCode.add quote("@") do:
      block:
        let rawp = `@world`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(batchIds)        ## batchIds: seq[uint]

  return quote("@") do:
    block:
      `@regis`
      const arch: uint16 = `@archIdCT`

      let ranges = allocateSparseEntities(`@world`, `@n`)

      ## Collect IDs first (single pass) for batch activation.
      var batchIds = newSeqOfCap[uint](`@n`)
      for r in ranges:
        for i in r.s..<r.e:
          batchIds.add i.uint

      `@activateBatchCode`

      var res = newSeq[TSHandle[`@mask`]](`@n`)
      var current = 0
      for r in ranges:
        for i in r.s..<r.e:
          let gen = `@world`.sparse_gens[i].uint32
          res[current] = TSHandle[`@mask`](
            id:   i.uint32,
            meta: (arch.uint32 shl 16) or gen
          )
          inc current

      res

macro migrateEntity*[S: static ArchetypeMask](
    world:   ECSWorld,
    d:       TDHandle[S],
    NewS: static ArchetypeMask
): untyped =
  let (_, newArchIdCT) = toArchetypeIDC(NewS.getComponents())
  let newArchIdLit = newArchIdCT

  return quote("@") do:
    block:
      const destArch: uint16 = `@newArchIdLit`
      let e = `@d`.obj
      check(`@world`.generations[`@d`.wid] == `@d`.gen,
        "MigrateEntity: stale handle (widx=" & $`@d`.widx & ").")
      checkWarn(destArch != e.archetypeId,
        "MigrateEntity: source and destination archetypes are identical.")

      if destArch != e.archetypeId:
        let (lst, id, bid) = ChangePartition(
          `@world`, `@S`, `@NewS`, e.id, e.archetypeId, destArch
        )
        `@world`.handles[id + bid * DEFAULT_BLK_SIZE] = `@world`.handles[e.id.toIdx]
        let (beid, eid) = e.id.getDenseMeta
        `@world`.handles[eid + beid * DEFAULT_BLK_SIZE] = `@world`.handles[lst]
        `@world`.entities[`@world`.handles[lst]].id = e.id
        e.id = makeId(bid, id)
        e.archetypeId = destArch

      TDHandle[NewS](world: `@world`, widx: `@d`.widx, gen: `@d`.gen)

macro migrateEntity*[S: static ArchetypeMask](
    world: ECSWorld,
    ents:  openArray[TDHandle[S]],
    NewS: static ArchetypeMask
): (seq[uint32], seq[uint32], seq[uint32]) =
  let (_, newArchIdCT) = toArchetypeIDC(NewS.getComponents())
  let newArchIdLit = newArchIdCT

  return quote("@") do:
    block:
      if `@ents`.len == 0:
        (@[], @[], @[])
      else:
        const destArch: uint16 = `@newArchIdLit`
        when not defined(danger):
          let srcArch = `@ents`[0].obj.archetypeId
          for bci in 1..<`@ents`.len:
            check(`@ents`[bci].obj.archetypeId == srcArch,
              "MigrateEntityBatch: mixed-archetype batch at index " & $bci &
              " (expected " & $srcArch & ", got " &
              $`@ents`[bci].obj.archetypeId & ").")
        checkWarn(destArch != `@ents`[0].obj.archetypeId,
          "MigrateEntityBatch: source and destination archetypes are identical — no-op.")
        changePartition(
          `@world`, `@ents`, `@NewS`, `@ents`[0].obj.archetypeId, destArch

macro addComponent*[S: static ArchetypeMask](
    world:    ECSWorld,
    d:        TDHandle[S],
    addComps: varargs[typed]
): untyped =
  
  var newMask = S
  for c in addComps:
    let id = getComponentIdFromRegistry(c)
    newMask = newMask.withComponent(id)
    for rc in getRequiredComps(id):
      newMask.withoutComponentInPlace(rc)

  let (_, newArchIdCT) = toArchetypeIDC(newMask.getComponents())
  let newMaskLit   = newMask
  let newArchIdLit = newArchIdCT

  var regis = newNimNode(nnkStmtList)
  for c in addComps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  return quote("@") do:
    block:
      `@regis`
      const destArch: uint16 = `@newArchIdLit`
      let e = `@d`.obj
      check(`@world`.generations[`@d`.wid] == `@d`.gen,
        "AddComponent: stale handle (widx=" & $`@d`.widx & ").")

      if destArch != e.archetypeId:
        ## Both S and NewS are statically known here — tChangePartitionD
        ## infers oldComps, newComps, and shared entirely from them.
        let (lst, id, bid) = changePartition[](
          `@world`, `@S`, `@newMaskLit`, e.id, e.archetypeId, destArch
        )
        `@world`.handles[id + bid * DEFAULT_BLK_SIZE] = `@world`.handles[e.id.toIdx]
        let (beid, eid) = e.id.getDenseMeta
        `@world`.handles[eid + beid * DEFAULT_BLK_SIZE] = `@world`.handles[lst]
        `@world`.entities[`@world`.handles[lst]].id = e.id
        e.id = makeId(bid, id)
        e.archetypeId = destArch

      TDHandle[`@newMaskLit`](world: `@world`, widx: `@d`.widx, gen: `@d`.gen)

## Remove one or more components from a typed dense handle.
##
## Mirror of `AddComponent` — `NewS` is derived from `S` minus `remComps`,
## all at compile time.  `tChangePartitionD[S, NewS]` handles the vtable-free
## data move.
##
## Returns `TDHandle[NewS]`.
macro removeComponent*[S: static ArchetypeMask](
    world:    ECSWorld,
    d:        TDHandle[S],
    remComps: varargs[typed]
): untyped =
  var newMask = S
  for c in remComps:
    newMask = newMask.withoutComponent(getComponentIdFromRegistry(c))

  let (_, newArchIdCT) = toArchetypeIDC(newMask.getComponents())
  let newMaskLit   = newMask
  let newArchIdLit = newArchIdCT

  return quote("@") do:
    block:
      const destArch: uint16 = `@newArchIdLit`
      let e = `@d`.obj
      check(`@world`.generations[`@d`.wid] == `@d`.gen,
        "RemoveComponent: stale handle (widx=" & $`@d`.widx & ").")

      if destArch != e.archetypeId:
        let (lst, id, bid) = tChangePartitionD[S, `@newMaskLit`](
          `@world`, e.id, e.archetypeId, destArch
        )
        `@world`.handles[id + bid * DEFAULT_BLK_SIZE] = `@world`.handles[e.id.toIdx]
        let (beid, eid) = e.id.getDenseMeta
        `@world`.handles[eid + beid * DEFAULT_BLK_SIZE] = `@world`.handles[lst]
        `@world`.entities[`@world`.handles[lst]].id = e.id
        e.id = makeId(bid, id)
        e.archetypeId = destArch

      TDHandle[`@newMaskLit`](world: `@world`, widx: `@d`.widx, gen: `@d`.gen)

macro addComponent*[S: static ArchetypeMask](
    world:    ECSWorld,
    s:        TSHandle[S],
    addComps: varargs[typed]
): untyped =
  var newMask = S
  for c in addComps:
    let id = getComponentIdFromRegistry(c)
    newMask = newMask.withComponent(id)
    for rc in getRequiredComps(id):
      newMask.withoutComponentInPlace(rc)

  let (_, newArchIdCT) = toArchetypeIDC(newMask.getComponents())
  let newMaskLit   = newMask
  let newArchIdLit = newArchIdCT

  var regis = newNimNode(nnkStmtList)
  for c in addComps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  var activateCode = newNimNode(nnkStmtList)
  for c in addComps:
    activateCode.add quote("@") do:
      block:
        var fr = castTo(`@world`.registry.entries[toComponentId(`@c`)].rawPointer, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(`@s`.id)

  return quote("@") do:
    block:
      `@regis`
      const destArch: uint16 = `@newArchIdLit`
      if destArch != `@s`.archID:
        `@activateCode`
      TSHandle[`@newMaskLit`](id: `@s`.id, meta: (destArch.uint32 shl 16) or `@s`.gen.uint32)

## Remove components from a sparse handle with a statically known mask.
## Deactivation is done via typed `castTo` per removed component (no vtable).
## Returns a `TSHandle[NewMask]`.
macro removeComponent*[S: static ArchetypeMask](
    world:    ECSWorld,
    s:        TSHandle[S],
    remComps: varargs[typed]
): untyped =
  var newMask = S
  for c in remComps:
    newMask.withoutComponentInPlace(getComponentIdFromRegistry(c))

  let (_, newArchIdCT) = toArchetypeIDC(newMask.getComponents())
  let newMaskLit   = newMask
  let newArchIdLit = newArchIdCT

  var deactivateCode = newNimNode(nnkStmtList)
  for c in remComps:
    deactivateCode.add quote("@") do:
      block:
        var fr = castTo(`@world`.registry.entries[toComponentId(`@c`)].rawPointer, `@c`, DEFAULT_BLK_SIZE)
        fr.deactivateSparseBit(`@s`.id)

  return quote("@") do:
    block:
      const destArch: uint16 = `@newArchIdLit`
      if destArch != `@s`.archID:
        `@deactivateCode`
      TSHandle[`@newMaskLit`](id: `@s`.id, meta: (destArch.uint32 shl 16) or `@s`.gen.uint32)

macro deleteEntity*[S: static ArchetypeMask](
    world: ECSWorld,
    d:     TDHandle[S]
): untyped =
  return quote("@") do:
    block:
      check(`@d`.widx < `@world`.entities.len.uint32,
        "tDeleteEntity: handle widx=" & $`@d`.widx & " out of bounds.")
      check(`@world`.generations[`@d`.wid] == `@d`.gen,
        "tDeleteEntity: stale handle (widx=" & $`@d`.widx & ").")

      let e = `@d`.obj
      ## S is statically known here — tDeleteRowS[S] infers the component loop.
      let l = deleteRow(`@world`, S, e.id, e.archetypeId)

      let (bid, id) = e.id.getDenseMeta
      `@world`.handles[id + bid * DEFAULT_BLK_SIZE] = `@world`.handles[l]
      `@world`.entities[`@world`.handles[l]].id = e.id

      `@world`.generations[`@d`.widx] += 1.uint16
      `@world`.free_entities.add(`@d`.widx)

## Delete a typed sparse entity.
##
## Component deactivation is unrolled at compile time from `S` — no vtable,
## no user-supplied component list.
macro deleteEntity*[S: static ArchetypeMask](
    world: ECSWorld,
    s:     TSHandle[S]
): untyped =
  ## Derive component IDs from S at macro-expansion time.
  let compIds = S.getComponents()

  var deactivateCode = newNimNode(nnkStmtList)
  for cid in compIds:
    let cNode = ID_TO_COMPONENT[cid]
    deactivateCode.add quote("@") do:
      block:
        var fr = castTo(`@world`.registry.entries[`@cid`].rawPointer, `@cNode`, DEFAULT_BLK_SIZE)
        fr.deactivateSparseBit(`@s`.id)

  return quote("@") do:
    block:
      `@deactivateCode`
      `@world`.sparse_gens[`@s`.id] += 1