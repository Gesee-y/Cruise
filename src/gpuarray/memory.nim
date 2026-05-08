##########################################################################################################################################################
################################################################ MEMORY MANAGEMENT #######################################################################
##########################################################################################################################################################

# This should be overloaded by every backend to make sure the physical size of the texture match those of the GPUSeq
proc ensureLen*[T, B](g: GPUSeq[B,T]) = discard
proc ensureLen*[N, T, B](g: GPUArray[N,B,T]) = discard
proc releaseData*[T: GPUSeq | GPUArray](g: T) = discard
proc clone*[B, T](src: GPUSeq[B, T]): GPUSeq[B, T] =
  result.data = src.data
  result.count = newRefCount()
  result.capacity = src.capacity
  result.startIdx = src.startIdx
  result.length = src.length

proc clone*[N, B, T](src: GPUArray[N, B, T]): GPUArray[N, B, T] =
  result.data = src.data
  result.count = newRefCount()

proc acquire*(r: RefCount): int =
  let c = r.count.fetchAdd(1)
  if c == 0:
    raise newException(RefCountError, "Trying acquire freed memory")

  return c+1

proc release*(r: RefCount): int =
  let c = r.count.fetchSub(1)
  if c == 0:
    raise newException(RefCountError, "Trying release freed memory")

  return c-1

proc ensureAlive*(r: RefCount): int =
  if r.isNil: raise newException(RefCountError, "Trying use freed or moved memory")
  let c = load(r.count)
  if c == 0:
    raise newException(RefCountError, "Trying use freed memory")

  return c

proc `=destroy`*[B, T](g: var GPUSeq[B, T]) {.raises: [RefCountError].} =
  var cnt = g.count
  if not cnt.isNil and cnt.count.load > 0:
    let c = release(cnt)
    if c == 0:
      releaseData(g)

proc `=destroy`*[N: static int, B, T](g: var GPUArray[N ,B, T]) {.raises: [RefCountError].} =
  var cnt = g.count
  if not cnt.isNil:
    let c = release(cnt)
    if c == 0:
      releaseData(g)
    g.count = nil

proc `=copy`*[B, T](dest: var GPUSeq[B, T], src: GPUSeq[B, T]) {.raises: [RefCountError].} =
  dest.data = src.data
  dest.count = src.count
  dest.capacity = src.capacity
  dest.length = src.length
  dest.startIdx = src.startIdx
  
  if dest.count != nil:
    discard acquire(dest.count)

proc `=copy`*[N: static int,T,B](dest: var GPUArray[N,T,B], src: GPUArray[N,T,B]) {.raises: [RefCountError].} =
  dest.data = src.data
  dest.count = src.count
  dest.startIdx = src.startIdx
  
  if dest.count != nil:
    discard acquire(dest.count)

proc `=wasMoved`*[B, T](src: var GPUSeq[B, T]) = 
  src.count = nil

proc `=wasMoved`*[N: static int,T,B](src: var GPUArray[N,T,B]) =  
  src.count = nil

proc `=sink`*[B,T](dest: var GPUSeq[B,T], source: GPUSeq[B,T]) =
  discard dest.count.count.fetchAdd(1)
  copyMem(addr(dest), addr(source), sizeof(GPUSeq[B,T]))
  `=destroy`(dest)
  wasMoved(dest) 

proc `=move`*[B,T](dest: var GPUSeq[B,T], source: GPUSeq[B,T]) =
  discard dest.count.count.fetchAdd(1)
  copyMem(addr(dest), addr(source), sizeof(GPUSeq[B,T]))
  `=destroy`(dest)
  wasMoved(dest) 

proc `dup=`*[B, T](src: var GPUSeq[B, T]): GPUSeq[B, T] = src.clone
proc `dup=`*[N: static int, B, T](src: var GPUArray[N, B, T]): GPUArray[N, B, T] = src.clone
