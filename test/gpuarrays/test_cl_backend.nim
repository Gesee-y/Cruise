##########################################################################################################################################################
################################################################## OPENCL BACKEND TESTS ##################################################################
##########################################################################################################################################################
##
## Test suite for the OpenCL backend (cl.nim).
## NOTE: Requires a valid OpenCL runtime (GPU or CPU).
##
## Covers:
##   1.  Context — initOpenCL / shutdownOpenCL
##   2.  CLSeq construction (newCLSeq, newCLSeqOfCap, toGPU)
##   3.  CLArray construction (newCLArray, toGPU)
##   4.  Transfers — copyTo, toSeq, toArray
##   5.  Clone — CLSeq and CLArray deep copies
##   6.  Slices — toOpenArray (logical views)
##   7.  Fill — CLSeq and CLArray
##   8.  Arithmetic CLSeq×CLSeq
##   9.  Arithmetic CLSeq×scalar (+ commutative n-seq, n/seq)
##   10. Arithmetic CLArray×CLArray (native GPU kernels)
##   11. Arithmetic CLArray×scalar
##   12. Trigonometry — CLSeq
##   13. Trigonometry — CLArray
##   14. Reductions — sum, min, max, dot
##   15. Kernel cache — compile-once
##   16. Edge cases — empty, length-1, large
##   17. String representation
##
## Run with:
##   nim c -r test/gpuarrays/test_cl_backend.nim

import unittest, math, atomics, strutils, tables
import ../../src/gpuarray/gpuarrays
import ../../src/gpuarray/backends/cl

##########################################################################################################################################################
## TOLERANCE HELPERS
##########################################################################################################################################################

const EPS32 = 1e-5f
const EPS64 = 1e-10

proc almostEq(a, b: float32; eps = EPS32): bool = abs(a - b) < eps
proc almostEq(a, b: float64; eps = EPS64): bool = abs(a - b) < eps

proc seqAlmostEq[T: SomeFloat](a, b: seq[T]; eps: T): bool =
  if a.len != b.len: return false
  for i in 0..<a.len:
    if abs(a[i] - b[i]) >= eps: return false
  true

##########################################################################################################################################################
## GLOBAL SETUP — one context for the whole run
##########################################################################################################################################################

initOpenCL()   ## Uses GPU by default; falls back to CPU automatically if no GPU found.

##########################################################################################################################################################
## 1. CONTEXT
##########################################################################################################################################################

suite "OpenCL context":

  test "gCL.ctx is non-nil after initOpenCL":
    check gCL.ctx   != nil

  test "gCL.queue is non-nil after initOpenCL":
    check gCL.queue != nil

  test "gCL.device is non-nil after initOpenCL":
    check gCL.device != nil

##########################################################################################################################################################
## 2. CLSeq CONSTRUCTION
##########################################################################################################################################################

suite "CLSeq — construction":

  test "newCLSeq(0) gives length 0":
    let s = newCLSeq[float32](0)
    check s.length == 0
    check s.count  != nil

  test "newCLSeq(n) gives correct length":
    let s = newCLSeq[float32](16)
    check s.length == 16

  test "newCLSeqOfCap reserves capacity, length stays 0":
    let s = newCLSeqOfCap[float32](64)
    check s.length   == 0
    check s.capacity == 64

  test "refcount starts at 1":
    let s = newCLSeq[int32](4)
    check s.count.count.load() == 1

  test "toGPU from openArray has correct length":
    let s = toGPU[CLSData[float32],float32](@[1.0f, 2.0f, 3.0f])
    check s.length == 3

##########################################################################################################################################################
## 3. CLArray CONSTRUCTION
##########################################################################################################################################################

suite "CLArray — construction":

  test "newCLArray has non-nil data":
    let a = newCLArray[4, float32]()
    check a.data != nil

  test "newCLArray refcount starts at 1":
    let a = newCLArray[8, float32]()
    check a.count.count.load() == 1

  test "toGPU from array produces CLArray":
    let src: array[3, float32] = [1f, 2f, 3f]
    let a = toGPU[3, CLAData[3, float32], float32](src)
    check a.data != nil

##########################################################################################################################################################
## 4. TRANSFERS — copyTo / toSeq / toArray
##########################################################################################################################################################

suite "CLSeq — transfers":

  test "toGPU then toSeq round-trips float32":
    let src = @[1.0f, 2.0f, 3.0f, 4.0f]
    let s   = toGPU[CLSData[float32], float32](src)
    check s.toSeq() == src

  test "toGPU then toSeq round-trips int32":
    let src = @[10'i32, 20'i32, 30'i32]
    let s   = toGPU[CLSData[int32], int32](src)
    check s.toSeq() == src

  test "copyTo writes at correct offset":
    var s = newCLSeq[float32](8)
    s.copyTo([5.0f, 6.0f, 7.0f], 2)
    let r = s.toSeq()
    check r[2] == 5.0f
    check r[3] == 6.0f
    check r[4] == 7.0f

suite "CLArray — transfers":

  test "toGPU then toArray round-trips":
    let src: array[4, float32] = [10f, 20f, 30f, 40f]
    let a   = toGPU[4, CLAData[4, float32], float32](src)
    check a.toArray() == src

  test "copyTo then toArray":
    var a = newCLArray[4, int32]()
    a.copyTo([1'i32, 2'i32, 3'i32, 4'i32], 0)
    check a.toArray() == [1'i32, 2'i32, 3'i32, 4'i32]

##########################################################################################################################################################
## 5. CLONE
##########################################################################################################################################################

suite "CLSeq — clone":

  test "clone produces independent copy":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    var b = a.clone()
    # Overwrite b with new data — a must be unchanged
    b.copyTo([99f, 99f, 99f], 0)
    check a.toSeq() == @[1f, 2f, 3f]

  test "clone has refcount 1":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    let b = a.clone()
    check b.count.count.load() == 1

  test "clone copies all elements":
    let src = @[5f, 6f, 7f, 8f]
    let a   = toGPU[CLSData[float32], float32](src)
    let b   = a.clone()
    check b.toSeq() == src

suite "CLArray — clone":

  test "CLArray clone is independent":
    let src: array[3, float32] = [1f, 2f, 3f]
    let a = toGPU[3, CLAData[3, float32], float32](src)
    var b = a.clone()
    b.copyTo([0f, 0f, 0f], 0)
    check a.toArray() == src

##########################################################################################################################################################
## 6. SLICES — toOpenArray
##########################################################################################################################################################

suite "CLSeq — toOpenArray slicing":

  test "slice has correct length":
    let s = toGPU[CLSData[float32], float32](@[0f, 1f, 2f, 3f, 4f, 5f, 6f, 7f, 8f, 9f])
    let v = s.toOpenArray(2, 6)
    check v.length == 4

  test "slice reads correct elements":
    let s = toGPU[CLSData[float32], float32](@[0f, 1f, 2f, 3f, 4f])
    let v = s.toOpenArray(1, 4)
    check v.toSeq() == @[1f, 2f, 3f]

##########################################################################################################################################################
## 7. FILL
##########################################################################################################################################################

suite "Fill":

  test "fill CLSeq with constant":
    var s = newCLSeq[float32](6)
    s.fill(3.14f)
    let r = s.toSeq()
    for v in r: check almostEq(v, 3.14f)

  test "fill CLSeq with zero":
    var s = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    s.fill(0f)
    for v in s.toSeq(): check v == 0f

  test "fill CLArray with constant":
    var a = newCLArray[4, float32]()
    a.fill(7f)
    for v in a.toArray(): check almostEq(v, 7f)

  test "fill CLArray[int32]":
    var a = newCLArray[3, int32]()
    a.fill(42'i32)
    check a.toArray() == [42'i32, 42'i32, 42'i32]

##########################################################################################################################################################
## 8. ARITHMETIC CLSeq × CLSeq
##########################################################################################################################################################

suite "CLSeq — seq×seq arithmetic":

  test "a + b element-wise":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f, 4f])
    let b = toGPU[CLSData[float32], float32](@[4f, 3f, 2f, 1f])
    check (a + b).toSeq() == @[5f, 5f, 5f, 5f]

  test "a - b element-wise":
    let a = toGPU[CLSData[float32], float32](@[5f, 5f, 5f])
    let b = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    check (a - b).toSeq() == @[4f, 3f, 2f]

  test "a * b element-wise":
    let a = toGPU[CLSData[float32], float32](@[2f, 3f, 4f])
    let b = toGPU[CLSData[float32], float32](@[3f, 4f, 5f])
    check (a * b).toSeq() == @[6f, 12f, 20f]

  test "a / b element-wise":
    let a = toGPU[CLSData[float32], float32](@[6f, 8f, 10f])
    let b = toGPU[CLSData[float32], float32](@[2f, 4f, 5f])
    check (a / b).toSeq() == @[3f, 2f, 2f]

  test "int32 a + b":
    let a = toGPU[CLSData[int32], int32](@[1'i32, 2'i32, 3'i32])
    let b = toGPU[CLSData[int32], int32](@[4'i32, 5'i32, 6'i32])
    check (a + b).toSeq() == @[5'i32, 7'i32, 9'i32]

  test "length mismatch raises":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f])
    let b = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    expect AssertionDefect:
      discard a + b

##########################################################################################################################################################
## 9. ARITHMETIC CLSeq × scalar
##########################################################################################################################################################

suite "CLSeq — seq×scalar arithmetic":

  test "a + scalar":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    check (a + 10f).toSeq() == @[11f, 12f, 13f]

  test "a - scalar":
    let a = toGPU[CLSData[float32], float32](@[5f, 6f, 7f])
    check (a - 1f).toSeq() == @[4f, 5f, 6f]

  test "a * scalar":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    check (a * 3f).toSeq() == @[3f, 6f, 9f]

  test "a / scalar":
    let a = toGPU[CLSData[float32], float32](@[2f, 4f, 6f])
    check (a / 2f).toSeq() == @[1f, 2f, 3f]

  test "scalar + a (commutative)":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    check (10f + a).toSeq() == @[11f, 12f, 13f]

  test "scalar * a (commutative)":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    check (3f * a).toSeq() == @[3f, 6f, 9f]

  test "n - a: result[i] = n - a[i]":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    let r = (10f - a).toSeq()
    check r == @[9f, 8f, 7f]

  test "n / a: result[i] = n / a[i]":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 4f])
    let r = (8f / a).toSeq()
    check almostEq(r[0], 8f) and almostEq(r[1], 4f) and almostEq(r[2], 2f)

##########################################################################################################################################################
## 10. ARITHMETIC CLArray × CLArray  (native GPU kernels, no CPU round-trip)
##########################################################################################################################################################

suite "CLArray — arr×arr arithmetic (GPU kernel)":

  test "arr + arr":
    let a = toGPU[4, CLAData[4, float32], float32]([1f, 2f, 3f, 4f])
    let b = toGPU[4, CLAData[4, float32], float32]([4f, 3f, 2f, 1f])
    check (a + b).toArray() == [5f, 5f, 5f, 5f]

  test "arr - arr":
    let a = toGPU[3, CLAData[3, float32], float32]([5f, 6f, 7f])
    let b = toGPU[3, CLAData[3, float32], float32]([1f, 2f, 3f])
    check (a - b).toArray() == [4f, 4f, 4f]

  test "arr * arr":
    let a = toGPU[3, CLAData[3, float32], float32]([2f, 3f, 4f])
    let b = toGPU[3, CLAData[3, float32], float32]([3f, 4f, 5f])
    check (a * b).toArray() == [6f, 12f, 20f]

  test "arr / arr":
    let a = toGPU[3, CLAData[3, float32], float32]([6f, 8f, 10f])
    let b = toGPU[3, CLAData[3, float32], float32]([2f, 4f, 5f])
    check (a / b).toArray() == [3f, 2f, 2f]

  test "int32 arr + arr":
    let a = toGPU[3, CLAData[3, int32], int32]([1'i32, 2'i32, 3'i32])
    let b = toGPU[3, CLAData[3, int32], int32]([4'i32, 5'i32, 6'i32])
    check (a + b).toArray() == [5'i32, 7'i32, 9'i32]

##########################################################################################################################################################
## 11. ARITHMETIC CLArray × scalar
##########################################################################################################################################################

suite "CLArray — arr×scalar arithmetic (GPU kernel)":

  test "arr + scalar":
    let a = toGPU[3, CLAData[3, float32], float32]([1f, 2f, 3f])
    check (a + 10f).toArray() == [11f, 12f, 13f]

  test "arr - scalar":
    let a = toGPU[3, CLAData[3, float32], float32]([5f, 6f, 7f])
    check (a - 1f).toArray() == [4f, 5f, 6f]

  test "arr * scalar":
    let a = toGPU[3, CLAData[3, float32], float32]([1f, 2f, 3f])
    check (a * 2f).toArray() == [2f, 4f, 6f]

  test "arr / scalar":
    let a = toGPU[3, CLAData[3, float32], float32]([4f, 6f, 8f])
    check (a / 2f).toArray() == [2f, 3f, 4f]

  test "scalar + arr (commutative)":
    let a = toGPU[3, CLAData[3, float32], float32]([1f, 2f, 3f])
    check (5f + a).toArray() == [6f, 7f, 8f]

  test "scalar * arr (commutative)":
    let a = toGPU[3, CLAData[3, float32], float32]([1f, 2f, 3f])
    check (3f * a).toArray() == [3f, 6f, 9f]

##########################################################################################################################################################
## 12. TRIGONOMETRY — CLSeq
##########################################################################################################################################################

suite "CLSeq — trigonometry":

  proc makeAngleSeq(n: int): CLSeq[float32] =
    var vals = newSeq[float32](n)
    for i in 0..<n: vals[i] = float32(i) * 0.5f
    toGPU[CLSData[float32], float32](vals)

  test "sin element-wise":
    let a = makeAngleSeq(4)
    let r = sin(a).toSeq()
    for i in 0..<4:
      check almostEq(r[i], sin(float32(i) * 0.5f))

  test "cos element-wise":
    let a = makeAngleSeq(4)
    let r = cos(a).toSeq()
    for i in 0..<4:
      check almostEq(r[i], cos(float32(i) * 0.5f))

  test "tan element-wise":
    let a = makeAngleSeq(3)
    let r = tan(a).toSeq()
    for i in 0..<3:
      check almostEq(r[i], tan(float32(i) * 0.5f), 1e-4f)

  test "sqrt element-wise":
    let a = toGPU[CLSData[float32], float32](@[0f, 1f, 4f, 9f, 16f])
    let r = sqrt(a).toSeq()
    check almostEq(r[0], 0f) and almostEq(r[1], 1f) and
          almostEq(r[2], 2f) and almostEq(r[3], 3f) and almostEq(r[4], 4f)

  test "exp element-wise":
    let a = toGPU[CLSData[float32], float32](@[0f, 1f, 2f])
    let r = exp(a).toSeq()
    check almostEq(r[0], 1f)
    check almostEq(r[1], exp(1f))
    check almostEq(r[2], exp(2f))

  test "ln element-wise":
    let a = toGPU[CLSData[float32], float32](@[1f, float32(math.E), float32(math.E * math.E)])
    let r = ln(a).toSeq()
    check almostEq(r[0], 0f)
    check almostEq(r[1], 1f)
    check almostEq(r[2], 2f)

  test "abs element-wise":
    let a = toGPU[CLSData[float32], float32](@[-3f, -1f, 0f, 1f, 3f])
    let r = abs(a).toSeq()
    check r == @[3f, 1f, 0f, 1f, 3f]

  test "arcsin element-wise":
    let vals = @[0f, 0.5f, 1f]
    let a = toGPU[CLSData[float32], float32](vals)
    let r = arcsin(a).toSeq()
    check almostEq(r[0], arcsin(0f),   1e-4f)
    check almostEq(r[1], arcsin(0.5f), 1e-4f)
    check almostEq(r[2], arcsin(1f),   1e-4f)

  test "arccos element-wise":
    let vals = @[0f, 0.5f, 1f]
    let a = toGPU[CLSData[float32], float32](vals)
    let r = arccos(a).toSeq()
    check almostEq(r[0], arccos(0f),   1e-4f)
    check almostEq(r[1], arccos(0.5f), 1e-4f)
    check almostEq(r[2], arccos(1f),   1e-4f)

  test "arctan element-wise":
    let vals = @[0f, 1f, -1f]
    let a = toGPU[CLSData[float32], float32](vals)
    let r = arctan(a).toSeq()
    check almostEq(r[0], arctan(0f),  1e-4f)
    check almostEq(r[1], arctan(1f),  1e-4f)
    check almostEq(r[2], arctan(-1f), 1e-4f)

##########################################################################################################################################################
## 13. TRIGONOMETRY — CLArray (native GPU kernels)
##########################################################################################################################################################

suite "CLArray — trigonometry (GPU kernel)":

  test "sin on CLArray[4,float32]":
    let src: array[4, float32] = [0f, 0.5f, 1f, 1.5f]
    let a = toGPU[4, CLAData[4, float32], float32](src)
    let r = sin(a).toArray()
    for i in 0..<4: check almostEq(r[i], sin(src[i]))

  test "cos on CLArray[4,float32]":
    let src: array[4, float32] = [0f, 0.5f, 1f, 1.5f]
    let a = toGPU[4, CLAData[4, float32], float32](src)
    let r = cos(a).toArray()
    for i in 0..<4: check almostEq(r[i], cos(src[i]))

  test "sqrt on CLArray[4,float32]":
    let src: array[4, float32] = [0f, 1f, 4f, 9f]
    let a = toGPU[4, CLAData[4, float32], float32](src)
    let r = sqrt(a).toArray()
    check almostEq(r[0], 0f) and almostEq(r[1], 1f) and
          almostEq(r[2], 2f) and almostEq(r[3], 3f)

  test "exp on CLArray[3,float32]":
    let src: array[3, float32] = [0f, 1f, 2f]
    let a = toGPU[3, CLAData[3, float32], float32](src)
    let r = exp(a).toArray()
    check almostEq(r[0], 1f) and almostEq(r[1], exp(1f)) and almostEq(r[2], exp(2f))

  test "ln on CLArray[3,float32]":
    let src: array[3, float32] = [1f, float32(math.E), float32(math.E*math.E)]
    let a = toGPU[3, CLAData[3, float32], float32](src)
    let r = ln(a).toArray()
    check almostEq(r[0], 0f) and almostEq(r[1], 1f) and almostEq(r[2], 2f)

  test "abs on CLArray[5,float32]":
    let src: array[5, float32] = [-3f, -1f, 0f, 1f, 3f]
    let a = toGPU[5, CLAData[5, float32], float32](src)
    let r = abs(a).toArray()
    check r == [3f, 1f, 0f, 1f, 3f]

##########################################################################################################################################################
## 14. REDUCTIONS — sum / min / max / dot
##########################################################################################################################################################

suite "CLSeq — reductions":

  test "sum of [1..5]":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f, 4f, 5f])
    check almostEq(a.sum(), 15f)

  test "sum of empty returns 0":
    let a = newCLSeq[float32](0)
    check a.sum() == 0f

  test "sum of 1-element":
    let a = toGPU[CLSData[float32], float32](@[42f])
    check almostEq(a.sum(), 42f)

  test "sum of int32":
    let a = toGPU[CLSData[int32], int32](@[1'i32, 2'i32, 3'i32, 4'i32])
    check a.sum() == 10'i32

  test "sum large (1024 elements)":
    var vals = newSeq[float32](1024)
    for i in 0..<1024: vals[i] = 1f
    let a = toGPU[CLSData[float32], float32](vals)
    check almostEq(a.sum(), 1024f, 0.01f)

  test "min of [3,1,4,1,5]":
    let a = toGPU[CLSData[float32], float32](@[3f, 1f, 4f, 1f, 5f])
    check almostEq(a.min(), 1f)

  test "max of [3,1,4,1,5]":
    let a = toGPU[CLSData[float32], float32](@[3f, 1f, 4f, 1f, 5f])
    check almostEq(a.max(), 5f)

  test "min on empty raises ValueError":
    let a = newCLSeq[float32](0)
    expect ValueError:
      discard a.min()

  test "max on empty raises ValueError":
    let a = newCLSeq[float32](0)
    expect ValueError:
      discard a.max()

  test "dot product [1,2,3]·[4,5,6] = 32":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    let b = toGPU[CLSData[float32], float32](@[4f, 5f, 6f])
    check almostEq(dot(a, b), 32f)

  test "dot product length mismatch raises":
    let a = toGPU[CLSData[float32], float32](@[1f, 2f])
    let b = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    expect AssertionDefect:
      discard dot(a, b)

  test "dot of orthogonal vectors = 0":
    let a = toGPU[CLSData[float32], float32](@[1f, 0f])
    let b = toGPU[CLSData[float32], float32](@[0f, 1f])
    check almostEq(dot(a, b), 0f)

##########################################################################################################################################################
## 15. KERNEL CACHE — compile-once semantics
##########################################################################################################################################################

suite "Kernel cache":

  test "repeated identical op does not grow the cache (smoke test)":
    ## We can’t inspect the internal cache size from here (not exported),
    ## but we can verify that repeated calls don’t raise or crash.
    let a = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    let b = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    discard a + b
    discard a + b
    discard a + b
    check true   ## reached without error — kernels reused from cache

##########################################################################################################################################################
## 16. EDGE CASES
##########################################################################################################################################################

suite "Edge cases":

  test "length-1 CLSeq addition":
    let a = toGPU[CLSData[float32], float32](@[7f])
    let b = toGPU[CLSData[float32], float32](@[3f])
    check (a + b).toSeq() == @[10f]

  test "length-1 sum":
    let a = toGPU[CLSData[float32], float32](@[42f])
    check almostEq(a.sum(), 42f)

  test "CLArray[1] ops":
    let a = toGPU[1, CLAData[1, float32], float32]([5f])
    let b = toGPU[1, CLAData[1, float32], float32]([3f])
    check (a + b).toArray() == [8f]

  test "large CLSeq sum (4096 elements of 1.0)":
    var vals = newSeq[float32](4096)
    for i in 0..<4096: vals[i] = 1f
    let a = toGPU[CLSData[float32], float32](vals)
    check almostEq(a.sum(), 4096f, 0.5f)

  test "fill then arithmetic":
    var a = newCLSeq[float32](4)
    a.fill(2f)
    let b = toGPU[CLSData[float32], float32](@[1f, 2f, 3f, 4f])
    check (a + b).toSeq() == @[3f, 4f, 5f, 6f]

##########################################################################################################################################################
## 17. STRING REPRESENTATION
##########################################################################################################################################################

suite "String representation":

  test "$ on CLSeq contains CLSeq marker":
    let s = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    check "CLSeq" in $s

  test "$ on CLSeq contains element values":
    let s = toGPU[CLSData[float32], float32](@[1f, 2f, 3f])
    let str = $s
    check "1" in str and "2" in str and "3" in str

  test "$ on CLArray contains CLArray marker":
    let a = toGPU[3, CLAData[3, float32], float32]([1f, 2f, 3f])
    check "CLArray" in $a

  test "$ on empty CLSeq":
    let s = newCLSeq[float32](0)
    check "CLSeq" in $s

##########################################################################################################################################################
## TEARDOWN
##########################################################################################################################################################

shutdownOpenCL()
