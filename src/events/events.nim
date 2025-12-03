#[
Event system for Cruise
This implement the event system for, a stateful event system. You can change the state of the events to make them behave differently 
]#
import macros
import locks
import threadpool
import asyncdispatch
import os

const CHANNEL_SIZE = 64

type
  TaskVar = enum
    tsSingle, tsMulti

  EmissionVar = enum
    emSync, emParallel

  NotifVar = enum
    nValue, nEmit

  ExecVar = enum
    exAll, exOldest, exLatest

  DelayVar = enum
    dNone, dDelay

  # First our emission hierarchy

  Notification = ref object

  ##[ Encapsultate how the Notifier can be executed
  They define how it should emit signals (synchronously, asynchronously, etc).
  ]##
  EmissionState = ref object
    mode:TaskMode
    case kind : EmissionVar
    of emSync:
      priorities:bool
      consumes:bool
    of emParallel:
      wait:bool
  
  ##[
  The notifier State, it contains all the necessary information about the stae of the notifier.
  ]##
  NotifierState[T] = ref object
    case kind: NotifVar
    of nValue:
      value:T
      ignore_eqvalue:bool
    of nEmit:
      discard

  ##[
  TaskMode define how the emission should be donne for the asynchronous state.
  ]##
  TaskMode = ref object
    kind:TaskVar

  ##[
  Define if there should be a delay between emissions.
  ]##
  DelayMode = ref object
    case kind:DelayVar
    of dNone:
      discard
    of dDelay:
      first:bool
      duration:int

  ##[
  Represent the ways in which Listeners can be organized.
  ]##
  ExecMode = ref object
    case kind:ExecVar
    of exAll:
      discard
    of exLatest, exOldest:
      count:int 
        
  ##[
  Exception throwed when a function is called on Notifier with the wrong state.
  ]##
  StateMismatch = object of CatchableError

  ##[
  This represent the interface any listener type should implement in order to be considered a listener
  ]##
  AbstractListener = concept x
    callback(x)
    consume(x)
    getpriority(x)
    shouldstop(x)

  ##[
  Concrete Listener. Is used by default.
  ]##
  Listener*[T] = object
    callback:T
    consume:bool
    priority:int
    stop:bool

  ##[
  List of listeners for a given callback. Serve for registration purposes.
  ]##
  EmissionCallback[T,L] = ref object
    listeners:seq[Listener[L]]
    data:T

  ##[
  Keep all the necessary informations about the state of a Notifier
  ]##
  StateData[T,L] = ref object
    emission:EmissionState
    mode:NotifierState[T]
    exec:ExecMode
    delay:DelayMode
    stream:Channel[EmissionCallback[T,L]]
    check:bool

  ##[
  This object can be used for the observer pattern. It use a state machine to allow users to modiy its behavior at runtime.
  ]##
  Notifier*[T,L] = ref object
    cond:Cond
    lck:Lock
    listeners*:seq[Listener[L]]
    buffer:seq[EmissionCallback[T,L]]
    state*:StateData[T,L]

############################################################### ACCESSORS ###############################################################

proc callback[L](l:Listener[L]) = l.callback
proc getstate*(n:Notifier) = 
  return n.state
proc getstream(s:StateData) = s.stream

############################################################# CONSTRUCTORS ##############################################################

proc ExecAll():ExecMode =
  return ExecMode(kind:exAll)

proc ExecLatest(count:int):ExecMode =
  return ExecMode(kind:exLatest,count:count)

proc ExecOldest(count:int):ExecMode =
  return ExecMode(kind:exOldest, count:count)

proc newStateMismatch(msg:string): ref StateMismatch = 
  return newException(StateMismatch, message=msg)

proc SingleTask():TaskMode =
  return TaskMode(kind:tsSingle)

proc MultipleTask():TaskMode =
  return TaskMode(kind:tsMulti)

proc NoDelay():DelayMode =
  return DelayMode(kind:dNone)

proc Delay(first:bool, dur:int):DelayMode =
  return DelayMode(kind:dDelay, first:first, duration:dur)

proc SyncState(priorities, consumes:bool): EmissionState =
  return EmissionState(mode:SingleTask(),kind:emSync, priorities:priorities, consumes:consumes)

proc ParallelState(w:bool, mode:TaskMode=SingleTask()): EmissionState =
  return EmissionState(mode:mode,kind:emParallel, wait:w)

proc ValState[T](ignore_eqvalue:bool):NotifierState[T] =
  return NotifierState[T](kind:nValue, ignore_eqvalue:ignore_eqvalue)

proc EmitState[T]():NotifierState[T] =
  return NotifierState[T](kind:nEmit)

proc newStateData[T,L]() :StateData[T,L] = 
  var chan = Channel[EmissionCallback[T,L]]()

  chan.open(CHANNEL_SIZE)
  
  return StateData[T,L](emission:EmissionState(mode:TaskMode(kind:tsSingle), kind:emSync, priorities:false, consumes:false), 
    mode:NotifierState[T](kind:nEmit), 
    exec:ExecMode(kind:exAll), delay:DelayMode(kind:dNone), stream:chan, check:false)

proc newNotifier*[T,L]() :Notifier[T,L] =
  var cond = Cond()
  var lck = Lock()

  lck.initLock()
  cond.initCond()
  
  return Notifier[T,L](cond:cond, lck:lck, listeners:newSeq[Listener[L]](), buffer:newSeq[EmissionCallback[T,L]](), state:newStateData[T,L]())

################################################################ HELPERS ################################################################

macro notifier*(args:untyped) = 
  let nname = args[0]
  nname.expectKind(nnkIdent)

  var names = newNimNode(nnkBracket)
  var types = newNimNode(nnkPar)
  var namedtypes = newNimNode(nnkTupleTy)
  var procty = newNimNode(nnkProcTy)
  var ty = args[1..<args.len]
  
  var params = newNimNode(nnkFormalParams)
  params.add(newNimNode(nnkEmpty))
  procty.add(params)
  procty.add(newNimNode(nnkEmpty))

  if args.len > 1:

    for col in ty:
      let ident = newNimNode(nnkIdentDefs)
      let id = col[0]
      let t = col[1]
      names.add(id)
      types.add(t)
      ident.add(id)
      ident.add(t)
      ident.add(newNimNode(nnkEmpty))
      params.add(ident)
      namedtypes.add(ident)
  
  return quote do:
    var `nname` = newNotifier[`namedtypes`, `procty`]()

## Generate fn(tup[1],tup[2],...)
## This allows us to even use varargs and call the function as if each parameters was passed one by one.
macro destructuredCall*(fn:untyped, tup:typed) =
  let n = len(getType(tup))-1
  var callex = newNimNode(nnkCall)
  callex.add(fn)
  for i in 0..<n:
    callex.add((quote do: `tup`[`i`]))

  return quote do:
   `callex`

macro destructuredCallRet*(name:untyped, fn:untyped, tup:typed) =
  let n = len(getType(tup))-1
  var callex = newNimNode(nnkCall)
  callex.add(fn)
  for i in 0..<n:
    callex.add((quote do: `tup`[`i`]))

  return quote do:
   let `name` = `callex`


macro anoFunc(name:untyped, obj:typed, body:untyped) =
  var data = obj.getType()[1]

  var f = newNimNode(nnkLambda)
  f.add(newNimNode(nnkEmpty))
  f.add(newNimNode(nnkEmpty))
  f.add(newNimNode(nnkEmpty))

  var params = newNimNode(nnkFormalParams)
  params.add(newNimNode(nnkEmpty))

  var vs = newNimNode(nnkLetSection)
  var arg_bundle = newNimNode(nnkIdentDefs)
  vs.add(arg_bundle)
  arg_bundle.add(ident("allarg"))
  arg_bundle.add(newNimNode(nnkEmpty))

  var tup = newNimNode(nnkTupleConstr)
  let ids = @["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "w", "y","z"]

  for i in 1..<data.len:
    var ident = newNimNode(nnkIdentDefs)
    let id = ident(ids[i-1])
    ident.add(id)
    tup.add(id)
    ident.add(data[i])
    ident.add(newNimNode(nnkEmpty))

    params.add(ident)

  arg_bundle.add(tup)

  f.add(params)
  f.add(newNimNode(nnkEmpty))
  f.add(newNimNode(nnkEmpty))
  
  var stmt = newNimNode(nnkStmtList)
  stmt.add(vs)

  for i in 0..<body[1].len:
    stmt.add(body[1][i])

  f.add(stmt)

  return quote do:
    var `name` = `f`



include "pipeline.nim"
include "operations.nim"
include "state_operations.nim"
include "val_operations.nim"