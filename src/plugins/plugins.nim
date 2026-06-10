####################################################################################################################################################
######################################################### PLUGIN SYSTEM ############################################################################
####################################################################################################################################################

import tables, typetraits, macros, options, std/monotimes, atomics, locks
import ../graph/graph
import ../events/events
include "bitset.nim"
include "data.nim"
include "message.nim"

type
  PluginStatus* = enum
    ## Define plugins status each representing a given state of a system, allowing his dependencies to know what is happening
    PLUGIN_OK # The plugin is working fine
    PLUGIN_ERR # The plugin encountered an error
    PLUGIN_DEPRECATED # The plugin data or state is stale
    PLUGIN_WAITING # The plugin is waiting for something 
    PLUGIN_NOT_READY # The plugin is not ready to execute
    PLUGIN_OFF # The plugin is uninitialized
  
  PluginNode* = ref object of RootObj
    ## Represents a system in our DAG, indexed by his ID
    ## `enabled` allows you make it run or not
    ## `localthread` forces the system to execute in the current thread.
    id*:int
    enabled*,localthread*:bool
    status:PluginStatus
    lasterr:CatchableError
    deps:Table[string, PluginNode]
    res:Bitset # Resources accessed by the system
    execAmount: int
    execCount: int
    lastTick*: int
    plugin: Plugin

  Plugin* = ref object
    ## Main object representing a set of system
    idtonode*:seq[PluginNode]
    res_manager*: PResourceManager
    bus: CEventBus
    graph:DiGraph
    parallel_cache:seq[array[2, seq[int]]]
    dirty:bool

  ParallelScheduler* = object
    graph: DiGraph
    execStream: Channel[int]
    cachedSorted: seq[int]
    cachedIndegree: seq[int]
    lock: Lock

  SynchronousScheduler* = object
    graph: DiGraph
    cachedSorted: seq[int]
    
  NullPluginNode* = ref object of PluginNode

const MAX_CHANNEL_SIZE = 128

proc newPlugin*(): Plugin =
  new(result)

template rebuildScheduler(p: Plugin, scheduler: untyped) =
  scheduler.graph = p.graph

  p.res_manager.buildGlobalAccessGraph()
  scheduler.graph.mergeEdgeInto(p.res_manager.cachedGraph)
  scheduler.cachedSorted = scheduler.graph.topo_sort

proc buildParallelScheduler(p: Plugin): ParallelScheduler =
  var scheduler = ParallelScheduler()
  p.rebuildScheduler(scheduler)
  scheduler.execStream.open(MAX_CHANNEL_SIZE)
  scheduler.lock.initLock()
  scheduler

proc buildSynchronousScheduler(p: Plugin): SynchronousScheduler =
  var scheduler = SynchronousScheduler()
  p.rebuildScheduler(scheduler)
  scheduler

template isDirty*(p: Plugin): bool = p.dirty
template getParallelCache*(p: Plugin): seq[array[2, seq[int]]] = p.parallel_cache
template getGraph*(p: Plugin): DiGraph = p.graph

template getStatus*(s:typed):untyped = s.status
template setStatus*(s:typed, st:PluginStatus) = 
  s.status = st

method awake*(p:PluginNode) {.base.} = p.setStatus(PLUGIN_OK)
method isReady*(p:PluginNode): bool {.base.} = true
method update*(p:PluginNode) {.base.} = discard
method shutdown*(p:PluginNode) {.base.} = p.setStatus(PLUGIN_OFF)
method merge*(p:PluginNode, p2:PluginNode):PluginNode {.base.} = p
method getObject(p:PluginNode):RootRef {.base.} = nil
method getCapability(p:PluginNode):RootRef {.base.} = nil
template asKey*(t:typedesc): string = $t
method asKey*(p:PluginNode):string {.base.} = asKey(p.typeof)
method increaseExecCount*(p: var PluginNode, n: int) {.base.} = p.execCount += n
method getExecCount(p: PluginNode): int {.base.} = p.execCount
method getExecAmount*(p: PluginNode): int {.base.} = 
  if p.execAmount == 0: 1 
  else: p.execAmount
method setExecAmount*(p: var PluginNode, n:int=1) {.base.} =
  p.execAmount = n

macro makeAsKey*(name) =
  return quote do:
    method asKey(p:`name`):string = $`name`

macro gameLogic*(name, logic:untyped) =
  return quote do:
    type
      `name` = ref object of PluginNode

    method update(self:`name`) =
      `logic`

    makeAsKey(`name`)

macro newSystem*(plugin: untyped, nameAndResources: untyped): untyped =
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

  let typeDef = quote do:
    type `sysName` = ref object of PluginNode
  
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

proc newNullPluginNode*():NullPluginNode =
  var v:NullPluginNode
  return v

include "operations.nim"
