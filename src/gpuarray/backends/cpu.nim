##########################################################################################################################################################
################################################################## GPU ARRAYS CORE #######################################################################
##########################################################################################################################################################

import ../gpuarrays, sequtils

type
  CPUSData*[T] = ref object
    data*: seq[T]
  CPUAData*[N: static int,T] = ref object
    data*: array[N,T]

  CPUSeq*[T] = GPUSeq[CPUSData[T], T]
  CPUArray*[N: static int, T] = GPUArray[N, CPUAData[N,T], T]

proc ensureLen*[T](c: var CPUSeq[T]) =
  if c.length > c.data.data.len:
    c.data.data.setLen(c.length)
  
template releaseData*[T: CPUArray | CPUSeq](c: T) =
  c.data = nil

proc clone*[T: CPUSeq](c: T): T =
  result.length = c.length
  result.capacity = c.capacity
  result.startIdx = c.startIdx
  result.count = newRefCount()
  new(result.data)

  result.data.data = c.data.data

proc clone*[T: CPUArray](c: T): T =
  result.startIdx = c.startIdx
  result.count = newRefCount()
  new(result.data)

  result.data.data = c.data.data

proc newGPUSeqOfCap*[B: CPUSData, T](cap: int): CPUSeq[T] =
  let data = CPUSData[T](data: newSeqOfCap[T](cap))
  result.data = data
  result.capacity = cap
  result.count = newRefCount()

proc newGPUSeq*[B: CPUSData, T](l: int=0): CPUSeq[T] =
  let data = CPUSData[T](data: newSeq[T](l))
  result.data = data
  result.capacity = l
  result.length = l
  result.count = newRefCount()

proc newGPUArray*[N: static int, B: CPUAData, T](): CPUArray[N, T] =
  result.count = newRefCount()
  result.data = CPUAData[N, T]()

proc newCPUSeqOfCap*[T](cap: int): CPUSeq[T] = newGPUSeqOfCap[CPUSData[T], T](cap)
proc newCPUSeq*[T](n=0) : CPUSeq[T] = newGPUSeq[CPUSData[T], T](n)

proc newCPUArray*[N: static int, T](): CPUArray[N, T] = newGPUArray[N, CPUAData[N,T], T]()

proc copyTo*[T](dest: var CPUSeq[T], src: openArray[T], dStart: int) =
  let physDestStart = dest.startIdx + dStart
  for i in 0..<src.len:
    dest.data.data[physDestStart + i] = src[i]

proc copyTo*[N: static int,T](dest: var CPUArray[N,T], src: openArray[T], dStart: int) =
  let physDestStart = dest.startIdx + dStart
  for i in 0..<src.len:
    dest.data.data[physDestStart + i] = src[i]

proc toSeq*[T](c: CPUSeq[T]): seq[T] = c.data.data[c.startIdx ..< (c.startIdx + c.length)]
proc toArray*[N: static int,T](c: CPUArray[N,T]): array[N,T] = c.data.data
proc toGPU*[B: CPUSData, T](arr: openArray[T]): CPUSeq[T] = 
  var res = newCPUSeq[T](arr.len)
  res.data.data = arr.toSeq
  res

proc toGPU*[N: static int, B: CPUAData, T](arr: array[N,T]): CPUSeq[T] = 
  var res = newCPUArray[N,T]()
  res.data.data = arr

##########################################################################################################################################################
################################################################ CPU BACKEND — OPERATORS #################################################################
##########################################################################################################################################################
##
## Element-wise arithmetic and trigonometric operators for the CPU backend.
##
## All operators return a new CPUSeq / CPUArray — inputs are never mutated.
## Scalar variants (seq OP scalar) broadcast the scalar across every element.
## Binary variants (seq OP seq) require equal lengths and assert at runtime.
##
## Trigonometric functions operate only on floating-point element types.

import math

##########################################################################################################################################################
## INTERNAL HELPERS
##########################################################################################################################################################

template checkLengths(a, b: typed) =
  ## Assert that two sequences have the same logical length before a binary op.
  assert a.length == b.length,
    "Element-wise op requires equal lengths: " & $a.length & " vs " & $b.length

template seqBinOp(op: untyped): untyped =
  ## Emit an element-wise binary CPUSeq OP CPUSeq implementation.
  result = newCPUSeq[T](a.length)
  for i in 0..<a.length:
    result.data.data[result.startIdx + i] =
      op(a.data.data[a.startIdx + i], b.data.data[b.startIdx + i])

template seqScalarOp(op: untyped): untyped =
  ## Emit an element-wise CPUSeq OP scalar implementation.
  result = newCPUSeq[T](a.length)
  for i in 0..<a.length:
    result.data.data[result.startIdx + i] =
      op(a.data.data[a.startIdx + i], T(n))

template arrayBinOp(op: untyped): untyped =
  ## Emit an element-wise binary CPUArray OP CPUArray implementation.
  result = newCPUArray[N, T]()
  for i in 0..<N:
    result.data.data[result.startIdx + i] =
      op(a.data.data[a.startIdx + i], b.data.data[b.startIdx + i])

template arrayScalarOp(op: untyped): untyped =
  ## Emit an element-wise CPUArray OP scalar implementation.
  result = newCPUArray[N, T]()
  for i in 0..<N:
    result.data.data[result.startIdx + i] =
      op(a.data.data[a.startIdx + i], T(n))

template seqUnaryOp(fn: untyped): untyped =
  ## Emit an element-wise unary function over a CPUSeq.
  result = newCPUSeq[T](a.length)
  for i in 0..<a.length:
    result.data.data[result.startIdx + i] =
      fn(a.data.data[a.startIdx + i])

template arrayUnaryOp(fn: untyped): untyped =
  ## Emit an element-wise unary function over a CPUArray.
  result = newCPUArray[N, T]()
  for i in 0..<N:
    result.data.data[result.startIdx + i] =
      fn(a.data.data[a.startIdx + i])

##########################################################################################################################################################
## CPUSeq OP CPUSeq
##########################################################################################################################################################

proc `+`*[T](a, b: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise addition of two sequences.
  checkLengths(a, b)
  seqBinOp(`+`)

proc `-`*[T](a, b: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise subtraction of two sequences.
  checkLengths(a, b)
  seqBinOp(`-`)

proc `*`*[T](a, b: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise multiplication of two sequences.
  checkLengths(a, b)
  seqBinOp(`*`)

proc `/`*[T](a, b: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise division of two sequences.
  checkLengths(a, b)
  seqBinOp(`/`)

##########################################################################################################################################################
## CPUSeq OP SomeInteger scalar
##########################################################################################################################################################

proc `+`*[T](a: CPUSeq[T], n: SomeInteger): CPUSeq[T] =
  ## Add a scalar integer to every element.
  seqScalarOp(`+`)

proc `-`*[T](a: CPUSeq[T], n: SomeInteger): CPUSeq[T] =
  ## Subtract a scalar integer from every element.
  seqScalarOp(`-`)

proc `*`*[T](a: CPUSeq[T], n: SomeInteger): CPUSeq[T] =
  ## Multiply every element by a scalar integer.
  seqScalarOp(`*`)

proc `/`*[T](a: CPUSeq[T], n: SomeInteger): CPUSeq[T] =
  ## Divide every element by a scalar integer.
  seqScalarOp(`/`)

# Commutative scalar variants (scalar OP seq)
proc `+`*[T](n: SomeInteger, a: CPUSeq[T]): CPUSeq[T] = a + n
proc `*`*[T](n: SomeInteger, a: CPUSeq[T]): CPUSeq[T] = a * n

##########################################################################################################################################################
## CPUSeq OP SomeFloat scalar
##########################################################################################################################################################

proc `+`*[T](a: CPUSeq[T], n: SomeFloat): CPUSeq[T] =
  ## Add a scalar float to every element.
  seqScalarOp(`+`)

proc `-`*[T](a: CPUSeq[T], n: SomeFloat): CPUSeq[T] =
  ## Subtract a scalar float from every element.
  seqScalarOp(`-`)

proc `*`*[T](a: CPUSeq[T], n: SomeFloat): CPUSeq[T] =
  ## Multiply every element by a scalar float.
  seqScalarOp(`*`)

proc `/`*[T](a: CPUSeq[T], n: SomeFloat): CPUSeq[T] =
  ## Divide every element by a scalar float.
  seqScalarOp(`/`)

proc `+`*[T](n: SomeFloat, a: CPUSeq[T]): CPUSeq[T] = a + n
proc `*`*[T](n: SomeFloat, a: CPUSeq[T]): CPUSeq[T] = a * n

##########################################################################################################################################################
## CPUArray OP CPUArray
##########################################################################################################################################################

proc `+`*[N: static int, T](a, b: CPUArray[N, T]): CPUArray[N, T] =
  ## Element-wise addition of two arrays.
  arrayBinOp(`+`)

proc `-`*[N: static int, T](a, b: CPUArray[N, T]): CPUArray[N, T] =
  ## Element-wise subtraction of two arrays.
  arrayBinOp(`-`)

proc `*`*[N: static int, T](a, b: CPUArray[N, T]): CPUArray[N, T] =
  ## Element-wise multiplication of two arrays.
  arrayBinOp(`*`)

proc `/`*[N: static int, T](a, b: CPUArray[N, T]): CPUArray[N, T] =
  ## Element-wise division of two arrays.
  arrayBinOp(`/`)

##########################################################################################################################################################
## CPUArray OP SomeInteger scalar
##########################################################################################################################################################

proc `+`*[N: static int, T](a: CPUArray[N, T], n: SomeInteger): CPUArray[N, T] =
  arrayScalarOp(`+`)

proc `-`*[N: static int, T](a: CPUArray[N, T], n: SomeInteger): CPUArray[N, T] =
  arrayScalarOp(`-`)

proc `*`*[N: static int, T](a: CPUArray[N, T], n: SomeInteger): CPUArray[N, T] =
  arrayScalarOp(`*`)

proc `/`*[N: static int, T](a: CPUArray[N, T], n: SomeInteger): CPUArray[N, T] =
  arrayScalarOp(`/`)

proc `+`*[N: static int, T](n: SomeInteger, a: CPUArray[N, T]): CPUArray[N, T] = a + n
proc `*`*[N: static int, T](n: SomeInteger, a: CPUArray[N, T]): CPUArray[N, T] = a * n

##########################################################################################################################################################
## CPUArray OP SomeFloat scalar
##########################################################################################################################################################

proc `+`*[N: static int, T](a: CPUArray[N, T], n: SomeFloat): CPUArray[N, T] =
  arrayScalarOp(`+`)

proc `-`*[N: static int, T](a: CPUArray[N, T], n: SomeFloat): CPUArray[N, T] =
  arrayScalarOp(`-`)

proc `*`*[N: static int, T](a: CPUArray[N, T], n: SomeFloat): CPUArray[N, T] =
  arrayScalarOp(`*`)

proc `/`*[N: static int, T](a: CPUArray[N, T], n: SomeFloat): CPUArray[N, T] =
  arrayScalarOp(`/`)

proc `+`*[N: static int, T](n: SomeFloat, a: CPUArray[N, T]): CPUArray[N, T] = a + n
proc `*`*[N: static int, T](n: SomeFloat, a: CPUArray[N, T]): CPUArray[N, T] = a * n

##########################################################################################################################################################
## TRIGONOMETRY — CPUSeq  (SomeFloat elements only)
##########################################################################################################################################################

proc sin*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise sine.
  seqUnaryOp(sin)

proc cos*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise cosine.
  seqUnaryOp(cos)

proc tan*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise tangent.
  seqUnaryOp(tan)

proc arcsin*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise arc sine.
  seqUnaryOp(arcsin)

proc arccos*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise arc cosine.
  seqUnaryOp(arccos)

proc arctan*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise arc tangent.
  seqUnaryOp(arctan)

proc sqrt*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise square root.
  seqUnaryOp(sqrt)

proc exp*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise e^x.
  seqUnaryOp(exp)

proc ln*[T: SomeFloat](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise natural logarithm.
  seqUnaryOp(ln)

proc abs*[T](a: CPUSeq[T]): CPUSeq[T] =
  ## Element-wise absolute value. Works on integers and floats.
  seqUnaryOp(abs)

##########################################################################################################################################################
## TRIGONOMETRY — CPUArray  (SomeFloat elements only)
##########################################################################################################################################################

proc sin*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(sin)

proc cos*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(cos)

proc tan*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(tan)

proc arcsin*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(arcsin)

proc arccos*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(arccos)

proc arctan*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(arctan)

proc sqrt*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(sqrt)

proc exp*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(exp)

proc ln*[N: static int, T: SomeFloat](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(ln)

proc abs*[N: static int, T](a: CPUArray[N, T]): CPUArray[N, T] =
  arrayUnaryOp(abs)

##########################################################################################################################################################
## FILL — constant initialisation
##########################################################################################################################################################
 
proc fill*[T](a: var CPUSeq[T], val: T) =
  ## Set every logical element of `a` to `val`.
  ##
  ## Example:
  ##   var s = newCPUSeq[float32](4)
  ##   s.fill(0.0'f32)   # [0, 0, 0, 0]
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] = val
 
proc fill*[N: static int, T](a: var CPUArray[N, T], val: T) =
  ## Set every element of the fixed-size array `a` to `val`.
  ##
  ## Example:
  ##   var arr = newCPUArray[4, int]()
  ##   arr.fill(1)   # [1, 1, 1, 1]
  for i in 0..<N:
    a.data.data[a.startIdx + i] = val
 
##########################################################################################################################################################
## REDUCTIONS — sum / min / max / dot
##########################################################################################################################################################
 
proc sum*[T: SomeNumber](a: CPUSeq[T]): T =
  ## Return the sum of all logical elements.
  ##
  ## Returns 0 for an empty sequence.
  result = T(0)
  for i in 0..<a.length:
    result += a.data.data[a.startIdx + i]
 
proc min*[T: SomeNumber](a: CPUSeq[T]): T =
  ## Return the minimum element.
  ##
  ## Raises `ValueError` on an empty sequence.
  if a.length == 0:
    raise newException(ValueError, "min on empty CPUSeq")
  result = a.data.data[a.startIdx]
  for i in 1..<a.length:
    let v = a.data.data[a.startIdx + i]
    if v < result: result = v
 
proc max*[T: SomeNumber](a: CPUSeq[T]): T =
  ## Return the maximum element.
  ##
  ## Raises `ValueError` on an empty sequence.
  if a.length == 0:
    raise newException(ValueError, "max on empty CPUSeq")
  result = a.data.data[a.startIdx]
  for i in 1..<a.length:
    let v = a.data.data[a.startIdx + i]
    if v > result: result = v
 
proc dot*[T: SomeNumber](a, b: CPUSeq[T]): T =
  ## Return the dot product: sum of a[i] * b[i] for all i.
  ##
  ## Both sequences must have the same logical length.
  assert a.length == b.length, "dot: length mismatch"
  result = T(0)
  for i in 0..<a.length:
    result += a.data.data[a.startIdx + i] * b.data.data[b.startIdx + i]
 
##########################################################################################################################################################
## toOpenArray — zero-copy logical slice (view, no allocation)
##########################################################################################################################################################
 
proc toOpenArray*[T](c: CPUSeq[T], start, stop: int): CPUSeq[T] =
  ## Return a view into `c` covering logical indices [start, stop).
  ##
  ## No data is copied — both the original and the view share the same
  ## underlying `seq[T]`.  Mutations through either handle are visible to
  ## the other, matching the OpenCL backend's shared-cl_mem behaviour.
  ##
  ## Parameters:
  ##   start  – first logical index to include (inclusive)
  ##   stop   – first logical index to exclude (exclusive)
  ##
  ## Example:
  ##   let full = [1, 2, 3, 4, 5].toGPU
  ##   let view = full.toOpenArray(1, 4)   # logical elements 2, 3, 4
  result.data     = c.data          # shared backing store
  result.count    = c.count         # shared reference count
  result.startIdx = c.startIdx + start
  result.length   = stop - start
  result.capacity = c.capacity
 
##########################################################################################################################################################
## NON-ALLOCATING "INTO" VARIANTS — binary
##########################################################################################################################################################
##
## Each proc writes the result of a pairwise element-wise operation into `dst`.
## If `dst` already has sufficient capacity the existing allocation is reused,
## matching the zero-allocation hot-path promised by the OpenCL backend.
##
## `dst.length` is updated to match `a.length` on every call.
##
## Aliasing: `a += a` (self-aliasing through `dst`) is safe on the CPU because
## reads and writes are sequential — no undefined behaviour unlike OpenCL 1.2.
 
proc add*[T](a, b: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise addition into `dst`: dst[i] = a[i] + b[i].
  assert a.length == b.length, "add: length mismatch"
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] =
      a.data.data[a.startIdx + i] + b.data.data[b.startIdx + i]
 
proc sub*[T](a, b: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise subtraction into `dst`: dst[i] = a[i] - b[i].
  assert a.length == b.length, "sub: length mismatch"
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] =
      a.data.data[a.startIdx + i] - b.data.data[b.startIdx + i]
 
proc mul*[T](a, b: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise multiplication into `dst`: dst[i] = a[i] * b[i].
  assert a.length == b.length, "mul: length mismatch"
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] =
      a.data.data[a.startIdx + i] * b.data.data[b.startIdx + i]
 
proc divInto*[T](a, b: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise division into `dst`: dst[i] = a[i] / b[i].
  ##
  ## Named `divInto` to avoid shadowing Nim's built-in integer `div` operator.
  assert a.length == b.length, "divInto: length mismatch"
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] =
      a.data.data[a.startIdx + i] / b.data.data[b.startIdx + i]
 
##########################################################################################################################################################
## NON-ALLOCATING "INTO" VARIANTS — scalar broadcast
##########################################################################################################################################################
 
proc addScalar*[T](a: CPUSeq[T], scalar: T, dst: var CPUSeq[T]) =
  ## Broadcast scalar addition into `dst`: dst[i] = a[i] + scalar.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = a.data.data[a.startIdx + i] + scalar
 
proc subScalar*[T](a: CPUSeq[T], scalar: T, dst: var CPUSeq[T]) =
  ## Broadcast scalar subtraction into `dst`: dst[i] = a[i] - scalar.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = a.data.data[a.startIdx + i] - scalar
 
proc mulScalar*[T](a: CPUSeq[T], scalar: T, dst: var CPUSeq[T]) =
  ## Broadcast scalar multiplication into `dst`: dst[i] = a[i] * scalar.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = a.data.data[a.startIdx + i] * scalar
 
proc divScalar*[T](a: CPUSeq[T], scalar: T, dst: var CPUSeq[T]) =
  ## Broadcast scalar division into `dst`: dst[i] = a[i] / scalar.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = a.data.data[a.startIdx + i] / scalar
 
##########################################################################################################################################################
## NON-ALLOCATING "INTO" VARIANTS — unary / trigonometric
##########################################################################################################################################################
##
## Each proc mirrors its OpenCL counterpart (sinInto, cosInto, …) and writes
## into a caller-supplied buffer, enabling allocation-free hot loops.
##
## Trigonometric procs are constrained to `SomeFloat` element types; `absInto`
## accepts any numeric type.
 
proc sinInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise sine into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = sin(a.data.data[a.startIdx + i])
 
proc cosInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise cosine into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = cos(a.data.data[a.startIdx + i])
 
proc tanInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise tangent into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = tan(a.data.data[a.startIdx + i])
 
proc arcsinInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise arc sine into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = arcsin(a.data.data[a.startIdx + i])
 
proc arccosInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise arc cosine into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = arccos(a.data.data[a.startIdx + i])
 
proc arctanInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise arc tangent into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = arctan(a.data.data[a.startIdx + i])
 
proc sqrtInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise square root into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = sqrt(a.data.data[a.startIdx + i])
 
proc expInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise e^x into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = exp(a.data.data[a.startIdx + i])
 
proc lnInto*[T: SomeFloat](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise natural logarithm into `dst`.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = ln(a.data.data[a.startIdx + i])
 
proc absInto*[T](a: CPUSeq[T], dst: var CPUSeq[T]) =
  ## Element-wise absolute value into `dst`.  Works on integers and floats.
  dst.length = a.length
  dst.ensureLen()
  for i in 0..<a.length:
    dst.data.data[dst.startIdx + i] = abs(a.data.data[a.startIdx + i])
 
##########################################################################################################################################################
## COMPOUND-ASSIGNMENT OPERATORS — CPUSeq OP CPUSeq
##########################################################################################################################################################
##
## All operators mutate the left-hand side in place without allocating a new seq.
## Unlike OpenCL 1.2, self-aliasing (`a += a`) is safe here because the CPU
## executes element operations sequentially with no parallelism hazard.
 
proc `+=`*[T](a: var CPUSeq[T], b: CPUSeq[T]) =
  ## In-place element-wise addition: a[i] += b[i].
  assert a.length == b.length, "+= : length mismatch"
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] += b.data.data[b.startIdx + i]
 
proc `-=`*[T](a: var CPUSeq[T], b: CPUSeq[T]) =
  ## In-place element-wise subtraction: a[i] -= b[i].
  assert a.length == b.length, "-= : length mismatch"
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] -= b.data.data[b.startIdx + i]
 
proc `*=`*[T](a: var CPUSeq[T], b: CPUSeq[T]) =
  ## In-place element-wise multiplication: a[i] *= b[i].
  assert a.length == b.length, "*= : length mismatch"
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] *= b.data.data[b.startIdx + i]
 
proc `/=`*[T](a: var CPUSeq[T], b: CPUSeq[T]) =
  ## In-place element-wise division: a[i] /= b[i].
  assert a.length == b.length, "/= : length mismatch"
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] /= b.data.data[b.startIdx + i]
 
##########################################################################################################################################################
## COMPOUND-ASSIGNMENT OPERATORS — CPUSeq OP scalar
##########################################################################################################################################################
 
proc `+=`*[T](a: var CPUSeq[T], scalar: T) =
  ## In-place scalar addition: a[i] += scalar.
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] += scalar
 
proc `-=`*[T](a: var CPUSeq[T], scalar: T) =
  ## In-place scalar subtraction: a[i] -= scalar.
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] -= scalar
 
proc `*=`*[T](a: var CPUSeq[T], scalar: T) =
  ## In-place scalar multiplication: a[i] *= scalar.
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] *= scalar
 
proc `/=`*[T](a: var CPUSeq[T], scalar: T) =
  ## In-place scalar division: a[i] /= scalar.
  for i in 0..<a.length:
    a.data.data[a.startIdx + i] /= scalar
 
##########################################################################################################################################################
## COMMUTATIVE MISSING VARIANTS — n - seq, n / seq
##########################################################################################################################################################
 
proc `-`*[T](n: SomeNumber, a: CPUSeq[T]): CPUSeq[T] =
  ## Scalar minus seq: result[i] = n - a[i].
  ##
  ## The symmetric `n + seq` and `n * seq` forms are already provided by the
  ## existing CPU backend; only subtraction and division are asymmetric and thus
  ## require their own implementations.
  result = newCPUSeq[T](a.length)
  for i in 0..<a.length:
    result.data.data[result.startIdx + i] = T(n) - a.data.data[a.startIdx + i]
 
proc `/`*[T](n: SomeNumber, a: CPUSeq[T]): CPUSeq[T] =
  ## Scalar divided by seq: result[i] = n / a[i].
  result = newCPUSeq[T](a.length)
  for i in 0..<a.length:
    result.data.data[result.startIdx + i] = T(n) / a.data.data[a.startIdx + i]
 
proc `-`*[N: static int, T](n: SomeNumber, a: CPUArray[N, T]): CPUArray[N, T] =
  ## Scalar minus array: result[i] = n - a[i].
  result = newCPUArray[N, T]()
  for i in 0..<N:
    result.data.data[result.startIdx + i] = T(n) - a.data.data[a.startIdx + i]
 
proc `/`*[N: static int, T](n: SomeNumber, a: CPUArray[N, T]): CPUArray[N, T] =
  ## Scalar divided by array: result[i] = n / a[i].
  result = newCPUArray[N, T]()
  for i in 0..<N:
    result.data.data[result.startIdx + i] = T(n) / a.data.data[a.startIdx + i]
 
## Helpers — check all lengths match the first operand.
proc checkAllLengths[T](ops: openArray[CPUSeq[T]]) =
  for i in 1..<ops.len:
    assert ops[i].length == ops[0].length,
      "Many-op length mismatch at index " & $i &
      ": " & $ops[i].length & " vs " & $ops[0].length

proc addMany*[T](operands: varargs[CPUSeq[T]]): CPUSeq[T] =
  ## Element-wise sum of any number of CPUSeq in a single pass.
  ## All operands must share the same logical length.
  ##
  ## Equivalent to operands[0] + operands[1] + … but with no intermediate
  ## allocations and only one iteration over the data.
  assert operands.len >= 2, "addMany requires at least 2 operands"
  checkAllLengths(operands)
  let n = operands[0].length
  result = newCPUSeq[T](n)
  for i in 0..<n:
    var acc = operands[0].data.data[operands[0].startIdx + i]
    for k in 1..<operands.len:
      acc += operands[k].data.data[operands[k].startIdx + i]
    result.data.data[result.startIdx + i] = acc

proc subMany*[T](operands: varargs[CPUSeq[T]]): CPUSeq[T] =
  ## Element-wise left-fold subtraction: op[0] - op[1] - op[2] - …
  ## All operands must share the same logical length.
  assert operands.len >= 2, "subMany requires at least 2 operands"
  checkAllLengths(operands)
  let n = operands[0].length
  result = newCPUSeq[T](n)
  for i in 0..<n:
    var acc = operands[0].data.data[operands[0].startIdx + i]
    for k in 1..<operands.len:
      acc -= operands[k].data.data[operands[k].startIdx + i]
    result.data.data[result.startIdx + i] = acc

proc mulMany*[T](operands: varargs[CPUSeq[T]]): CPUSeq[T] =
  ## Element-wise product of any number of CPUSeq in a single pass.
  assert operands.len >= 2, "mulMany requires at least 2 operands"
  checkAllLengths(operands)
  let n = operands[0].length
  result = newCPUSeq[T](n)
  for i in 0..<n:
    var acc = operands[0].data.data[operands[0].startIdx + i]
    for k in 1..<operands.len:
      acc *= operands[k].data.data[operands[k].startIdx + i]
    result.data.data[result.startIdx + i] = acc

proc divMany*[T](operands: varargs[CPUSeq[T]]): CPUSeq[T] =
  ## Element-wise left-fold division: op[0] / op[1] / op[2] / …
  assert operands.len >= 2, "divMany requires at least 2 operands"
  checkAllLengths(operands)
  let n = operands[0].length
  result = newCPUSeq[T](n)
  for i in 0..<n:
    var acc = operands[0].data.data[operands[0].startIdx + i]
    for k in 1..<operands.len:
      acc /= operands[k].data.data[operands[k].startIdx + i]
    result.data.data[result.startIdx + i] = acc

## "Into" variants — write into a caller-supplied buffer (zero allocation).

proc addManyInto*[T](operands: openArray[CPUSeq[T]], dst: var CPUSeq[T]) =
  ## addMany with explicit destination buffer — no allocation.
  assert operands.len >= 2, "addManyInto requires at least 2 operands"
  checkAllLengths(operands)
  dst.length = operands[0].length
  dst.ensureLen()
  for i in 0..<operands[0].length:
    var acc = operands[0].data.data[operands[0].startIdx + i]
    for k in 1..<operands.len:
      acc += operands[k].data.data[operands[k].startIdx + i]
    dst.data.data[dst.startIdx + i] = acc

proc subManyInto*[T](operands: openArray[CPUSeq[T]], dst: var CPUSeq[T]) =
  ## subMany with explicit destination buffer — no allocation.
  assert operands.len >= 2, "subManyInto requires at least 2 operands"
  checkAllLengths(operands)
  dst.length = operands[0].length
  dst.ensureLen()
  for i in 0..<operands[0].length:
    var acc = operands[0].data.data[operands[0].startIdx + i]
    for k in 1..<operands.len:
      acc -= operands[k].data.data[operands[k].startIdx + i]
    dst.data.data[dst.startIdx + i] = acc

proc mulManyInto*[T](operands: openArray[CPUSeq[T]], dst: var CPUSeq[T]) =
  ## mulMany with explicit destination buffer — no allocation.
  assert operands.len >= 2, "mulManyInto requires at least 2 operands"
  checkAllLengths(operands)
  dst.length = operands[0].length
  dst.ensureLen()
  for i in 0..<operands[0].length:
    var acc = operands[0].data.data[operands[0].startIdx + i]
    for k in 1..<operands.len:
      acc *= operands[k].data.data[operands[k].startIdx + i]
    dst.data.data[dst.startIdx + i] = acc

proc divManyInto*[T](operands: openArray[CPUSeq[T]], dst: var CPUSeq[T]) =
  ## divMany with explicit destination buffer — no allocation.
  assert operands.len >= 2, "divManyInto requires at least 2 operands"
  checkAllLengths(operands)
  dst.length = operands[0].length
  dst.ensureLen()
  for i in 0..<operands[0].length:
    var acc = operands[0].data.data[operands[0].startIdx + i]
    for k in 1..<operands.len:
      acc /= operands[k].data.data[operands[k].startIdx + i]
    dst.data.data[dst.startIdx + i] = acc

##########################################################################################################################################################
## $ — string representation
##########################################################################################################################################################
 
proc `$`*[T](c: CPUSeq[T]): string =
  ## Return a human-readable representation of the logical slice of `c`.
  ##
  ## Matches the OpenCL backend's format: ``CPUSeq(@[1, 2, 3])``.
  "CPUSeq(" & $c.toSeq() & ")"
 
proc `$`*[N: static int, T](c: CPUArray[N, T]): string =
  ## Return a human-readable representation of the fixed-size array `c`.
  ##
  ## Matches the OpenCL backend's format: ``CPUArray([1, 2, 3])``.
  "CPUArray(" & $c.toArray() & ")"