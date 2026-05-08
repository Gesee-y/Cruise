##########################################################################################################################################################
################################################################ MEMORY MANAGEMENT #######################################################################
##########################################################################################################################################################

# This should be overloaded by every backend to make sure the physical size of the texture match those of the GPUSeq
proc ensureLen*[T, B](g: GPUSeq[B,T]) = discard
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

proc acquire(r: RefCount): int =
  let c = load(r.count)
  if c == 0:
    raise newException(RefCountError, "Trying acquire freed memory")

  r.count.store(c+1)
  return c+1

proc release(r: RefCount): int =
  let c = load(r.count)
  if c == 0:
    raise newException(RefCountError, "Trying release freed memory")

  r.count.store(c-1)
  return c-1

proc ensureAlive(r: RefCount): int =
  if r.isNil: raise newException(RefCountError, "Trying use freed or moved memory")
  let c = load(r.count)
  if c == 0:
    raise newException(RefCountError, "Trying use freed memory")

  return c

template `=destroy`*[T: GPUSeq | GPUArray](g: T) =
  var cnt = g.count
  if cnt != nil:
    let c = release(cnt)
    if c == 0:
      releaseData(g.data)

template `=copy`*[T: GPUSeq | GPUArray](dest: var T, src: T) =
  dest.data = src.data
  dest.count = src.count
  dest.capacity = src.capacity
  dest.length = src.length
  dest.startIdx = src.startIdx
  
  if dest.count != nil:
    acquire(dest.count)

template `=wasMove`*[T: GPUSeq | GPUArray](src: var T) =  
  src.count = nil
  src.data = B()

template `dup=`*[T: GPUSeq | GPUArray](src: T): T = src.clone