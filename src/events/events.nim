#[
Event system for Cruise
This implement the event system for, a stateful event system. You can change the state of the events to make them behave differently 
]#
import macros

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
  Listener[T] = object
    callback:T
    consume:bool
    priority:int
    stop:bool

  ##[
  List of listeners for a given callback. Serve for registration purposes.
  ]##
  EmissionCallback[T] = ref object
    listeners:seq[Listener[T]]

  ##[
  State that specify to the Notifier to execute all the callbacks
  ]##
  ExecAll = object of ExecMode

  ##[
  State that specify to the Notifier to execute just the latest callback
  ]##
  ExecLatest = object of ExecMode

  ##[
  This indicate to the Notifier to execute the first callbacks and ignore the others
  ]##
  ExecOldest = object of ExecMode

  ##[
  This indicate to the Notifier to run all the listeners in one big task for async state
  ]##
  SingleTask = object of TaskMode

  ##[
  Indicate to the Notifier to run each listener on a specific task
  ]##
  MultipleTask = object of TaskMode

  ##[
  Says to the Notifier not to add a delay between listeners execution
  ]##
  NoDelay = object of DelayMode

  ##[
  Specify to the Notifier to add a delay of duration `duration` between listeners call.
  If `first` is true, then before the first listener is call, there will be a delay.
  ]##
  Delay = object of DelayMode
    first:bool
    duration:float

  ##[
  Specify to the Notifier to run asynchronously or in parallel.
  `mode` indicate how listeners should be called
  `wait` specify if the Notifier should wait for all the listener to finish before pursuing the program
  ]##
  AsyncState = object of EmissionState
    mode:TaskMode
    wait:bool
    parallel:bool

  ##[
  Specify to the Notifier to run synchronously, which means on a single thread.
  `priorities` enable the Notifier to take listener's priority into account
  `consumes` enable listeners to consume themselves
  ]##
  SyncState = object of EmissionState
    priorities:bool
    consumes:bool

  ##[
  Specify the Notifier to keep the value of the last emission.
  `ignore_eqvalue` means that the Notifier will not emit if the new value is the same as the old one.
  ]##
  ValState[T] = object of NotifierState
    ignore_eqvalue:bool
    value:T

  ##[
  This tel the Notifier we don't car eabout the last value it had.
  ]##
  EmitState = object of NotifierState

  ##[

  ]##
  StateData[T] = ref object
    emission:EmissionState
    mode:NotifierState
    exec:ExecMode
    delay:DelayMode
    stream:Channel[EmissionCallback[T]]
    check:bool


## Generete fn(tup[1],tup[2],...)
## This allows us to even use varargs and call the function as if each parameters was passed one by one.
macro destructuredCall*(fn:untyped, tup:typed) =
  let n = len(getType(tup))-1
  result = newNimNode(nnkCall)
  result.add(fn)
  for i in 0..<n:
    result.add((quote do: `tup`[`i`]))


################################################################ HELPERS ################################################################
proc newStateMismatch(msg:string): ref StateMismatch = 
  result = newException(StateMismatch, msg)