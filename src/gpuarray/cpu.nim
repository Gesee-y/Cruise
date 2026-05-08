##########################################################################################################################################################
################################################################## GPU ARRAYS CORE #######################################################################
##########################################################################################################################################################

import gpuarrays

type
  CPUSData[T] = ref object
    data: seq[T]
  CPUAData[N,T] = ref object
    data: array[N,T]

  CPUSeq[T] = GPUSeq[CPUSData[T], T]
  CPUArray[N: static int, T] = GPUArray[N, CPUAData[N,T], T]

proc ensureLen*[T](c: var CPUSeq[T]) =
  if c.lenght > c.data.data.len:
    c.data.data.setLen(c.lenght)
  
template releaseData*[T: CPUArray | CPUSeq](c: T) =
  c.data = nil

proc clone*[T: CPUArray | CPUSeq](c: T): T =
  result = c
  result.data = nil
  result.startIdx = c.startIdx
  result.count = newRefCount()
  new(result.data)

  result.data.data = c.data.data
  
proc newGPUSeqOfCap[B: CPUSData, T](cap: int): CPUSeq[T] =
  let data = CPUSData(data: newSeqOfCap[T](cap))
  result.data = data
  result.capacity = cap
  result.count = RefCount(count:1)

proc newGPUSeq[B: CPUSData, T](l: int=0): CPUSeq[T] =
  let data = CPUSData(data: newSeq[T](l))
  result.data = data
  result.capacity = DEFAULT_CAPACITY + l*2
  result.lenght = l
  result.count = RefCount(count:1)

proc newGPUArray*[N: static int, B: CPUAData, T](): GPUArray[N, B, T] =
  result.count = newRefCount()
  result.data = CPUAData[N, T]()

proc newCPUSeqOfCap[T](cap: int): CPUSeq[T] = newGPUSeqOfCap[CPUSData, T](cap)
proc newCPUSeq[T](n=0): CPUSeq[T] = newGPUSeq[CPUSData, T](n)

proc newCPUArray[N: static int, T](): CPUArray[N, CPUAData, T] = newGPUArray[N, CPUAData, T]()

proc copyTo*[T](dest: var CPUSeq[T], src: openArray[T], dStart: int) =
  let physDestStart = dest.startIdx + dStart
  for i in 0..<src.len:
    dest.data.data[physDestStart + i] = src[i]

proc copyTo*[N: static int,T](dest: var CPUArray[N,T], src: openArray[T], dStart: int) =
  let physDestStart = dest.startIdx + dStart
  for i in 0..<src.len:
    dest.data.data[physDestStart + i] = src[i]

proc toSeq*[T](c: CPUSeq[T]): seq[T] = c.data.data
proc toArray*[N: static int,T](c: CPUArray[N,T]): array[N,T] = c.data.data

