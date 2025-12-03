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

proc addcallback[T,L](n:var Notifier[T,L], data:T) =
  send(n.state.stream, EmissionCallback[T,L](data:data, listeners:n.listeners))

proc delay_first(d:DelayMode) =
  if d.kind == dDelay and d.first: sleep(d.duration)

proc delay(d:DelayMode) =
  if d.kind == dDelay: sleep(d.duration)

proc validate[T,L](n:Notifier[T,L], s:NotifierState[T], c:int, mx:int):bool =
  if (s.kind == nEmit) or (c == 0 or mx <= 1 or (not s.ignore_eqvalue)): return true

  return not (n.buffer[c-1].data == n.buffer[c].data)

proc setvalue[T,L](n:Notifier[T,L], s:var NotifierState[T]) =
  if s.kind == nValue:
    s.value = n.buffer[^1].data

proc call_listener[L,T](l:Listener[L], data:T, d:DelayMode) =
  let callb = l.callback
  destructuredCall(callb, data)
  delay(d)

proc nexec_all[T,L](n:var Notifier[T,L]) = 
  var tried = n.state.stream.tryRecv()

  while tried.dataAvailable:
    n.buffer.add(tried.msg)
    tried = n.state.stream.tryRecv()

proc nexec_latest[T,L](notif:var Notifier[T,L], count:int) = 
  var stream = notif.state.stream
  var tried = stream.tryRecv()
  var n = count

  while tried.dataAvailable and n > 0:
    if n < peek(stream): continue
    notif.buffer.add(tried.msg)
    n -= 1
    tried = stream.tryRecv()

proc nexec_oldest[T,L](notif:var Notifier[T,L], count:int) = 
  var stream = notif.state.stream
  var tried = stream.tryRecv()
  var n = count

  while tried.dataAvailable and n > 0:
    notif.buffer.add(tried.msg)
    n -= 1
    tried = stream.tryRecv()

proc filtering[T,L](n:var Notifier[T,L], e:ExecMode) =
  if e.kind == exAll:
    nexec_all(n)
  elif e.kind == exLatest:
    nexec_latest(n, e.count)
  elif e.kind == exOldest:
    nexec_oldest(n, e.count)

proc emit_sync[T,L](n:var Notifier[T,L], em:EmissionState) =
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

proc emit_parallel_single[T,L](n:var Notifier[T,L], em:EmissionState) =
  var count = 0
  var maxlen = n.buffer.len
  for emcallback in n.buffer:
    let data = emcallback.data
    let listeners = emcallback.listeners

    if not validate(n, n.state.mode, count, maxlen): continue
    count += 1

    delay_first(n.state.delay)

    #parallel:
    for listener in listeners:
      setvalue(n, n.state.mode)
      call_listener(listener, data, n.state.delay)

    if em.wait: sync()

proc emit_parallel_multi[T,L](n:Notifier[T,L], em:EmissionState) =
  var count = 0
  var maxlen = n.buffer.len
  for emcallback in n.buffer:
    let data = emcallback.data
    let listeners = emcallback.listeners

    if not validate(n, n.state.mode, count, maxlen): continue
    count += 1

    delay_first(n.state.delay)

    #parallel:
    for listener in listeners:
      setvalue(n, n.state.mode)
      call_listener(listener, data, n.state.delay)

    if em.wait: sync()

proc emission[T,L](n:var Notifier[T,L], em:EmissionState, ts:TaskMode) =
  if em.kind == emSync:
    emit_sync(n, em)
  elif em.kind == emParallel:
    if ts.kind == tsSingle:
      emit_parallel_single(n, em)
    else:
      emit_parallel_multi(n, em)

proc execute_pipeline[T,L](n:var Notifier[T,L]) =
  var state = n.state

  n.buffer.setLen(0)
  filtering(n, state.exec)
  emission(n, state.emission, state.emission.mode)

#  if peek(state.stream) > 0:
#    execute_pipeline(n)

