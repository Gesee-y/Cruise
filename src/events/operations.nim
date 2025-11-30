#################################################################################################################################################
################################################################# HANDLING OPERATIONS ###########################################################
#################################################################################################################################################

##[
Connect the `callback` to the notifier `n`.
This means that each time a `n` will emit some data, they will be passed to the callback for a call.
]##
proc connect*[T,L](n:Notifier[T,L], callback:L, consume:bool=true, priority:int=0) =
  let l = Listener[L](callback:callback, consume:consume, priority:priority, stop:false)
  
  # This is to avoid modifying the listeners if we are currently executing the notifier
  lock(n.lck):
    n.listeners.add(l)

proc disconnect*[T,L](n:Notifier[T,L], callback:L) =
  # Same as `connect`
  lock(n.lck):

    # Just some basic swap and pop logic
    for i in 0..<n.listeners.len:
      let l = n.listeners[i]

      if l.callback() == callback:
        n.listeners[i] = n.listeners[^1]
        n.listeners.pop()

        return

proc open*[T,L](n:Notifier[T,L]) =
  n.lck.initLock()
  n.cond.initCond()
  n.state.stream.open()

proc close*[T,L](n:Notifier[T,L]) =
  n.lck.deinitLock()
  n.cond.deinitCond()
  n.state.stream.close()

proc reset*[T,L](n:Notifier[T,L]) =
  n.open()
  n.listeners.setLen(0)

proc wait*[T,L](n:Notifier[T,L]) = n.cond.wait()

proc emit*[T,L](n:Notifier[T,L], args:T) =
  let success = n.lck.tryAcquire()
  addcallback(n, args)

  n.cond.signal()
  if success: 
    execute_pipeline(n)
    n.lck.release()

proc `[]`*[T,L](n:Notifier[T,L]) =
  let mode = n.state.mode
  doAssert mode is ValState

  return mode.value

proc `[]=`*[T,L](n:Notifier[T,L], args:T) =
  let mode = n.state.mode
  doAssert mode is ValState

  emit(n, args)