####################################################################################################################################################
########################################################### OPERATIONS ON PLUGINS ##################################################################
####################################################################################################################################################

template isinitialized(s:typed):untyped = getstatus(s) == PLUGIN_OK
template isuninitialized(s:typed):untyped = getstatus(s) == PLUGIN_OFF
template isDeprecated(s:typed):untyped = getstatus(s) == PLUGIN_DEPRECATED
template hasFailed(s:typed):untyped = getstatus(s) == PLUGIN_ERR

template getLastError(s:typed):untyped = s.lasterr
template setLastErr(s:typed, e) = 
  s.lasterr = e

template hasFailedDeps(s:typed):untyped = 
  var res = false
  for k,v in s.deps.pairs:
    if hasfailed(v):
      res = true

  res

template hasUninitializedDeps(s:typed):untyped = 
  var res = false
  for k,v in s.deps.pairs:
    if isuninitialized(v):
      res = true

  res

template hasAllDepsInitialized(s:typed):untyped =
  var res = true
  for k,v in s.deps.pairs:
    if isuninitialized(v) or hasfailed(v):
      res = false
      break
  res


#template hasdeaddeps(s:typed):untyped = any(isnothing, values(_getdata(s.deps)))
template getDependency[T](n:typed):untyped = 
  let d = $T
  if not n.deps.hasKey(d): 
    raise newException(OSError, "Dependency $n not found in node")

  T(n.deps[d])
#add_status_callback(f, p::CRPluginNode) = connect(f, p.status)

template getNodeid(n:typed, s:string):untyped =
  var res = -1

  for i,v in n.idtonode:
    if $(v.getObject.typeof) == s:
      res = i

  res 

template addSystem(p:var Plugin, obj):int =
  var id = -1
  for i in 0..<p.idtonode.len:
    if p.idtonode[i].asKey == obj.asKey:
      id = i
      break

  if id < 0:
    id = add_vertex(p.graph)

    if id < p.idtonode.len:
      p.idtonode[id] = obj
    else:
      p.idtonode.add(obj)

    obj.id = id
    p.dirty = true

  if id > p.res_manager.maxRequestId:
    p.res_manager.maxRequestId = id

  id

proc remSystem(p:var Plugin, id:int) =
  if id >= p.idtonode.len or p.idtonode[id] == nil: return

  rem_vertex(p.graph, id)
  p.idtonode[id] = nil
  p.dirty = true

  for res in p.res_manager.resources.mitems:
    res.dirty = res.readRequests.contains(id) or res.writeRequests.contains(id)
    res.readRequests.excl id

proc addDependency(p:var Plugin, start:int, to:int):bool =
  if add_edge(p.graph, start, to):
    let par = p.idtonode[start]
    var child = p.idtonode[to]

    child.deps[par.asKey] = par
    p.dirty = true

    return true

  return false

proc remDependency(p:var Plugin, start:int, to:int) =
  if rem_edge(p.graph, start, to):
    p.idtonode[to].deps.del(p.idtonode[start].asKey)
    p.dirty = true

proc mergePlugin(p1:var Plugin, p2:var Plugin) =
  var
    obj_to_id:Table[string, int]
    idmap:Table[int,int]

  for i,n in p1.idtonode:
    obj_to_id[n.asKey] = i

  for i in 0..<p2.idtonode.len:
    var n = p2.idtonode[i]
    if obj_to_id.hasKey(n.asKey):
      idmap[i] = obj_to_id[n.asKey]
    else:
      let id = add_system(p1, n)
      idmap[i] = id

  for i,vec in p2.graph.outedges:
    if p2.graph.indegrees[i] >= 0:
      for j in vec:
        let start = idmap[i]
        let stop = idmap[j.idx]

        discard addDependency(p1, start, stop)

  p1.dirty = true

template exec_node(f, n) =
  try:
    f(n)
  except CatchableError as e:
    n.setLastErr(e[])
    n.setStatus(PLUGIN_ERR)

proc computeParallelLevel(p:var Plugin) =
  var graph = p.graph

  p.res_manager.buildGlobalAccessGraph
  graph.mergeEdgeInto(p.res_manager.cachedGraph)

  let sorted = graph.topo_sort()
  var levels = newSeq[int](graph.indegrees.len)
  var maximum = 0

  for v in sorted:
    var max_parent_level = -1

    for p in graph.inedges[v]:
      max_parent_level = max(max_parent_level, levels[p.idx])

    maximum = max(max_parent_level, maximum)
    levels[v] = max_parent_level+1

  var result:seq[array[2, seq[int]]]
  for i in 0..levels[sorted[^1]]:
    result.add([newSeq[int](0), newSeq[int](0)])

  for i in sorted:
    let mainthread_id = p.idtonode[i].mainthread.int
    let level = levels[i]

    result[level][mainthread_id].add(i)

  p.parallel_cache = result
  p.dirty = false

template smap(f:untyped,p:Plugin) =
  let tsort = p.graph.topo_sort()
  for i in tsort:
    var n = p.idtonode[i]
    exec_node(f, n)

template pmap(f:untyped,p:Plugin) =
  if p.dirty: computeParallelLevel(p)

  for level in p.parallel_cache:
    
    # TODO: Add parallelism here
    for i in level[0]:
      var n = p.idtonode[i]
      exec_node(f, n)

    for i in level[1]:
      var n = p.idtonode[i]
      exec_node(f, n)
             