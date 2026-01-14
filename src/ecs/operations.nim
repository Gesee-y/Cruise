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

## Creates a single new entity in the dense ECS storage.
##
## Dense storage is optimized for cache coherence and iteration speed. Entities are stored
## in blocks/chunks defined by their Archetype (set of components).
##
## @param world: The mutable `ECSWorld` instance.
## @param arch: The `ArchetypeMask` defining which components this entity initially has.
## @return: A `DenseHandle` used to safely refer to the entity. Includes a pointer to the
##          entity data and a generation ID for stale reference checks.
proc createEntity*(world:var ECSWorld, arch:ArchetypeMask):DenseHandle =
  # Acquire a stable internal ID (widx) for the entity record.
  let pid = getStableEntity(world)
  
  # Allocate actual space for the entity data within the specific archetype.
  # Returns block ID (bid), internal block index (id), and the archetype instance ID (archId).
  let (bid, id, archId) = allocateEntity(world, arch)

  # Calculate the flat index into the handles array based on block arithmetic.
  # Combines the block ID and the local ID within the block.
  let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
  
  # Retrieve the memory address of the entity record.
  var e = addr world.entities[pid]

  # Map the handle pointer at this index to the entity record.
  # This allows O(1) access from an ID to the entity metadata.
  world.handles[idx] = e
  
  # Initialize entity metadata.
  e.id = (bid shl BLK_SHIFT) or id.uint 
  e.archetypeId = archId                
  e.widx = pid                          
  
  world.events.emitDenseEntityCreated(result)
  # Return a public handle containing the pointer and the current generation (for safety checks).
  return DenseHandle(obj:e, gen:world.generations[pid])

## Overload of `createEntity` that accepts a list of Component IDs.
##
## @param world: The mutable `ECSWorld` instance.
## @param cids: A variadic list of Component IDs defining the entity's archetype.
## @return: A `DenseHandle` to the newly created entity.
proc createEntity*(world:var ECSWorld, cids:varargs[int]):DenseHandle =
  return world.createEntity(maskOf(cids))

## Creates multiple entities in a batch within the dense ECS storage.
##
## This is significantly more efficient than calling `createEntity` in a loop as it
## allocates contiguous memory blocks and reduces metadata overhead.
##
## @param world: The mutable `ECSWorld` instance.
## @param n: The number of entities to create.
## @param arch: The `ArchetypeMask` for the new entities.
## @return: A sequence of `DenseHandle` objects, one for each created entity.
proc createEntities*(world:var ECSWorld, n:int, arch:ArchetypeMask):seq[DenseHandle] =
  result = newSeqOfCap[DenseHandle](n)
  
  # Acquire 'n' stable internal IDs.
  let pids = getStableEntities(world, n)
  
  # Find or create the archetype node responsible for this mask.
  var archNode = world.archGraph.findArchetypeFast(arch)
  let archId = archNode.id
  
  # Allocate the block space for 'n' entities. 
  # 'res' contains ranges of allocated slots across potentially multiple blocks.
  let res = allocateEntities(world, n, archNode)
  var current = 0

  # Iterate through the allocation results (Block ID, Range of IDs)
  for (bid, r) in res:
    let b = (bid shl BLK_SHIFT)

    for id in r.s..<r.e:
      # Setup variables for the current entity being processed.
      let pid = pids[current]
      let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
      var e = addr world.entities[pid]

      # Map handles and initialize metadata similar to single entity creation.
      world.handles[idx] = e
      e.id = b or id.uint
      e.archetypeId = archId
      e.widx = pid

      current += 1
      # Create the handle with the specific generation for this PID.
      result.add(DenseHandle(obj:e, gen:world.generations[pid]))
  
  return result

## Overload of `createEntities` that accepts a list of Component IDs.
##
## @param world: The mutable `ECSWorld` instance.
## @param n: The number of entities to create.
## @param cids: A variadic list of Component IDs.
## @return: A sequence of `DenseHandle` objects.
proc createEntities*(world:var ECSWorld, n:int, cids:varargs[int]):seq[DenseHandle] =
  return world.createEntities(n, maskOf(cids))

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
  world.events.emitDenseEntityDestroyed(d)
  let l = deleteRow(world, e.id, e.archetypeId)
  
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
  world.cb[buffer_id].addCommmand(DeleteOp.int, d.obj.archetypeId, 0'u32, PayLoad(eid:d.obj.widx.uint, obj:d))

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
    # Move the data. 
    # changePartition moves component data from old archetype to new archetype.
    # Returns: index of the swapped-in last element (lst), new ID, new Block ID.
    let (lst, id, bid) = changePartition(world, e.id, e.archetypeId, archNode)
    
    # Decode the old Entity ID into local indices.
    let eid = e.id and BLK_MASK
    let beid = (e.id shr BLK_SHIFT) and BLK_MASK

    # Fix the handle pointers. 
    # The handle at the *new* location must point to our entity.
    world.handles[id+bid*DEFAULT_BLK_SIZE] = world.handles[eid+beid*DEFAULT_BLK_SIZE]
    
    # The handle at the *old* location (now occupied by the swapped entity) must point to that entity.
    world.handles[eid+beid*DEFAULT_BLK_SIZE] = world.handles[lst]

    # Update the ID of the swapped entity to reflect its new physical position (the old spot).
    world.handles[lst].id = e.id

    # Update the migrating entity's ID to its new physical position.
    let oldArchId = e.archetypeId
    e.id = (bid shl BLK_SHIFT) or id
    e.archetypeId = archNode.id
    world.events.emitDenseEntityMigrated(d, oldArchId, archNode.id)
    
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

    if archNode.id != e.archetypeId:
      # Perform batch partition change.
      changePartition(world, ents, e.archetypeId, archNode)

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
  world.cb[buffer_id].addCommmand(MigrateOp.int, archNode.id, d.obj.archetypeId.uint32, PayLoad(eid:d.obj.widx.uint, obj:d))

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

## Creates a new entity in the sparse ECS storage.
##
## Sparse storage uses a HiBitSet approach.
## It is more flexible for dynamic changes and just a but slower to iterate than Dense storage.
##
## @param w: The mutable `ECSWorld` instance.
## @param components: A variadic list of Component IDs the entity starts with.
## @return: A `SparseHandle` containing the entity ID, generation, and component mask.
proc createSparseEntity*(w:var ECSWorld, components:varargs[int]):SparseHandle =
  # Allocate space in the sparse set.
  let id = w.allocateSparseEntity(components)
  let mask = maskOf(components)
  let s = SparseHandle(id:id, gen:w.sparse_gens[id], mask:mask)
  # Return the handle containing the bitmask of components.
  w.events.emitSparseEntityCreated(s)
  return s

## Creates multiple entities in the sparse ECS storage.
##
## @param w: The mutable `ECSWorld` instance.
## @param n: The number of entities to create.
## @param components: A variadic list of Component IDs.
## @return: A sequence of `SparseHandle` objects.
proc createSparseEntities*(w:var ECSWorld, n:int, components:varargs[int]):seq[SparseHandle] =
  var res = newSeqOfCap[SparseHandle](n)
  # Batch allocate sparse IDs.
  let ids = w.allocateSparseEntities(n, components)
  let mask = maskOf(components)

  # Iterate through the allocated ID ranges.
  for r in ids:
    for i in r.s..<r.e:
      res.add(SparseHandle(id:i.uint, gen:w.sparse_gens[i], mask:mask))

  return res

## Deletes an entity from the sparse storage.
##
## @param w: The mutable `ECSWorld` instance.
## @param s: The `SparseHandle` of the entity to delete.
proc deleteEntity*(w:var ECSWorld, s:var SparseHandle) =
  w.events.emitSparseEntityDestroyed(s)
  w.deleteSparseRow(s.id, s.mask)
  # Increment generation to invalidate handles.
  w.sparse_gens[s.id] += 1

## Adds components to a sparse entity.
##
## In sparse sets, this usually involves updating the entity's bitmask
## and activating memory slots for the new components.
##
## @param w: The mutable `ECSWorld` instance.
## @param s: The `SparseHandle` of the entity.
## @param components: Variadic list of Component IDs to add.
proc addComponent*(w:var ECSWorld, s:var SparseHandle, components:varargs[int]) =
  let oldMask = s.mask
  s.mask.setBit(components)
  w.activateComponentsSparse(s.id, components)
  w.events.emitSparseComponentAdded(s, components.toSeq)

## Removes components from a sparse entity.
##
## Updates the bitmask and deactivates memory slots (logic varies by implementation).
##
## @param w: The mutable `ECSWorld` instance.
## @param s: The `SparseHandle` of the entity.
## @param components: Variadic list of Component IDs to remove.
proc removeComponent*(w:var ECSWorld, s:var SparseHandle, components:varargs[int]) =
  let oldMask = s.mask
  s.mask.unSetBit(components)
  w.deactivateComponentsSparse(s.id, components)
  w.events.emitSparseComponentRemoved(s, components.toSeq)

###################################################################################################################################################
#################################################### SPARSE/DENSE OPERATIONS ######################################################################
###################################################################################################################################################

## Converts a Sparse entity into a Dense entity.
##
## ## @param world: The mutable `ECSWorld` instance.
## @param s: The `SparseHandle` to convert.
## @return: A new `DenseHandle` representing the entity in dense storage.
proc makeDense*(world:var ECSWorld, s:var SparseHandle):DenseHandle =
  var d = world.createEntity(s.mask)
  
  # Iterate through the component mask to find active components.
  for m in s.mask:
    var mask = m
    while mask != 0:
      # Extract the ID of the active component.
      let id = countTrailingZeroBits(mask)
      var entry = world.registry.entries[id]
      
      # Invoke the specific copy operation (Sparse to Dense).
      entry.overrideDSOp(entry.rawPointer, d, s)
      
      # Clear the bit to move to the next component.
      mask = mask and (mask - 1)

  # Cleanup the original Sparse entity.
  world.deleteEntity(s)
  world.events.emitDensified(s, d)

  return d

## Converts a Dense entity into a Sparse entity.
##
## @param world: The mutable `ECSWorld` instance.
## @param d: The `DenseHandle` to convert.
## @return: A new `SparseHandle` representing the entity in sparse storage.
proc makeSparse*(world:var ECSWorld, d:DenseHandle):SparseHandle =
  var s = world.createSparseEntity(world.archGraph.nodes[d.obj.archetypeId].partition.components)
  
  # Iterate through the component mask.
  for m in s.mask:
    var mask = m
    while mask != 0:
      let id = countTrailingZeroBits(mask)
      var entry = world.registry.entries[id]
      
      # Invoke the specific copy operation (Dense to Sparse).
      entry.overrideSDOp(entry.rawPointer, s, d)
      
      mask = mask and (mask - 1)

  # Cleanup the original Dense entity.
  world.deleteEntity(d)
  world.events.emitSparsified(d, s)

  return s