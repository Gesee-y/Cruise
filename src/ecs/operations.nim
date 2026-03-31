###################################################################################################################################################
############################################################# ECS OPERATIONS ######################################################################
###################################################################################################################################################

## Defines the operation codes used for deferred execution within the Command Buffer.
## These codes indicate whether a deferred operation is intended to delete an entity
## or migrate (move) it to a different archetype.
type
  ECSOpCode = enum
    DeleteOp = 0  
    MigrateOp = 1

###################################################################################################################################################
############################################################ DENSE OPERATIONS ######################################################################
###################################################################################################################################################

macro createEntity*(world: ECSWorld, comps:varargs[typed]):DenseHandle =
  let enable_event=EVENT_ACTIVE
  var compIds = newNimNode(nnkBracket)
  for c in comps:
    compIds.add quote("@") do: 
      toComponentId(`@c`)
  if compIds.len == 0:
    compIds = quote("@") do: array[0, int](`@compIds`)
  return quote("@") do:
    # Acquire a stable internal ID (widx) for the entity record.
    let pid = getStableEntity(`@world`)
    let arch = `@world`.archGraph.findArchetype(`@compIds`)
    
    # Allocate actual space for the entity data within the specific archetype.
    # Returns block ID (bid), internal block index (id), and the archetype instance ID (archId).
    let (bid, id, archId) = allocateEntity(`@world`, arch, `@comps`)

    # Calculate the flat index into the handles array based on block arithmetic.
    # Combines the block ID and the local ID within the block.
    let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
    
    # Retrieve the memory address of the entity record.
    var e = addr `@world`.entities[pid]

    # Map the handle pointer at this index to the entity record.
    # This allows O(1) access from an ID to the entity metadata.
    `@world`.handles[idx] = e
    
    # Initialize entity metadata.
    e.id = (bid shl BLK_SHIFT) or id.uint 
    e.archetypeId = archId                
    e.widx = pid

    var d = DenseHandle()
    d.obj = e 
    d.gen = `@world`.generations[pid]
    if `@enable_event`: `@world`.events.emitDenseEntityCreated(d)

    d

macro createEntities*(world:ECSWorld, n:untyped, comps:varargs[typed]):seq[DenseHandle] =
  var compIds = newNimNode(nnkBracket)
  for c in comps:
    compIds.add quote("@") do: 
      toComponentId(`@c`)
  
  return quote("@") do:
    var rest = newSeq[DenseHandle](`@n`)
    var archNode = `@world`.archGraph.findArchetype(`@compIds`)
    
    # Acquire 'n' stable internal IDs.
    let pids = getStableEntities(`@world`, `@n`)
    let archId = archNode.id
    
    # Allocate the block space for 'n' entities. 
    # 'res' contains ranges of allocated slots across potentially multiple blocks.
    let res = allocateEntities(`@world`, `@n`, archNode, `@comps`)
    var current = 0

    # Iterate through the allocation results (Block ID, Range of IDs)
    for (bid, r) in res:
      let b = (bid shl BLK_SHIFT)

      for id in r.s..<r.e:
        # Setup variables for the current entity being processed.
        let pid = pids[current]
        let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
        var e = addr `@world`.entities[pid]

        # Map handles and initialize metadata similar to single entity creation.
        `@world`.handles[idx] = e
        e.id = b or id.uint
        e.archetypeId = archId
        e.widx = pid

        # Create the handle with the specific generation for this PID.
        rest[current] = (DenseHandle(obj:e, gen:`@world`.generations[pid]))
        current += 1
    
    rest

## Immediately deletes an entity from the dense storage.
##
## This operation performs a "swap-and-pop" at the block level to maintain memory contiguity.
## The generation counter is incremented to invalidate existing handles (stale references).
##
## @param world: The mutable `ECSWorld` instance.
## @param d: The `DenseHandle` of the entity to delete.
template deleteEntity*(world:var ECSWorld, d:DenseHandle) =
  let e = d.obj
  
  check(not e.isNil, "Invalid access. Trying to access nil entity.")
  check(world.generations[e.widx] == d.gen, "Invalid Entity. Entity is stale (already dead).")

  # Remove the entity's data row from its archetype block.
  # Returns the index of the last row that was swapped into the deleted position ('l').
  let l = deleteRow(world, e.id, e.archetypeId)
  world.events.emitDenseEntityDestroyed(d, l)
  
  # Update the handle lookup table.
  # The handle at the deleted entity's position now points to the entity that was moved.
  world.handles[(e.id and BLK_MASK) + ((e.id shr BLK_SHIFT) and BLK_MASK)*DEFAULT_BLK_SIZE] = world.handles[l]
  
  # Update the ID of the moved entity so it matches its new memory location.
  world.handles[l].id = e.id
  
  # Increment the generation to mark the old ID as "dead" and invalidate handles.
  world.generations[e.widx] += 1.uint32
  
  # Recycle the stable ID (widx) back to the free list.
  world.free_entities.add(e.widx)

## Defers the deletion of an entity.
##
## Instead of deleting immediately, the command is pushed to a Command Buffer (`cb`).
## This is useful for performing structural changes during iteration where immediate
## deletion would invalidate pointers.
##
## @param world: The mutable `ECSWorld` instance.
## @param d: The `DenseHandle` of the entity to delete.
## @param buffer_id: The ID of the command buffer to use.
template deleteEntityDefer*(world:var ECSWorld, d:DenseHandle, buffer_id:int) =
  # Add a DeleteOp command with the source archetype ID and the entity's world index (widx).
  world.commandBufs[buffer_id].addCommand(DeleteOp.int, d.obj.archetypeId, 0'u32, PayLoad(eid:d.obj.widx.uint, obj:d))

## Immediately migrates an entity to a new archetype (Dense storage).
##
## Migration is the process of moving an entity from one memory layout (Archetype A) to another
## (Archetype B), typically because components were added or removed. 
##
## @param world: The mutable `ECSWorld` instance.
## @param d: The `DenseHandle` of the entity to migrate.
## @param archNode: The target `ArchetypeNode` (destination archetype).
proc migrateEntity*(world: var ECSWorld, d:DenseHandle, archNode:ArchetypeNode) =
  let e = d.obj

  # Validate that the handle points to a living entity.
  check(not e.isNil, "Invalid access. Trying to access nil entity.")
  check(world.generations[e.widx] == d.gen, "Invalid Entity. Entity is stale (already dead).")
  
  # Only perform migration if the target archetype is different from the current one.
  if archNode.id != e.archetypeId:
    let oldId = e.id # Keep this for events

    # Move the data. 
    # changePartition moves component data from old archetype to new archetype.
    # Returns: index of the swapped-in last element (lst), new ID, new Block ID.
    let (lst, id, bid) = changePartition(world, e.id, e.archetypeId, archNode)
    
    # Decode the old Entity ID into local indices.
    let eid = e.id and BLK_MASK
    let beid = (e.id shr BLK_SHIFT) and BLK_MASK

    # Fix the handle pointers. 
    # The handle at the *new* location must point to our entity.
    world.handles[id+bid*DEFAULT_BLK_SIZE] = world.handles[e.id.toIdx]
    
    # The handle at the *old* location (now occupied by the swapped entity) must point to that entity.
    world.handles[eid+beid*DEFAULT_BLK_SIZE] = world.handles[lst]

    # Update the ID of the swapped entity to reflect its new physical position (the old spot).
    world.handles[lst].id = e.id

    # Update the migrating entity's ID to its new physical position.
    let oldArchId = e.archetypeId
    let newId = (bid shl BLK_SHIFT) or id
    e.id = newId
    e.archetypeId = archNode.id
    world.events.emitDenseEntityMigrated(d, oldId, lst.uint, oldArchId, archNode.id)
    
## Batch migration for multiple entities (Dense storage).
##
## Optimizes moving a group of entities to a new archetype.
##
## @param world: The mutable `ECSWorld` instance.
## @param ents: An open array of `DenseHandle` to migrate.
## @param archNode: The target `ArchetypeNode`.
template migrateEntity*(world: var ECSWorld, ents:var openArray, archNode:ArchetypeNode) =
  if ents.len != 0:
    # Assume all entities in the batch are currently in the same archetype (based on the first one).
    let e = ents[0].obj
    let oldArchId = e.archetypeId

    if archNode.id != oldArchId:
      var ids = newSeq[uint](ents.len)
      for i in 0..<ents.len:
        ids[i] = ents[i].obj.id

      # Perform batch partition change.
      let (toSwap, toAdd) = changePartition(world, ents, oldArchId, archNode)
      world.events.emitDenseEntityMigratedBatch(ids, toSwap, toAdd, oldArchId, archNode.id)

## Defers the migration of an entity.
##
## Adds a migration command to the Command Buffer to be executed later.
##
## @param world: The mutable `ECSWorld` instance.
## @param d: The `DenseHandle` of the entity to migrate.
## @param archNode: The target `ArchetypeNode`.
## @param buffer_id: The ID of the command buffer.
template migrateEntityDefer*(world:var ECSWorld, d:DenseHandle, archNode:ArchetypeNode, buffer_id:int) =
  # Add a MigrateOp command: Destination Archetype ID, Source Archetype ID, Payload.
  world.commandBufs[buffer_id].addCommand(MigrateOp.int, archNode.id, d.obj.archetypeId.uint32, PayLoad(eid:d.obj.widx.uint, obj:d))

## Adds components to an existing entity (Dense storage).
##
## This effectively changes the entity's archetype, triggering a migration.
##
## @param world: The mutable `ECSWorld` instance.
## @param d: The `DenseHandle` of the entity.
## @param components: Variadic list of Component IDs to add.
proc addComponent*(world:var EcsWorld, d:DenseHandle, components:varargs[int]) =
  let e = d.obj
  let oldArch = world.archGraph.nodes[e.archetypeId]
  var archNode = oldArch
  
  # Traverse the archetype graph, adding components one by one to find the target node.
  for id in components:
    archNode = world.archGraph.addComponent(archNode, id)

  # Perform the migration to the new archetype.
  migrateEntity(world, d, archNode)
  world.events.emitDenseComponentAdded(d, components)

## Removes components from an existing entity (Dense storage).
##
## This effectively changes the entity's archetype, triggering a migration.
##
## @param world: The mutable `ECSWorld` instance.
## @param d: The `DenseHandle` of the entity.
## @param components: Variadic list of Component IDs to remove.
proc removeComponent*(world:var EcsWorld, d:DenseHandle, components:varargs[int]) =
  let e = d.obj
  let oldArch = world.archGraph.nodes[e.archetypeId]
  var archNode = oldArch
  
  # Traverse the archetype graph, removing components one by one to find the target node.
  for id in components:
    archNode = world.archGraph.removeComponent(archNode, id)

  # Perform the migration to the new archetype.
  migrateEntity(world, d, archNode)
  world.events.emitDenseComponentRemoved(d, components)

###################################################################################################################################################
########################################################## SPARSE OPERATIONS ######################################################################
###################################################################################################################################################

## createSparseEntity — typed, zero vtable.
##
## Replaces:
##   proc createSparseEntity*(w, components:varargs[int])
## which calls allocateSparseEntity → vtable chain.
macro createSparseEntity*(world: ECSWorld, comps: varargs[typed]): SparseHandle =
  var compIds = newNimNode(nnkBracket)
  for c in comps:
    compIds.add quote("@") do: toComponentId(`@c`)
  if compIds.len == 0:
    compIds = quote("@") do: array[0, int](`@compIds`)

  return quote("@") do:
    block:
      let archNode = `@world`.archGraph.findArchetype(`@compIds`)
      let id       = allocateSparseEntity(`@world`, `@comps`)

      var s = SparseHandle()
      s.id     = id
      s.archID = archNode.id
      `@world`.events.emitSparseEntityCreated(s)
      s


## createSparseEntities — typed batch, zero vtable.
macro createSparseEntities*(
  world: ECSWorld,
  n:     typed,
  comps: varargs[typed]
): seq[SparseHandle] =

  var compIds = newNimNode(nnkBracket)
  for c in comps:
    compIds.add quote("@") do: toComponentId(`@c`)
  if compIds.len == 0:
    compIds = quote("@") do: array[0, int](`@compIds`)

  return quote("@") do:
    block:
      let archNode = `@world`.archGraph.findArchetype(`@compIds`)
      let archID   = archNode.id
      let ranges   = allocateSparseEntities(`@world`, `@n`, `@comps`)

      var result = newSeqOfCap[SparseHandle](`@n`)
      for r in ranges:
        for i in r.s..<r.e:
          result.add(SparseHandle(id: i.uint, archID: archID))

      result

## addComponent (sparse, single) — typed, zero vtable.
##
## Only activates the NEW components — the entity already has the others.
macro addComponent*(
  world:      ECSWorld,
  s:          var SparseHandle,
  addedComps: varargs[typed]
): untyped =

  var addedIds = newNimNode(nnkBracket)
  for c in addedComps:
    addedIds.add quote("@") do: toComponentId(`@c`)
  if addedIds.len == 0:
    addedIds = quote("@") do: array[0, int](`@addedIds`)

  ## Direct typed activation — one castTo per added component.
  var activateCode = newNimNode(nnkStmtList)
  for c in addedComps:
    activateCode.add quote("@") do:
      block:
        let rawp = `@world`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(`@s`.id)

  return quote("@") do:
    block addComp:
      ## Walk the archetype graph with compile-time ids — result is runtime node.
      var archNode = `@world`.archGraph.nodes[`@s`.archID]
      for cid in `@addedIds`:
        archNode = `@world`.archGraph.addComponent(archNode, cid)

      if archNode.id == `@s`.archID: break addComp

      `@s`.archID = archNode.id

      ## Activate only the added components — typed, no vtable.
      `@activateCode`


## addComponent batch (sparse) — typed, zero vtable.
##
## Collects all entity ids once, then does one typed batch activation
## per added component type — Component-Outside Entity-Inside pattern.
macro addComponent*(
  world:      ECSWorld,
  entities:   var openArray[SparseHandle],
  addedComps: varargs[typed]
): untyped =

  var addedIds = newNimNode(nnkBracket)
  for c in addedComps:
    addedIds.add quote("@") do: toComponentId(`@c`)
  if addedIds.len == 0:
    addedIds = quote("@") do: array[0, int](`@addedIds`)

  ## One typed batch activateSparseBit per component.
  var activateBatchCode = newNimNode(nnkStmtList)
  for c in addedComps[0]:
    activateBatchCode.add quote("@") do:
      block:
        let rawp = `@world`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(batchIds)

  return quote("@") do:
    block addComp:
      if `@entities`.len == 0: break addComp

      ## Collect ids once — shared across all per-component passes.
      var batchIds = newSeqOfCap[uint](`@entities`.len)
      for i in 0..<`@entities`.len:
        batchIds.add(`@entities`[i].id)

      ## Update archetype node per entity (runtime graph walk).
      var lastArchID = -1
      var lastArch:ArchetypeNode = nil
      for i in 0..<`@entities`.len:
        let archId = `@entities`[i].archID
        if lastArchID != archID.int: 
          lastArchId = archID.int
          lastArch = `@world`.archGraph.nodes[`@entities`[i].archID]
          for cid in `@addedIds`:
            lastArch = `@world`.archGraph.addComponent(lastArch, cid)

        `@entities`[i].archID = lastArch.id

      ## Typed batch activation — one castTo + one pass per component.
      `@activateBatchCode`


## removeComponent (sparse, single) — typed, zero vtable.
macro removeComponent*(
  world:        ECSWorld,
  s:            var SparseHandle,
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
      var archNode = `@world`.archGraph.nodes[`@s`.archID]
      for cid in `@removedIds`:
        archNode = `@world`.archGraph.removeComponent(archNode, cid)

      if archNode.id == `@s`.archID: break remComp

      `@s`.archID = archNode.id
      `@deactivateCode`


## removeComponent batch (sparse) — typed, zero vtable.
macro removeComponent*(
  world:        ECSWorld,
  entities:     var openArray[SparseHandle],
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

      for i in 0..<`@entities`.len:
        var lastArchID = -1
      var lastArch:ArchetypeNode = nil
      for i in 0..<`@entities`.len:
        let archId = `@entities`[i].archID
        if lastArchID != archID.int: 
          lastArchId = archID.int
          lastArch = `@world`.archGraph.nodes[`@entities`[i].archID]

        for cid in `@removedIds`:
          lastArch = `@world`.archGraph.removeComponent(lastArch, cid)

        `@entities`[i].archID = lastArch.id

      `@deactivateBatchCode`
## Deletes an entity from the sparse storage.
##
## @param w: The mutable `ECSWorld` instance.
## @param s: The `SparseHandle` of the entity to delete.
proc deleteEntity*(w:var ECSWorld, s:var SparseHandle) =
  #w.events.emitSparseEntityDestroyed(s)
  w.deleteSparseRow(s.id, w.archGraph.nodes[s.archID].componentIds)
  # Increment generation to invalidate handles.
  w.sparse_gens[s.id] += 1

proc migrateEntity(w:var ECSWorld, s:var SparseHandle, newArch:var ArchetypeNode) = 
  let oldNode = addr w.archGraph.nodes[s.archID]
  if newArch.id == s.archID: return
  
  let toActivate = newArch.mask and not (oldNode.mask)
  let toDeactivate = oldNode.mask and not (newArch.mask)

  w.deactivateComponentsSparse(s.id, toDeactivate)
  s.archID = oldNode.id
  w.activateComponentsSparse(s.id, toActivate)  

###################################################################################################################################################
#################################################### SPARSE/DENSE OPERATIONS ######################################################################
###################################################################################################################################################

## Converts a Sparse entity into a Dense entity.
##
## ## @param world: The mutable `ECSWorld` instance.
## @param s: The `SparseHandle` to convert.
## @return: A new `DenseHandle` representing the entity in dense storage.
proc makeDense*(world:var ECSWorld, s:var SparseHandle):DenseHandle =
  var archNode = world.archGraph.nodes[s.archID]
  var d = world.createEntity()
  world.migrateEntity(d, archNode)
  
  # Iterate through the component mask to find active components.
  for id in archNode.componentIds:
    var entry = world.registry.entries[id]
    
    # Invoke the specific copy operation (Sparse to Dense).
    entry.overrideDSOp(entry.rawPointer, d, s)
    
  # Cleanup the original Sparse entity.
  world.events.emitDensified(s, d) 
  world.deleteEntity(s)

  return d

## Converts a Dense entity into a Sparse entity.
##
## @param world: The mutable `ECSWorld` instance.
## @param d: The `DenseHandle` to convert.
## @return: A new `SparseHandle` representing the entity in sparse storage.
proc makeSparse*(world:var ECSWorld, d:DenseHandle):SparseHandle =
  var comps = world.archGraph.nodes[d.obj.archetypeId].componentIds
  var s = world.createSparseEntity()
  world.migrateEntity(s, world.archGraph.nodes[d.obj.archetypeId])

  # Iterate through the component mask.
  for id in comps:
    var entry = world.registry.entries[id]
    
    # Invoke the specific copy operation (Dense to Sparse).
    entry.overrideSDOp(entry.rawPointer, s, d)

  # Cleanup the original Dense entity.
  world.events.emitSparsified(d, s)
  world.deleteEntity(d)
  
  return s