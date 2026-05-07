##########################################################################################################################################################
################################################################ MEMORY MANAGEMENT #######################################################################
##########################################################################################################################################################

proc newGPUSeqOfCap*[B, T](cap: int): GPUSeq[B, T] =
  result.count = RefCount(count: 1)
  result.length = 0
  result.capacity = cap
  result.ensureLen()

proc newGPUSeq*[B, T](cap: int): GPUSeq[B, T] = newGPUSeqOfCap[B, T](DEFAULT_CAPACITY)

proc toGPU*[B, T](data: openArray[T]): GPUSeq[B, T] =
  result = newGPUSeqOfCap[B, T](data.len)
  result.count = RefCount(count: 1)
  result.length = data.len
  result.copyTo(data, 0, data.len)

proc newGPUArray*[N: static int, B, T](): GPUArray[N, B, T] =
  result.count = RefCount(count: 1)
  result.ensureLen()

proc toSeq*[B, T](g: GPUSeq[B, T]): seq[T] =
  result = newSeq[T](g.length)

proc toArray*[N,B,T](g: GPUArray[N,B,T]): array[N,T] =
  let res: array[N,T]
  res

proc toOpenArray*[T: GPUSeq | GPUArray](g: T): T =
  result = T
  result.startIdx = g.startIdx + start
  result.lenght = g.startIdx + stop

proc copyTo*[B,T](g: GPUSeq[B,T], src: openArray[T], start, stop: int) =
  discard

proc add*[B, T](g: var GPUSeq[B, T], item: T) =
  let oldLen = g.length
  g.length += 1
  g.ensureLen()
  
  copyTo(g, @[item], oldLen, oldLen+1)

proc append*[B, T](g: var GPUSeq[B, T], items: seq[T]) =
  let n = items.len
  let oldLen = g.length
  g.length += n
  g.ensureLen()
  
  copyto(g, items, oldLen, oldLen+n)

proc `$`*[B, T](g: GPUSeq[B, T]): string =
  let cpuData = g.toSeq()
  return "GPUSeq(" & $cpuData & ")"

proc `$`*[N, B, T](g: GPUSeq[N, B, T]): string =
  let cpuData = g.toArray()
  return "GPUArray(" & $cpuData & ")"