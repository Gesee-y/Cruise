################################################################################################################################################### 
############################################################# ECS OPERATIONS ######################################################################
################################################################################################################################################### 

template createEntity(world:var EcsWorld, component:varargs[string]):untyped =
  var e = newEntity()
  var cids:seq[int]

  for c in component:
    cids.add(world.registry.cmap[c])

  let arch = maskOf(cids)
  let (bid, id) = allocateEntity(world, arch)
  e.id = (bid shl BLK_SHIFT) or (id.s).uint
  e.archetype = arch
  world.entities[id.s.uint mod DEFAULT_BLK_SIZE + bid*DEFAULT_BLK_SIZE] = e

  e

template deleteEntity(world:var EcsWorld, e:Entity) =
  let l = deleteRow(world, (e.id and ((1.uint shl BLK_SHIFT)-1)).int, e.archetype)
  world.entities[(e.id and BLK_MASK) + ((e.id shr BLK_SHIFT) and BLK_MASK)*DEFAULT_BLK_SIZE] = world.entities[l]
  world.entities[l].id = e.id
  world.entities[l] = nil

template addComponent(world:var EcsWorld, e:Entity, components:varargs[string]) =
  let oldArch = e.archetype
  let eid = e.id and BLK_MASK
  let beid = (e.id shr BLK_SHIFT) and BLK_MASK

  for c in components:
    let id = world.registry.cmap[c]
    e.archetype.setBit(id)

  if oldArch != e.archetype:
    let (lst, id, bid) = changePartition(world, e.id, oldArch, e.archetype)

    world.entities[id+bid*DEFAULT_BLK_SIZE] = e
    world.entities[eid+beid*DEFAULT_BLK_SIZE] = world.entities[lst]

    world.entities[lst].id = e.id
    world.entities[lst] = nil

    e.id = (bid shl BLK_SHIFT) or id

template removeComponent(world:var EcsWorld, e:Entity, components:varargs[string]) =
  let oldArch = e.archetype
  let eid = e.id and BLK_MASK
  let beid = (e.id shr BLK_SHIFT) and BLK_MASK

  for c in components:
    let id = world.registry.cmap[c]
    e.archetype.unSetBit(id)

  if oldArch != e.archetype:
    let (lst, id, bid) = changePartition(world, e.id, oldArch, e.archetype)

    world.entities[id+bid*DEFAULT_BLK_SIZE] = e
    world.entities[eid+beid*DEFAULT_BLK_SIZE] = world.entities[lst]

    world.entities[lst].id = e.id
    world.entities[lst] = nil
    e.id = (bid shl BLK_SHIFT) or id