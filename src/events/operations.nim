# ############################################################################################################################################### #
# ################################################################ HANDLING OPERATIONS ########################################################## #
# ############################################################################################################################################### #

proc connect*[T,L](n:Notifier[T,L], callback:L, consume:bool=false, priority:int=0) =
  ## Connect a callback to the notifier.
  ## When the notifier emits data, all connected callbacks will be invoked with that data.
  ##   
  ## Parameters:
  ##   - `n`: The notifier to connect to
  ##   - `callback`: The callback function to be invoked when data is emitted
  ##   - `consume`: If true, the callback consumes the data (default: true)
  ##   - `priority`: Execution priority, higher values execute first (default: 0)
  ##   
  ## Example:
  ## ```nim
  ## notifier notif(x:int)
  ##   
  ## proc myCallback(value: int) =
  ##   echo "Received: ", value
  ##     
  ## notif.connect(myCallback)
  ## notif.emit(42)  # Will call myCallback(42)
  ## ```
  let l = Listener[L](callback:callback, consume:consume, priority:priority, stop:false)
  
  # This is to avoid modifying the listeners if we are currently executing the notifier
  withLock(n.lck):
    let mode = n.state.emission

    if mode.kind == emSync:
      if mode.priorities:
        n.listeners.insertSorted(l)
        return

    n.listeners.add(l)

proc disconnect*[T,L](n:Notifier[T,L], callback:L) =
  ## Disconnect a callback from the notifier.  
  ## After disconnection, the callback will no longer be invoked when the notifier emits data.
  ## 
  ## Parameters:
  ##   - `n`: The notifier to disconnect from
  ##   - `callback`: The callback function to remove
  ##   
  ## Example:
  ## ```nim
  ## notifier notif(x:int)
  ##     
  ## proc myCallback(value: int) =
  ##   echo "Received: ", value
  ##     
  ## notif.connect(myCallback)
  ## notif.emit(10)  # Calls myCallback
  ##     
  ## notif.disconnect(myCallback)
  ## notif.emit(20)  # myCallback is NOT called
  ## ```
  
  # Same as `connect`
  withLock(n.lck):

    # Just some basic swap and pop logic
    for i in 0..<n.listeners.len:
      let l = n.listeners[i]

      if l.callback == callback:
        n.listeners[i] = n.listeners[^1]
        discard n.listeners.pop()

        return

proc open*[T,L](n:Notifier[T,L]) =
  ## Initialize and open the notifier for operation.
  ## This initializes internal locks, conditions, and streams necessary for the notifier to function.
  ## Must be called before using the notifier.
  ##   
  ## Parameters:
  ##   - `n`: The notifier to open
  ##   
  ## Example:
  ## ```nim
  ## notifier notif(x: int)
  ## notif.open()  # Initialize the notifier
  ##     
  ## # Now ready to connect callbacks and emit data
  ## ```
  n.lck.initLock()
  n.cond.initCond()
  n.state.stream.open()

proc close*[T,L](n:Notifier[T,L]) =
  ## Close the notifier and release its resources.
  ## This deinitializes locks, conditions, and streams. Should be called when done using the notifier.
  ##   
  ## Parameters:
  ##   - `n`: The notifier to close
  ##   
  ## Example:
  ## ```nim
  ## notifier notif(x: int)
  ## notif.open()
  ##     
  ## # ... use the notifier ...
  ##     
  ## notif.close()  # Clean up resources
  ## ```

  n.lck.deinitLock()
  n.cond.deinitCond()
  n.state.stream.close()

proc reset*[T,L](n:Notifier[T,L]) =
  ## Reset the notifier to its initial state.  
  ## This reopens the notifier and clears all connected listeners.
  ##   
  ## Parameters:
  ##   - `n`: The notifier to reset
  ##   
  ## Example:
  ## ```nim
  ## notifier notif(x: int)
  ## notif.open()
  ## notif.connect(someCallback)    
  ## notif.reset()  # Reopens and removes all callbacks
  ## ```
  n.open()
  n.listeners.setLen(0)

proc wait*[T,L](n:Notifier[T,L]) = 
  ## Wait for the notifier to signal a condition.  
  ## Blocks the current thread until the notifier's condition variable is signaled.
  ##   
  ## Parameters:
  ##   - `n`: The notifier to wait on
  ##   
  ## Example:
  ## ```nim
  ## notifier notif(x: int)
  ## notif.open()
  ##     
  ## # In some thread:
  ## notif.wait()  # Blocks until signal
  ##     
  ## # In another thread:
  ## notif.emit(42)  # Signals the waiting thread
  ## ```
  n.cond.wait(n.lck)

proc emit*[T,L](n:var Notifier[T,L], args:T) =
  ## Emit data through the notifier to all connected callbacks.  
  ## This triggers all connected callbacks with the provided data. The execution is thread-safe
  ## and uses a lock to ensure consistency.
  ##     
  ## Parameters:
  ##   - `n`: The notifier to emit from
  ##   - `args`: The data to emit to all callbacks
  ##   
  ## Example:
  ## ```nim
  ## notifier notif(x: int)
  ## notif.open()
  ##     
  ## proc printValue(x: int) =
  ##   echo "Value: ", x
  ##     
  ## notif.connect(printValue)
  ## notif.emit(100)  # Prints "Value: 100"
  ## ```
  n.cond.signal()
  if n.listeners.len > 0:
    let success = n.lck.tryAcquire()
    addcallback(n, args)  
    if success:
      execute_pipeline(n)
      n.lck.release()

proc emitDefer*[T,L](n:var Notifier[T,L], args:T) =
  ## Deferred version of emit.
  ## This will just register the emission as to be executed but won't do it right away.
  ## Only the next call to emit will execute the emission
  addcallback(n, args)
  n.cond.signal()

proc flush*[T,L](n:var Notifier[T,L]) =
  ## Execute the pipeline if there are any remaining events. Useful if you have deferred some events.
  n.lck.acquire()
  execute_pipeline(n)
  n.lck.release()

proc `[]`*[T,L](n:Notifier[T,L], i:int=0):T =
  ## For a notifier in the Value mode, allows you to get the latest emitted value
  let mode = n.state.mode
  doAssert mode.kind == nValue

  return mode.value

proc `[]=`*[T,L](n:var Notifier[T,L],i:int, args:T) =
  ## Let you set the value of a notifier in value mode, and emit that value.
  let mode = n.state.mode
  doAssert mode.kind == nValue

  if mode.ignore_eqvalue and mode.value == args:
    return
  
  emit(n, args)

# Self explanatory
proc connect*[T](s: CRSubject[T], f: Observer[T]) =
  s.observers.add(f)

proc disconnect*[T](s: CRSubject[T], f: Observer[T]) =
  s.observers.keepIf(proc(x: Observer[T]): bool = x != f)

proc notify*[T](s: CRSubject[T]) =
  for obs in s.observers:
    obs(s.value)

proc `[]`*[T](s: CRSubject[T]): T =
  s.value

proc `[]=`*[T](s: CRSubject[T], v: T) =
  s.value = v
