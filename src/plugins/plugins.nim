####################################################################################################################################################
######################################################### PLUGIN SYSTEM ############################################################################
####################################################################################################################################################

import tables, typetraits
import ../graph/graph
import ../events/events
include "bitset.nim"
include "data.nim"

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
    res_manager: PResourceManager
    graph:DiGraph
    parallel_cache:seq[array[2, seq[int]]]
    dirty:bool

  NullPluginNode = ref object of PluginNode

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

macro newSystem*(plugin: untyped, nameAndResources: untyped, body: untyped): untyped =
  var res = newStmtList()

  # Parse system name and optional resource list
  var sysName: NimNode
  var readReqs: seq[NimNode] = @[]
  var writeReqs: seq[NimNode] = @[]

  if nameAndResources.kind == nnkBracketExpr:
    # system_name[R1, var R2, ...]
    sysName = nameAndResources[0]
    for i in 1..<nameAndResources.len:
      let param = nameAndResources[i]
      if param.kind == nnkVarTy:
        writeReqs.add(param[0])
      else:
        readReqs.add(param)
  else:
    # plain system_name
    sysName = nameAndResources

  # Generate: type system_name = ref object of PluginNode
  #             field1: T1
  #             ...
  var recList = newNimNode(nnkRecList)
  for field in body:
    let ex = newNimNode(nnkIdentDefs)
    ex.add(field[0], field[1][0], newNimNode(nnkEmpty))
    recList.add(ex)

  let typeDef = quote do:
    type `sysName` = ref object of PluginNode
  
  # Inject fields into the object def
  typeDef[0][2][0][2] = recList
  res.add(typeDef)

  # Generate: makeAsKey(system_name)
  res.add(newCall(ident"makeAsKey", sysName))

  # Generate: let id = addSystem(plugin, system_name)
  let idSym = genSym(nskLet, "id")
  res.add(quote do:
    let `idSym` = addSystem(`plugin`, `sysName`())
  )

  # Generate read/write requests
  for r in readReqs:
    res.add(quote do:
      addReadRequest[`r`](`plugin`.res_manager, `idSym`)
    )
  for w in writeReqs:
    res.add(quote do:
      addWriteRequest[`w`](`plugin`.res_manager, `idSym`)
    )

  # Return value is the id
  res.add(idSym)
  return res

macro genSystemTy*(sysName: untyped, body: untyped) =
  var res = newStmtList()

  # Generate: type system_name = ref object of PluginNode
  #             field1: T1
  #             ...
  var recList = newNimNode(nnkRecList)
  for field in body:
    let ex = newNimNode(nnkIdentDefs)
    ex.add(field[0], field[1][0], newNimNode(nnkEmpty))
    recList.add(ex)

  let typeDef = quote do:
    type `sysName` = ref object of PluginNode
  
  # Inject fields into the object def
  typeDef[0][2][0][2] = recList
  res.add(typeDef)

  # Generate: makeAsKey(system_name)
  res.add(newCall(ident"makeAsKey", sysName))

  return res

macro attachSystem*(plugin: untyped, nameAndResources: untyped, body: untyped): untyped =
  var res = newStmtList()

  # Parse system name and optional resource list
  var sysName: NimNode
  var readReqs: seq[NimNode] = @[]
  var writeReqs: seq[NimNode] = @[]

  if nameAndResources.kind == nnkBracketExpr:
    # system_name[R1, var R2, ...]
    sysName = nameAndResources[0]
    for i in 1..<nameAndResources.len:
      let param = nameAndResources[i]
      if param.kind == nnkVarTy:
        writeReqs.add(param[0])
      else:
        readReqs.add(param)
  else:
    # plain system_name
    sysName = nameAndResources

  # Generate: let id = addSystem(plugin, system_name)
  let idSym = genSym(nskLet, "id")
  res.add(quote do:
    let `idSym` = addSystem(`plugin`, `sysName`())
  )

  # Generate read/write requests
  for r in readReqs:
    res.add(quote do:
      addReadRequest[`r`](`plugin`.res_manager, `idSym`)
    )
  for w in writeReqs:
    res.add(quote do:
      addWriteRequest[`w`](`plugin`.res_manager, `idSym`)
    )

  # Return value is the id
  res.add(idSym)
  return res

proc newNullPluginNode():NullPluginNode =
  var v:NullPluginNode
  return v

include "operations.nim"
