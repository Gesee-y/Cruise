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

import math, strutils, tables
import ../gpuarrays
import ../../../externalLib/nimopencl/src/opencl   ## raw OpenCL 1.2 bindings (the wrapper you already have)

##########################################################################################################################################################
## CONTEXT
##########################################################################################################################################################

type
  CLContext* = object
    ## Owns the OpenCL platform, device, context, and command queue.
    ## One instance is typically enough for the whole application.
    platform*:  Pplatform_id
    device*:    Pdevice_id
    ctx*:       Pcontext
    queue*:     Pcommand_queue

var gCL* {.threadvar.}: CLContext  ## Process-wide default context.

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

  gCL.ctx   = createContext(nil, 1, addr gCL.device, nil, nil, addr err)
  check err
  gCL.queue = createCommandQueue(gCL.ctx, gCL.device, 0, addr err)
  check err

proc shutdownOpenCL*() =
  ## Release the default OpenCL context and command queue.
  ## Call at application exit.
  if gCL.queue != nil: check releaseCommandQueue(gCL.queue)
  if gCL.ctx   != nil: check releaseContext(gCL.ctx)
  gCL = CLContext()

##########################################################################################################################################################
## BUFFER DATA TYPES
##########################################################################################################################################################

type
  CLSData*[T] = ref object
    ## Device-side backing store for a CLSeq.
    ## `mem` is a cl_mem buffer of `cap` elements of type T.
    mem*: Pmem
    cap*: int   ## allocated element count (NOT byte count)

  CLAData*[N: static int, T] = ref object
    ## Device-side backing store for a CLArray of fixed size N.
    mem*: Pmem

  CLSeq*[T]               = GPUSeq[CLSData[T], T]
  CLArray*[N: static int, T] = GPUArray[N, CLAData[N, T], T]

##########################################################################################################################################################
## MEMORY MANAGEMENT — releaseData / ensureLen / clone
##########################################################################################################################################################

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

  if c.length <= c.data.cap: return   ## already fits

  let newCap  = max(c.length, c.data.cap * 2)
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
  result.length   = src.length
  result.capacity = src.capacity
  result.startIdx = src.startIdx
  result.count    = newRefCount()

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
  result.count    = newRefCount()
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
  result.length   = 0
  result.count    = newRefCount()

proc newCLSeq*[T](n: int = 0): CLSeq[T] =
  ## Allocate a CLSeq of length `n`, zero-initialised on the device.
  var err: TClResult
  let cap   = max(n, 1)
  let bytes = cap * sizeof(T)
  result.data = CLSData[T](
    mem: createBuffer(gCL.ctx, MEM_READ_WRITE or MEM_ALLOC_HOST_PTR,
                      bytes, nil, addr err),
    cap: cap)
  check err
  result.capacity = cap
  result.length   = n
  result.count    = newRefCount()

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
  let byteSize   = src.len * sizeof(T)
  check enqueueWriteBuffer(gCL.queue, dest.data.mem,
    CL_TRUE,                      ## blocking write
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

proc toGPU*[T](arr: openArray[T]): CLSeq[T] =
  ## Upload a CPU seq / array to a new CLSeq on the device.
  result = newCLSeq[T](arr.len)
  result.copyTo(arr, 0)

proc toGPU*[N: static int, T](arr: array[N, T]): CLArray[N, T] =
  ## Upload a fixed-size CPU array to a new CLArray on the device.
  result = newCLArray[N, T]()
  result.copyTo(arr, 0)

##########################################################################################################################################################
## toOpenArray — logical slice (view, no copy)
##########################################################################################################################################################

proc toOpenArray*[T](c: CLSeq[T], start, stop: int): CLSeq[T] =
  ## Return a logical view into `c` covering indices [start, stop).
  ## No device memory is allocated or copied — both objects share the same cl_mem.
  result.data     = c.data
  result.count    = c.count
  result.startIdx = c.startIdx + start
  result.length   = stop - start
  result.capacity = c.capacity
  if c.count != nil: discard c.count.acquire()

##########################################################################################################################################################
## KERNEL CACHE — compile-once, reuse forever
##########################################################################################################################################################

type KernelEntry = object
  program: Pprogram
  kernel:  Pkernel

var kernelCache {.global.} = initTable[string, KernelEntry]()

proc getKernel(src, name: string): Pkernel =
  ## Return a cached kernel, compiling it on first call.
  if name in kernelCache: return kernelCache[name].kernel

  var err:    TClResult
  var srcPtr: cstring = src.cstring
  var srcLen: int     = src.len

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
  when T is float32:  "float"
  elif T is float64:  "double"
  elif T is int32:    "int"
  elif T is int64:    "long"
  elif T is uint32:   "uint"
  elif T is uint64:   "ulong"
  elif T is int16:    "short"
  elif T is uint16:   "ushort"
  elif T is int8:     "char"
  elif T is uint8:    "uchar"
  else: "float"   ## safe fallback

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
## DISPATCH HELPERS
##########################################################################################################################################################

proc dispatchBinOp[T](a, b: CLSeq[T], op, kernName: string): CLSeq[T] =
  ## Compile (once) and dispatch a binary element-wise kernel.
  let clTy = clTypeName(T)
  let src   = binOpKernelSrc(clTy, op, kernName & "_" & clTy)
  let k     = getKernel(src, kernName & "_" & clTy)
  result    = newCLSeq[T](a.length)

  var aOff   = a.startIdx.cint
  var bOff   = b.startIdx.cint
  var outOff = 0.cint
  var n      = a.length.cint

  check setKernelArg(k, 0, sizeof(Pmem),  addr a.data.mem)
  check setKernelArg(k, 1, sizeof(Pmem),  addr b.data.mem)
  check setKernelArg(k, 2, sizeof(Pmem),  addr result.data.mem)
  check setKernelArg(k, 3, sizeof(cint),  addr aOff)
  check setKernelArg(k, 4, sizeof(cint),  addr bOff)
  check setKernelArg(k, 5, sizeof(cint),  addr outOff)
  check setKernelArg(k, 6, sizeof(cint),  addr n)

  var globalSize = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil,
    addr globalSize, nil, 0, nil, nil)
  check finish(gCL.queue)

proc dispatchScalarOp[T](a: CLSeq[T], scalar: T, op, kernName: string): CLSeq[T] =
  ## Compile (once) and dispatch a scalar broadcast kernel.
  let clTy = clTypeName(T)
  let src   = scalarOpKernelSrc(clTy, op, kernName & "_" & clTy)
  let k     = getKernel(src, kernName & "_" & clTy)
  result    = newCLSeq[T](a.length)

  var aOff   = a.startIdx.cint
  var outOff = 0.cint
  var n      = a.length.cint
  var s      = scalar

  check setKernelArg(k, 0, sizeof(Pmem),   addr a.data.mem)
  check setKernelArg(k, 1, sizeof(T),      addr s)
  check setKernelArg(k, 2, sizeof(Pmem),   addr result.data.mem)
  check setKernelArg(k, 3, sizeof(cint),   addr aOff)
  check setKernelArg(k, 4, sizeof(cint),   addr outOff)
  check setKernelArg(k, 5, sizeof(cint),   addr n)

  var globalSize = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil,
    addr globalSize, nil, 0, nil, nil)
  check finish(gCL.queue)

proc dispatchUnaryOp[T](a: CLSeq[T], fn, kernName: string): CLSeq[T] =
  ## Compile (once) and dispatch a unary element-wise kernel.
  let clTy = clTypeName(T)
  let src   = unaryOpKernelSrc(clTy, fn, kernName & "_" & clTy)
  let k     = getKernel(src, kernName & "_" & clTy)
  result    = newCLSeq[T](a.length)

  var aOff   = a.startIdx.cint
  var outOff = 0.cint
  var n      = a.length.cint

  check setKernelArg(k, 0, sizeof(Pmem),  addr a.data.mem)
  check setKernelArg(k, 1, sizeof(Pmem),  addr result.data.mem)
  check setKernelArg(k, 2, sizeof(cint),  addr aOff)
  check setKernelArg(k, 3, sizeof(cint),  addr outOff)
  check setKernelArg(k, 4, sizeof(cint),  addr n)

  var globalSize = a.length
  check enqueueNDRangeKernel(gCL.queue, k, 1, nil,
    addr globalSize, nil, 0, nil, nil)
  check finish(gCL.queue)

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

proc `+`*[T](a: CLSeq[T], n: SomeNumber): CLSeq[T] = dispatchScalarOp(a, T(n), "+", "adds")
proc `-`*[T](a: CLSeq[T], n: SomeNumber): CLSeq[T] = dispatchScalarOp(a, T(n), "-", "subs")
proc `*`*[T](a: CLSeq[T], n: SomeNumber): CLSeq[T] = dispatchScalarOp(a, T(n), "*", "muls")
proc `/`*[T](a: CLSeq[T], n: SomeNumber): CLSeq[T] = dispatchScalarOp(a, T(n), "/", "divs")

proc `+`*[T](n: SomeNumber, a: CLSeq[T]): CLSeq[T] = a + n
proc `*`*[T](n: SomeNumber, a: CLSeq[T]): CLSeq[T] = a * n

##########################################################################################################################################################
## TRIGONOMETRY — CLSeq
##########################################################################################################################################################

proc sin*[T: SomeFloat](a: CLSeq[T]): CLSeq[T]    = dispatchUnaryOp(a, "sin",    "sin")
proc cos*[T: SomeFloat](a: CLSeq[T]): CLSeq[T]    = dispatchUnaryOp(a, "cos",    "cos")
proc tan*[T: SomeFloat](a: CLSeq[T]): CLSeq[T]    = dispatchUnaryOp(a, "tan",    "tan")
proc arcsin*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "asin",   "arcsin")
proc arccos*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "acos",   "arccos")
proc arctan*[T: SomeFloat](a: CLSeq[T]): CLSeq[T] = dispatchUnaryOp(a, "atan",   "arctan")
proc sqrt*[T: SomeFloat](a: CLSeq[T]): CLSeq[T]   = dispatchUnaryOp(a, "sqrt",   "sqrt")
proc exp*[T: SomeFloat](a: CLSeq[T]): CLSeq[T]    = dispatchUnaryOp(a, "exp",    "exp")
proc ln*[T: SomeFloat](a: CLSeq[T]): CLSeq[T]     = dispatchUnaryOp(a, "log",    "ln")  ## OpenCL uses log() for ln
proc abs*[T](a: CLSeq[T]): CLSeq[T]               = dispatchUnaryOp(a, "fabs",   "abs")

##########################################################################################################################################################
## CLArray — arithmetic via toSeq round-trip (arrays are small by design)
##########################################################################################################################################################
##
## CLArrays are statically sized and typically small (e.g. transform matrices,
## parameter blocks).  Rather than generating specialised kernels for every N,
## we round-trip through the CPU for array×array ops.  This is acceptable
## because: (a) arrays are small, (b) GPUArray ops are rare in hot loops.
## If you need high-throughput array ops, use CLSeq instead.

proc `+`*[N: static int, T](a, b: CLArray[N, T]): CLArray[N, T] =
  let sa = a.toArray(); let sb = b.toArray()
  var r: array[N, T]
  for i in 0..<N: r[i] = sa[i] + sb[i]
  toGPU[N, T](r)

proc `-`*[N: static int, T](a, b: CLArray[N, T]): CLArray[N, T] =
  let sa = a.toArray(); let sb = b.toArray()
  var r: array[N, T]
  for i in 0..<N: r[i] = sa[i] - sb[i]
  toGPU[N, T](r)

proc `*`*[N: static int, T](a, b: CLArray[N, T]): CLArray[N, T] =
  let sa = a.toArray(); let sb = b.toArray()
  var r: array[N, T]
  for i in 0..<N: r[i] = sa[i] * sb[i]
  toGPU[N, T](r)

proc `/`*[N: static int, T](a, b: CLArray[N, T]): CLArray[N, T] =
  let sa = a.toArray(); let sb = b.toArray()
  var r: array[N, T]
  for i in 0..<N: r[i] = sa[i] / sb[i]
  toGPU[N, T](r)

proc `+`*[N: static int, T](a: CLArray[N, T], n: SomeNumber): CLArray[N, T] =
  let sa = a.toArray(); var r: array[N, T]
  for i in 0..<N: r[i] = sa[i] + T(n)
  toGPU[N, T](r)

proc `-`*[N: static int, T](a: CLArray[N, T], n: SomeNumber): CLArray[N, T] =
  let sa = a.toArray(); var r: array[N, T]
  for i in 0..<N: r[i] = sa[i] - T(n)
  toGPU[N, T](r)

proc `*`*[N: static int, T](a: CLArray[N, T], n: SomeNumber): CLArray[N, T] =
  let sa = a.toArray(); var r: array[N, T]
  for i in 0..<N: r[i] = sa[i] * T(n)
  toGPU[N, T](r)

proc `/`*[N: static int, T](a: CLArray[N, T], n: SomeNumber): CLArray[N, T] =
  let sa = a.toArray(); var r: array[N, T]
  for i in 0..<N: r[i] = sa[i] / T(n)
  toGPU[N, T](r)

##########################################################################################################################################################
## $ — string representation (blocking read-back)
##########################################################################################################################################################

proc `$`*[T](c: CLSeq[T]): string =
  "CLSeq(" & $c.toSeq() & ")"

proc `$`*[N: static int, T](c: CLArray[N, T]): string =
  "CLArray(" & $c.toArray() & ")"