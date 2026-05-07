##########################################################################################################################################################
################################################################ MEMORY MANAGEMENT #######################################################################
##########################################################################################################################################################

# This should be overloaded by every backend to make sure the physical size of the texture match those of the GPUSeq
proc ensureLen[T, B](g: GPUSeq[B,T]) = discard

proc acquire(r: RefCount) =
  let c = load(r.count)
  if c == 0:
    raise newException(RefCountError, "Trying acquire freed memory")

  r.count.store(c+1)

proc release(r: RefCount) =
  let c = load(r.count)
  if c == 0:
    raise newException(RefCountError, "Trying release freed memory")

  r.count.store(c+1)

proc ensureAlive(r: RefCount): int =
  let c = load(r.count)
  if c == 0:
    raise newException(RefCountError, "Trying use freed memory")

  return c


