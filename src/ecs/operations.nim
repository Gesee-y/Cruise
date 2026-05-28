# ################################################################################################################################################# #
# ############################################################ ECS OPERATIONS ##################################################################### #
# ################################################################################################################################################# #

type
  ECSOpCode = enum
    ## Defines the operation codes used for deferred execution within the Command Buffer.
    ## These codes indicate whether a deferred operation is intended to delete an entity
    ## or migrate (move) it to a different archetype.
    DeleteOp = 0
    MigrateOp = 1

# ################################################################################################################################################# #
# ########################################################### DENSE OPERATIONS #################################################################### #
# ################################################################################################################################################# #

macro createEntity*(world: ECSWorld, comps: varargs[typed]): DenseHandle =
  ## Create a new dense entity with the given components (that you enter as types)
  ## Example:
  ## ```nim
  ## world.createEntity(Position, Velocity)
  ## ```
  let enable_event = EVENT_ACTIVE
  var (compIds, components) = getComponentsMetadata(comps)
  var regis = newNimNode(nnkStmtList)
  for c in comps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  return quote("@") do:
    `@regis`
    # Acquire a stable internal ID (widx) for the entity record.
    let pid = getStableEntity(`@world`)
    var arch = `@world`.archGraph.findArchetype(`@compIds`)

    # Allocate actual space for the entity data within the specific archetype.
    # Returns block ID (bid), internal block index (id), and the archetype instance ID (archId).
    let (bid, id) = allocateEntity(`@world`, arch, `@components`)

    # Calculate the flat index into the handles array based on block arithmetic.
    # Combines the block ID and the local ID within the block.
    let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE

    # Retrieve the memory address of the entity record.
    var e = addr `@world`.entities[pid]

    # Map the handle pointer at this index to the entity record.
    # This allows O(1) access from an ID to the entity metadata.
    `@world`.handles[idx] = pid

    # Initialize entity metadata.
    e.id = makeId(bid, id)
    e.archetypeId = arch

    var d = DenseHandle()
    d.widx = pid
    d.gen = `@world`.generations[pid]
    d.world = `@world`
    if `@enable_event`: 
      var ev = `@world`.events
      ev.emitDenseEntityCreated(d)

    d

macro createEntities*(world: ECSWorld, n: untyped, comps: varargs[typed]): seq[DenseHandle] =
  ## Same as `createEntity` but create `n` entities in bulk.
  var (compIds, components) = getComponentsMetadata(comps)
  var regis = newNimNode(nnkStmtList)
  for c in comps:
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)

  return quote("@") do:
    `@regis`
    var rest = newSeq[DenseHandle](`@n`)
    var arch = `@world`.archGraph.findArchetype(`@compIds`)

    # Acquire 'n' stable internal IDs.
    let pids = getStableEntities(`@world`, `@n`)

    # Allocate the block space for 'n' entities.
    # 'res' contains ranges of allocated slots across potentially multiple blocks.
    let res = allocateEntities(`@world`, `@n`, arch, `@components`)
    var current = 0

    # Iterate through the allocation results (Block ID, Range of IDs)
    for (bid, r) in res:
      for id in r.s..<r.e:
        # Setup variables for the current entity being processed.
        let pid = pids[current]
        let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
        var e = addr `@world`.entities[pid]

        # Map handles and initialize metadata similar to single entity creation.
        `@world`.handles[idx] = pid
        e.id = makeID(bid, id)
        e.archetypeId = arch

        # Create the handle with the specific generation for this PID.
        rest[current] = DenseHandle(world: `@world`, widx: pid, gen: `@world`.generations[pid])
        current += 1

    rest

template deleteEntity*(world: var ECSWorld, d: DenseHandle) =
  ## Immediately deletes an entity from the dense storage.
  ##
  ## This operation performs a "swap-and-pop" at the block level to maintain memory contiguity.
  ## The generation counter is incremented to invalidate existing handles (stale references).
  ##
  ## Parameter:
  ## - world: The mutable `ECSWorld` instance.
  ## - d: The `DenseHandle` of the entity to delete.
  check(d.widx < world.entities.len.uint32,
    "deleteEntity: handle widx=" & $d.widx &
    " is out of bounds for entities array (len=" & $world.entities.len &
    "). The DenseHandle is corrupted or belongs to a different ECSWorld.")
  let e = d.obj

  check(world.generations[d.wid] == d.gen,
    "deleteEntity: stale handle detected. Stored gen=" & $world.generations[d.wid] &
    " but handle gen=" & $d.gen & " (widx=" & $d.widx &
    "). Entity was already deleted or the slot was recycled.")

  # Remove the entity's data row from its archetype block.
  # Returns the index of the last row that was swapped into the deleted position ('l').
  let l = deleteRow(world, e.id, e.archetypeId)
  var ev = world.events
  ev.emitDenseEntityDestroyed(d, l, cast[pointer](world))

  # Update the handle lookup table.
  # The handle at the deleted entity's position now points to the entity that was moved.
  let (bid, id) = e.id.getDenseMeta
  world.handles[id + bid*DEFAULT_BLK_SIZE] = world.handles[l]

  # Update the ID of the moved entity so it matches its new memory location.
  world.entities[world.handles[l]].id = e.id

  # Increment the generation to mark the old ID as "dead" and invalidate handles.
  world.generations[d.widx] += 1.uint16

  # Recycle the stable ID (widx) back to the free list.
  world.free_entities.add(d.widx)

## Immediately deletes an entity from the dense storage using a DWEntity.
template deleteEntity*(dw: var DWEntity) =
  deleteEntity(dw.w, dw.handle)

template deleteEntityDefer*(buffer: var ECommandBuffer, d: DenseHandle) =
  ## Defers the deletion of an entity.
  ##
  ## Instead of deleting immediately, the command is pushed to a Command Buffer (`cb`).
  ## This is useful for performing structural changes during iteration where immediate
  ## deletion would invalidate pointers.
  ##
  ## Parameters:
  ## - world: The mutable `ECSWorld` instance.
  ## - d: The `DenseHandle` of the entity to delete.
  ## - buffer_id: The ID of the command buffer to use.
  buffer.addCommand(eckRemEntity, d)

## Defers the deletion of an entity using a DWEntity.
template deleteEntityDefer*(dw: var DWEntity, buffer_id: int) =
  deleteEntityDefer(dw.w, dw.handle, buffer_id)

proc migrateEntity*(world: var ECSWorld, d: DenseHandle, archNode: uint16) =
  ## Immediately migrates an entity to a new archetype (Dense storage).
  ##
  ## Migration is the process of moving an entity from one memory layout (Archetype A) to another
  ## (Archetype B), typically because components were added or removed.
  ##
  ## Parameters:
  ## - world: The mutable `ECSWorld` instance.
  ## - d: The `DenseHandle` of the entity to migrate.
  ## - archNode: The target `ArchetypeNode` (destination archetype).
  check(d.widx < world.entities.len.uint32,
    "migrateEntity: handle widx=" & $d.widx &
    " is out of bounds (entities.len=" & $world.entities.len & ").")
  let e = d.obj
  check(world.generations[d.wid] == d.gen,
    "migrateEntity: stale handle. Stored gen=" & $world.generations[d.wid] &
    " but handle gen=" & $d.gen & " (widx=" & $d.widx & "). Entity already deleted.")
  checkWarn(archNode != e.archetypeId,
    "migrateEntity: target archetype id=" & $archNode &
    " is the same as the current archetype id=" & $e.archetypeId &
    ". Migration is a no-op. Verify addComponent/removeComponent logic.")

  # Only perform migration if the target archetype is different from the current one.
  if archNode != e.archetypeId:
    let oldId = e.id # Keep this for events

    # Move the data.
    # changePartition moves component data from old archetype to new archetype.
    # Returns: index of the swapped-in last element (lst), new ID, new Block ID.
    let (lst, id, bid) = changePartition(world, e.id, e.archetypeId, archNode)

    # Decode the old Entity ID into local indices.
    let (beid, eid) = e.id.getDenseMeta

    # Fix the handle pointers.
    # The handle at the *new* location must point to our entity.
    world.handles[id+bid*DEFAULT_BLK_SIZE] = world.handles[e.id.toIdx]

    # The handle at the *old* location (now occupied by the swapped entity) must point to that entity.
    world.handles[eid+beid*DEFAULT_BLK_SIZE] = world.handles[lst]

    # Update the ID of the swapped entity to reflect its new physical position (the old spot).
    world.entities[world.handles[lst]].id = e.id

    # Update the migrating entity's ID to its new physical position.
    let oldArchId = e.archetypeId
    let newId = makeId(bid, id)
    
    e.id = newId
    e.archetypeId = archNode
    var ev = world.events
    ev.emitDenseEntityMigrated(d, oldId, lst.uint, oldArchId, archNode)

template migrateEntity*(world: var ECSWorld, ents: openArray[DenseHandle],
    archNode: uint16) =
  ## Batch migration for multiple entities (Dense storage).
  ##
  ## Optimizes moving a group of entities to a new archetype.
  ##
  ## Parameters:
  ## - world: The mutable `ECSWorld` instance.
  ## - ents: An open array of `DenseHandle` to migrate.
  ## - archNode: The target `ArchetypeNode`.
  if ents.len != 0:
    # Assume all entities in the batch share the same source archetype.
    let e = ents[0].obj
    let oldArchId = e.archetypeId
    when not defined(release) and not defined(danger):
      for batchCheckIdx in 1..<ents.len:
        let batchEnt = ents[batchCheckIdx].obj
        if not batchEnt.isNil and batchEnt.archetypeId != oldArchId:
          debugEcho "[ECS WARN] migrateEntity batch: entity[" & $batchCheckIdx &
            "] has archetype " & $batchEnt.archetypeId &
            " but entity[0] has archetype " & $oldArchId &
            ". Mixed-archetype batches produce undefined behaviour."
    if archNode != oldArchId:
      # Perform batch partition change.
      let (ids, toSwap, toAdd) = changePartition(world, ents, oldArchId, archNode)
      var ev = world.events
      ev.emitDenseEntityMigratedBatch(ids, toSwap, toAdd, oldArchId, archNode)

## Immediately migrates an entity to a new archetype using a DWEntity.
proc migrateEntity*(dw: var DWEntity, archNode: uint16) =
  migrateEntity(dw.w, dw.handle, archNode)

template migrateEntity*(ents: var openArray[DWEntity],
    archNode: uint16) =
  if ents.len != 0:
    var hnd = newSeq[DenseHandle](ents.len)
    for i in 0..<ents.len:
      hnd[i] = ents[i].handle

    ents[0].w.migrateEntity(hnd, archNode)

template migrateEntityDefer*(buffer: var ECommandBuffer, d: DenseHandle,
    archNode: uint16) =
  ## Defers the migration of an entity.
  ##
  ## Adds a migration command to the Command Buffer to be executed later.
  ##
  ## Parameters:
  ## - world: The mutable `ECSWorld` instance.
  ## - d: The `DenseHandle` of the entity to migrate.
  ## - archNode: The target `ArchetypeNode` id.
  ## - buffer_id: The ID of the command buffer.
  buffer.addCommand(eckRemEntity, d, archNode.)

proc addComponent*(world: var ECSWorld, d: DenseHandle, components: openArray[int]) =
  ## Adds components to an existing entity (Dense storage).
  ##
  ## This effectively changes the entity's archetype, triggering a migration.
  ##
  ## Parameters: 
  ## - world: The mutable `ECSWorld` instance.
  ## - d: The `DenseHandle` of the entity.
  ## - components: Variadic list of Component IDs to add.
  check(components.len > 0,
    "addComponent: component list is empty — no structural change will occur. " &
    "Pass at least one component ID.")
  let e = d.obj
  let oldArch = world.archGraph.nodes[e.archetypeId]
  for cid in components:
    check(cid >= 0 and cid < MAX_COMPONENTS,
      "addComponent: component ID=" & $cid &
      " is out of valid range [0, " & $MAX_COMPONENTS & "). " &
      "Ensure the component is registered before use.")
  var archNode = oldArch.id

  # Traverse the archetype graph, adding components one by one to find the target node.
  for id in components:
    archNode = world.archGraph.addComponent(archNode, id)

  # Perform the migration to the new archetype.
  migrateEntity(world, d, archNode)
  var ev = world.events
  ev.emitDenseComponentAdded(d, components)

macro addComponent*(
  world: var ECSWorld,
  d: DenseHandle,
  addedComps: varargs[typed]
): untyped =
  var addedIds = newNimNode(nnkBracket)
  var regis = newNimNode(nnkStmtList)
  for c in addedComps:
    addedIds.add quote("@") do: toComponentId(`@c`)
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)
  if addedIds.len == 0:
    addedIds = quote("@") do: array[0, int](`@addedIds`)

  return quote("@") do: 
    `@regis`
    let components = `@addedIds`
    check(components.len > 0,
    "addComponent: component list is empty — no structural change will occur. " &
    "Pass at least one component ID.")
    
    let e = `@d`.obj
    let oldArch = `@world`.archGraph.nodes[e.archetypeId]
    for cid in components:
      check(cid >= 0 and cid < MAX_COMPONENTS,
        "addComponent: component ID=" & $cid &
        " is out of valid range [0, " & $MAX_COMPONENTS & "). " &
        "Ensure the component is registered before use.")
    var archNode = oldArch.id

    # Traverse the archetype graph, adding components one by one to find the target node.
    for id in components:
      archNode = `@world`.archGraph.addComponent(archNode, id)

    # Perform the migration to the new archetype.
    migrateEntity(`@world`, `@d`, archNode)
    var ev = `@world`.events

## Adds components to an existing entity using a DWEntity.
proc addComponent*(dw: var DWEntity, components: varargs[int]) =
  addComponent(dw.w, dw.handle, components)

proc removeComponent*(world: var ECSWorld, d: DenseHandle, components: openArray[int]) =
  ## Removes components from an existing entity (Dense storage).
  ##
  ## This effectively changes the entity's archetype, triggering a migration.
  ##
  ## Parameters:
  ## - world: The mutable `ECSWorld` instance.
  ## - d: The `DenseHandle` of the entity.
  ## - components: Variadic list of Component IDs to remove.
  check(components.len > 0,
    "removeComponent: component list is empty — no structural change will occur.")
  let e = d.obj
  let oldArch = world.archGraph.nodes[e.archetypeId]
  for cid in components:
    check(cid >= 0 and cid < MAX_COMPONENTS,
      "removeComponent: component ID=" & $cid &
      " is out of valid range [0, " & $MAX_COMPONENTS & ").")
    checkWarn(oldArch.mask.hasComponent(cid),
      "removeComponent: entity (archetypeId=" & $e.archetypeId &
      ") does not have component ID=" & $cid &
      ". Removing a non-existent component produces an undefined archetype edge.")
  var archNode = oldArch.id

  # Traverse the archetype graph, removing components one by one to find the target node.
  for id in components:
    archNode = world.archGraph.removeComponent(archNode, id)

  # Perform the migration to the new archetype.
  migrateEntity(world, d, archNode)
  var ev = world.events
  ev.emitDenseComponentRemoved(d, components)

macro removeComponent*(
  world: var ECSWorld,
  d: DenseHandle,
  removedComps: varargs[typed]
): untyped =
  var removedIds = newNimNode(nnkBracket)
  var regis = newNimNode(nnkStmtList)
  for c in removedComps:
    removedIds.add quote("@") do: toComponentId(`@c`)
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)
  if removedIds.len == 0:
    removedIds = quote("@") do: array[0, int](`@removedIds`)

  return quote("@") do: 
    `@regis`
    let components = `@removedIds`
    check(components.len > 0,
    "removeComponent: component list is empty — no structural change will occur.")
    let e = `@d`.obj
    let oldArch = `@world`.archGraph.nodes[e.archetypeId]
    for cid in components:
      check(cid >= 0 and cid < MAX_COMPONENTS,
        "removeComponent: component ID=" & $cid &
        " is out of valid range [0, " & $MAX_COMPONENTS & ").")
      checkWarn(oldArch.mask.hasComponent(cid),
        "removeComponent: entity (archetypeId=" & $e.archetypeId &
        ") does not have component ID=" & $cid &
        ". Removing a non-existent component produces an undefined archetype edge.")
    var archNode = oldArch.id

    # Traverse the archetype graph, removing components one by one to find the target node.
    for id in components:
      archNode = `@world`.archGraph.removeComponent(archNode, id)

    # Perform the migration to the new archetype.
    migrateEntity(`@world`, `@d`, archNode)
    var ev = `@world`.events
    ev.emitDenseComponentRemoved(`@d`, components)

proc removeComponent*(dw: var DWEntity, components: varargs[int]) =
  removeComponent(dw.w, dw.handle, components)

# ################################################################################################################################################# #
# ######################################################### SPARSE OPERATIONS ##################################################################### #
# ################################################################################################################################################# #

macro createSparseEntity*(world: ECSWorld, comps: varargs[
    typed]): SparseHandle =
  var compIds = newNimNode(nnkBracket)
  var regis = newNimNode(nnkStmtList)
  for c in comps:
    compIds.add quote("@") do: toComponentId(`@c`)
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)
  if compIds.len == 0:
    compIds = quote("@") do: array[0, int](`@compIds`)

  return quote("@") do:
    block:
      `@regis`
      let archID = `@world`.archGraph.findArchetype(`@compIds`)
      let id = allocateSparseEntity(`@world`, `@comps`)
      let gen = `@world`.sparse_gens[id]

      var s = SparseHandle()
      s.id = id
      s.gen =  gen
      `@world`.sparse_arch[id] = archID
      var ev = `@world`.events
      ev.emitSparseEntityCreated(s)
      s

macro createSparseEntities*(
  world: ECSWorld,
  n: typed,
  comps: varargs[typed]
): seq[SparseHandle] =

  var compIds = newNimNode(nnkBracket)
  var regis = newNimNode(nnkStmtList)
  for c in comps:
    compIds.add quote("@") do: toComponentId(`@c`)
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)
  if compIds.len == 0:
    compIds = quote("@") do: array[0, int](`@compIds`)

  return quote("@") do:
    block:
      `@regis`
      let archID = `@world`.archGraph.findArchetype(`@compIds`)
      let ranges = allocateSparseEntities(`@world`, `@n`, `@comps`)

      var res = newSeq[SparseHandle](`@n`)
      var current = 0
      for r in ranges:
        for i in r.s..<r.e:
          let gen = `@world`.sparse_gens[i]
          `@world`.sparse_arch[i] = archID
          res[current] = SparseHandle(id: i.uint32, gen: gen)
          current += 1

      res

macro addComponent*(
  world: var ECSWorld,
  s: SparseHandle,
  addedComps: varargs[typed]
): untyped =
  var addedIds = newNimNode(nnkBracket)
  var regis = newNimNode(nnkStmtList)
  for c in addedComps:
    addedIds.add quote("@") do: toComponentId(`@c`)
    regis.add quote("@") do: discard `@world`.registerComponent(`@c`)
  if addedIds.len == 0:
    addedIds = quote("@") do: array[0, int](`@addedIds`)

  var activateCode = newNimNode(nnkStmtList)
  for c in addedComps:
    activateCode.add quote("@") do:
      block:
        let rawp = `@world`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(`@s`.id)

  return quote("@") do:
    block addComp:
      `@regis`
      var archID = `@world`.archGraph.nodes[`@world`.sparse_arch[`@s`.id]].id
      for cid in `@addedIds`:
        archID = `@world`.archGraph.addComponent(archID, cid)

      if archID == `@world`.sparse_arch[`@s`.id]: break addComp
      `@world`.sparse_arch[`@s`.id] = archID

      `@activateCode`

macro addComponent*(
  sw: var SWEntity,
  addedComps: varargs[typed]
): untyped =
  quote do:
    addComponent(`sw`.w, `sw`.handle, `addedComps`)

macro addComponent*(
  world: ECSWorld,
  entities: openArray[SparseHandle],
  addedComps: varargs[typed]
): untyped =
  ## addComponent batch (sparse)
  var addedIds = newNimNode(nnkBracket)
  var batchIdent = ident("batchIds")
  for c in addedComps:
    addedIds.add quote("@") do: toComponentId(`@c`)
  if addedIds.len == 0:
    addedIds = quote("@") do: array[0, int](`@addedIds`)

  # One typed batch activateSparseBit per component.
  var activateBatchCode = newNimNode(nnkStmtList)
  for c in addedComps:
    activateBatchCode.add quote("@") do:
      block:
        let rawp = `@world`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(`@batchIdent`)

  return quote("@") do:
    block addComp:
      if `@entities`.len == 0: break addComp

      # Collect ids once — shared across all per-component passes.
      var `@batchIdent` = newSeqOfCap[uint](`@entities`.len)

      # Update archetype node per entity (runtime graph walk).
      var lastArchID = -1
      var lastArch: int = -1
      for i in 0..<`@entities`.len:
        `@batchIdent`.add(`@entities`[i].id)
        let archId = `@world`.sparse_arch[`@entities`[i].id]
        if lastArchID != archID.int:
          lastArchId = archID.int
          lastArch = `@world`.sparse_arch[`@entities`[i].id].int
          for cid in `@addedIds`:
            lastArch = `@world`.archGraph.addComponent(lastArch.uint16, cid).int
        
        `@world`.sparse_arch[`@entities`[i].id] = archID

      # Typed batch activation — one castTo + one pass per component.
      `@activateBatchCode`

macro removeComponent*(
  world: var ECSWorld,
  s: SparseHandle,
  removedComps: varargs[typed]
): untyped =
  var removedIds = newNimNode(nnkBracket)
  for c in removedComps:
    removedIds.add quote("@") do: toComponentId(`@c`)
  if removedIds.len == 0:
    removedIds = quote("@") do: array[0, int](`@removedIds`)

  var deactivateCode = newNimNode(nnkStmtList)
  for c in removedComps:
    deactivateCode.add quote("@") do:
      block:
        let rawp = `@world`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.deactivateSparseBit(`@s`.id)

  return quote("@") do:
    block remComp:
      var archNode = `@world`.archGraph.nodes[`@world`.sparse_arch[`@s`.id]].id
      for cid in `@removedIds`:
        archNode = `@world`.archGraph.removeComponent(archNode, cid)

      if archNode == `@world`.sparse_arch[`@s`.id]: break remComp

      `@world`.sparse_arch[`@s`.id] = archNode
      `@deactivateCode`

macro removeComponent*(
  sw: var SWEntity,
  removedComps: varargs[typed]
): untyped =
  quote do:
    removeComponent(`sw`.w, `sw`.handle, `removedComps`)

macro removeComponent*(
  world: ECSWorld,
  entities: openArray[SparseHandle],
  removedComps: varargs[typed]
): untyped =

  var removedIds = newNimNode(nnkBracket)
  for c in removedComps:
    removedIds.add quote("@") do: toComponentId(`@c`)
  if removedIds.len == 0:
    removedIds = quote("@") do: array[0, int](`@removedIds`)

  var deactivateBatchCode = newNimNode(nnkStmtList)
  for c in removedComps:
    deactivateBatchCode.add quote("@") do:
      block:
        let rawp = `@world`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.deactivateSparseBit(batchIds)

  return quote("@") do:
    block remComp:
      if `@entities`.len == 0: break remComp

      var batchIds = newSeqOfCap[uint](`@entities`.len)
      for i in 0..<`@entities`.len:
        batchIds.add(`@entities`[i].id)

      
      var lastArchID = -1
      var lastArch: int = -1
      for i in 0..<`@entities`.len:
        let archId = `@world`.sparse_arch[`@entities`[i].id]
        if lastArchID != archID.int:
          lastArchId = archID.int
          lastArch = `@world`.sparse_arch[`@entities`[i].id].int

          for cid in `@removedIds`:
            lastArch = `@world`.archGraph.removeComponent(lastArch.uint16, cid).int

        `@world`.sparse_arch[`@entities`[i].id] = archID

      `@deactivateBatchCode`

proc deleteEntity*(w: var ECSWorld, s: SparseHandle) =
  ## Deletes an entity from the sparse storage.
  ##
  ## Parameters:
  ## - w: The mutable `ECSWorld` instance.
  ## - s: The `SparseHandle` of the entity to delete.
  var ev = w.events
  ev.emitSparseEntityDestroyed(s)
  w.deleteSparseRow(s.id, w.archGraph.nodes[w.sparse_arch[s.id]].componentIds)
  # Increment generation to invalidate handles.
  w.sparse_gens[s.id] += 1

proc deleteEntity*(sw: var SWEntity) =
  deleteEntity(sw.w, sw.handle)

proc migrateEntity(w: var ECSWorld, s: var SparseHandle,
    newArch: var ArchetypeNode) =
  let oldNode = addr w.archGraph.nodes[w.sparse_arch[s.id]]
  if newArch.id == w.sparse_arch[s.id]: return

  let toActivate = newArch.mask and not (oldNode.mask)
  let toDeactivate = oldNode.mask and not (newArch.mask)

  w.deactivateComponentsSparse(s.id, toDeactivate)
  w.sparse_arch[s.id] = newArch.id
  w.activateComponentsSparse(s.id, toActivate)

proc isAlive*(dw: DWEntity): bool = isAlive(dw.w, dw.handle)
proc isAlive*(sw: SWEntity): bool = sw.handle.gen == sw.w.sparse_gens[sw.handle.id]

###################################################################################################################################################
#################################################### SPARSE/DENSE OPERATIONS ######################################################################
###################################################################################################################################################

proc makeDense*(world: var ECSWorld, s: var SparseHandle): DenseHandle =
  ## Converts a Sparse entity into a Dense entity.
  ##
  ## Parameters:
  ## - world: The mutable `ECSWorld` instance.
  ## - s: The `SparseHandle` to convert.
  ## 
  ## return: A new `DWEntity` representing the entity in dense storage.
  var d = world.createEntity()
  world.migrateEntity(d, world.sparse_arch[s.id])

  # Iterate through the component mask to find active components.
  for id in world.archGraph.nodes[world.sparse_arch[s.id]].componentIds:
    var entry = world.registry.entries[id]

    # Invoke the specific copy operation (Sparse to Dense).
    entry.overrideDSOp(entry.rawPointer, d.id, s.id)

  # Cleanup the original Sparse entity.
  var ev = world.events
  ev.emitDensified(s, d)
  world.deleteEntity(s)

  return d

proc makeDense*(sw: var SWEntity): DWEntity =
  DWEntity(handle: makeDense(sw.w, sw.handle), w: sw.w)

proc makeSparse*(world: var ECSWorld, d: DenseHandle): SparseHandle =
  ## Converts a Dense entity into a Sparse entity.
  ##
  ## Parameters:
  ## - world: The mutable `ECSWorld` instance.
  ## - d: The `DenseHandle` to convert.
  ## 
  ## return: A new `SWEntity` representing the entity in sparse storage.
  var comps = world.archGraph.nodes[d.obj.archetypeId].componentIds
  var s = world.createSparseEntity()
  world.migrateEntity(s, world.archGraph.nodes[d.obj.archetypeId])

  # Iterate through the component mask.
  for id in comps:
    var entry = world.registry.entries[id]

    # Invoke the specific copy operation (Dense to Sparse).
    entry.overrideSDOp(entry.rawPointer, s.id, d.id)

  # Cleanup the original Dense entity.
  var ev = world.events
  ev.emitSparsified(d, s)
  world.deleteEntity(d)

  return s

proc makeSparse*(dw: var DWEntity): SWEntity =
  SWEntity(handle: makeSparse(dw.w, dw.handle), w: dw.w)
