############################################################################################################################
#################################################### RESOURCES DAG #########################################################
############################################################################################################################

type
  PluginResource* = object
    data: pointer
    readRequests: seq[int]
    writeRequests: seq[int]
    cachedGraph:DiGraph

  PResourceManager* = ref object
    resources: seq[PluginResource]
    toId: Table[string, int]

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

proc addReadRequest*[T](manager: PResourceManager, sys, id:int) =
  var res = manager.resources[id]

  if sys in res.readRequests: return
  res.readRequests.add sys

proc addWriteRequest*[T](manager: PResourceManager, sys, id:int) =
  var res = manager.resources[id]

  if sys in res.writeRequests: return
  res.writeRequests.add sys

