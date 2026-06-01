# ######################################################################################################################################################## #
# ################################################################# EDA MESSAGE PASSING ################################################################## #
# ######################################################################################################################################################## #

type
  CInstance[T] = ref object
    data: seq[T]
    timestamp: seq[int]
  CMessage = object
    data: pointer
    lock: Lock
    clear: proc(p: pointer)
    free: proc(p: pointer)

  CEventBus = object
    messages: Table[string, CMessage]

template newMessage[T](): CMessage =
  let data: CInstance[T]
  new(data)
  GC_ref(data)
  result.data = cast[pointer](data)
  result.clear = 
    proc(p: pointer) = 
      var d = cast[CInstance[T]](p)
      d.data.setLen(0)
  result.free = 
    proc(p: pointer) = 
      var d = cast[CInstance[T]](p)
      GC_unref(d)

proc addMessage*[T](bus: var CEventBus, obj: T) =
  if $T notin bus.messages:
    bus.messages[$T] = newMessage[T]()

  var msg = bus.messages[$T]
  msg.lock.acquire()
  var d = cast[CInstance[T]](msg.data)
  d.data.add(obj)
  d.data.add(getMonoTime().ticks)
  msg.lock.release()

proc getMessage*[T](bus: var CEventBus, obj: T): Option[CInstance[T]] =
  if $T notin bus.messages:
    return none(CInstance[T])

  var msg = bus.messages[$T]
  msg.lock.acquire()
  var d = cast[CInstance[T]](msg.data)
  if d.data.len <= 0:
    return none(CInstance[T])

  msg.lock.release()
  some(d)


proc clearMessage(bus: var CEventBus) =
  for k, msg in bus.messages.mpairs:
    msg.lock.acquire()
    msg.clear(msg.data)
    msg.lock.release()

proc `destroy=`(bus: var CEventBus) =
  for k, msg in bus.messages.mpairs:
    msg.lock.acquire()
    msg.free(msg.data)
    msg.lock.release()

