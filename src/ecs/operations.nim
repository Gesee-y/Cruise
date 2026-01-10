################################################################################################################################################### 
############################################################# ECS OPERATIONS ######################################################################
################################################################################################################################################### 

proc createEntity(world:var EcsWorld, cids:seq[int]):ptr Entity =
  let arch = maskOf(cids)
  let (bid, id, archId) = allocateEntity(world, arch, cids)

  let idx = id.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
  var e = addr world.entities[idx]
  e.id = (bid shl BLK_SHIFT) or id.uint
  e.archetypeId = archId
  
  return e

template deleteEntity(world:var EcsWorld, e:SomeEntity) =
  let l = deleteRow(world, (e.id and ((1.uint shl BLK_SHIFT)-1)).int, e.archetypeId)
  world.entities[(e.id and BLK_MASK) + ((e.id shr BLK_SHIFT) and BLK_MASK)*DEFAULT_BLK_SIZE] = world.entities[l]
  world.entities[l].id = e.id


proc migrateEntity(world: var ECSWorld, e:SomeEntity, archNode:ArchetypeNode) =
  if archNode.id != e.archetypeId:
    let (lst, id, bid) = changePartition(world, e.id, e.archetypeId, archNode)
    
    let eid = e.id and BLK_MASK
    let beid = (e.id shr BLK_SHIFT) and BLK_MASK

    world.entities[id+bid*DEFAULT_BLK_SIZE] = world.entities[eid+beid*DEFAULT_BLK_SIZE]
    world.entities[eid+beid*DEFAULT_BLK_SIZE] = world.entities[lst]

    world.entities[lst].id = e.id

    e.id = (bid shl BLK_SHIFT) or id
    e.archetypeId = archNode.id

template migrateEntity(world: var ECSWorld, ents:var openArray, archNode:ArchetypeNode) =
  if ents.len != 0:
    let e = ents[0]

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
