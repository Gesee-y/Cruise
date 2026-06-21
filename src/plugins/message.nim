# ######################################################################################################################################################## #
# ################################################################# EDA MESSAGE PASSING ################################################################## #
# ######################################################################################################################################################## #

type
  CMData*[T] = ref object
    ## Contains the all the messages for a given type `T` and their timestamp
    data: seq[T]
    timestamps: seq[int]
    lock: RWLock

  # Internal structure for a type erased thread-safe message handle
  CMessage = object
    data: pointer
    clear: proc(p: pointer)
    free: proc(p: pointer)

  CEventBus* = object
    lock: Lock
    messages: Table[string, CMessage]

var MESSAGE_TYPE_REGISTRY {.compileTime.} = initTable[int, NimNode]()

proc registerMessageType(t: NimNode) =
  MESSAGE_TYPE_REGISTRY[t.getTypeInst.repr.hash.int] = t

template newMessage[T](): CMessage =
  let data: CMData[T]
  new(data)
  GC_ref(data)
  data.lock.initLock()
  result.data = cast[pointer](data)
  result.clear =
    proc(p: pointer) =
      var d = cast[CMData[T]](p)
      d.lock.withWriteLock:
        d.data.setLen(0)
        d.timestamps.setLen(0)
  result.free =
    proc(p: pointer) =
      var d = cast[CMData[T]](p)
      GC_unref(d)

macro newCEventBus*(): CEventBus =
  let msgAdd = newNimNode(nnkStmtList)
  let bus = ident"bus"

  for t in MESSAGE_TYPE_REGISTRY.values:
    msgAdd.add quote do:
      `bus`.messages[$`t`] = newMessage[`t`]()

  return quote do:
    var `bus` = CEventBus()
    `msgAdd`

macro addMessage*[T](bus: var CEventBus, obj: T) =
  registerMessageType(obj)

  return quote do:
    var msg = `bus`.messages[$`T`]
    var d = cast[CMData[`T`]](msg.data)
    d.lock.withWriteLock:
      d.data.add(`obj`)
      d.timestamps.add(getMonoTime().ticks)

proc getMessage*[T](bus: var CEventBus, obj: T): Option[CMData[T]] =
  if $T notin bus.messages:
    return none(CMData[T])

  var msg = bus.messages[$T]
  var d = cast[CMData[`T`]](msg.data)
  d.lock.withReadLock:
    var d = cast[CMData[T]](msg.data)
    if d.data.len <= 0:
      return none(CMData[T])

    some(d)

proc clearMessage*(bus: var CEventBus) =
  for k, msg in bus.messages.mpairs:
    msg.clear(msg.data)

proc `[]`*[T](c: CMData[T], i: int): T = c.data[i]
proc timestamp*[T](c: CMData[T], i: int): int = c.timestamps[i]

iterator items*[T](c: CMData[T]): T =
  c.lock.withReadLock:
    for data in c.data:
      yield data

proc destroy*(bus: var CEventBus) =
  for k, msg in bus.messages.mpairs:
    msg.free(msg.data)

proc `destroy=`(bus: var CEventBus) =
  bus.destroy()
