##########################################################################################################################################################
################################################################ MEMORY MANAGEMENT #######################################################################
##########################################################################################################################################################

proc newGPUSeqOfCap*[B: static int, T](cap: int): GPUSeq[B, T] =
  result.count = newRefCount()
  result.length = 0
  result.capacity = cap
  result.ensureLen()

proc newGPUSeq*[B: static int, T](n: int=0): GPUSeq[B, T] = newGPUSeqOfCap[B, T](n)

proc toGPU*[B: static int, T](data: openArray[T]): GPUSeq[B, T] =
  result = newGPUSeqOfCap[B, T](data.len)
  result.count = newRefCount()
  result.length = data.len
  result.copyTo(data, 0, data.len)

proc newGPUArray*[N: static int, B: static int, T](): GPUArray[N, B, T] =
  result.count = newRefCount()
  result.ensureLen()

proc toSeq*[B: static int, T](g: GPUSeq[B, T]): seq[T] =
  result = newSeq[T](g.length)

proc toArray*[N,B,T](g: GPUArray[N,B,T]): array[N,T] =
  let res: array[N,T]
  res

proc toOpenArray*[T: GPUSeq](g: T, start, stop: int): T =
  result.data = g.data
  result.count = g.count
  result.startIdx = g.startIdx + start
  result.length = stop - start

proc toOpenArray*[T: GPUArray](g: T, start, stop: int): T =
  result.data = g.data
  result.count = g.count
  result.startIdx = g.startIdx + start

template `[]`*(g: GPUSeq, i): untyped = 
  assert_scalar("[]", CURRENT_INDEXING)
  g.toSeq[i]
template `[]`*(g: GPUArray, i): untyped = 
  assert_scalar("[]", CURRENT_INDEXING)
  g.toArray[i]
template `[]=`*(g: GPUSeq | GPUArray, i, item: untyped): untyped =
  assert_scalar("[]=", CURRENT_INDEXING)
  g.ensureLen()
  copyTo(g, @[item], i)

proc copyTo*[B,T](g: GPUSeq[B,T], src: openArray[T], start: int) =
  discard

proc copyTo*[N,B,T](g: GPUArray[N,B,T], src: openArray[T], start: int) =
  discard

template add*[B, T](g: var GPUSeq[B, T], item: T) =
  let oldLen = g.length
  g.length += 1
  if g.length > g.capacity: g.capacity *= 2
  g.ensureLen()
  
  copyTo(g, @[item], oldLen)

template append*[B, T](g: var GPUSeq[B, T], items: seq[T]) =
  let n = items.len
  let oldLen = g.length
  g.length += n
  if g.length > g.capacity:
    g.capacity += n 
    g.capacity *= 2
  g.ensureLen()
  
  copyto(g, items, oldLen)

template `$`*[B, T](g: GPUSeq[B, T]): string =
  let cpuData = g.toSeq()
  "GPUSeq(" & $cpuData & ")"

template `$`*[N, B, T](g: GPUArray[N, B, T]): string =
  let cpuData = g.toArray()
  "GPUArray(" & $cpuData & ")"