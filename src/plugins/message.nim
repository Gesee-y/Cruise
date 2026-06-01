# ######################################################################################################################################################## #
# ################################################################# EDA MESSAGE PASSING ################################################################## #
# ######################################################################################################################################################## #

type
  CMessage = object
    data: pointer
    free: proc(p: pointer)

  CEventBus = object
    messages: Table[string, CMessage]
    lock: Lock

template newMessage[T](): CMessage =
  let data: ref seq[T]
  new(data)
  GC_ref(data)
  result.data = cast[pointer](data)
  result.free = 
    proc(p: pointer) = 
      var d = cast[ref seq[T]](p)
      d.setLen(0)

proc addMessage*[T](bus: var CEventBus, obj: T) =
  bus.lock.acquire()
  if $T notin bus.messages:
    bus.messages[$T] = newMessage[T]()

  var msg = bus.messages[$T]
  var d = cast[ref seq[T]](msg.data)
  d[].add(obj)
  bus.lock.release()

proc getMessage*[T](bus: var CEventBus, obj: T): Option[ref seq[T]] =
  if $T notin bus.messages:
    return none(T)

  var msg = bus.messages[$T]
  var d = cast[ref seq[T]](msg.data)
  some(d)

proc clearMessage(bus: var CEventBus) =
  for k, msg in bus.messages:
    msg.free(msg.data)
