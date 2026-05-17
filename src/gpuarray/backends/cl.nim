##########################################################################################################################################################
################################################################ OPENCL BACKEND ##########################################################################
##########################################################################################################################################################
##
## OpenCL backend for GPUArrays.
##
## Mirrors the CPU backend API exactly — any code written against CPUSeq / CPUArray
## can be swapped to CLSeq / CLArray by changing the type alias, with no other changes.
##
## Lifecycle:
##   1. Call `initOpenCL()` once at startup to pick a platform + device and
##      create a shared context and command queue.
##   2. Use `newCLSeq`, `newCLArray`, `toGPU` to allocate device buffers.
##   3. Use `toSeq` / `toArray` to read results back to the CPU (blocking).
##   4. Call `shutdownOpenCL()` at exit to release the context and queue.
##
## Threading:
##   The global CLContext is shared across the process.  All enqueue calls are
##   serialised through a single in-order command queue, which is safe from any
##   thread as long as calls are externally synchronised.  For multi-queue usage,
##   instantiate a second CLContext manually.
##
## Operator kernels:
##   Arithmetic and trig operators compile a tiny OpenCL C kernel on first use
##   and cache it for the lifetime of the process (compileTime table keyed on the
##   operation + element type string).  Recompilation never happens at runtime.
##
## Buffer reuse:
##   Every allocating operator (`+`, `-`, `*`, `/`, `sin`, …) has a matching
##   non-allocating "into" variant that writes into a caller-supplied buffer:
##
##     add(a, b, dst)      # binary   — no allocation if dst.data.cap >= a.length
##     addScalar(a, s, dst)# scalar   — same
##     sinInto(a, dst)     # unary    — same
##
##   Compound-assignment operators (`+=`, `-=`, …) also write in-place without
##   allocating a new cl_mem buffer.
##
##   NOTE on aliasing: the in-place compound operators (e.g. `a += a`) share
##   the same cl_mem for read and write.  OpenCL 1.2 does not formally guarantee
##   safety when the same buffer appears as both input and output in a kernel.
##   For the common case (a += b where a ≠ b) this is always safe.  If you need
##   to support `a += a`, clone `a` first.

import math, strutils, tables, dynlib
import ../gpuarrays
import ../../../externalLib/nimopencl/src/opencl ## raw OpenCL 1.2 bindings

##########################################################################################################################################################
## CONTEXT
##########################################################################################################################################################

when defined(windows):
  const clDll = "OpenCL.dll"
elif defined(linux):
  const clDll = "libOpenCL.so.1"
elif defined(macosx):
  const clDll = "libOpenCL.dylib" # deprecated mais existe encore

type
  CLContext* = object
    ## Owns the OpenCL platform, device, context, and command queue.
    ## One instance is typically enough for the whole application.
    platform*: Pplatform_id
    device*: Pdevice_id
    ctx*: Pcontext
    queue*: Pcommand_queue

var gCL* {.threadvar.}: CLContext ## Process-wide default context.

proc isOpenCLAvailable*(): bool =
  let lib = loadLib(clDll)
  if lib == nil: return false
  freeLib(lib)
  return true

proc initOpenCL*(deviceType: TDeviceType = DEVICE_TYPE_GPU) =
  ## Initialise the default OpenCL context.
  ##
  ## Picks the first available platform and the first device of `deviceType`.
  ## Falls back to `DEVICE_TYPE_CPU` automatically if no GPU is found.
  ##
  ## Call once before any CLSeq / CLArray operation.
  var numPlatforms: uint32
  check getPlatformIDs(0, nil, addr numPlatforms)
  if numPlatforms == 0:
    raise newException(IOError, "OpenCL: no platforms found")

  check getPlatformIDs(1, addr gCL.platform, nil)

  var err: TClResult
  # Try requested device type, fall back to CPU
  err = getDeviceIDs(gCL.platform, deviceType, 1, addr gCL.device, nil)
  if err == DEVICE_NOT_FOUND:
    err = getDeviceIDs(gCL.platform, DEVICE_TYPE_CPU, 1, addr gCL.device, nil)
  check err

  gCL.ctx = createContext(nil, 1, addr gCL.device, nil, nil, addr err)
  check err
  gCL.queue = createCommandQueue(gCL.ctx, gCL.device, 0, addr err)
  check err

proc shutdownOpenCL*() =
  ## Release the default OpenCL context and command queue.
  ## Call at application exit.
  if gCL.queue != nil: check releaseCommandQueue(gCL.queue)
  if gCL.ctx != nil: check releaseContext(gCL.ctx)
  gCL = CLContext()

##########################################################################################################################################################
## BUFFER DATA TYPES
##########################################################################################################################################################

type
  CLSData*[T] = ref object
    ## Device-side backing store for a CLSeq.
    ## `mem` is a cl_mem buffer of `cap` elements of type T.
    mem*: Pmem
    cap*: int ## allocated element count (NOT byte count)

  CLAData*[N: static int, T] = ref object
    ## Device-side backing store for a CLArray of fixed size N.
    mem*: Pmem

  CLSeq*[T] = GPUSeq[CLSData[T], T]
  CLArray*[N: static int, T] = GPUArray[N, CLAData[N, T], T]

##########################################################################################################################################################
## MEMORY MANAGEMENT — releaseData / ensureLen / clone
##########################################################################################################################################################

template clWaitForCPU*() = check finish(gCL.queue)

proc releaseData*[T](d: CLSData[T]) =
  ## Free the device buffer.  Called automatically by `=destroy` when the
  ## last owner of a CLSeq is destroyed.
  if d != nil and d.mem != nil:
    check releaseMemObject(d.mem)
    d.mem = nil

proc releaseData*[N: static int, T](d: CLAData[N, T]) =
  ## Free the device buffer for a CLArray.
  if d != nil and d.mem != nil:
    check releaseMemObject(d.mem)
    d.mem = nil

proc ensureLen*[T](c: var CLSeq[T]) =
  ## Grow the device buffer so it can hold at least `c.length` elements.
  ## If the buffer is already large enough, this is a no-op.
  ## Data already on the device is preserved via an async copy.
  if c.data == nil:
    var err: TClResult
    let bytes = c.length * sizeof(T)
    c.data = CLSData[T](
      mem: createBuffer(gCL.ctx, MEM_READ_WRITE, bytes, nil, addr err),
      cap: c.length)
    check err
    return

  if c.length <= c.data.cap: return ## already fits

  let newCap = max(c.length, c.data.cap * 2)
  let newBytes = newCap * sizeof(T)
  var err: TClResult

  let newMem = createBuffer(gCL.ctx, MEM_READ_WRITE, newBytes, nil, addr err)
  check err

  # Copy existing content from old buffer to new buffer on the device
  if c.data.cap > 0 and c.data.mem != nil:
    check enqueueCopyBuffer(gCL.queue,
      c.data.mem, newMem,
      0, 0, c.data.cap * sizeof(T),
      0, nil, nil)

  releaseData(c.data)
  c.data = CLSData[T](mem: newMem, cap: newCap)

proc clone*[T](src: CLSeq[T]): CLSeq[T] =
  ## Deep copy: allocate a new device buffer and copy all elements into it.
  ## The result has an independent reference count (refcount = 1).
  result.length = src.length
  result.capacity = src.capacity
  result.startIdx = src.startIdx
  result.count = newRefCount()

  if src.data == nil or src.length == 0: return

  var err: TClResult
  let bytes = src.length * sizeof(T)
  result.data = CLSData[T](
    mem: createBuffer(gCL.ctx, MEM_READ_WRITE, bytes, nil, addr err),
    cap: src.length)
  check err
  check enqueueCopyBuffer(gCL.queue,
    src.data.mem, result.data.mem,
    src.startIdx * sizeof(T), 0, bytes,
    0, nil, nil)
  check finish(gCL.queue)

proc clone*[N: static int, T](src: CLArray[N, T]): CLArray[N, T] =
  ## Deep copy of a CLArray.
  result.startIdx = src.startIdx
  result.count = newRefCount()
  if src.data == nil: return
  var err: TClResult
  let bytes = N * sizeof(T)
  result.data = CLAData[N, T](
    mem: createBuffer(gCL.ctx, MEM_READ_WRITE, bytes, nil, addr err))
  check err
  check enqueueCopyBuffer(gCL.queue,
    src.data.mem, result.data.mem,
    0, 0, bytes, 0, nil, nil)
  check finish(gCL.queue)

##########################################################################################################################################################
## CONSTRUCTION
##########################################################################################################################################################

proc newCLSeqOfCap*[T](cap: int): CLSeq[T] =
  ## Allocate a CLSeq with room for `cap` elements but length 0.
  var err: TClResult
  let bytes = max(cap, 1) * sizeof(T)
  result.data = CLSData[T](
    mem: createBuffer(gCL.ctx, MEM_READ_WRITE, bytes, nil, addr err),
    cap: cap)
  check err
  result.capacity = cap
  result.length = 0
  result.count = newRefCount()

proc newCLSeq*[T](n: int = 0): CLSeq[T] =
  ## Allocate a CLSeq of length `n`, zero-initialised on the device.
  var err: TClResult
  let cap = max(n, 1)
  let bytes = cap * sizeof(T)
  result.data = CLSData[T](
    mem: createBuffer(gCL.ctx, MEM_READ_WRITE or MEM_ALLOC_HOST_PTR,
                      bytes, nil, addr err),
    cap: cap)
  check err
  result.capacity = cap
  result.length = n
  result.count = newRefCount()

proc newCLArray*[N: static int, T](): CLArray[N, T] =
  ## Allocate a CLArray of static size N, zero-initialised on the device.
  var err: TClResult
  result.data = CLAData[N, T](
    mem: createBuffer(gCL.ctx, MEM_READ_WRITE or MEM_ALLOC_HOST_PTR,
                      N * sizeof(T), nil, addr err))
  check err
  result.count = newRefCount()

##########################################################################################################################################################
## copyTo — CPU → device transfer
##########################################################################################################################################################

proc copyTo*[T](dest: var CLSeq[T], src: openArray[T], dStart: int) =
  ## Write `src` into the device buffer starting at logical index `dStart`.
  ## Blocks until the transfer is complete.
  if src.len == 0: return
  dest.ensureLen()
  let byteOffset = (dest.startIdx + dStart) * sizeof(T)
  let byteSize = src.len * sizeof(T)
  check enqueueWriteBuffer(gCL.queue, dest.data.mem,
    CL_TRUE, ## blocking write
    byteOffset, byteSize,
    unsafeAddr src[0],
    0, nil, nil)

proc copyTo*[N: static int, T](dest: var CLArray[N, T], src: openArray[T], dStart: int) =
  ## Write `src` into a CLArray device buffer starting at `dStart`.
  assert dStart + src.len <= N, "CLArray copyTo: out of bounds"
  if src.len == 0: return
  let byteOffset = (dest.startIdx + dStart) * sizeof(T)
  check enqueueWriteBuffer(gCL.queue, dest.data.mem,
    CL_TRUE,
    byteOffset, src.len * sizeof(T),
    unsafeAddr src[0],
    0, nil, nil)

##########################################################################################################################################################
## toSeq / toArray — device → CPU transfer
##########################################################################################################################################################

proc toSeq*[T](c: CLSeq[T]): seq[T] =
  ## Read the logical slice [startIdx, startIdx+length) back to the CPU.
  ## Blocks until the transfer is complete.
  result = newSeq[T](c.length)
  if c.length == 0 or c.data == nil: return
  check enqueueReadBuffer(gCL.queue, c.data.mem,
    CL_TRUE,
    c.startIdx * sizeof(T), c.length * sizeof(T),
    addr result[0],
    0, nil, nil)

proc toArray*[N: static int, T](c: CLArray[N, T]): array[N, T] =
  ## Read the full CLArray back to the CPU.  Blocks until complete.
  if c.data == nil: return
  check enqueueReadBuffer(gCL.queue, c.data.mem,
    CL_TRUE,
    0, N * sizeof(T),
    addr result[0],
    0, nil, nil)

##########################################################################################################################################################
## toGPU — CPU → device convenience constructors
##########################################################################################################################################################

proc toGPU*[B: CLSData, T](arr: openArray[T]): CLSeq[T] =
  ## Upload a CPU seq / array to a new CLSeq on the device.
  result = newCLSeq[T](arr.len)
  result.copyTo(arr, 0)

proc toGPU*[N: static int, B: CLAData, T](arr: array[N, T]): CLArray[N, T] =
  ## Upload a fixed-size CPU array to a new CLArray on the device.
  result = newCLArray[N, T]()
  result.copyTo(arr, 0)

##########################################################################################################################################################
## toOpenArray — logical slice (view, no copy)
##########################################################################################################################################################

proc toOpenArray*[T](c: CLSeq[T], start, stop: int): CLSeq[T] =
  ## Return a logical view into `c` covering indices [start, stop).
  ## No device memory is allocated or copied — both objects share the same cl_mem.
  result.data = c.data
  result.count = c.count
  result.startIdx = c.startIdx + start
  result.length = stop - start
  result.capacity = c.capacity
  if c.count != nil: discard c.count.acquire()

##########################################################################################################################################################
## KERNEL CACHE — compile-once, reuse forever
##########################################################################################################################################################

type KernelEntry = object
  program: Pprogram
  kernel: Pkernel

var kernelCache {.global.} = initTable[string, KernelEntry]()

proc getKernel(src, name: string): Pkernel =
  ## Return a cached kernel, compiling it on first call.
  if name in kernelCache: return kernelCache[name].kernel

  var err: TClResult
  var srcPtr: cstring = src.cstring
  var srcLen: int = src.len

  let prog = createProgramWithSource(gCL.ctx, 1,
               cast[cstringArray](addr srcPtr),
               addr srcLen, addr err)
  check err
  let buildErr = buildProgram(prog, 1, addr gCL.device, nil, nil, nil)
  if buildErr != TClResult.SUCCESS:
    var logLen: int
    discard getProgramBuildInfo(prog, gCL.device, PROGRAM_BUILD_LOG,
                                0, nil, addr logLen)
    var log = newString(logLen)
    discard getProgramBuildInfo(prog, gCL.device, PROGRAM_BUILD_LOG,
                                logLen, addr log[0], nil)
    raise newException(IOError, "OpenCL build error:\n" & log)

  let k = createKernel(prog, name.cstring, addr err)
  check err
  kernelCache[name] = KernelEntry(program: prog, kernel: k)
  return k

##########################################################################################################################################################
## KERNEL SOURCE GENERATION
##########################################################################################################################################################

proc clTypeName(T: typedesc): string {.compileTime.} =
  ## Map a Nim type to its OpenCL C scalar type name.
  when T is float32: "float"
  elif T is float64: "double"
  elif T is int32: "int"
  elif T is int64: "long"
  elif T is uint32: "uint"
  elif T is uint64: "ulong"
  elif T is int16: "short"
  elif T is uint16: "ushort"
  elif T is int8: "char"
  elif T is uint8: "uchar"
  else: "float" ## safe fallback

proc binOpKernelSrc(clTy, opSym, kernName: string): string =
  ## Generate an element-wise binary kernel: out[i] = a[i] OP b[i]
  """
__kernel void $1(
    __global const $2* a,
    __global const $2* b,
    __global       $2* out,
    const int aOff, const int bOff, const int outOff, const int n)
{
    int i = get_global_id(0);
    if (i < n) out[outOff + i] = a[aOff + i] $3 b[bOff + i];
}""".replace("$1", kernName).replace("$2", clTy).replace("$3", opSym)

proc scalarOpKernelSrc(clTy, opSym, kernName: string): string =
  ## Generate an element-wise scalar kernel: out[i] = a[i] OP scalar
  """
__kernel void $1(
    __global const $2* a,
    const          $2  scalar,
    __global       $2* out,
    const int aOff, const int outOff, const int n)
{
    int i = get_global_id(0);
    if (i < n) out[outOff + i] = a[aOff + i] $3 scalar;
}""".replace("$1", kernName).replace("$2", clTy).replace("$3", opSym)

proc unaryOpKernelSrc(clTy, fn, kernName: string): string =
  ## Generate an element-wise unary kernel: out[i] = fn(a[i])
  """
__kernel void $1(
    __global const $2* a,
    __global       $2* out,
    const int aOff, const int outOff, const int n)
{
    int i = get_global_id(0);
    if (i < n) out[outOff + i] = $3(a[aOff + i]);
}""".replace("$1", kernName).replace("$2", clTy).replace("$3", fn)

##########################################################################################################################################################
## DISPATCH HELPERS — internal, with explicit destination buffer
##########################################################################################################################################################
##
## Every `dispatchXxxInto` proc writes into a caller-supplied `dst` buffer.
## `dst.length` is updated to match the source length and `dst.ensureLen()`
## is called to grow the underlying cl_mem if necessary — but no new buffer
## is allocated when the existing capacity is already sufficient.
##
## The allocating `dispatchXxx` wrappers simply construct a fresh CLSeq and
## delegate to their `Into` counterpart, keeping the hot-path code in one place.

proc dispatchBinOpInto[T](a, b: CLSeq[T], op, kernName: string, dst: var CLSeq[T]) =
  ## Write element-wise `a OP b` into `dst`.  Reuses `dst`'s cl_mem buffer
  ## when its capacity is large enough; grows it (via ensureLen) otherwise.
  let clTy = clTypeName(T)
  let kn = kernName & "_" & clTy
  let src = binOpKernelSrc(clTy, op, kn)
  let k = getKernel(src, kn)

  dst.length = a.length
  dst.ensureLen()

  var aOff = a.startIdx.cint
  var bOff = b.startIdx.cint
  var dstOff = dst.startIdx.cint
  var n = a.length.cint

  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(Pmem), addr b.data.mem)
  check setKernelArg(k, 2, sizeof(Pmem), addr dst.data.mem)
  check setKernelArg(k, 3, sizeof(cint), addr aOff)
  check setKernelArg(k, 4, sizeof(cint), addr bOff)
  check setKernelArg(k, 5, sizeof(cint), addr dstOff)
  check setKernelArg(k, 6, sizeof(cint), addr n)

  var gs = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

proc dispatchBinOp[T](a, b: CLSeq[T], op, kernName: string): CLSeq[T] =
  ## Allocating wrapper: create a fresh CLSeq and delegate to dispatchBinOpInto.
  result = newCLSeq[T](a.length)
  dispatchBinOpInto(a, b, op, kernName, result)

proc dispatchScalarOpInto[T](a: CLSeq[T], scalar: T, op, kernName: string,
    dst: var CLSeq[T]) =
  ## Write element-wise `a OP scalar` into `dst`.  Reuses `dst`'s cl_mem buffer
  ## when its capacity is large enough; grows it (via ensureLen) otherwise.
  let clTy = clTypeName(T)
  let kn = kernName & "_" & clTy
  let src = scalarOpKernelSrc(clTy, op, kn)
  let k = getKernel(src, kn)

  dst.length = a.length
  dst.ensureLen()

  var aOff = a.startIdx.cint
  var dstOff = dst.startIdx.cint
  var n = a.length.cint
  var s = scalar

  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(T), addr s)
  check setKernelArg(k, 2, sizeof(Pmem), addr dst.data.mem)
  check setKernelArg(k, 3, sizeof(cint), addr aOff)
  check setKernelArg(k, 4, sizeof(cint), addr dstOff)
  check setKernelArg(k, 5, sizeof(cint), addr n)

  var gs = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

proc dispatchScalarOp[T](a: CLSeq[T], scalar: T, op, kernName: string): CLSeq[T] =
  ## Allocating wrapper: create a fresh CLSeq and delegate to dispatchScalarOpInto.
  result = newCLSeq[T](a.length)
  dispatchScalarOpInto(a, scalar, op, kernName, result)

proc dispatchUnaryOpInto[T](a: CLSeq[T], fn, kernName: string, dst: var CLSeq[T]) =
  ## Write element-wise `fn(a)` into `dst`.  Reuses `dst`'s cl_mem buffer
  ## when its capacity is large enough; grows it (via ensureLen) otherwise.
  let clTy = clTypeName(T)
  let kn = kernName & "_" & clTy
  let src = unaryOpKernelSrc(clTy, fn, kn)
  let k = getKernel(src, kn)

  dst.length = a.length
  dst.ensureLen()

  var aOff = a.startIdx.cint
  var dstOff = dst.startIdx.cint
  var n = a.length.cint

  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(Pmem), addr dst.data.mem)
  check setKernelArg(k, 2, sizeof(cint), addr aOff)
  check setKernelArg(k, 3, sizeof(cint), addr dstOff)
  check setKernelArg(k, 4, sizeof(cint), addr n)

  var gs = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

proc dispatchUnaryOp[T](a: CLSeq[T], fn, kernName: string): CLSeq[T] =
  ## Allocating wrapper: create a fresh CLSeq and delegate to dispatchUnaryOpInto.
  result = newCLSeq[T](a.length)
  dispatchUnaryOpInto(a, fn, kernName, result)

##########################################################################################################################################################
## CLArray DISPATCH HELPERS — native GPU kernels (no CPU round-trip)
##########################################################################################################################################################

proc dispatchBinOpArr*[N: static int, T](a, b: CLArray[N, T], op,
    kernName: string): CLArray[N, T] =
  ## Binary element-wise kernel for CLArray. Reuses the same cached kernel as CLSeq.
  let clTy = clTypeName(T)
  let kn = kernName & "_" & clTy
  let src = binOpKernelSrc(clTy, op, kn)
  let k = getKernel(src, kn)
  result = newCLArray[N, T]()
  var aOff = 0.cint
  var bOff = 0.cint
  var outOff = 0.cint
  var n = N.cint
  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(Pmem), addr b.data.mem)
  check setKernelArg(k, 2, sizeof(Pmem), addr result.data.mem)
  check setKernelArg(k, 3, sizeof(cint), addr aOff)
  check setKernelArg(k, 4, sizeof(cint), addr bOff)
  check setKernelArg(k, 5, sizeof(cint), addr outOff)
  check setKernelArg(k, 6, sizeof(cint), addr n)
  var gs = N
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

proc dispatchScalarOpArr*[N: static int, T](a: CLArray[N, T], scalar: T, op,
    kernName: string): CLArray[N, T] =
  ## Scalar broadcast kernel for CLArray.
  let clTy = clTypeName(T)
  let kn = kernName & "_" & clTy
  let src = scalarOpKernelSrc(clTy, op, kn)
  let k = getKernel(src, kn)
  result = newCLArray[N, T]()
  var aOff = 0.cint
  var outOff = 0.cint
  var n = N.cint
  var s = scalar
  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(T), addr s)
  check setKernelArg(k, 2, sizeof(Pmem), addr result.data.mem)
  check setKernelArg(k, 3, sizeof(cint), addr aOff)
  check setKernelArg(k, 4, sizeof(cint), addr outOff)
  check setKernelArg(k, 5, sizeof(cint), addr n)
  var gs = N
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

proc dispatchUnaryOpArr*[N: static int, T](a: CLArray[N, T], fn,
    kernName: string): CLArray[N, T] =
  ## Unary element-wise kernel for CLArray.
  let clTy = clTypeName(T)
  let kn = kernName & "_" & clTy
  let src = unaryOpKernelSrc(clTy, fn, kn)
  let k = getKernel(src, kn)
  result = newCLArray[N, T]()
  var aOff = 0.cint
  var outOff = 0.cint
  var n = N.cint
  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(Pmem), addr result.data.mem)
  check setKernelArg(k, 2, sizeof(cint), addr aOff)
  check setKernelArg(k, 3, sizeof(cint), addr outOff)
  check setKernelArg(k, 4, sizeof(cint), addr n)
  var gs = N
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

##########################################################################################################################################################
## FILL — constant initialisation
##########################################################################################################################################################

proc fillKernelSrc(clTy, kernName: string): string =
  """
__kernel void $1(
    __global $2* out,
    const    $2  val,
    const int outOff, const int n)
{
    int i = get_global_id(0);
    if (i < n) out[outOff + i] = val;
}""".replace("$1", kernName).replace("$2", clTy)

proc fill*[T](a: var CLSeq[T], val: T) =
  ## Fill every logical element of `a` with `val` on the GPU.
  if a.length == 0 or a.data == nil: return
  let clTy = clTypeName(T)
  let kn = "fill_" & clTy
  let k = getKernel(fillKernelSrc(clTy, kn), kn)
  var outOff = a.startIdx.cint
  var n = a.length.cint
  var v = val
  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(T), addr v)
  check setKernelArg(k, 2, sizeof(cint), addr outOff)
  check setKernelArg(k, 3, sizeof(cint), addr n)
  var gs = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

proc fill*[N: static int, T](a: var CLArray[N, T], val: T) =
  ## Fill every element of `a` with `val` on the GPU.
  if a.data == nil: return
  let clTy = clTypeName(T)
  let kn = "fill_" & clTy
  let k = getKernel(fillKernelSrc(clTy, kn), kn)
  var outOff = 0.cint
  var n = N.cint
  var v = val
  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(T), addr v)
  check setKernelArg(k, 2, sizeof(cint), addr outOff)
  check setKernelArg(k, 3, sizeof(cint), addr n)
  var gs = N
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

##########################################################################################################################################################
## REDUCTION KERNELS — sum / min / max / dot
##########################################################################################################################################################

proc reduceKernelSrcSum(clTy, kernName: string): string =
  """
__kernel void $1(
    __global const $2* a,
    __global       $2* out,
    __local        $2* scratch,
    const int aOff, const int n)
{
    int gid = get_global_id(0);
    int lid = get_local_id(0);
    int lsz = get_local_size(0);
    scratch[lid] = (gid < n) ? a[aOff + gid] : ($2)0;
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int s = lsz >> 1; s > 0; s >>= 1) {
        if (lid < s) scratch[lid] += scratch[lid + s];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (lid == 0) out[get_group_id(0)] = scratch[0];
}""".replace("$1", kernName).replace("$2", clTy)

proc reduceKernelSrcMin(clTy, kernName, bigVal: string): string =
  """
__kernel void $1(
    __global const $2* a,
    __global       $2* out,
    __local        $2* scratch,
    const int aOff, const int n)
{
    int gid = get_global_id(0);
    int lid = get_local_id(0);
    int lsz = get_local_size(0);
    scratch[lid] = (gid < n) ? a[aOff + gid] : ($3);
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int s = lsz >> 1; s > 0; s >>= 1) {
        if (lid < s) scratch[lid] = (scratch[lid] < scratch[lid+s]) ? scratch[lid] : scratch[lid+s];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (lid == 0) out[get_group_id(0)] = scratch[0];
}""".replace("$1", kernName).replace("$2", clTy).replace("$3", bigVal)

proc reduceKernelSrcMax(clTy, kernName, smallVal: string): string =
  """
__kernel void $1(
    __global const $2* a,
    __global       $2* out,
    __local        $2* scratch,
    const int aOff, const int n)
{
    int gid = get_global_id(0);
    int lid = get_local_id(0);
    int lsz = get_local_size(0);
    scratch[lid] = (gid < n) ? a[aOff + gid] : ($3);
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int s = lsz >> 1; s > 0; s >>= 1) {
        if (lid < s) scratch[lid] = (scratch[lid] > scratch[lid+s]) ? scratch[lid] : scratch[lid+s];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (lid == 0) out[get_group_id(0)] = scratch[0];
}""".replace("$1", kernName).replace("$2", clTy).replace("$3", smallVal)

proc runGroupReduce[T](a: CLSeq[T], kernSrc, kernName: string,
    localSize: int = 64): seq[T] =
  ## Execute one GPU reduction pass; return the per-group partial results to CPU.
  let numGroups = max(1, (a.length + localSize - 1) div localSize)
  var err: TClResult
  let partMem = createBuffer(gCL.ctx, MEM_READ_WRITE, numGroups * sizeof(T),
      nil, addr err)
  check err
  let k = getKernel(kernSrc, kernName)
  var aOff = a.startIdx.cint
  var n = a.length.cint
  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(Pmem), addr partMem)
  check setKernelArg(k, 2, localSize * sizeof(T), nil)
  check setKernelArg(k, 3, sizeof(cint), addr aOff)
  check setKernelArg(k, 4, sizeof(cint), addr n)
  var gs = numGroups * localSize
  var ls = localSize
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, addr ls, 0, nil, nil)
  result = newSeq[T](numGroups)
  check enqueueReadBuffer(gCL.queue, partMem, CL_TRUE, 0, numGroups * sizeof(T),
      addr result[0], 0, nil, nil)
  check releaseMemObject(partMem)

proc sum*[T: SomeNumber](a: CLSeq[T]): T =
  ## GPU parallel reduction: sum of all elements.
  if a.length == 0: return T(0)
  let clTy = clTypeName(T)
  let kn = "rsum_" & clTy
  let parts = runGroupReduce(a, reduceKernelSrcSum(clTy, kn), kn)
  result = T(0)
  for p in parts: result += p

proc min*[T: SomeNumber](a: CLSeq[T]): T =
  ## GPU parallel reduction: minimum element.
  if a.length == 0: raise newException(ValueError, "min on empty CLSeq")
  let clTy = clTypeName(T)
  let kn = "rmin_" & clTy
  when T is SomeFloat:
    let bigVal = "(" & clTy & ")1e38"
  else:
    let bigVal = "(" & clTy & ")2147483647"
  let parts = runGroupReduce(a, reduceKernelSrcMin(clTy, kn, bigVal), kn)
  result = parts[0]
  for i in 1..<parts.len:
    if parts[i] < result: result = parts[i]

proc max*[T: SomeNumber](a: CLSeq[T]): T =
  ## GPU parallel reduction: maximum element.
  if a.length == 0: raise newException(ValueError, "max on empty CLSeq")
  let clTy = clTypeName(T)
  let kn = "rmax_" & clTy
  when T is SomeFloat:
    let smallVal = "-(" & clTy & ")1e38"
  else:
    let smallVal = "-(" & clTy & ")2147483648"
  let parts = runGroupReduce(a, reduceKernelSrcMax(clTy, kn, smallVal), kn)
  result = parts[0]
  for i in 1..<parts.len:
    if parts[i] > result: result = parts[i]

proc dot*[T: SomeNumber](a, b: CLSeq[T]): T =
  ## GPU dot product: sum(a[i] * b[i]).
  assert a.length == b.length, "dot: length mismatch"
  let prod = dispatchBinOp(a, b, "*", "mul")
  result = prod.sum()

##########################################################################################################################################################
## CLSeq OP CLSeq
##########################################################################################################################################################

proc `+`*[T](a, b: CLSeq[T]): CLSeq[T] =
  assert a.length == b.length, "CLSeq +: length mismatch"
  dispatchBinOp(a, b, "+", "add")

proc `-`*[T](a, b: CLSeq[T]): CLSeq[T] =
  assert a.length == b.length, "CLSeq -: length mismatch"
  dispatchBinOp(a, b, "-", "sub")

proc `*`*[T](a, b: CLSeq[T]): CLSeq[T] =
  assert a.length == b.length, "CLSeq *: length mismatch"
  dispatchBinOp(a, b, "*", "mul")

proc `/`*[T](a, b: CLSeq[T]): CLSeq[T] =
  assert a.length == b.length, "CLSeq /: length mismatch"
  dispatchBinOp(a, b, "/", "div_op")

##########################################################################################################################################################
## CLSeq OP scalar (SomeInteger / SomeFloat)
##########################################################################################################################################################

proc `+`*[T](a: CLSeq[T], n: SomeNumber): CLSeq[T] = dispatchScalarOp(a, T(n),
    "+", "adds")
proc `-`*[T](a: CLSeq[T], n: SomeNumber): CLSeq[T] = dispatchScalarOp(a, T(n),
    "-", "subs")
proc `*`*[T](a: CLSeq[T], n: SomeNumber): CLSeq[T] = dispatchScalarOp(a, T(n),
    "*", "muls")
proc `/`*[T](a: CLSeq[T], n: SomeNumber): CLSeq[T] = dispatchScalarOp(a, T(n),
    "/", "divs")

proc `+`*[T](n: SomeNumber, a: CLSeq[T]): CLSeq[T] = a + n
proc `*`*[T](n: SomeNumber, a: CLSeq[T]): CLSeq[T] = a * n

##########################################################################################################################################################
## TRIGONOMETRY — CLSeq
##########################################################################################################################################################

proc sin*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "sin", "sin")
proc cos*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "cos", "cos")
proc tan*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "tan", "tan")
proc arcsin*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "asin", "arcsin")
proc arccos*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "acos", "arccos")
proc arctan*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "atan", "arctan")
proc sqrt*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "sqrt", "sqrt")
proc exp*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "exp", "exp")
proc ln*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "log",
    "ln") ## OpenCL uses log() for ln
proc abs*[T](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "fabs", "abs")

##########################################################################################################################################################
## CLSeq — non-allocating "into" variants (binary)
##########################################################################################################################################################
##
## These procs write results into a caller-supplied `dst` buffer, avoiding any
## cl_mem allocation on the hot path.  Typical usage:
##
##   var buf = newCLSeq[float32](n)   # allocate once outside the loop
##   for step in 0..<iterations:
##     add(a, b, buf)                 # reuse `buf` every iteration — zero allocation
##     mulScalar(buf, 0.5, buf)       # chaining is safe as long as a != buf (see aliasing note)
##
## The buffer is grown automatically if `dst.data.cap < a.length`, but is never
## shrunk.  `dst.length` is always updated to reflect the new logical size.

proc add*[T](a, b: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise addition into `dst`.  No allocation when `dst` is large enough.
  assert a.length == b.length, "add: length mismatch"
  dispatchBinOpInto(a, b, "+", "add", dst)

proc sub*[T](a, b: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise subtraction into `dst`.  No allocation when `dst` is large enough.
  assert a.length == b.length, "sub: length mismatch"
  dispatchBinOpInto(a, b, "-", "sub", dst)

proc mul*[T](a, b: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise multiplication into `dst`.  No allocation when `dst` is large enough.
  assert a.length == b.length, "mul: length mismatch"
  dispatchBinOpInto(a, b, "*", "mul", dst)

proc divInto*[T](a, b: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise division into `dst`.  No allocation when `dst` is large enough.
  ## Named `divInto` to avoid shadowing Nim's built-in integer `div` operator.
  assert a.length == b.length, "divInto: length mismatch"
  dispatchBinOpInto(a, b, "/", "div_op", dst)

##########################################################################################################################################################
## CLSeq — non-allocating "into" variants (scalar broadcast)
##########################################################################################################################################################

proc addScalar*[T](a: CLSeq[T], scalar: T, dst: var CLSeq[T]) =
  ## Broadcast scalar addition into `dst`.  No allocation when `dst` is large enough.
  dispatchScalarOpInto(a, scalar, "+", "adds", dst)

proc subScalar*[T](a: CLSeq[T], scalar: T, dst: var CLSeq[T]) =
  ## Broadcast scalar subtraction into `dst`.  No allocation when `dst` is large enough.
  dispatchScalarOpInto(a, scalar, "-", "subs", dst)

proc mulScalar*[T](a: CLSeq[T], scalar: T, dst: var CLSeq[T]) =
  ## Broadcast scalar multiplication into `dst`.  No allocation when `dst` is large enough.
  dispatchScalarOpInto(a, scalar, "*", "muls", dst)

proc divScalar*[T](a: CLSeq[T], scalar: T, dst: var CLSeq[T]) =
  ## Broadcast scalar division into `dst`.  No allocation when `dst` is large enough.
  dispatchScalarOpInto(a, scalar, "/", "divs", dst)

##########################################################################################################################################################
## CLSeq — non-allocating "into" variants (unary / trig)
##########################################################################################################################################################

proc sinInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise sine into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "sin", "sin", dst)

proc cosInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise cosine into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "cos", "cos", dst)

proc tanInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise tangent into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "tan", "tan", dst)

proc arcsinInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise arc sine into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "asin", "arcsin", dst)

proc arccosInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise arc cosine into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "acos", "arccos", dst)

proc arctanInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise arc tangent into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "atan", "arctan", dst)

proc sqrtInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise square root into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "sqrt", "sqrt", dst)

proc expInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise e^x into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "exp", "exp", dst)

proc lnInto*[T: SomeFloat](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise natural logarithm into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "log", "ln", dst)

proc absInto*[T](a: CLSeq[T], dst: var CLSeq[T]) =
  ## Element-wise absolute value into `dst`.  No allocation when `dst` is large enough.
  dispatchUnaryOpInto(a, "fabs", "abs", dst)

##########################################################################################################################################################
## CLSeq — in-place compound assignment operators
##########################################################################################################################################################
##
## These operators mutate the left-hand side in place using the same cl_mem
## buffer for both input and output.  No new device allocation ever occurs.
##
## Aliasing warning: `a += a` (same buffer as both operands) is technically
## undefined in OpenCL 1.2 when the kernel reads and writes the same location.
## For the typical case (a += b, a != b) this is always safe.
## If self-aliasing is required, clone first: `a += a.clone()`.

proc `+=`*[T](a: var CLSeq[T], b: CLSeq[T]) =
  ## In-place element-wise addition: a[i] += b[i].
  assert a.length == b.length, "+= : length mismatch"
  dispatchBinOpInto(a, b, "+", "add", a)

proc `-=`*[T](a: var CLSeq[T], b: CLSeq[T]) =
  ## In-place element-wise subtraction: a[i] -= b[i].
  assert a.length == b.length, "-= : length mismatch"
  dispatchBinOpInto(a, b, "-", "sub", a)

proc `*=`*[T](a: var CLSeq[T], b: CLSeq[T]) =
  ## In-place element-wise multiplication: a[i] *= b[i].
  assert a.length == b.length, "*= : length mismatch"
  dispatchBinOpInto(a, b, "*", "mul", a)

proc `/=`*[T](a: var CLSeq[T], b: CLSeq[T]) =
  ## In-place element-wise division: a[i] /= b[i].
  assert a.length == b.length, "/= : length mismatch"
  dispatchBinOpInto(a, b, "/", "div_op", a)

proc `+=`*[T](a: var CLSeq[T], scalar: T) =
  ## In-place scalar addition: a[i] += scalar.
  dispatchScalarOpInto(a, scalar, "+", "adds", a)

proc `-=`*[T](a: var CLSeq[T], scalar: T) =
  ## In-place scalar subtraction: a[i] -= scalar.
  dispatchScalarOpInto(a, scalar, "-", "subs", a)

proc `*=`*[T](a: var CLSeq[T], scalar: T) =
  ## In-place scalar multiplication: a[i] *= scalar.
  dispatchScalarOpInto(a, scalar, "*", "muls", a)

proc `/=`*[T](a: var CLSeq[T], scalar: T) =
  ## In-place scalar division: a[i] /= scalar.
  dispatchScalarOpInto(a, scalar, "/", "divs", a)

##########################################################################################################################################################
## CLArray — arithmetic via native GPU kernels
##########################################################################################################################################################

proc `+`*[N: static int, T](a, b: CLArray[N, T]): CLArray[N, T] =
  dispatchBinOpArr(a, b, "+", "add")

proc `-`*[N: static int, T](a, b: CLArray[N, T]): CLArray[N, T] =
  dispatchBinOpArr(a, b, "-", "sub")

proc `*`*[N: static int, T](a, b: CLArray[N, T]): CLArray[N, T] =
  dispatchBinOpArr(a, b, "*", "mul")

proc `/`*[N: static int, T](a, b: CLArray[N, T]): CLArray[N, T] =
  dispatchBinOpArr(a, b, "/", "div_op")

proc `+`*[N: static int, T](a: CLArray[N, T], n: SomeNumber): CLArray[N, T] =
  dispatchScalarOpArr(a, T(n), "+", "adds")

proc `-`*[N: static int, T](a: CLArray[N, T], n: SomeNumber): CLArray[N, T] =
  dispatchScalarOpArr(a, T(n), "-", "subs")

proc `*`*[N: static int, T](a: CLArray[N, T], n: SomeNumber): CLArray[N, T] =
  dispatchScalarOpArr(a, T(n), "*", "muls")

proc `/`*[N: static int, T](a: CLArray[N, T], n: SomeNumber): CLArray[N, T] =
  dispatchScalarOpArr(a, T(n), "/", "divs")

proc `+`*[N: static int, T](n: SomeNumber, a: CLArray[N, T]): CLArray[N, T] = a + n
proc `*`*[N: static int, T](n: SomeNumber, a: CLArray[N, T]): CLArray[N, T] = a * n

##########################################################################################################################################################
## CLArray — TRIGONOMETRY via native GPU kernels
##########################################################################################################################################################

proc sin*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "sin", "sin")
proc cos*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "cos", "cos")
proc tan*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "tan", "tan")
proc arcsin*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "asin", "arcsin")
proc arccos*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "acos", "arccos")
proc arctan*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "atan", "arctan")
proc sqrt*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "sqrt", "sqrt")
proc exp*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "exp", "exp")
proc ln*[N: static int, T: SomeFloat](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "log", "ln")
proc abs*[N: static int, T](a: CLArray[N, T]): CLArray[N, T] =
  dispatchUnaryOpArr(a, "fabs", "abs")

##########################################################################################################################################################
## CLSeq — commutative missing variants (n - seq, n / seq)
##########################################################################################################################################################

proc `-`*[T](n: SomeNumber, a: CLSeq[T]): CLSeq[T] =
  ## Scalar minus seq: result[i] = n - a[i]
  let clTy = clTypeName(T)
  let kn = "rsubs_" & clTy
  let src = """
__kernel void $1(
    __global const $2* a,
    const          $2  scalar,
    __global       $2* out,
    const int aOff, const int outOff, const int n)
{
    int i = get_global_id(0);
    if (i < n) out[outOff + i] = scalar - a[aOff + i];
}""".replace("$1", kn).replace("$2", clTy)
  let k = getKernel(src, kn)
  result = newCLSeq[T](a.length)
  var aOff = a.startIdx.cint
  var outOff = 0.cint
  var cnt = a.length.cint
  var sv = T(n)
  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(T), addr sv)
  check setKernelArg(k, 2, sizeof(Pmem), addr result.data.mem)
  check setKernelArg(k, 3, sizeof(cint), addr aOff)
  check setKernelArg(k, 4, sizeof(cint), addr outOff)
  check setKernelArg(k, 5, sizeof(cint), addr cnt)
  var gs = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

proc `/`*[T](n: SomeNumber, a: CLSeq[T]): CLSeq[T] =
  ## Scalar divided by seq: result[i] = n / a[i]
  let clTy = clTypeName(T)
  let kn = "rdivs_" & clTy
  let src = """
__kernel void $1(
    __global const $2* a,
    const          $2  scalar,
    __global       $2* out,
    const int aOff, const int outOff, const int n)
{
    int i = get_global_id(0);
    if (i < n) out[outOff + i] = scalar / a[aOff + i];
}""".replace("$1", kn).replace("$2", clTy)
  let k = getKernel(src, kn)
  result = newCLSeq[T](a.length)
  var aOff = a.startIdx.cint
  var outOff = 0.cint
  var cnt = a.length.cint
  var sv = T(n)
  check setKernelArg(k, 0, sizeof(Pmem), addr a.data.mem)
  check setKernelArg(k, 1, sizeof(T), addr sv)
  check setKernelArg(k, 2, sizeof(Pmem), addr result.data.mem)
  check setKernelArg(k, 3, sizeof(cint), addr aOff)
  check setKernelArg(k, 4, sizeof(cint), addr outOff)
  check setKernelArg(k, 5, sizeof(cint), addr cnt)
  var gs = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

## Generate source for a many-operand kernel.
## `opSym`  — one of "+", "-", "*", "/"
## `opName` — used in the kernel name ("add", "sub", "mul", "div")
## `count`  — number of input buffers
## `clTy`   — OpenCL scalar type string ("float", "double", …)
proc manyOpKernelSrc(opSym, opName, clTy: string, count: int): string =
  let kernName = opName & "Many_" & $count & "_" & clTy

  # Parameter list: one __global const pointer per operand + offsets
  var params = ""
  for k in 0..<count:
    params &= "    __global const " & clTy & "* a" & $k & ",\n"
    params &= "    const int off" & $k & ",\n"
  params &= "    __global " & clTy & "* out,\n"
  params &= "    const int outOff,\n"
  params &= "    const int n"

  # Body: accumulate with the chosen operator
  var body = "a0[off0 + i]"
  for k in 1..<count:
    body &= " " & opSym & " a" & $k & "[off" & $k & " + i]"

  result = "__kernel void " & kernName & "(\n" & params & ")\n{\n"
  result &= "    int i = get_global_id(0);\n"
  result &= "    if (i < n) out[outOff + i] = " & body & ";\n"
  result &= "}\n"

## Core dispatcher — writes result into `dst`, reusing its cl_mem when possible.
proc dispatchManyOpInto[T](
    operands: openArray[CLSeq[T]],
    opSym, opName: string,
    dst: var CLSeq[T]) =

  assert operands.len >= 2, opName & "Many requires at least 2 operands"
  for i in 1..<operands.len:
    assert operands[i].length == operands[0].length,
      opName & "Many length mismatch at index " & $i

  let clTy = clTypeName(T)
  let count = operands.len
  let kernName = opName & "Many_" & $count & "_" & clTy
  let src = manyOpKernelSrc(opSym, opName, clTy, count)
  let k = getKernel(src, kernName)

  dst.length = operands[0].length
  dst.ensureLen()

  # Set kernel args: for each operand → (Pmem, offset cint)
  var argIdx: uint32 = 0
  for op in operands:
    var mem = op.data.mem
    var off = op.startIdx.cint
    check setKernelArg(k, argIdx, sizeof(Pmem), addr mem)
    check setKernelArg(k, argIdx + 1, sizeof(cint), addr off)
    argIdx += 2

  # Output buffer + offset + n
  var outOff = dst.startIdx.cint
  var n = operands[0].length.cint
  check setKernelArg(k, argIdx, sizeof(Pmem), addr dst.data.mem)
  check setKernelArg(k, argIdx + 1, sizeof(cint), addr outOff)
  check setKernelArg(k, argIdx + 2, sizeof(cint), addr n)

  var gs = operands[0].length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil, addr gs, nil, 0, nil, nil)

## Allocating wrappers — mirror the CPU API exactly.

proc addMany*[T](operands: varargs[CLSeq[T]]): CLSeq[T] =
  ## Element-wise sum of any number of CLSeq in a single GPU kernel.
  ## All operands must share the same logical length.
  result = newCLSeq[T](operands[0].length)
  dispatchManyOpInto(operands, "+", "add", result)

proc subMany*[T](operands: varargs[CLSeq[T]]): CLSeq[T] =
  ## Element-wise left-fold subtraction in a single GPU kernel.
  result = newCLSeq[T](operands[0].length)
  dispatchManyOpInto(operands, "-", "sub", result)

proc mulMany*[T](operands: varargs[CLSeq[T]]): CLSeq[T] =
  ## Element-wise product of any number of CLSeq in a single GPU kernel.
  result = newCLSeq[T](operands[0].length)
  dispatchManyOpInto(operands, "*", "mul", result)

proc divMany*[T](operands: varargs[CLSeq[T]]): CLSeq[T] =
  ## Element-wise left-fold division in a single GPU kernel.
  result = newCLSeq[T](operands[0].length)
  dispatchManyOpInto(operands, "/", "div", result)

## "Into" variants — zero allocation on the GPU hot path.

proc addManyInto*[T](operands: openArray[CLSeq[T]], dst: var CLSeq[T]) =
  ## addMany into a caller-supplied buffer — no cl_mem allocation.
  dispatchManyOpInto(operands, "+", "add", dst)

proc subManyInto*[T](operands: openArray[CLSeq[T]], dst: var CLSeq[T]) =
  ## subMany into a caller-supplied buffer — no cl_mem allocation.
  dispatchManyOpInto(operands, "-", "sub", dst)

proc mulManyInto*[T](operands: openArray[CLSeq[T]], dst: var CLSeq[T]) =
  ## mulMany into a caller-supplied buffer — no cl_mem allocation.
  dispatchManyOpInto(operands, "*", "mul", dst)

proc divManyInto*[T](operands: openArray[CLSeq[T]], dst: var CLSeq[T]) =
  ## divMany into a caller-supplied buffer — no cl_mem allocation.
  dispatchManyOpInto(operands, "/", "div", dst)


##########################################################################################################################################################
## $ — string representation (blocking read-back)
##########################################################################################################################################################

proc `$`*[T](c: CLSeq[T]): string =
  "CLSeq(" & $c.toSeq() & ")"

proc `$`*[N: static int, T](c: CLArray[N, T]): string =
  "CLArray(" & $c.toArray() & ")"
