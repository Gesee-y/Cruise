####################################################################################################################################################
############################################################# GRAPHS IMPLEMENTATION ################################################################
####################################################################################################################################################

import algorithm

# digraph.nim
# Directed graph (dynamic) with O(1) edge removal via swap-remove + back-index.
# - outedges[u]: seq[EdgeInfo]  => children of u (u -> v)
# - inedges[v]: seq[EdgeInfo] => parents of v (u <- v)
# - EdgeInfo.back = index in the opposite list

type
  EdgeInfo = object
    idx: int    # neighbor node index
    back: int   # index in the opposite adjacency list

  DiGraph = object
    outedges: seq[seq[EdgeInfo]]     # children lists
    inedges: seq[seq[EdgeInfo]]  # parent lists
    indegrees: seq[int]
    free_list: seq[int]
    sort_cache: seq[int]
    dirty: bool

# ---------- Construction ----------

proc newGraph(initialNodes = 0): DiGraph =
  result.outedges = newSeq[seq[EdgeInfo]](initialNodes)
  result.inedges = newSeq[seq[EdgeInfo]](initialNodes)
  result.indegrees = newSeq[int](initialNodes)
  result.free_list = @[]
  for i in 0..<initialNodes:
    result.outedges[i] = @[]
    result.inedges[i] = @[]
    result.indegrees[i] = 0

# ----------- Iterators ----------

iterator indexIterator(s:seq[seq[EdgeInfo]], v:int):int =
  for info in s[v]:
    let idx:int = info.idx
    yield idx

# ----------- Utilities ----------

proc isValid(d: DiGraph, v: int): bool =
  result = v >= 0 and v < d.indegrees.len and d.indegrees[v] >= 0

# find position of neighbor 'target' in edges[u]; returns -1 if not found
proc findPosChild(d: DiGraph, u, target: int): int =
  result = -1
  if not isValid(d, u): return
  for i in 0..<d.outedges[u].len:
    if d.outedges[u][i].idx == target:
      result = i
      break

# find position of neighbor 'target' in outedges[v]; returns -1 if not found
proc findPosParent(d: DiGraph, v, target: int): int =
  result = -1
  if not isValid(d, v): return
  for i in 0..<d.inedges[v].len:
    if d.inedges[v][i].idx == target:
      result = i
      break

# swap-remove helper for children list edges[u] at position pos
proc swapPopChild(d: var DiGraph, u, pos: int) =
  let last = d.outedges[u].len - 1
  if pos < 0 or pos > last: return
  if pos != last:
    let moved = d.outedges[u][last]
    d.outedges[u][pos] = moved
    # update the moved element's counterpart in outedges[moved.idx]
    # moved.back is the index in outedges[moved.idx] where the reference to u sits
    d.inedges[moved.idx][moved.back].back = pos
  d.outedges[u].setLen(last)

# swap-remove helper for parents list outedges[v] at position pos
proc swapPopParent(d: var DiGraph, v, pos: int) =
  let last = d.inedges[v].len - 1
  if pos < 0 or pos > last: return
  if pos != last:
    let moved = d.inedges[v][last]
    d.inedges[v][pos] = moved
    # update counterpart in edges[moved.idx]
    d.outedges[moved.idx][moved.back].back = pos
  d.inedges[v].setLen(last)

proc has_cycle(d:DiGraph):bool =
  var indegrees = d.indegrees

  var queue:seq[int] = newSeq[int]()
  var queue_cursor:int = 0

  for idx, v in indegrees:
    if v == 0:
      queue.add(idx)

  while queue_cursor < queue.len:
    let v = queue[queue_cursor]
    queue_cursor += 1

    for info in d.outedges[v]:
      let i = info.idx
      indegrees[i] -= 1

      if indegrees[i] == 0:
        queue.add(i)

  return queue_cursor != indegrees.len()

# ---------- Vertex ops ----------

proc add_vertex(d: var DiGraph): int =
  d.dirty = true
  if d.free_list.len > 0:
    let id = d.free_list.pop()
    d.outedges[id].setLen(0)
    d.inedges[id].setLen(0)
    d.indegrees[id] = 0
    return id
  else:
    let id = d.outedges.len
    d.outedges.add(newSeq[EdgeInfo](0))
    d.inedges.add(newSeq[EdgeInfo](0))
    d.indegrees.add(0)
    return id

proc rem_vertex(d: var DiGraph, v: int) =
  if not isValid(d, v): return
  d.dirty = true

  # collect parents and children indices (we iterate copies because removals mutate lists)
  var parents = newSeq[int]()
  for e in d.inedges[v]:
    parents.add(e.idx)
  var children = newSeq[int]()
  for e in d.outedges[v]:
    children.add(e.idx)

  # remove incoming edges u -> v
  for u in parents:
    # find pos of v in children[u] (should exist)
    let posChild = findPosChild(d, u, v)
    if posChild >= 0:
      swapPopChild(d, u, posChild)
    # find the parent's pos in outedges[v] (may shift while removing multiple edges, but we remove by child side later)
    # we will remove entries from outedges[v] after children removals

  # remove outgoing edges v -> w
  for w in children:
    let posParent = findPosParent(d, w, v)
    if posParent >= 0:
      swapPopParent(d, w, posParent)
      dec d.indegrees[w]

  # finally, clear remaining references in v's own lists (they should be empty but ensure)
  d.outedges[v].setLen(0)
  d.inedges[v].setLen(0)
  d.indegrees[v] = -1
  d.free_list.add(v)

# ---------- Edge ops ----------

# reachable search: does 'start' reach 'target' ? (DFS iterative)
proc reachable(d: DiGraph, start, target: int): bool =
  if not isValid(d, start) or not isValid(d, target): return false
  if start == target: return true
  
  var seen = newSeq[bool](d.indegrees.len)
  var stack = newSeq[int]()
  
  stack.add(start)
  seen[start] = true
  
  while stack.len > 0:
    let x = stack.pop()
    for e in d.outedges[x]:
      let y = e.idx
      if y == target: return true
      if not seen[y]:
        seen[y] = true
        stack.add(y)

  return false

# Add directed edge u -> v if it doesn't create a cycle.
# Returns true if added, false otherwise.
proc add_edge(d: var DiGraph, u, v: int): bool =
  if not isValid(d,u) or not isValid(d,v) or u == v: return false
  # if edge already exists, nothing to do
  if findPosChild(d, u, v) >= 0:
    return true

  # cheap cycle test: if v reaches u, adding u->v would create a cycle
  if reachable(d, v, u):
    return false

  d.dirty = true
  let posChild = d.outedges[u].len
  let posParent = d.inedges[v].len

  d.outedges[u].add(EdgeInfo(idx: v, back: posParent))
  d.inedges[v].add(EdgeInfo(idx: u, back: posChild))
  inc d.indegrees[v]
  return true

proc rem_edge(d: var DiGraph, u, v: int):bool =
  if not isValid(d,u) or not isValid(d,v): return false
  
  d.dirty = true
  let posChild = findPosChild(d, u, v)
  if posChild == -1: return false
  let backIdx = d.outedges[u][posChild].back
  # swap-remove both sides (order: child then parent)
  swapPopChild(d, u, posChild)
  swapPopParent(d, v, backIdx)
  dec d.indegrees[v]

  return true


template DFSTopoSort*(d): untyped =

  ## Eval to a topological sort of the graph, or `len==0 seq` if cyclic.
  if d.dirty:                      # scope for `procs`
    var did = newSeq[bool](d.indegrees.len)     # Could save space with `result: HashSet[I]` or
    var result: seq[int]            #..just `seq[T].contains` for really small TCs.
    
    proc visit(x: int) =          # Depth First Search (DFS)
      did[x] = true             # Mark current node as visited.
      for y in indexIterator(d.outedges,x):    # Recurse to all kids of this node
        if not did[y]: visit(y)
      result.add x              # Add node to stack storing reversed result                                                            
    for b in 0..<d.indegrees.len:
      if not did[b]: visit(b)
    result.reverse
    
    d.sort_cache = result
    d.dirty = false

  d.sort_cache

template topo_sort(d:var DiGraph):untyped =
  if d.dirty:
    var indegrees = d.indegrees

    var queue:seq[int]
    var res:seq[int]

    var queue_cursor:int = 0

    for i in 0..<indegrees.len:
      if indegrees[i] == 0:
        queue.add(i)

    while queue_cursor < queue.len:
      let v = queue[queue_cursor]
      res.add(v)
      inc queue_cursor

      for i in indexIterator(d.outedges,v):
        dec indegrees[i]

        if indegrees[i] == 0:
          queue.add(i)

    d.sort_cache = res
    d.dirty = false

  d.sort_cache

# ---------- Debug helpers ----------

proc debugPrint(d: DiGraph) =
  echo "Graph:"
  for i in 0..<d.outedges.len:
    if d.indegrees[i] < 0: continue
    stdout.write($i & ": children = [")

    for idx,e in d.outedges[i]:
      stdout.write($e.idx & "(" & $e.back & ")")
      if idx < d.outedges[i].len-1:
        stdout.write(", ")
    stdout.write("] parents = [")
    for idx,p in d.inedges[i]:
      stdout.write($p.idx & "(" & $p.back & ")")
      if idx < d.inedges[i].len-1:
        stdout.write(", ")
    stdout.write("]\n")

