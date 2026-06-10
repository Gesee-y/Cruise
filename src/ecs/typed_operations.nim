

macro createTEntity*(world: ECSWorld, comps: varargs[typed]): untyped =
  ## Construct a new typed entity
  ## Those entities entirely bypass vtable which allows faster operation
  # Determine mask and archetype ID at compile time.
  var ids: seq[int]
  var create = newNimNode(nnkCall)
  create.add(ident "createEntity")
  create.add world
  
  for c in comps:
    create.add c
    ids.add getComponentIdFromRegistry(c)
    for req in getRequiredComps(getComponentIdFromRegistry(c)):
      if req notin ids: ids.add req

  let (mask, archIdCT) = toArchetypeIDC(ids)

  return quote("@") do:
    let d = `@create`
    TDHandle[`@mask`](d)

macro createTEntities*(world: ECSWorld, n: typed, comps: varargs[typed]): untyped =
  ## Create `n` dense entities with a statically known archetype.  Returns
  ## `seq[TDHandle[S]]`.  Batch-allocation logic is identical to `createEntities`
  ## but the archetype lookup is a compile-time constant.
  var ids: seq[int]
  var create = newNimNode(nnkCall)
  create.add(ident "createEntities")
  create.add world
  create.add n
  for c in comps:
    create.add c
    ids.add getComponentIdFromRegistry(c)
    for req in getRequiredComps(getComponentIdFromRegistry(c)):
      if req notin ids: ids.add req

  let (mask, archIdCT) = toArchetypeIDC(ids)

  return quote("@") do:
    let ents = `@create`
    cast[seq[TDHandle[`@mask`]]](ents)
    

# ################################################################################################################################################## #
# ######################################################### TYPED SPARSE CREATION ################################################################## #
# ################################################################################################################################################## #

macro createTSparseEntity*(world: ECSWorld, comps: varargs[typed]): untyped =
  ## Create a single sparse entity with a statically known archetype.
  var ids: seq[int]
  var create = newNimNode(nnkCall)
  create.add(ident "createSparseEntity")
  create.add world
  for c in comps:
    create.add c
    ids.add getComponentIdFromRegistry(c)
    for req in getRequiredComps(getComponentIdFromRegistry(c)):
      if req notin ids: ids.add req

  let (mask, archIdCT) = toArchetypeIDC(ids)

  return quote("@") do:
    block:
      let s = `@create`
      TSHandle[`@mask`](s)

macro createTSparseEntities*(world: ECSWorld, n: typed, comps: varargs[typed]): untyped =
  ## Create `n` sparse entities with a statically known archetype.
  var ids: seq[int]
  var create = newNimNode(nnkCall)
  create.add(ident "createSparseEntities")
  create.add world
  create.add n
  for c in comps:
    create.add c
    ids.add getComponentIdFromRegistry(c)
    for req in getRequiredComps(getComponentIdFromRegistry(c)):
      if req notin ids: ids.add req

  let (mask, archIdCT) = toArchetypeIDC(ids)

  return quote("@") do:
    let s = `@create`
    cast[seq[TSHandle[`@mask`]]](s)

macro migrateEntity*[S: static ArchetypeMask](
    world:   ECSWorld,
    d:       TDHandle[S],
    NewS: static ArchetypeMask
): untyped =
  ## Move an entity from an archetype to another
  ## It Use the mask of the destination archetype
  ## Example:
  ## ```nim
  ## world.migrateEntity(d, maskOf(Position, Velocity, ...))
  ## ```
  let (_, newArchIdCT) = toArchetypeIDC(NewS.getComponents())
  let newArchIdLit = newArchIdCT.uint16

  return quote("@") do:
    block:
      let destArch: uint16 = `@world`.archGraph.findArchetype(`@NewS`)
      let e = `@d`.obj
      check(`@world`.generations[`@d`.wid] == `@d`.gen,
        "MigrateEntity: stale handle (widx=" & $`@d`.wid & ").")
      checkWarn(destArch != e.archetypeId,
        "MigrateEntity: source and destination archetypes are identical.")

      if destArch != e.archetypeId:
        let (lst, id, bid) = changePartition(`@world`, `@S`, `@NewS`, e.id)
        `@world`.handles[id + bid * DEFAULT_BLK_SIZE] = `@world`.handles[e.id.toIdx]
        let (beid, eid) = e.id.getDenseMeta
        `@world`.handles[eid + beid * DEFAULT_BLK_SIZE] = `@world`.handles[lst]
        `@world`.entities[`@world`.handles[lst]].id = e.id
        e.id = makeId(bid, id)
        e.archetypeId = destArch

      TDHandle[`@NewS`](DenseHandle(world: `@world`, widx: `@d`.wid, gen: `@d`.gen))

macro migrateEntity*[S: static ArchetypeMask](
    world: ECSWorld,
    ents:  openArray[TDHandle[S]],
    NewS: static ArchetypeMask
): untyped =
  ## Move a sequences of typed entity from an archetype to another
  ## It use the mask of the destination archetype
  ## Example:
  ## ```nim
  ## world.migrateEntity(myTypedEntities, maskOf(Position, Velocity, ...))
  ## ```
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
        changePartition(`@world`, `@ents`, `@NewS`, `@ents`[0].obj.archetypeId, destArch)
        cast[seq[TDHandle[`@NewS`]]](`@ents`)

macro addComponent*[S: static ArchetypeMask](
    world:    ECSWorld,
    d:        TDHandle[S],
    addComps: varargs[untyped]
): untyped =
  ## Add one or more components from a typed dense handle.
  ##
  ## `NewS` is derived from `S` plus `remComps`,
  ## Returns `TDHandle[NewS]`.
  var newComps = S.getComponents
  for c in addComps:
    let id = getComponentIdFromRegistry(c)
    newComps.add(id)
    for rc in getRequiredComps(id):
      newComps.add(rc)
  let newMask = maskOf(newComps) or S

  var regis = newNimNode(nnkStmtList)
  for c in addComps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  return quote("@") do:
    `@regis`
    migrateEntity(`@world`, `@d`, `@newMask`)


macro removeComponent*[S: static ArchetypeMask](
    world:    ECSWorld,
    d:        TDHandle[S],
    remComps: varargs[untyped]
): untyped =
  ## Remove one or more components from a typed dense handle.
  ##
  ## `NewS` is derived from `S` minus `remComps`,
  ## Returns `TDHandle[NewS]`.
  var newComps = S.getComponents
  var newMask = maskOf(newComps)
  for c in remComps:
    let id = getComponentIdFromRegistry(c)
    newMask.withoutComponentInPlace(id)

  return quote("@") do:
    migrateEntity(`@world`, `@d`, `@newMask`)

macro addComponent*[S: static ArchetypeMask](
    world:    ECSWorld,
    s:        TSHandle[S],
    addComps: varargs[typed]
): untyped =
  ## Add one or more components from a typed sparse handle.
  ##
  ## `NewS` is derived from `S` plus `remComps`,
  ## Returns `TSHandle[NewS]`.
  var newComps = S.getComponents
  for c in addComps:
    let id = getComponentIdFromRegistry(c)
    newComps.add(id)
    for rc in getRequiredComps(id):
      newComps.add(rc)
  let newMask = maskOf(newComps) or S
  let (_, newArchIdCT) = toArchetypeIDC(newMask.getComponents())
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

  if newMask == S: return quote("@") do: `@s`
  return quote("@") do:
    `@regis`
    let destArch = `@world`.archGraph.findArchetype(`@newMask`)
    `@activateCode`
    `@world`.sparse_arch[`@s`.id] = destArch
    TSHandle[`@newMask`](`@s`)

macro removeComponent*[S: static ArchetypeMask](
    world:    ECSWorld,
    s:        TSHandle[S],
    remComps: varargs[typed]
): untyped =
  ## Remove components from a sparse handle with a statically known mask.
  ## Returns a `TSHandle[NewMask]`.
  var newComps = S.getComponents
  var newMask = maskOf(newComps)
  for c in remComps:
    let id = getComponentIdFromRegistry(c)
    newMask.withoutComponentInPlace(id)

  let (_, newArchIdCT) = toArchetypeIDC(newMask.getComponents())
  let newArchIdLit = newArchIdCT.uint16

  var deactivateCode = newNimNode(nnkStmtList)
  for c in remComps:
    deactivateCode.add quote("@") do:
      block:
        var fr = castTo(`@world`.registry.entries[toComponentId(`@c`)].rawPointer, `@c`, DEFAULT_BLK_SIZE)
        fr.deactivateSparseBit(`@s`.id)

  if newMask == S: return quote("@") do: `@s` 
  return quote("@") do:
    let destArch: uint16 = `@newArchIdLit`
    `@deactivateCode`
    `@world`.sparse_arch[`@s`.id] = destArch
    TSHandle[`@newMask`](`@s`)

macro deleteEntity*[S: static ArchetypeMask](
    world: ECSWorld,
    d:     TDHandle[S]
): untyped =
  ## Delete a typed dense entity.
  return quote("@") do:
    block:
      check(`@d`.wid < `@world`.entities.len.uint32,
        "tDeleteEntity: handle widx=" & $`@d`.wid & " out of bounds.")
      check(`@world`.generations[`@d`.wid] == `@d`.gen,
        "tDeleteEntity: stale handle (widx=" & $`@d`.wid & ").")

      let e = `@d`.obj
      let l = deleteRow(`@world`, `@S`, e.id)

      let (bid, id) = e.id.getDenseMeta
      `@world`.handles[id + bid * DEFAULT_BLK_SIZE] = `@world`.handles[l]
      `@world`.entities[`@world`.handles[l]].id = e.id

      `@world`.generations[`@d`.wid] += 1.uint16
      `@world`.free_entities.add(`@d`.wid)

macro deleteEntity*[S: static ArchetypeMask](
    world: ECSWorld,
    s:     TSHandle[S]
): untyped =
  ## Delete a typed sparse entity.
  ## Component deactivation is unrolled at compile time from `S` so no vtable,
  let compIds = S.getComponents()

  var deactivateCode = newNimNode(nnkStmtList)
  for cid in compIds:
    let cNode = ID_TO_COMPONENT[cid]
    deactivateCode.add quote("@") do:
      block:
        var fr = castTo(`@world`.registry.entries[`@cid`].rawPointer, typedesc[`@cNode`], DEFAULT_BLK_SIZE)
        fr.deactivateSparseBit(`@s`.id)

  return quote("@") do:
    block:
      `@deactivateCode`
      `@world`.free_list.add(`@s`.id)
      `@world`.sparse_gens[`@s`.id] += 1