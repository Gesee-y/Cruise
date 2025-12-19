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
    lasterr:CatchableError
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
    parallel_cache:seq[array[2, seq[int]]]
    dirty:bool

  NullPluginNode = ref object of PluginNode

include "layout.nim"

template getStatus(s:typed):untyped = s.status
template setStatus(s:typed, st:PluginStatus) = 
  s.status = st

method awake(p:PluginNode) {.base.} = p.setStatus(PLUGIN_OK)
method update(p:PluginNode) {.base.} = discard
method shutdown(p:PluginNode) {.base.} = p.setStatus(PLUGIN_OFF)
method merge(p:PluginNode, p2:PluginNode):PluginNode {.base.} = p
method getObject(p:PluginNode):int {.base.} = 0
method getCapability(p:PluginNode):int {.base.} = 0
method asKey(p:PluginNode):string {.base.} = $(p.typeof)

macro makeAsKey(name) =
  return quote do:
    method asKey(p:`name`):string = $`name`

macro gameLogic(name, logic:untyped) =
  return quote do:
    type
      `name` = ref object of PluginNode

    method update(self:`name`) =
      `logic`

    makeAsKey(`name`)
  
proc newNullPluginNode():NullPluginNode =
  var v:NullPluginNode
  return v

include "operations.nim"

gameLogic tst:
  echo "0"
