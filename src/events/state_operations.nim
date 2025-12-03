#################################################################################################################################################
########################################################## STATE OPERATIONS #####################################################################
#################################################################################################################################################

##[
Add a delay to the notifier between each listener call.
- `dur` is the duration of the delay in milliseconds
- `first` is if there should be a delay before the first listener call
]##
proc delay*[T,L](n: var Notifier[T,L], dur:int, first:bool=false) =
  let d = Delay(first, dur)
  n.state.delay = d

proc hasDelay*[T,L](n:Notifier[T,L]):bool = 
  return n.state.delay.kind == nDelay

proc hasDelayFirst*[T,L](n:Notifier[T,L]):bool = 
  return n.state.delay.kind == nDelay && n.state.delay.first

##[
Whether there should be a delay before the first listener call
]##
proc delayFirst*[T,L](n: var Notifier[T,L], first:bool=false) =
  var d = n.state.delay
  doAssert d.kind == dDelay

  d.first = first

##[
Remove the delay between listeners calls if there is any
]##
proc noDelay*[T,L](n: var Notifier[T,L]) =
  n.state.delay = NoDelay()

##[
Set the Notifier to a synchronous state.
This means listeners will be executed sequentially, each should finish before the next one start.
]##
proc syncNotif*[T,L](n: var Notifier[T,L], consumes:bool=false, priorities:bool=false) =
  n.state.emission = SyncState(consumes:consumes, priorities:priorities)

proc isSyncNotif*[T,L](n:Notifier[T,L]):bool = 
  return n.state.emission.kind == emSync

##[
Set the Notifier to a parallel state.
This means each listener will be executed as a parallel task.
`wait` is whether we should wait for all the listeners to finish or not.
]##
proc parallelNotif*[T,L](n: var Notifier[T,L], wait:bool=false) =
  n.state.emission = ParallelState(wait:wait, mode:SingleTask())

proc isParallelNotif*[T,L](n:Notifier[T,L]):bool = 
  return n.state.emission.kind == emParallel

##[
Set the Notifier to a single task mode.
The Notifier should be a parallel notif for this to work. Else it will throw an error.
In this mode, all listeners execution will be passed as one big parallel task
]##
proc singleTask*[T,L](n: var Notifier[T,L]) =
  var em = n.state.emission
  doAssert em.kind == emParallel

  em.mode = SingleTask()

proc isSingleTask*[T,L](n:Notifier[T,L]):bool = 
  if n.state.emission.kind == emSync: return true

  n.state.emission.mode.kind == tsSingle

##[
Set the Notifier to a single task mode.
The Notifier should be a parallel notif for this to work. Else it will throw an error.
In this mode, listeners execution will be passed as multiple parallel task
]##
proc multipleTask*[T,L](n: var Notifier[T,L]) =
  var em = n.state.emission
  doAssert em.kind == emParallel

  em.mode = MultipleTask()

proc isMultiTask*[T,L](n:Notifier[T,L]):bool = 
  if n.state.emission.kind == emSync: return false

  n.state.emission.mode.kind == tsMulti

##[
Allows the Notifier to keep value of the latest change.
`ignore_eqv` is if the notifir should emit even if the change is the same as the last value
]##
proc enableValue*[T,L](n: var Notifier[T,L], ignore_eqv=false) =
  n.state.mode = ValState[T](ignore_eqv)

proc hasValue*[T,L](n: Notifier[T,L]):bool =
  n.state.mode.kind == nValue

##[
The notifier will no be able to keep the value of the latest changafter this function applied on it
]##
proc disableValue*[T,L](n: var Notifier[T,L]) =
  n.state.mode = EmitState[T]()

##[
For a Notifier able to keep value, this say if value equal to the latest change should trigger an emission.
]##
proc ignoreEqValue*[T,L](n: var Notifier[T,L], ignore_eqv=true) =
  var m = n.state.mode
  doAssert m.kind == nValue

  m.ignore_eqvalue = ignore_eqv

proc doesIgnoreEqValue*[T,L](n: Notifier[T,L]):bool =
  if n.state.mode.kind != nValue: return false

  return n.state.mode.ignore_eqv


##[
This mode says to the Notifier to execute all the listeners.
]##
proc execAll*[T,L](n: var Notifier[T,L]) =
  n.state.exec = ExecAll()

proc isExecAll*[T,L](n: Notifier[T,L]):bool =
  n.state.exec.kind == exAll

##[
This says to the Notifier to execute only the `count` latest changes.
]##
proc execLatest*[T,L](n: var Notifier[T,L], count:int=1) =
  n.state.exec = ExecLatest(count:count)

proc isExecLatest*[T,L](n: Notifier[T,L]):bool =
  n.state.exec.kind == exLatest

##[
This say to the Notifier to only execute the `count` first changes.
]##
proc execOldest*[T,L](n: var Notifier[T,L], count:int=1) =
  n.state.exec = ExecOldest(count:count)

proc isExecOldest*[T,L](n: Notifier[T,L]):bool =
  n.state.exec.kind == exOldest

proc getExecCount*[T,L](n: Notifier[T,L]):int =
  if n.state.exec.kind == exAll: return -1
  return n.state.exec.count