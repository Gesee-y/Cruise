# ######################################################################################################################################################## #
# ################################################################# EDA MESSAGE PASSING ################################################################## #
# ######################################################################################################################################################## #

type
  CMessage = object
    data: pointer
    lock: Lock
    clear: proc(p: pointer)
    free: proc(p: pointer)

  CEventBus = object
    messages: Table[string, CMessage]

template newMessage[T](): CMessage =
  let data: ref seq[T]
  new(data)
  GC_ref(data)
  result.data = cast[pointer](data)
  result.clear = 
    proc(p: pointer) = 
      var d = cast[ref seq[T]](p)
      d.setLen(0)
  result.free = 
    proc(p: pointer) = 
      var d = cast[ref seq[T]](p)
      GC_unref(d)

proc addMessage*[T](bus: var CEventBus, obj: T) =
  if $T notin bus.messages:
    bus.messages[$T] = newMessage[T]()

  var msg = bus.messages[$T]
  msg.lock.acquire()
  var d = cast[ref seq[T]](msg.data)
  d[].add(obj)
  msg.lock.release()

proc getMessage*[T](bus: var CEventBus, obj: T): Option[ref seq[T]] =
  if $T notin bus.messages:
    return none(ref seq[T])

  var msg = bus.messages[$T]
  msg.lock.acquire()
  var d = cast[ref seq[T]](msg.data)
  if d.len <= 0:
    return none(ref seq[T])
    
  msg.lock.release()
  some(d)


proc clearMessage(bus: var CEventBus) =
  for k, msg in bus.messages:
    msg.lock.acquire()
    msg.clear(msg.data)
    msg.lock.release()

proc `destroy=`(c: var CEventBus) =
  for k, msg in bus.messages:
    msg.lock.acquire()
    msg.free(msg.data)
    msg.lock.release()

