####################################################################################################################################################
######################################################### PLUGIN SYSTEM ############################################################################
####################################################################################################################################################

import tables, typetraits
include "../graph/graph.nim"
include "../events/events.nim"


type

  PluginStatus = enum
    PLUGIN_OK, PLUGIN_ERR, PLUGIN_DEPRECATED, PLUGIN_OFF
  
  PluginNode = ref object of RootObj
    id:int
    enabled,mainthread:bool
    status:PluginStatus
    lasterr:Exception
    deps:Table[string, PluginNode]

  EffectivePluginNode = concept node
    awake(node)
    update(node)
    shutdown(node)
    getCapability(node)
    getObject(node)

  Plugin = object
    idtonode:seq[PluginNode]
    graph:DiGraph
    parallel_cache:seq[(seq[int], seq[int])]
    dirty:bool

  NullPluginNode = object of PluginNode

template getStatus(s:typed):untyped = s.status
template setStatus(s:typed, st:PluginStatus) = 
  s.status = st

method awake(p:PluginNode) {.base.} = p.setStatus(PLUGIN_OK)
method update(p:PluginNode) {.base.} = discard
method shutdown(p:PluginNode) {.base.} = p.setStatus(PLUGIN_OFF)
method getObject(p:PluginNode):int {.base.} = 0
method getCapability(p:PluginNode):int {.base.} = 0
method asKey(p:PluginNode):string = $(p.getObject.typeof)

include "operations.nim"