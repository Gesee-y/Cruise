#################################################################################################################################################
########################################################### CRUISE EVENT PIPELINE ###############################################################
#################################################################################################################################################


#[
The Event pipeline is subdivided into multiple phases, we can notably say:
  - Filtering phase. Consist of filtering emission stream to remove irrelevvant calls.
    Should return a set of listeners to run.
  - State phase: We stores the relevant informations for the notifier state
  - Delay phase: We add the dalays and stuffs
  - Emission phase: We schedule the event and launch them.
]#

proc addcallback[T,L](n:Notifier[T,L], data:T) =
  send(n.state.stream, EmissionCallback[T,L](data:data, listeners:n.listeners))

proc delay_first(d:NoDelay) = discard
proc delay_first(d:Delay) =
  if d.first: sleep(d.duration)

proc delay(d:NoDelay) = discard
proc delay(d:Delay) = sleep(d.duration)

proc validate[T,L](n:Notifier[T,L], s:EmitState, c:int, mx:int) = true
proc validate[T,L](n:Notifier[T,L], s:ValState, c:int, mx:int) =
  if c == 0 or mx <= 1 or (not s.ignore_eqvalue): return true

  return not (n.buffer[c-1].data == n.buffer[c].data)

proc setvalue[T,L](n:Notifier[T,L], s:EmitState) = discard
proc setvalue[T,L](n:Notifier[T,L], s:ValState[T]) =
  s.value = n.buffer[^1].dara

func call_listener[L,T](l:Listener[L], data:T, d:DelayMode) =
  destructuredCall(l.callback(), data)
  delay(d)

proc filtering[T,L](n:Notifier[T,L], e:ExecAll) = 
  var buffer = n.buffer
  var stream = n.state.stream
  var tried = stream.tryRecv()

  while tried.dataAvailable:
    buffer.add(tried.msg)
    tried = stream.tryRecv()

proc filtering[T,L](n:Notifier[T,L], exec:ExecLatest) = 
  var buffer = n.buffer
  var stream = n.state.stream
  var count = exec.count
  var tried = stream.tryRecv()

  while stream.dataAvailable and count > 0:
    if count < peek(stream): continue
    buffer.add(tried.msg)
    count -= 1
    tried = stream.tryRecv()

proc filtering[T,L](n:Notifier[T,L], exec:ExecOldest) = 
  var buffer = n.buffer
  var stream = n.state.stream
  var count = exec.count
  var tried = stream.tryRecv()

  while tried.dataAvailable and count > 0:
    buffer.add(tried.msg)
    count -= 1
    tried = stream.tryRecv()

proc emission[T,L](n:Notifier[T,L], em:SyncState, ts:SingleTask) =
  var count = 0
  var maxlen = n.buffer.len

  for emcallback in n.buffer:
    let data = emcallback.data
    let listeners = emcallback.listeners

    if not validate(n, n.state.mode, count, maxlen): continue
    count += 1

    delay_first(n.state.delay)

    for listener in listeners:
      setvalue(n, n.state.mode)
      call_listener(listener, data, n.state.delay)

proc emission[T,L](n:Notifier[T,L], em:ParallelState, ts:SingleTask) =
  var count = 0
  var maxlen = n.buffer.len
  for emcallback in n.buffer:
    let data = emcallback.data
    let listeners = emcallback.listeners

    if not validate(n, n.state.mode, count, maxlen): continue
    count += 1

    delay_first(n.state.delay)

    parallel:
      spawn for listener in listeners:
        setvalue(n, n.state.mode)
        call_listener(listener, data, n.state.delay)

    if em.wait: sync()

proc emission[T,L](n:Notifier[T,L], em:ParallelState, ts:MultipleTask) =
  var count = 0
  var maxlen = n.buffer.len
  for emcallback in n.buffer:
    let data = emcallback.data
    let listeners = emcallback.listeners

    if not validate(n, n.state.mode, count, maxlen): continue
    count += 1

    delay_first(n.state.delay)

    parallel:
      for listener in listeners:
        setvalue(n, n.state.mode)
        spawn call_listener(listener, data, n.state.delay)

    if em.wait: sync()

proc execute_pipeline[T,L](n:Notifier[T,L]) =
  var state = n.state

  n.buffer.setLen(0)
  filtering(n, state.exec)
  emission(n, state.emission, state.emission.mode)

  if peek(state.stream) > 0:
    execute_pipeline(n)

