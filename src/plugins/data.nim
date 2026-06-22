############################################################################################################################
#################################################### RESOURCES DAG #########################################################
############################################################################################################################

type
  PluginResource* = object
    data: pointer
    readRequests: BitSet   # sys ids who read this resource
    writeRequests: BitSet  # sys ids who write this resource
    isWriteRequested: Atomic[int]
    isReadRequested: Atomic[int]
    dirty: bool
    cachedGraph: DiGraph

  PResourceManager* = object
    resources*: seq[PluginResource]
    maxRequestId: int
    cachedGraph: DiGraph
    toId:Table[string, seq[int]]
    sysToRes: Table[int, seq[int]]
    dirty: bool
    inited: bool

proc newPluginResource[T](obj: T): PluginResource =
  result.data = cast[pointer](obj)

template contains(s: seq[bool], sys:int): bool =
  s[sys]

template contains(s: var seq[Atomic[bool]], sys:int): bool =
  s[sys].load()

proc anySet(s: seq[bool]): bool =
  for b in s:
    if b:
      return true

  return false

proc anySet(s: var seq[Atomic[bool]]): bool =
  for b in s.mitems():
    if b.load():
      return true

  return false

proc addResource*[T](manager: var PResourceManager, obj: T): int =
  let id = manager.resources.len
  manager.resources.add(newPluginResource(obj))
  manager.dirty = true

  if not manager.toId.hasKey($T):
    manager.toId[$T] = newSeq[int]()

  manager.toId[$T].add(id)

  return id

proc getId[T](m:PResourceManager, t:typedesc[T], i: int = 0): int =
  m.toId[$T][i]

proc getResourceFromId*[T](manager: PResourceManager, id: int): T =
  return cast[T](manager.resources[id].data)

proc getResource*[T](manager: var PResourceManager, i:int=0): T =
  let id = manager.toId[$T][i]
  return cast[T](manager.resources[id].data)

proc resetRequest(res: var PluginResource, sys: int) =
  if sys in res.writeRequests: discard res.isWriteRequested.fetchSub(1)
  if sys in res.readRequests: discard res.isReadRequested.fetchSub(1)

proc addReadRequest*(manager: var PResourceManager, sys, id: int) =
  # A sys cannot read and write the same resource
  assert not manager.resources[id].writeRequests.contains(sys),
    "sys " & $sys & " already has a write request on resource " & $id
  if sys in manager.resources[id].readRequests: return

  if sys > manager.maxRequestId:
    manager.maxRequestId = sys

  if sys notin manager.sysToRes:
    manager.sysToRes[sys] = @[]

  manager.sysToRes[sys].add(id)
  manager.resources[id].dirty = true
  manager.dirty = true
  manager.resources[id].readRequests.incl sys

proc addReadRequest*[T](manager: var PResourceManager, sys: int) =
  manager.addReadRequest(sys, manager.toId[$T][0])

proc addWriteRequest*(manager: var PResourceManager, sys, id: int) =
  # A sys cannot read and write the same resource
  assert not manager.resources[id].readRequests.contains(sys),
    "sys " & $sys & " already has a read request on resource " & $id
  if sys in manager.resources[id].writeRequests: return

  if sys > manager.maxRequestId:
    manager.maxRequestId = sys

  if sys notin manager.sysToRes:
    manager.sysToRes[sys] = @[]

  manager.sysToRes[sys].add(id)
  manager.resources[id].dirty = true
  manager.dirty = true
  manager.resources[id].writeRequests.incl sys

proc addWriteRequest[T](manager: var PResourceManager, sys: int) =
  manager.addWriteRequest(sys, manager.toId[$T][0])

# ------------------------------------------------------------
# Build the access graph for a single resource.
#
# Rules:
#   - writer -> all other writers   (W/W conflict: must be sequential)
#   - writer -> all readers         (W/R conflict: must be sequential)
#   - reader -> all writers         (R/W conflict: must be sequential)
#   - reader <-> reader             (no conflict: parallel allowed, no edge)
#
# The direction of the edge encodes execution order (u must run before v).
# When both orderings would create a cycle (e.g. two writers with no prior
# ordering), add_edge will refuse the second direction; the caller should
# enforce an explicit ordering via a scheduler pass afterward.
# ------------------------------------------------------------
proc buildAccessGraph(res: var PluginResource) =
  if not res.dirty: return
  # Collect the total number of systems involved to size the graph.
  # We work with sys IDs directly as node indices, so we need a graph
  # large enough to hold the largest sys id.

  var maxId = max(res.readRequests.max, res.writeRequests.max)

  res.cachedGraph = newGraph(maxId + 1)

  # Writers conflict with everyone else (readers and other writers).
  for w in res.writeRequests:
    # w -> every other writer (sequential ordering between writers)
    for w2 in res.writeRequests:
      if w == w2: continue
      discard res.cachedGraph.add_edge(w, w2)

    # w -> every reader
    for r in res.readRequests:
      discard res.cachedGraph.add_edge(w, r)

# Build and merge access graphs for ALL resources into one global graph
# that encodes which systems can run in parallel across all resources.
proc buildGlobalAccessGraph(manager: var PResourceManager) =
  if not manager.dirty and manager.inited: return
  var result = newGraph(manager.maxRequestId+1)
  for i in 0..<manager.resources.len:
    buildAccessGraph(manager.resources[i])
    result.mergeEdgeInto(manager.resources[i].cachedGraph)

  manager.inited = true
  manager.dirty = false
  manager.cachedGraph = result

proc getAccessGraph(res: var PluginResource): DiGraph =
  if res.dirty:
    res.buildAccessGraph
    res.dirty = false

  return res.cachedGraph

proc mergeResourceManager*(p1, p2: var PResourceManager, idmap: Table[int, int]) =
  for t, resourceIds in p2.toId:
    if t notin p1.toId:
      p1.toId[t] = newSeq[int]()

    for resIdx in resourceIds:
      var resource = p2.resources[resIdx]

      # Remap read requests
      var newReadRequests = newBitSet()
      for i in resource.readRequests:
        if i in idmap:
          newReadRequests.incl(idmap[i])
      resource.readRequests = newReadRequests

      # Remap write requests
      var newWriteRequests = newBitSet()
      for i in resource.writeRequests:
        if i in idmap:
          newWriteRequests.incl(idmap[i])
      resource.writeRequests = newWriteRequests

      resource.dirty = true

      p1.toId[t].add(p1.resources.len)
      p1.resources.add(resource)

    p1.dirty = true
