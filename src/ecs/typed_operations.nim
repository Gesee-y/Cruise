

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
