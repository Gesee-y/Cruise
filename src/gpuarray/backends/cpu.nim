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