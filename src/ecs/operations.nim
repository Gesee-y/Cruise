################################################################################################################################################### 
############################################################# ECS OPERATIONS ######################################################################
################################################################################################################################################### 

proc createEntity(world:var EcsWorld, cids:seq[int]):DenseHandle =
  let pid = getStableEntity(world)
  let arch = maskOf(cids)
  let (bid, id, archId) = allocateEntity(world, arch, cids)

  let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
  var e = addr world.entities[pid]

  world.handles[idx] = e
  e.id = (bid shl BLK_SHIFT) or id.uint
  e.archetypeId = archId
  e.widx = pid
  
  return DenseHandle(obj:e, gen:world.generations[pid])

proc createEntities(world:var EcsWorld, n:int, cids:seq[int]):seq[DenseHandle] =
  result = newSeqOfCap[DenseHandle](n)
  let pids = getStableEntities(world, n)
  let arch = maskOf(cids)
  var archNode = world.archGraph.findArchetypeFast(arch)
  let archId = archNode.id
  let res = allocateEntities(world, n, archNode, cids)
  var current = 0

  for (bid, r) in res:
    let b = (bid shl BLK_SHIFT)

    for id in r.s..<r.e:
      let pid = pids[current]
      let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
      var e = addr world.entities[pid]

      world.handles[idx] = e
      e.id = b or id.uint
      e.archetypeId = archId
      e.widx = pid

      current += 1
      result.add(DenseHandle(obj:e, gen:world.generations[pid]))
  
  return result

template deleteEntity(world:var EcsWorld, d:DenseHandle) =
  let e = d.obj
  
  check(not e.isNil, "Invalid access. Trying to access nil entity.")
  check(world.generation[e.widx] == d.gen, "Invalid Entity. Entity is stale (already dead).")

  let l = deleteRow(world, e.id, e.archetypeId)
  world.handles[(e.id and BLK_MASK) + ((e.id shr BLK_SHIFT) and BLK_MASK)*DEFAULT_BLK_SIZE] = world.handles[l]
  world.handles[l].id = e.id
  world.generations[e.widx] += 1.uint32
  world.free_entities.add(e.widx)

proc migrateEntity(world: var ECSWorld, d:DenseHandle, archNode:ArchetypeNode) =
  let e = d.obj

  check(not e.isNil, "Invalid access. Trying to access nil entity.")
  check(world.generation[e.widx] == d.gen, "Invalid Entity. Entity is stale (already dead).")
  
  if archNode.id != e.archetypeId:
    let (lst, id, bid) = changePartition(world, e.id, e.archetypeId, archNode)
    
    let eid = e.id and BLK_MASK
    let beid = (e.id shr BLK_SHIFT) and BLK_MASK

    world.handles[id+bid*DEFAULT_BLK_SIZE] = world.handles[eid+beid*DEFAULT_BLK_SIZE]
    world.handles[eid+beid*DEFAULT_BLK_SIZE] = world.handles[lst]

    world.handles[lst].id = e.id

    e.id = (bid shl BLK_SHIFT) or id
    e.archetypeId = archNode.id
    
template migrateEntity(world: var ECSWorld, ents:var openArray, archNode:ArchetypeNode) =
  if ents.len != 0:
    let e = ents[0].obj

    if archNode.id != e.archetypeId:
      changePartition(world, ents, e.archetypeId, archNode)

proc addComponent(world:var EcsWorld, e:SomeEntity, components:seq[int]) =
  let oldArch = world.archGraph.nodes[e.archetypeId]
  var archNode = oldArch
  for id in components:
    archNode = world.archGraph.addComponent(archNode, id)

  migrateEntity(world, e, archNode)

proc removeComponent(world:var EcsWorld, e:SomeEntity, components:seq[int]) =
  let oldArch = world.archGraph.nodes[e.archetypeId]
  var archNode = oldArch
  for id in components:
    archNode = world.archGraph.removeComponent(archNode, id)

  migrateEntity(world, e, archNode)
