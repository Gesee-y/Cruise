#[
Event system for Cruise
This implement the event system for, a stateful event system. You can change the state of the events to make them behave differently 
]#
import macros
import locks

const CHANNEL_SIZE = 64

type
  # First our emission hierarchy

  ##[ Encapsultate how the Notifier can be executed
  They define how it should emit signals (synchronously, asynchronously, etc).
  ]##
  EmissionState = ref object of RootObj
  
  ##[
  The notifier State, it contains all the necessary information about the stae of the notifier.
  ]##
  NotifierState = ref object of RootObj

  ##[
  TaskMode define how the emission should be donne for the asynchronous state.
  ]##
  TaskMode = ref object of RootObj

  ##[
  Define if there should be a delay between emissions.
  ]##
  DelayMode = ref object of RootObj

  ##[
  Represent the ways in which Listeners can be organized.
  ]##
  ExecMode = ref object of RootObj

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
  State that specify to the Notifier to execute all the callbacks
  ]##
  ExecAll = ref object of ExecMode

  ##[
  State that specify to the Notifier to execute just the latest callback
  ]##
  ExecLatest = ref object of ExecMode
    cond:Cond
    lck:Lock

  ##[
  This indicate to the Notifier to execute the first callbacks and ignore the others
  ]##
  ExecOldest = ref object of ExecMode
    lck:Lock
    count:int
  
  ##[
  This indicate to the Notifier to run all the listeners in one big task for async state
  ]##
  SingleTask = ref object of TaskMode

  ##[
  Indicate to the Notifier to run each listener on a specific task
  ]##
  MultipleTask = ref object of TaskMode

  ##[
  Says to the Notifier not to add a delay between listeners execution
  ]##
  NoDelay = ref object of DelayMode

  ##[
  Specify to the Notifier to add a delay of duration `duration` between listeners call.
  If `first` is true, then before the first listener is call, there will be a delay.
  ]##
  Delay = ref object of DelayMode
    first:bool
    duration:float

  ##[
  Specify to the Notifier to run asynchronously or in parallel.
  `mode` indicate how listeners should be called
  `wait` specify if the Notifier should wait for all the listener to finish before pursuing the program
  ]##
  AsyncState = ref object of EmissionState
    mode:TaskMode
    wait:bool
    parallel:bool

  ##[
  Specify to the Notifier to run synchronously, which means on a single thread.
  `priorities` enable the Notifier to take listener's priority into account
  `consumes` enable listeners to consume themselves
  ]##
  SyncState = ref object of EmissionState
    priorities:bool
    consumes:bool

  ##[
  Specify the Notifier to keep the value of the last emission.
  `ignore_eqvalue` means that the Notifier will not emit if the new value is the same as the old one.
  ]##
  ValState[T] = ref object of NotifierState
    ignore_eqvalue:bool
    value:T

  ##[
  This tell the Notifier we don't car eabout the last value it had.
  ]##
  EmitState = ref object of NotifierState

  ##[
  Keep all the necessary informations about the state of a Notifier
  ]##
  StateData[T,L] = ref object
    emission:EmissionState
    mode:NotifierState
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
    state*:StateData[T,L]

############################################################### ACCESSORS ###############################################################

proc getstate*(n:Notifier) = 
  return n.state
proc getstream(s:StateData) = s.stream

############################################################# CONSTRUCTORS ##############################################################

proc newExecLatest(notif:Notifier, count:int) =
  return ExecLatest(Lock(),count)

proc newExecOldest(notif:Notifier, count:int) =
  return ExecOldest(Lock(),count)

proc newStateMismatch(msg:string): ref StateMismatch = 
  return newException(StateMismatch, message=msg)

proc newStateData[T,L]() :StateData[T,L] = 
  return StateData[T,L](emission:SyncState(priorities:false, consumes:false), mode:EmitState(), 
    exec:ExecAll(), delay:NoDelay(), stream:Channel[EmissionCallback[T,L]](), check:false)

proc newNotifier*[T,L]() :Notifier[T,L] =
  return Notifier[T,L](cond:Cond(), lck:Lock(), listeners:newSeq[Listener[L]](), state:newStateData[T,L]())

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
   let `nname` = newNotifier[`namedtypes`, `procty`]()

## Generate fn(tup[1],tup[2],...)
## This allows us to even use varargs and call the function as if each parameters was passed one by one.
macro destructuredCall*(nm:untyped, fn:untyped, tup:typed) =
  let n = len(getType(tup))-1
  var callex = newNimNode(nnkCall)
  callex.add(fn)
  for i in 0..<n:
    callex.add((quote do: `tup`[`i`]))

  return quote do:
   let `nm` = `callex`
