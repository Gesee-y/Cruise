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

template deleteEntity(world:var EcsWorld, e:ptr Entity) =
  let l = deleteRow(world, (e.id and ((1.uint shl BLK_SHIFT)-1)).int, e.archetypeId)
  world.entities[(e.id and BLK_MASK) + ((e.id shr BLK_SHIFT) and BLK_MASK)*DEFAULT_BLK_SIZE] = world.entities[l]
  world.entities[l].id = e.id

proc addComponent(world:var EcsWorld, e:ptr Entity | var Entity, components:seq[int]) =
  let oldArch = world.archGraph.nodes[e.archetypeId]
  var archNode = oldArch
  for id in components:
    archNode = world.archGraph.addComponent(oldArch, id)

  if archNode.id != e.archetypeId:
    let (lst, id, bid) = changePartition(world, e.id, e.archetypeId, archNode)
    
    let eid = e.id and BLK_MASK
    let beid = (e.id shr BLK_SHIFT) and BLK_MASK

    world.entities[id+bid*DEFAULT_BLK_SIZE] = e[]
    world.entities[eid+beid*DEFAULT_BLK_SIZE] = world.entities[lst]

    world.entities[lst].id = e.id

    e.id = (bid shl BLK_SHIFT) or id
    e.archetypeId = archNode.id

proc removeComponent(world:var EcsWorld, e:ptr Entity | var Entity, components:seq[int]) =
  let oldArch = world.archGraph.nodes[e.archetypeId]
  var archNode = oldArch
  for id in components:
    archNode = world.archGraph.removeComponent(oldArch, id)

  if archNode.id != e.archetypeId:
    let eid = e.id and BLK_MASK
    let beid = (e.id shr BLK_SHIFT) and BLK_MASK
    let (lst, id, bid) = changePartition(world, e.id, e.archetypeId, archNode)

    world.entities[id+bid*DEFAULT_BLK_SIZE] = e[]
    world.entities[eid+beid*DEFAULT_BLK_SIZE] = world.entities[lst]

    world.entities[lst].id = e.id
    
    e.id = (bid shl BLK_SHIFT) or id
    e.archetypeId = archNode.id
