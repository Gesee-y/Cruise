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
  # Skip validation if not in emit mode, first item, single item, or not ignoring equal values
  if (s.kind == nEmit) or (c == 0 or mx <= 1 or (not s.ignore_eqvalue)): return true
  
  # Check if current data differs from previous to avoid duplicate emissions
  return not (n.buffer[c-1].data == n.buffer[c].data)

proc setvalue[T,L](n:Notifier[T,L], s:var NotifierState[T]) =
  # Update the stored value with the latest emitted data
  if s.kind == nValue:
    s.value = n.buffer[^1].data

proc call_listener[L,T](l:Listener[L], data:T, d:DelayMode) =
  let callb = l.callback
  destructuredCall(callb, data)
  delay(d)

proc nexec_all[T,L](n:var Notifier[T,L]) = 
  # Retrieve all available messages from the stream
  var tried = n.state.stream.tryRecv()
  
  while tried.dataAvailable:
    n.buffer.add(tried.msg)
    tried = n.state.stream.tryRecv()

proc nexec_latest[T,L](notif:var Notifier[T,L], count:int) = 
  # Get the latest N messages, skipping older ones
  var stream = notif.state.stream
  var tried = stream.tryRecv()
  var n = count
  
  while tried.dataAvailable and n > 0:
    notif.buffer.add(tried.msg)
    n -= 1
    tried = stream.tryRecv()

proc nexec_oldest[T,L](notif:var Notifier[T,L], count:int) = 
  # Get the oldest N messages from the stream
  var stream = notif.state.stream
  var tried = stream.tryRecv()
  var n = count
  
  while tried.dataAvailable and n > 0:
    # Skip if there are more messages in stream than we need
    if n < peek(stream): continue
    
    notif.buffer.add(tried.msg)
    n -= 1
    tried = stream.tryRecv()

proc filtering[T,L](n:var Notifier[T,L], e:ExecMode) =
  # Apply the execution mode filtering strategy
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
    
    # Skip if this emission doesn't pass validation (e.g., duplicate value)
    if not validate(n, n.state.mode, count, maxlen): continue
    count += 1
    delay_first(n.state.delay)
    
    # Call each listener synchronously in sequence
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
    # TODO: parallel execution block would go here
    
    for listener in listeners:
      setvalue(n, n.state.mode)
      call_listener(listener, data, n.state.delay)
    
    # Wait for all parallel tasks to complete if required
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

    # TODO: parallel execution block would go here
    for listener in listeners:
      setvalue(n, n.state.mode)
      call_listener(listener, data, n.state.delay)
    if em.wait: sync()

proc emission[T,L](n:var Notifier[T,L], em:EmissionState, ts:TaskMode) =
  # Select emission strategy based on configuration
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
  
  # Step 1: Filter incoming messages according to execution mode
  filtering(n, state.exec)
  
  # Step 2: Emit filtered data to listeners
  emission(n, state.emission, state.emission.mode)
  
  # Step 3: Recursively process if more data is available
  if ready(state.stream):
    execute_pipeline(n)