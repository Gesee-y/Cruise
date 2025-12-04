#################################################################################################################################################
########################################################## STATE OPERATIONS #####################################################################
#################################################################################################################################################

##[
Adds a delay to the notifier between each listener call.

Parameters:
- `dur`: duration of the delay in milliseconds.
- `first`: whether to apply a delay before the *first* listener call.

Example:
```nim
var n = newNotifier[int, proc(x:int)]()
n.delay(100)        # 100 ms delay between listeners
n.delay(50, true)   # also delays the very first call
```
]##
proc delay*[T,L](n: var Notifier[T,L], dur:int, first:bool=false) =
  let d = Delay(first, dur)
  n.state.delay = d

##[
Returns true if the notifier has a delay between listener calls.

Example:

```nim
n.delay(100)
assert n.hasDelay()
```
]##
proc hasDelay*[T,L](n:Notifier[T,L]):bool = 
  return n.state.delay.kind == dDelay

##[
Returns true if the notifier has a delay AND also delays before the first listener call.

Example:

```nim
n.delay(100, true)
assert n.hasDelayFirst()
```
]##
proc hasDelayFirst*[T,L](n:Notifier[T,L]):bool = 
  return n.state.delay.kind == dDelay and n.state.delay.first

##[
Sets whether the notifier should apply a delay before the first listener call.

The notifier must already have a delay set.

Example:

```nim
n.delay(100)
n.delayFirst(true)
```
]##
proc delayFirst*[T,L](n: var Notifier[T,L], first:bool=false) =
  var d = n.state.delay
  doAssert d.kind == dDelay

  d.first = first

##[
Removes any delay set between listener calls.

Example:

```nim
n.noDelay()
assert not n.hasDelay()
```
]##
proc noDelay*[T,L](n: var Notifier[T,L]) =
  n.state.delay = NoDelay()

##[
Sets the notifier to a synchronous dispatch mode.
In this mode:

- Listeners run sequentially.

- Each listener must complete before the next starts.

## Parameters:

- `consumes`: whether the sync scheduler respects the listener consume flag.

- `priorities`: whether to apply listener priority ordering.

Example:

```nim
n.syncNotif(consumes=true)
assert n.isSyncNotif()
```
]##
proc syncNotif*[T,L](n: var Notifier[T,L], consumes:bool=false, priorities:bool=false) =
  n.state.emission = SyncState(consumes:consumes, priorities:priorities)

##[
Returns true if the notifier dispatches events synchronously.
]##
proc isSyncNotif*[T,L](n:Notifier[T,L]):bool = 
  return n.state.emission.kind == emSync

##[
Sets the notifier to parallel dispatch mode.
In this mode:

- Each listener is executed in parallel.

- If `wait` is true, the emitter waits for all listeners to finish.

Example:

```nim
n.parallelNotif(wait=true)
assert n.isParallelNotif()
```
]##
proc parallelNotif*[T,L](n: var Notifier[T,L], wait:bool=false) =
  n.state.emission = ParallelState(wait:wait, mode:SingleTask())

##[
Returns `true` if the notifier dispatches listeners in parallel.
]##
proc isParallelNotif*[T,L](n:Notifier[T,L]):bool = 
  return n.state.emission.kind == emParallel

##[
Sets the notifier to single-task mode.
The notifier must already be in **parallel mode**.

In this mode:

- All listeners are executed inside one parallel task.

Example:

```nim
n.parallelNotif()
n.singleTask()
assert n.isSingleTask()
```
]##
proc singleTask*[T,L](n: var Notifier[T,L]) =
  var em = n.state.emission
  doAssert em.kind == emParallel

  em.mode = SingleTask()

##[
Returns `true` if the notifier runs listeners as a single task.
Note: synchronous mode is always considered "single task".
]##
proc isSingleTask*[T,L](n:Notifier[T,L]):bool = 
  if n.state.emission.kind == emSync: return true

  n.state.emission.mode.kind == tsSingle

##[
Sets the notifier to multi-task mode.
The notifier must already be in **parallel mode**.

In this mode:

- Each listener is executed as its own parallel task.

Example:

```nim
n.parallelNotif()
n.multipleTask()
assert n.isMultiTask()
```
]##
proc multipleTask*[T,L](n: var Notifier[T,L]) =
  var em = n.state.emission
  doAssert em.kind == emParallel

  em.mode = MultipleTask()

##[
Returns `true` if the notifier dispatches each listener in its own parallel task.
]##
proc isMultiTask*[T,L](n:Notifier[T,L]):bool = 
  if n.state.emission.kind == emSync: return false

  n.state.emission.mode.kind == tsMulti

##[
Enables value storage for the notifier.

This means:

- The latest emitted value is kept.

- It can be accessed using n[0].

Parameters:

- `ignore_eqv`: if true, emitting the same value still triggers listeners.

Example:

```nim
n.enableValue()
n.emit(10)
assert n[0] == 10
```
]##
proc enableValue*[T,L](n: var Notifier[T,L], ignore_eqv=false) =
  n.state.mode = ValState[T](ignore_eqv)

##[
Returns `true` if the notifier can store the latest value.
]##
proc hasValue*[T,L](n: Notifier[T,L]):bool =
  n.state.mode.kind == nValue


##[
Disables value storage for the notifier.
After this:

- The notifier no longer stores the latest value.
- Accessing n[] is invalid.

Example:

```nim
n.disableValue()
assert not n.hasValue()
```
]##
proc disableValue*[T,L](n: var Notifier[T,L]) =
  n.state.mode = EmitState[T]()

##[
Sets whether the notifier should ignore or emit equal values.
Only works when value mode is enabled.

Example:

```nim
n.enableValue()
n.ignoreEqValue(true)
```
]##
proc ignoreEqValue*[T,L](n: var Notifier[T,L], ignore_eqv=true) =
  var m = n.state.mode
  doAssert m.kind == nValue

  m.ignore_eqvalue = ignore_eqv

##[
Returns whether the notifier ignores identical values.
]##
proc doesIgnoreEqValue*[T,L](n: Notifier[T,L]):bool =
  if n.state.mode.kind != nValue: return false

  return n.state.mode.ignore_eqv


##[
Sets the notifier to execute all listeners for each emission.

Example:

```nim
n.execAll()
assert n.isExecAll()
```
]##
proc execAll*[T,L](n: var Notifier[T,L]) =
  n.state.exec = ExecAll()

##[
Returns `true` if the notifier executes all changes.
]##
proc isExecAll*[T,L](n: Notifier[T,L]):bool =
  n.state.exec.kind == exAll

##[
Configures the notifier so that only the latest count changes are executed.

Example:

```nim
n.execLatest(3)
assert n.isExecLatest()
```

]##
proc execLatest*[T,L](n: var Notifier[T,L], count:int=1) =
  n.state.exec = ExecLatest(count:count)

##[
Returns true if the notifier executes only the latest changes.
]##
proc isExecLatest*[T,L](n: Notifier[T,L]):bool =
  n.state.exec.kind == exLatest

##[
Configures the notifier so that only the oldest count changes are executed.

Example:

```nim
n.execOldest(2)
assert n.isExecOldest()
```
]##
proc execOldest*[T,L](n: var Notifier[T,L], count:int=1) =
  n.state.exec = ExecOldest(count:count)

##[
Returns true if the notifier executes only the oldest changes.
]##
proc isExecOldest*[T,L](n: Notifier[T,L]):bool =
  n.state.exec.kind == exOldest

##[
Returns the execution count associated with the current execution mode.
Meaning:

- `-1` if ExecAll is active.
- Otherwise the number configured for latest/oldest.

Example:

```nim
n.execLatest(5)
assert n.getExecCount() == 5
```

]##
proc getExecCount*[T,L](n: Notifier[T,L]):int =
  if n.state.exec.kind == exAll: return -1
  return n.state.exec.count