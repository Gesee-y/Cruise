################################################################################################################################################### 
############################################################# ECS OPERATIONS ######################################################################
################################################################################################################################################### 

type
  ECSOpCode = enum
    DeleteOp = 0
    MigrateOp = 1

################################################################################################################################################### 
############################################################ DENSE OPERATIONS ######################################################################
################################################################################################################################################### 

proc createEntity(world:var ECSWorld, cids:varargs[int]):DenseHandle =
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

proc createEntities(world:var ECSWorld, n:int, cids:varargs[int]):seq[DenseHandle] =
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

template deleteEntity(world:var ECSWorld, d:DenseHandle) =
  let e = d.obj
  
  #check(not e.isNil, "Invalid access. Trying to access nil entity.")
  #check(world.generations[e.widx] == d.gen, "Invalid Entity. Entity is stale (already dead).")

  let l = deleteRow(world, e.id, e.archetypeId)
  world.handles[(e.id and BLK_MASK) + ((e.id shr BLK_SHIFT) and BLK_MASK)*DEFAULT_BLK_SIZE] = world.handles[l]
  world.handles[l].id = e.id
  world.generations[e.widx] += 1.uint32
  world.free_entities.add(e.widx)

template deleteEntityDefer(world:var ECSWorld, d:DenseHandle, buffer_id:int) =
  world.cb[buffer_id].addComponent(DeleteOp.int, d.obj.archetypeId, 0'u32, PayLoad(eid:d.obj.widx.uint, obj:d))

proc migrateEntity(world: var ECSWorld, d:DenseHandle, archNode:ArchetypeNode) =
  let e = d.obj

  check(not e.isNil, "Invalid access. Trying to access nil entity.")
  check(world.generations[e.widx] == d.gen, "Invalid Entity. Entity is stale (already dead).")
  
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

template migrateEntityDefer(world:var ECSWorld, d:DenseHandle, archNode:ArchetypeNode, buffer_id:int) =
  world.cb[buffer_id].addComponent(MigrateOp.int, archNode.id, d.obj.archetypeId.uint32, PayLoad(eid:d.obj.widx.uint, obj:d))

proc addComponent(world:var EcsWorld, d:DenseHandle, components:varargs[int]) =
  let e = d.obj
  let oldArch = world.archGraph.nodes[e.archetypeId]
  var archNode = oldArch
  for id in components:
    archNode = world.archGraph.addComponent(archNode, id)

  migrateEntity(world, d, archNode)

proc removeComponent(world:var EcsWorld, d:DenseHandle, components:varargs[int]) =
  let e = d.obj
  let oldArch = world.archGraph.nodes[e.archetypeId]
  var archNode = oldArch
  for id in components:
    archNode = world.archGraph.removeComponent(archNode, id)

  migrateEntity(world, d, archNode)

################################################################################################################################################### 
########################################################## SPARSE OPERATIONS ######################################################################
################################################################################################################################################### 

proc createSparseEntity(w:var ECSWorld, components:varargs[int]):SparseHandle =
  let id = w.allocateSparseEntity(components)
  return SparseHandle(id:id, gen:w.sparse_gens[id], mask:maskOf(components))

proc createSparseEntities(w:var ECSWorld, n:int, components:varargs[int]):seq[SparseHandle] =
  var res = newSeqOfCap[SparseHandle](n)
  let ids = w.allocateSparseEntities(n, components)
  let mask = maskOf(components)

  for r in ids:
    for i in r.s..<r.e:
      res.add(SparseHandle(id:i.uint, gen:w.sparse_gens[i], mask:mask))

  return res

proc deleteEntity(w:var ECSWorld, s:var SparseHandle) =
  w.deleteSparseRow(s.id, s.mask)
  w.sparse_gens[s.id] += 1

proc addComponent(w:var ECSWorld, s:var SparseHandle, components:varargs[int]) =
  s.mask.setBit(components)
  w.activateComponentsSparse(s.id, components)

proc removeComponent(w:var ECSWorld, s:var SparseHandle, components:varargs[int]) =
  s.mask.unSetBit(components)
  w.deactivateComponentsSparse(s.id, components)
