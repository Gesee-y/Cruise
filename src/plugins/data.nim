############################################################################################################################
#################################################### RESOURCES DAG #########################################################
############################################################################################################################

type
  PluginResource* = object
    data: pointer
    readRequests: seq[int]   # sys ids who read this resource
    writeRequests: seq[int]  # sys ids who write this resource
    dirty: bool
    cachedGraph: DiGraph

  PResourceManager* = ref object
    resources: seq[PluginResource]
    toId: Table[string, int]
    maxRequestId: int

proc newPluginResource[T](obj: T): PluginResource =
  result.data = cast[pointer](obj)

proc addResource*[T](manager: PResourceManager, obj: T): int =
  let id = manager.resources.len
  manager.resources.add(newPluginResource(obj))
  manager.toId[$T] = id
  return id

proc getResource*[T](manager: PResourceManager, id: int): T =
  return cast[T](manager.resources[id].data)

proc getResource*[T](manager: PResourceManager): T =
  getResource[T](manager, manager.toId[$T])

proc addReadRequest*(manager: PResourceManager, sys, id: int) =
  # A sys cannot read and write the same resource
  assert sys notin manager.resources[id].writeRequests,
    "sys " & $sys & " already has a write request on resource " & $id
  
  if sys in manager.resources[id].readRequests: return
  if sys > manager.maxRequestId:
    manager.maxRequestId = sys

  manager.resources[id].dirty = true
  manager.resources[id].readRequests.add sys

proc addReadRequest*[T](manager: PResourceManager, sys: int): int =
  var id = -1
  if not manager.toId.hasKey($T): addResource[T](manager)

proc addWriteRequest*(manager: PResourceManager, sys, id: int) =
  # A sys cannot read and write the same resource
  assert sys notin manager.resources[id].readRequests,
    "sys " & $sys & " already has a read request on resource " & $id
  
  if sys in manager.resources[id].writeRequests: return
  if sys > manager.maxRequestId:
    manager.maxRequestId = sys
  
  manager.resources[id].dirty = true
  manager.resources[id].writeRequests.add sys

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
proc buildAccessGraph*(res: var PluginResource) =
  # Collect the total number of systems involved to size the graph.
  # We work with sys IDs directly as node indices, so we need a graph
  # large enough to hold the largest sys id.
  
  res.readRequests.sort
  res
  var maxId = 0
  for s in res.readRequests:
    if s > maxId: maxId = s
  for s in res.writeRequests:
    if s > maxId: maxId = s

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
proc buildGlobalAccessGraph*(manager: PResourceManager): DiGraph =
  result = newGraph(manager.maxRequestId+1)
  for i in 0..<manager.resources.len:
    buildAccessGraph(manager.resources[i])
    discard result.mergeEdgeInto(manager.resources[i].cachedGraph)

proc getAccessGraph*(res: var PluginResource): DiGraph =
  if res.dirty:
    res.buildAccessGraph
    res.dirty = false

  return res.cachedGraph

