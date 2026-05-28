#################################################################################################################################################
########################################################## STATE OPERATIONS #####################################################################
#################################################################################################################################################

proc delay*[T,L](n: var Notifier[T,L], dur:int, first:bool=false) =
  ## Adds a delay to the notifier between each listener call.
  ## 
  ## Parameters:
  ## - `dur`: duration of the delay in milliseconds.
  ## - `first`: whether to apply a delay before the *first* listener call.
  ## 
  ## Example:
  ## ```nim
  ## var n = newNotifier[int, proc(x:int)]()
  ## n.delay(100)        # 100 ms delay between listeners
  ## n.delay(50, true)   # also delays the very first call
  ## ```
  let d = Delay(first, dur)
  n.state.delay = d

proc setPriority*[T,L](n: var Notifier[T,L], v:bool=false) =
  if n.state.emission.kind == emSync:
    n.state.emission.priorities = v

proc setConsume*[T,L](n: var Notifier[T,L], v:bool=false) =
  n.state.emission.consumes = v

proc hasDelay*[T,L](n:Notifier[T,L]):bool = 
  ## Returns true if the notifier has a delay between listener calls.
  ## 
  ## Example:
  ## 
  ## ```nim
  ## n.delay(100)
  ## assert n.hasDelay()
  ## ```
  return n.state.delay.kind == dDelay

proc hasDelayFirst*[T,L](n:Notifier[T,L]):bool = 
  ## Returns true if the notifier has a delay AND also delays before the first listener call.
  ## 
  ## Example:
  ## 
  ## ```nim
  ## n.delay(100, true)
  ## assert n.hasDelayFirst()
  ## ```
  return n.state.delay.kind == dDelay and n.state.delay.first

proc delayFirst*[T,L](n: var Notifier[T,L], first:bool=false) =
  ## Sets whether the notifier should apply a delay before the first listener call.
  ## The notifier must already have a delay set.
  ## 
  ## Example:
  ## 
  ## ```nim
  ## n.delay(100)
  ## n.delayFirst(true)
  ## ```
  var d = n.state.delay
  doAssert d.kind == dDelay

  d.first = first

proc noDelay*[T,L](n: var Notifier[T,L]) =
  ## Removes any delay set between listener calls.
  ## 
  ## Example:
  ## ```nim
  ## n.noDelay()
  ## assert not n.hasDelay()
  ## ```
  n.state.delay = NoDelay()

proc syncNotif*[T,L](n: var Notifier[T,L], consumes:bool=false, priorities:bool=false) =
  ## Sets the notifier to a synchronous dispatch mode.
  ## In this mode:
  ## - Listeners run sequentially.
  ## - Each listener must complete before the next starts.
  ## 
  ## Parameters:
  ## - `consumes`: whether the sync scheduler respects the listener consume flag.
  ## - `priorities`: whether to apply listener priority ordering.
  ## 
  ## Example:
  ## 
  ## ```nim
  ## n.syncNotif(consumes=true)
  ## assert n.isSyncNotif()
  ## ```
  n.state.emission = SyncState(consumes:consumes, priorities:priorities)

proc isSyncNotif*[T,L](n:Notifier[T,L]):bool = 
  ## Returns true if the notifier dispatches events synchronously.
  return n.state.emission.kind == emSync

proc parallelNotif*[T,L](n: var Notifier[T,L], wait:bool=false) =
  ## Sets the notifier to parallel dispatch mode.
  ## In this mode:
  ## - Each listener is executed in parallel.
  ## - If `wait` is true, the emitter waits for all listeners to finish.
  ## 
  ## Example:
  ## 
  ## ```nim
  ## n.parallelNotif(wait=true)
  ## assert n.isParallelNotif()
  ## ```
  n.state.emission = ParallelState(wait:wait, mode:SingleTask())

proc isParallelNotif*[T,L](n:Notifier[T,L]):bool = 
  ## Returns `true` if the notifier dispatches listeners in parallel.
  return n.state.emission.kind == emParallel

proc singleTask*[T,L](n: var Notifier[T,L]) =
  ## Sets the notifier to single-task mode.
  ## The notifier must already be in **parallel mode**.
  ## 
  ## In this mode:
  ## - All listeners are executed inside one parallel task.
  ## 
  ## Example:
  ## 
  ## ```nim
  ## n.parallelNotif()
  ## n.singleTask()
  ## assert n.isSingleTask()
  ## ```
  doAssert n.state.emissionkind == emParallel
  n.state.emissionmode = SingleTask()

proc isSingleTask*[T,L](n:Notifier[T,L]):bool = 
  ## Returns `true` if the notifier runs listeners as a single task.
  ## Note: synchronous mode is always considered "single task".
  if n.state.emission.kind == emSync: return true
  n.state.emission.mode.kind == tsSingle

proc multipleTask*[T,L](n: var Notifier[T,L]) =
  ## Sets the notifier to multi-task mode.
  ## The notifier must already be in **parallel mode**.
  ## 
  ## In this mode:
  ## - Each listener is executed as its own parallel task.
  ## 
  ## Example:
  ## 
  ## ```nim
  ## n.parallelNotif()
  ## n.multipleTask()
  ## assert n.isMultiTask()
  ## ```
  doAssert n.state.emission.kind == emParallel
  n.state.emission.mode = MultipleTask()

proc isMultiTask*[T,L](n:Notifier[T,L]):bool = 
  ## Returns `true` if the notifier dispatches each listener in its own parallel task.
  if n.state.emission.kind == emSync: return false
  n.state.emission.mode.kind == tsMulti

proc enableValue*[T,L](n: var Notifier[T,L], ignore_eqv=false) =
  ## Enables value storage for the notifier.
  ## This means:
  ## - The latest emitted value is kept.
  ## - It can be accessed using n[0].
  ## 
  ## Parameters:
  ## - `ignore_eqv`: if true, emitting the same value still triggers listeners.
  ## 
  ## Example:
  ## ```nim
  ## n.enableValue()
  ## n.emit(10)
  ## assert n[0] == 10
  ## ```
  n.state.mode = ValState[T](ignore_eqv)

proc hasValue*[T,L](n: Notifier[T,L]):bool =
  ## Returns `true` if the notifier can store the latest value.
  n.state.mode.kind == nValue

proc disableValue*[T,L](n: var Notifier[T,L]) =
  ## Disables value storage for the notifier.
  ## After this:
  ## - The notifier no longer stores the latest value.
  ## - Accessing n[] is invalid.
  ## 
  ## Example:
  ## ```nim
  ## n.disableValue()
  ## assert not n.hasValue()
  ## ```
  n.state.mode = EmitState[T]()

proc ignoreEqValue*[T,L](n: var Notifier[T,L], ignore_eqv=true) =
  ## Sets whether the notifier should ignore or emit equal values.
  ## Only works when value mode is enabled.
  ## 
  ## Example:
  ## ```nim
  ## n.enableValue()
  ## n.ignoreEqValue(true)
  ## ```
  doAssert n.state.mode.kind == nValue
  n.state.mode.ignore_eqvalue = ignore_eqv

proc doesIgnoreEqValue*[T,L](n: Notifier[T,L]):bool =
  ## Returns whether the notifier ignores identical values.
  if n.state.mode.kind != nValue: return false
  return n.state.mode.ignore_eqvalue

proc execAll*[T,L](n: var Notifier[T,L]) =
  ## Sets the notifier to execute all listeners for each emission.
  ## 
  ## Example:
  ## ```nim
  ## n.execAll()
  ## assert n.isExecAll()
  ## ```
  n.state.exec = ExecAll()

proc isExecAll*[T,L](n: Notifier[T,L]):bool =
  ## Returns `true` if the notifier executes all changes.
  n.state.exec.kind == exAll

proc execLatest*[T,L](n: var Notifier[T,L], count:int=1) =
  ## Configures the notifier so that only the latest count changes are executed.
  ## 
  ## Example:
  ## ```nim
  ## n.execLatest(3)
  ## assert n.isExecLatest()
  ## ```
  n.state.exec = ExecLatest(count:count)

proc isExecLatest*[T,L](n: Notifier[T,L]):bool =
  ## Returns true if the notifier executes only the latest changes.
  n.state.exec.kind == exLatest

proc execOldest*[T,L](n: var Notifier[T,L], count:int=1) =
  ## Configures the notifier so that only the oldest count changes are executed.
  ## 
  ## Example:
  ## 
  ## ```nim
  ## n.execOldest(2)
  ## assert n.isExecOldest()
  ## ```
  n.state.exec = ExecOldest(count:count)

proc isExecOldest*[T,L](n: Notifier[T,L]):bool =
  ## Returns true if the notifier executes only the oldest changes.
  n.state.exec.kind == exOldest

proc getExecCount*[T,L](n: Notifier[T,L]):int =
  ## Returns the execution count associated with the current execution mode.
  ## Meaning:
  ## - `-1` if ExecAll is active.
  ## - Otherwise the number configured for latest/oldest.
  ## 
  ## Example:
  ## ```nim
  ## n.execLatest(5)
  ## assert n.getExecCount() == 5
  ## ```
  if n.state.exec.kind == exAll: return -1
  return n.state.exec.count
  