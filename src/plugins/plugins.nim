####################################################################################################################################################
######################################################### PLUGIN SYSTEM ############################################################################
####################################################################################################################################################

import tables
include "../graph/graph.nim"

type

  PluginStatus = enum
    PLUGIN_OK, PLUGIN_ERR, PLUGIN_DEPRECATED, PLUGIN_OFF
  
  PluginNode = object of RootObj
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
    parallel_cache:seq[int]
