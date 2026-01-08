################################################################################################################################################### 
############################################################# ECS OPERATIONS ######################################################################
################################################################################################################################################### 

proc createEntity(world:var EcsWorld, cids:seq[int]):ptr Entity =
  let arch = maskOf(cids)
  let (bid, id) = allocateEntity(world, arch, cids)

  let idx = id.s.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE
  var e = addr world.entities[idx]
  e.id = (bid shl BLK_SHIFT) or (id.s).uint
  e.archetype = arch
  
  addr world.entities[idx]

template deleteEntity(world:var EcsWorld, e:ptr Entity) =
  let l = deleteRow(world, (e.id and ((1.uint shl BLK_SHIFT)-1)).int, e.archetype)
  world.entities[(e.id and BLK_MASK) + ((e.id shr BLK_SHIFT) and BLK_MASK)*DEFAULT_BLK_SIZE] = world.entities[l]
  world.entities[l].id = e.id

template addComponent(world:var EcsWorld, e:ptr Entity| var Entity, components:seq[int]) =
  let oldArch = e.archetype
  let eid = e.id and BLK_MASK
  let beid = (e.id shr BLK_SHIFT) and BLK_MASK

  for id in components:
    e.archetype.setBit(id)

  if oldArch != e.archetype:
    let (lst, id, bid) = changePartition(world, e.id, oldArch, e.archetype)

    world.entities[id+bid*DEFAULT_BLK_SIZE] = e
    world.entities[eid+beid*DEFAULT_BLK_SIZE] = world.entities[lst]

    world.entities[lst].id = e.id

    e.id = (bid shl BLK_SHIFT) or id

template removeComponent(world:var EcsWorld, e:ptr Entity| var Entity, components:seq[int]) =
  let oldArch = e.archetype
  let eid = e.id and BLK_MASK
  let beid = (e.id shr BLK_SHIFT) and BLK_MASK

  for id in components:
    e.archetype.unSetBit(id)

  if oldArch != e.archetype:
    let (lst, id, bid) = changePartition(world, e.id, oldArch, e.archetype)

    world.entities[id+bid*DEFAULT_BLK_SIZE] = e
    world.entities[eid+beid*DEFAULT_BLK_SIZE] = world.entities[lst]

    world.entities[lst].id = e.id
    
    e.id = (bid shl BLK_SHIFT) or id