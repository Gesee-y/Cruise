####################################################################################################################################################
########################################################### OPERATIONS ON PLUGINS ##################################################################
####################################################################################################################################################

template isinitialized(s:typed):untyped = getstatus(s) == PLUGIN_OK
template isuninitialized(s:typed):untyped = getstatus(s) == PLUGIN_OFF
template isDeprecated(s:typed):untyped = getstatus(s) == PLUGIN_DEPRECATED
template hasFailed(s:typed):untyped = getstatus(s) == PLUGIN_ERR

template getLastError(s:typed):untyped = s.lasterr
template setLastErr(s:typed, e:Exception) = 
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
template getDependency(n:typed, d:string) = 
  if n.deps.hasKey(d): 
    return n.deps[d] 
    #else: error("Dependency $n not found in node")

#add_status_callback(f, p::CRPluginNode) = connect(f, p.status)

template getNodeid(n:typed, s:string):untyped =
  var res = -1

  for i,v in n.idtonode:
    if $(v.getObject.typeof) == s:
      res = i

  res 

proc addSystem(p:var Plugin, obj:var PluginNode):int =
  let id = add_vertex(p.graph)

  if id < p.idtonode.len:
    p.idtonode[id] = obj
  else:
    p.idtonode.add(obj)

  obj.id = id
  p.dirty = true

  return id

proc remSystem(p:var Plugin, id:int) =
  if id >= p.idtonode.len or p.idtonode[id] is NullPluginNode: return

  rem_vertex(p.graph, id)
  p.idtonode[id] = newNullPluginNode()
  p.dirty = true

proc addDependency(p:var Plugin, start:int, to:int) =
  if add_edge(p.graph, start, to):
    let par = p.idtonode[start]
    var child = p.idtonode[to]

    child.deps[par.asKey] = par
    p.dirty = true

    return true

  return false

proc remDependency(p:var Plugin, start:int, to:int) =
  if rem_edge(p.graph, start, to):
    p.idtonode[to].deps.delete(p.idtonode[start].asKey)
    p.dirty = true

proc mergePlugin(p1:Plugin, p2:Plugin) =
  var
    obj_to_id:Table[string, id]
    idmap:Table[int,int]

  for i,n in p1.idtonode:
    obj_to_id[n.asKey] = i

  for i,n in p2.idtonode:
    if obj_to_id.hasKey(n.asKey):
      idmap[i] = obj_to_id[n.asKey]
    else:
      let id = add_system(p1, n)
      idmap[i] = id

  for i,vec in p2.graph.outedges:
    if p.graph.indegrees[i] >= 0:
      for j in vec:
        let start = idmap[i]
        let stop = idmap[j]

        addDependency(p1, start, stop)

  p.dirty = true

template exec_node(f, n) =
  try:
    f(n)
  except as e:
    n.setLastErr(e)
    n.setStatus(PLUGIN_ERR)

proc computeParallelLevel(p:var Plugin) =
  let graph = p.graph
  let sorted = graph.KahnTopoSort()
  var levels = newSeq[int](graph.indegrees.len)
  var maximum = 0

  for v in sorted:
    var max_parent_level = -1

    for p in graph.inedges[v]:
      max_parent_level = max(max_parent_level, levels[p])

    maximum = max(max_parent_level, maximum)
    levels[v] = max_parent_level+1

  var result:seq[(seq[int], seq[int])]
  for i in 1..maximum:
    result.add((newSeq[int](0), newSeq[int](0)))

  for i in sorted:
    let mainthread_id = p.idtonode[i].mainthread.int
    let level = levels[i]

    result[level][mainthread_id].add(i)

  p.parallel_cache = result
  p.dirty = false

template smap(f,p:Plugin) =
  let tsort = p.graph.KahnTopoSort()
  for i in tsort:
    var n = p.idtonode[i]
    exec_node(f, n)

template pmap(f,p:Plugin) =
  if p.dirty: computeParallelLevel(p)

  for level in p.parallel_cache:
    
    # TODO: Add parallelism here
    for i in level[0]:
      var n = p.idtonode[i]
      exec_node(f, n)

    for i in level[1]:
      var n = p.idtonode[i]
      exec_node(f, n)
