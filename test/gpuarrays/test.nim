##########################################################################################################################################################
################################################################## CPU BACKEND TESTS #####################################################################
##########################################################################################################################################################
##
## Test suite for the CPU backend implementation of GPUArrays.
##
## Covers:
##   - CPUSeq construction, capacity, length
##   - CPUArray construction
##   - RefCount acquire / release / lifecycle
##   - copy semantics (shared ref)
##   - move semantics (ownership transfer)
##   - clone (deep copy, independent ref)
##   - toOpenArray (logical views / slices)
##   - copyTo (writing into a buffer)
##   - toSeq / toArray round-trips
##   - add / append
##   - indexing [] / []=
##   - $ (string representation)
##   - destroy / double-free safety
##   - scalar indexing guard (ScalarDisallowed / ScalarWarn / allowScalar)
##
## Run with:
##   nim c -r test_cpu_backend.nim

import unittest, math, atomics, strutils
import ../../src/gpuarray/gpuarrays          # core abstraction
import ../../src/gpuarray/backends/cpu       # CPU backend

##########################################################################################################################################################
## HELPERS
##########################################################################################################################################################

CURRENT_INDEXING = ScalarAllowed

## Build a CPUSeq[float32] pre-filled with [0.0, 1.0, 2.0, ... n-1]
proc makeFloatSeq(n: int): CPUSeq[float32] =
  result = newCPUSeq[float32](n)
  for i in 0..<n:
    result[i] = float32(i)

## Build a CPUSeq[int32] pre-filled with [0, 1, 2, ... n-1]
proc makeIntSeq(n: int): CPUSeq[int32] =
  result = newCPUSeq[int32](n)
  for i in 0..<n:
    result[i] = int32(i)

##########################################################################################################################################################
## 1. CONSTRUCTION
##########################################################################################################################################################

suite "CPUSeq — construction":

  test "newCPUSeq default creates empty sequence":
    let s = newCPUSeq[float32]()
    check s.length   == 0
    check s.capacity >= 0
    check s.count    != nil

  test "newCPUSeq with length allocates correct size":
    let s = newCPUSeq[int32](16)
    check s.length   == 16
    check s.capacity >= 16

  test "newCPUSeqOfCap reserves capacity without setting length":
    let s = newCPUSeqOfCap[float32](64)
    check s.length   == 0
    check s.capacity == 64

  test "newCPUArray creates array of static size":
    let a = newCPUArray[8, float32]()
    check a.count != nil
    # Static size is encoded at type level — no runtime length field needed

  test "refcount starts at 1 after construction":
    let s = newCPUSeq[float32](4)
    check s.count.count.load() == 1

##########################################################################################################################################################
## 2. COPY SEMANTICS (shared ownership)
##########################################################################################################################################################

suite "CPUSeq — copy semantics":

  test "copy shares the same data buffer":
    var a = newCPUSeq[int32](4)
    a[0] = 42.int32
    let b = a         # triggers =copy
    check b[0] == 42

  test "copy increments refcount":
    var a = newCPUSeq[float32](4)
    let b = a
    check a.count.count.load() == 2

  test "mutation through copy is visible in original":
    ## CPU backend shares the underlying ref object — this is expected
    ## (GPU semantics: both variables point to the same buffer)
    var a = newCPUSeq[int32](4)
    var b = a
    b[0] = 99.int32
    check a[0] == 99

  test "copy of CPUArray increments refcount":
    var a = newCPUArray[4, float32]()
    let b = a
    check a.count.count.load() == 2

##########################################################################################################################################################
## 3. MOVE SEMANTICS
##########################################################################################################################################################

suite "CPUSeq — move semantics":

  test "move sets source count to nil":
    var a = newCPUSeq[float32](4)
    let b = move(a)   # triggers =wasMoved
    check a.count == nil

  test "moved-into value owns the data":
    var a = newCPUSeq[int32](4)
    a[0] = 7'i32
    let b = move(a)
    check b[0] == 7

  test "refcount stays at 1 after move":
    var a = newCPUSeq[float32](8)
    let b = move(a)
    check b.count.count.load() == 1

##########################################################################################################################################################
## 4. CLONE (deep copy)
##########################################################################################################################################################

suite "CPUSeq — clone":

  test "clone produces independent copy":
    var a = makeFloatSeq(4)
    var b = a.clone()
    b[0] = 999.0'f32
    check a[0] == 0.0   # original unaffected

  test "clone has refcount of 1":
    let a = makeFloatSeq(4)
    let b = a.clone()
    check b.count.count.load() == 1
    check a.count.count.load() == 1   # original unchanged

  test "clone copies all elements":
    let a = makeFloatSeq(8)
    let b = a.clone()
    let sa = a.toSeq()
    let sb = b.toSeq()
    check sa == sb

  test "clone of CPUArray is independent":
    var a = newCPUArray[4, float32]()
    a[0] = 1.0'f32
    var b = a.clone()
    b[0] = 2.0'f32
    check a[0] == 1.0

##########################################################################################################################################################
## 5. REFCOUNT LIFECYCLE
##########################################################################################################################################################

suite "RefCount — lifecycle":

  test "acquire increments count":
    var r = newRefCount()
    discard r.acquire()
    check r.count.load() == 2

  test "release decrements count":
    var r = newRefCount()
    discard r.acquire()   # → 2
    discard r.release()   # → 1
    check r.count.load() == 1

  test "release to zero is allowed (memory freed)":
    var r = newRefCount()
    discard r.release()   # → 0
    check r.count.load() == 0

  test "acquire on freed memory raises RefCountError":
    var r = newRefCount()
    discard r.release()   # → 0
    expect RefCountError:
      discard r.acquire()

  test "release on freed memory raises RefCountError":
    var r = newRefCount()
    discard r.release()   # → 0
    expect RefCountError:
      discard r.release()

  test "ensureAlive raises on nil":
    var r: RefCount = nil
    expect RefCountError:
      discard r.ensureAlive()

  test "ensureAlive raises on count == 0":
    var r = newRefCount()
    discard r.release()
    expect RefCountError:
      discard r.ensureAlive()

##########################################################################################################################################################
## 6. DESTROY
##########################################################################################################################################################

suite "GPUSeq — destroy":

  test "destroy reduces refcount":
    var a = newCPUSeq[float32](4)
    var b = a             # refcount = 2
    `=destroy`(b)         # refcount → 1
    check a.count.count.load() == 1

  test "last destroy releases data":
    ## After the last owner is destroyed, count reaches 0 and releaseData is called.
    ## We verify that data is nil after release (CPU backend sets data = nil).
    var a = newCPUSeq[float32](4)
    `=destroy`(a)
    check a.count == nil or a.count.count.load() == 0

  test "destroy on nil count is a no-op":
    var a = newCPUSeq[float32](4)
    `=wasMoved`(a)        # count = nil
    # Should not raise
    `=destroy`(a)

##########################################################################################################################################################
## 7. copyTo
##########################################################################################################################################################

suite "CPUSeq — copyTo":

  test "copyTo writes values at correct offset":
    var s = newCPUSeq[int32](8)
    s.copyTo([10'i32, 20'i32, 30'i32], 2)
    check s[2] == 10
    check s[3] == 20
    check s[4] == 30

  test "copyTo at offset 0":
    var s = newCPUSeq[float32](4)
    s.copyTo([1.0'f32, 2.0'f32, 3.0'f32, 4.0'f32], 0)
    check s.toSeq() == @[1.0'f32, 2.0'f32, 3.0'f32, 4.0'f32]

  test "copyTo on CPUArray":
    var a = newCPUArray[4, int32]()
    a.copyTo([5'i32, 6'i32], 1)
    let arr = a.toArray()
    check arr[1] == 5
    check arr[2] == 6

##########################################################################################################################################################
## 8. toSeq / toArray ROUND-TRIPS
##########################################################################################################################################################

suite "Round-trips":

  test "toSeq returns correct elements":
    let s = makeFloatSeq(5)
    let r = s.toSeq()
    check r == @[0.0'f32, 1.0'f32, 2.0'f32, 3.0'f32, 4.0'f32]

  test "toArray returns correct elements":
    var a = newCPUArray[3, int32]()
    a.copyTo([7'i32, 8'i32, 9'i32], 0)
    let arr = a.toArray()
    check arr == [7'i32, 8'i32, 9'i32]

  test "toGPU round-trip preserves data":
    let src = @[10'i32, 20'i32, 30'i32, 40'i32]
    let g   = toGPU[CPUSData[int32], int32](src)
    check g.toSeq() == src

##########################################################################################################################################################
## 9. add / append
##########################################################################################################################################################

suite "CPUSeq — add / append":

  test "add increases length by 1":
    var s = newCPUSeq[int32]()
    s.add(42'i32)
    check s.length == 1

  test "add stores correct value":
    var s = newCPUSeq[float32]()
    s.add(3.14'f32)
    check abs(s[0] - 3.14'f32) < 1e-5

  test "multiple adds preserve order":
    var s = newCPUSeq[int32]()
    for i in 0..<5:
      s.add(int32(i * 10))
    check s.toSeq() == @[0'i32, 10'i32, 20'i32, 30'i32, 40'i32]

  test "append increases length by n":
    var s = newCPUSeq[int32]()
    s.append(@[1'i32, 2'i32, 3'i32])
    check s.length == 3

  test "append preserves order":
    var s = newCPUSeq[int32]()
    s.append(@[5'i32, 6'i32, 7'i32])
    check s.toSeq() == @[5'i32, 6'i32, 7'i32]

  test "append after add":
    var s = newCPUSeq[int32]()
    s.add(1'i32)
    s.append(@[2'i32, 3'i32])
    check s.toSeq() == @[1'i32, 2'i32, 3'i32]

  test "capacity grows automatically on overflow":
    var s = newCPUSeqOfCap[int32](2)
    s.add(1'i32); s.add(2'i32); s.add(3'i32)   # exceeds initial capacity
    check s.length   == 3
    check s.capacity >= 3

##########################################################################################################################################################
## 10. INDEXING
##########################################################################################################################################################

suite "CPUSeq — indexing":

  test "[] reads correct element":
    let s = makeIntSeq(8)
    check s[3] == 3
    check s[7] == 7

  test "[]= writes correct element":
    var s = newCPUSeq[int32](4)
    s[2] = 55'i32
    check s[2] == 55

  test "[] on CPUArray":
    var a = newCPUArray[4, float32]()
    a[1] = 7.5'f32
    check a[1] == 7.5'f32

##########################################################################################################################################################
## 11. toOpenArray (LOGICAL VIEWS / SLICES)
##########################################################################################################################################################

suite "CPUSeq — toOpenArray (slicing)":

  test "slice has correct length":
    let s = makeFloatSeq(10)
    let v = s.toOpenArray(2, 6)
    check v.length == 4   # [2, 6) → 4 elements

  test "slice starts at correct offset":
    let s = makeFloatSeq(10)
    let v = s.toOpenArray(3, 7)
    check v.startIdx == s.startIdx + 3

  test "slice reads correct elements":
    let s = makeFloatSeq(8)
    let v = s.toOpenArray(2, 5)
    check v.toSeq() == @[2.0'f32, 3.0'f32, 4.0'f32]

  test "slice of slice composes correctly":
    let s = makeFloatSeq(10)
    let v1 = s.toOpenArray(2, 8)   # [2.0 .. 7.0]
    let v2 = v1.toOpenArray(1, 4)  # [3.0 .. 5.0]
    check v2.toSeq() == @[3.0'f32, 4.0'f32, 5.0'f32]

##########################################################################################################################################################
## 12. SCALAR INDEXING GUARD
##########################################################################################################################################################

suite "Scalar indexing guard":

  CURRENT_INDEXING = ScalarAllowed
  test "ScalarDisallowed raises ScalarIndexingError on [] access":
    var s = makeFloatSeq(4)
    CURRENT_INDEXING = ScalarDisallowed
    expect ScalarIndexingError:
      discard s[0]

  CURRENT_INDEXING = ScalarAllowed
  test "ScalarWarn does not raise, but logs":
    var s = makeFloatSeq(4)
    CURRENT_INDEXING = ScalarWarn
    # Should complete without raising
    discard s[0]

  CURRENT_INDEXING = ScalarAllowed
  test "allowScalar permits indexing inside block":
    var s = makeFloatSeq(4)
    CURRENT_INDEXING = ScalarDisallowed
    allowScalar:
      check s[2] == 2.0'f32   # no exception

  CURRENT_INDEXING = ScalarAllowed
  test "allowScalar restores previous mode after block":
    CURRENT_INDEXING = ScalarDisallowed
    allowScalar:
      discard
    check CURRENT_INDEXING == ScalarDisallowed
  
  CURRENT_INDEXING = ScalarAllowed
  test "allowScalar restores mode even on exception":
    CURRENT_INDEXING = ScalarDisallowed
    try:
      allowScalar:
        raise newException(ValueError, "test error")
    except ValueError:
      discard
    check CURRENT_INDEXING == ScalarDisallowed

##########################################################################################################################################################
## 13. STRING REPRESENTATION
##########################################################################################################################################################
CURRENT_INDEXING = ScalarAllowed

suite "String representation":

  test "$ on CPUSeq contains element values":
    let s = makeIntSeq(3)
    let str = $s
    check "GPUSeq" in str
    check "0"      in str
    check "1"      in str
    check "2"      in str

  test "$ on empty CPUSeq":
    let s = newCPUSeq[float32]()
    check "GPUSeq" in $s

  test "$ on CPUArray contains element values":
    var a = newCPUArray[3, int32]()
    a.copyTo([1'i32, 2'i32, 3'i32], 0)
    let str = $a
    check "GPUArray" in str
    check "1" in str

##########################################################################################################################################################
## 14. ensureLen
##########################################################################################################################################################

suite "CPUSeq — ensureLen":

  test "ensureLen grows underlying buffer when length > data.len":
    var s = newCPUSeqOfCap[float32](4)
    s.length = 8
    s.ensureLen()
    check s.data.data.len >= 8

  test "ensureLen is a no-op when buffer is already large enough":
    var s = newCPUSeq[float32](16)
    let oldAddr = s.data.data[0].addr
    s.length = 4
    s.ensureLen()
    check s.data.data[0].addr == oldAddr   # no reallocation

##########################################################################################################################################################
## 15. ARITHMETIC OPERATORS (stubs — will fail until implemented)
##########################################################################################################################################################

suite "Arithmetic operators (CPU backend)":

  test "seq + seq element-wise":
    let a = makeFloatSeq(4)
    let b = makeFloatSeq(4)
    let c = a + b
    check c.toSeq() == @[0.0'f32, 2.0'f32, 4.0'f32, 6.0'f32]

  test "seq - seq element-wise":
    var a = makeFloatSeq(4)
    let b = makeFloatSeq(4)
    let c = a - b
    check c.toSeq() == @[0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32]

  test "seq * scalar":
    let a = makeFloatSeq(4)
    let c = a * 2.0'f32
    check c.toSeq() == @[0.0'f32, 2.0'f32, 4.0'f32, 6.0'f32]

  test "seq / scalar":
    let a = makeFloatSeq(4)
    let c = a / 2.0'f32
    check c.toSeq() == @[0.0'f32, 0.5'f32, 1.0'f32, 1.5'f32]

  test "seq + integer scalar":
    let a = makeIntSeq(3)
    let c = a + 10'i32
    check c.toSeq() == @[10'i32, 11'i32, 12'i32]

  test "array + array element-wise":
    var a = newCPUArray[3, float32]()
    var b = newCPUArray[3, float32]()
    a.copyTo([1.0'f32, 2.0'f32, 3.0'f32], 0)
    b.copyTo([4.0'f32, 5.0'f32, 6.0'f32], 0)
    let c = a + b
    check c.toArray() == [5.0'f32, 7.0'f32, 9.0'f32]

##########################################################################################################################################################
## 16. TRIG OPERATORS (stubs)
##########################################################################################################################################################

suite "Trig operators (CPU backend)":

  test "sin element-wise":
    let a = makeFloatSeq(4)
    let r = sin(a)
    let s = r.toSeq()
    for i in 0..<4:
      check abs(s[i] - sin(float32(i))) < 1e-5

  test "cos element-wise":
    let a = makeFloatSeq(4)
    let r = cos(a)
    let s = r.toSeq()
    for i in 0..<4:
      check abs(s[i] - cos(float32(i))) < 1e-5

  test "tan element-wise":
    let a = makeFloatSeq(3)
    let r = tan(a)
    let s = r.toSeq()
    for i in 0..<3:
      check abs(s[i] - tan(float32(i))) < 1e-4
