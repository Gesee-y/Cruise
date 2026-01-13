import std/[times]

import times, os

type
  Queue*[T] = object
    data: seq[T]
    readCursor: int
    writeCursor: int

proc initQueue*[T](initialCapacity: int = 64): Queue[T] =
  result.data = newSeqOfCap[T](initialCapacity)
  result.readCursor = 0
  result.writeCursor = 0

proc clear*[T](q: var Queue[T]) {.inline.} =
  q.readCursor = 0
  q.writeCursor = 0

proc enqueue*[T](q: var Queue[T], item: T) {.inline.} =
  if q.writeCursor >= q.data.len:
    q.data.setLen(q.writeCursor + 1)
  q.data[q.writeCursor] = item
  inc q.writeCursor

proc enqueueMultiple*[T](q: var Queue[T], items: openArray[T]) {.inline.} =
  let needed = q.writeCursor + items.len
  if needed > q.data.len:
    q.data.setLen(needed)
  
  for item in items:
    q.data[q.writeCursor] = item
    inc q.writeCursor

proc dequeue*[T](q: var Queue[T]): T {.inline.} =
  assert q.readCursor < q.writeCursor, "Queue is empty"
  result = q.data[q.readCursor]
  inc q.readCursor

proc tryDequeue*[T](q: var Queue[T], res: var T): bool {.inline.} =
  if q.readCursor < q.writeCursor:
    res = q.data[q.readCursor]
    inc q.readCursor
    return true
  return false

proc peek*[T](q: Queue[T]): T {.inline.} =
  assert q.readCursor < q.writeCursor, "Queue is empty"
  return q.data[q.readCursor]

proc isEmpty*[T](q: Queue[T]): bool {.inline.} =
  q.readCursor >= q.writeCursor

proc len*[T](q: Queue[T]): int {.inline.} =
  max(0, q.writeCursor - q.readCursor)

proc capacity*[T](q: Queue[T]): int {.inline.} =
  q.data.len

iterator items*[T](q: var Queue[T]): T =
  while q.readCursor < q.writeCursor:
    yield q.data[q.readCursor]
    inc q.readCursor

iterator pairs*[T](q: var Queue[T]): (int, T) =
  var idx = 0
  while q.readCursor < q.writeCursor:
    yield (idx, q.data[q.readCursor])
    inc q.readCursor
    inc idx

iterator itemsReadOnly*[T](q: Queue[T]): lent T =
  for i in q.readCursor..<q.writeCursor:
    yield q.data[i]

proc reserve*[T](q: var Queue[T], additionalCapacity: int) {.inline.} =
  let needed = q.writeCursor + additionalCapacity
  if needed > q.data.len:
    q.data.setLen(needed)

proc compact*[T](q: var Queue[T]) =
  if q.readCursor > 0:
    let remaining = q.writeCursor - q.readCursor
    if remaining > 0:
      for i in 0..<remaining:
        q.data[i] = q.data[q.readCursor + i]
    q.writeCursor = remaining
    q.readCursor = 0

proc `$`*[T](q: Queue[T]): string =
  result = "Queue[len=" & $q.len & ", cap=" & $q.capacity & "]: ["
  var first = true
  for i in q.readCursor..<q.writeCursor:
    if not first:
      result.add(", ")
    result.add($q.data[i])
    first = false
  result.add("]")
  