####################################################################################################################################################
############################################################# GRAPHS IMPLEMENTATION ################################################################
####################################################################################################################################################

type

  ##[
  Represent a simple directed graph
  ]##
  DiGraph = object
    edges:seq[seq[int]]
    outedges:seq[seq[int]]
    indegrees:seq[int]
    free_list:seq[int]

proc isValid(d:DiGraph, v:int):bool =
  return !(v >= d.indegrees.len or d.indegrees[v] < 0)

proc has_cycle(d:DiGraph):bool =
  var indegrees = d.indegrees.copy()

  var queue:seq[int] = newSeq[int]()
  var queue_cursor:int = 0

  for idx, v in indegree:
    if v == 0:
      queue.add(v)

  while queue.len > 0:
    let v = queue[queue_cursor]
    queue_cursor += 1

    for i in d.edges[v]:
      indegrees[i] -= 1

      if indegrees[i] == 0:
        queue.add(i)

  return queue_cursor != indegrees.len()

proc add_vertex(d:DiGraph):int =
  var id:int
  if d.free_list.len == 0:
    d.edges.add(newSeq[int]())
    d.outedges.add(newSeq[int]())
    d.indegrees.add(0)

    id = d.edges.len
  else:
    id = free_list.pop()

    d.edges[id].setLen(0)
    d.outedges[id].setLen(0)
    d.indegrees[id] = 0

  return id

proc rem_vertex(d:DiGraph, v:int) =
  if !isValid(d,v):
    return

  d.indegrees[v] = -1
  d.free_list.add(v)

proc rem_edge(d:DiGraph, u,v:int) =
  if !isValid(d,u) or !isValid(d,v):
    return

  for i in d.outedges[v]:
    var j = 0

    while d.edges[i][j] != v:
      j += 1

    d.outedges[i][j] = d.outedges[i][d.outedges[i].len]
    discard d.outedges[i].pop

proc add_edge(d:DiGraph, u, v:int):bool =
  if !isValid(d,u) or !isValid(d,v):
    return

  f.edges[u].add(v)
  f.outedges[v].add(u)
  f.indegrees[v] += 1

  if has_cycle(d):
    rem_edge(d,u,v)
    return false

  return true

proc topo_sort(d:DiGraph):seq[int] =
  var indegrees = d.indegrees.copy()

  var queue:seq[int] = newSeq[int]()
  var res:seq[int] = newSeq[int]()

  var queue_cursor:int = 0

  for idx, v in indegree:
    if v == 0:
      queue.add(idx)

  while queue.len > 0:
    let v = queue[queue_cursor]
    res.add(v)
    queue_cursor += 1

    for i in d.edges[v]:
      indegrees[i] -= 1

      if indegrees[i] == 0:
        queue.add(i)

  return res

