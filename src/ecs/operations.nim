################################################################################################################################################### 
############################################################# ECS OPERATIONS ######################################################################
################################################################################################################################################### 

template createEntity(world:var EcsWorld, component:varargs):untyped =
  var e = newEntity()
  var cids:seq[int]

  for c in component:
    cids.add(world.registry.cmap[$typeof(c)])

  let arch = maskOf(cids)
  let (bid, id) = allocateEntity(world, arch)
  e.id = (bid shl 32) or (id.e-1).uint
  e.archetype = arch
  world.entities[e.id] = e

  e

template deleteEntity(world:var EcsWorld, e:Entity) =
  let l = deleteRow(world, e.id and ((1.uint << 32)-1), e.arch)
  world.entities[l].id = e.id

template addComponent(world:var EcsWorld, e:Entity, components:varargs[typed]) =
  let oldArch = e.archetype
  let eid = e.id and (1.uint << 32)-1

  for c in component:
    let id = world.registry.cmap[$typeof(c)]
    e.archetype.setBit(id)

  if oldArch == e.archetype: return
  let lst, id, bid = changeArchetype(world, eid, oldArch, e.archetype)

  world.entities[id] = e
  world.entities[eid] = world.entities[lst]

  world.entities[lst].id = e.id
  e.id = (bid shl 32) or id

template removeComponent(world:var EcsWorld, e:Entity, components:varargs[typedesc]) =
  let oldArch = e.archetype
  let eid = e.id and (1.uint << 32)-1

  for c in component:
    let id = world.registry.cmap[$c]
    e.archetype.unSetBit(id)

  if oldArch == e.archetype: return
  let lst, id, bid = changeArchetype(world, eid, oldArch, e.archetype)

  world.entities[id] = e
  world.entities[eid] = world.entities[lst]

  world.entities[lst].id = e.id
  e.id = (bid shl 32) or id