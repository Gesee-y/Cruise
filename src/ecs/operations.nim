################################################################################################################################################### 
############################################################# ECS OPERATIONS ######################################################################
################################################################################################################################################### 

proc createEntity(world:var EcsWorld, component:varargs[typed]):Entity =
  var e = newEntity()
  var cids:seq[int]

  for c in component:
    cids.add(world.registry.cmap[$typeof(c)])

  let arch = maskOf(component)
  let (bid, id) = allocateEntity(world, arch, cids)
  e.id = (bid shl 32) or id
  e.archetype = arch
  world.entities[id] = e

  return e

proc deleteEntity(world:var EcsWorld, e:Entity) =
  let l = deleteRow(world, e.id and ((1.uint << 32)-1), e.arch)
  world.entities[l].id = e.id