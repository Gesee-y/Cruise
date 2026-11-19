# ################################################################################################################################################################## #
# ##################################################################### OPENCL BACKEND ############################################################################# #
# ################################################################################################################################################################## #

import std/[strutils, tables]
import ../../../externalModule/nimopencl/src/opencl
import object_config
import ../bytecode

const
  MAX_BUFFERS* = 8
  DEFAULT_VM_FEATURES* = {bfCalls, bfMatrices, bfVectorMath, bfTranscendentals, bfMixing, bfReg256}

# Optimized OpenCL C kernel source code interpreting CVM bytecode
const OpenClVmKernelSource* = staticRead("opencl_vm.opencl")

type
  OpenClVariant* = object
    program*: Pprogram
    kernel*: Pkernel
    features*: set[BytecodeFeature]

  OpenClContext* = ref object
    platform*: Pplatform_id
    device*: Pdevice_id
    context*: Pcontext
    queue*: Pcommand_queue
    program*: Pprogram
    kernel*: Pkernel
    dummyBuffer*: Pmem
    deviceName*: string
    platformName*: string
    variants*: Table[uint16, OpenClVariant]

  OpenClVm* = object
    ctx*: OpenClContext
    uniform*: seq[uint32]
    buffers*: array[MAX_BUFFERS, Pmem]
    bufferSizes*: array[MAX_BUFFERS, int]
    bufferHostPtrs*: array[MAX_BUFFERS, pointer]
    progMem*: Pmem
    progLen*: int
    uniMem*: Pmem
    uniLen*: int
    activeKernel*: Pkernel

  # ###################################################################################################### #
 # ############################################# LOGGING & BUILD ######################################### #
# ###################################################################################################### #

proc getBuildLog(program: Pprogram, device: Pdevice_id): string =
  var logSize: int = 0
  discard getProgramBuildInfo(program, device, PROGRAM_BUILD_LOG, 0, nil, addr logSize)
  if logSize > 0:
    var logBuffer = newString(logSize)
    discard getProgramBuildInfo(program, device, PROGRAM_BUILD_LOG, logSize, addr logBuffer[0], nil)
    result = logBuffer
  else:
    result = "No build log available"

proc buildVariant*(ctx: OpenClContext, features: set[BytecodeFeature]): OpenClVariant =
  let regBytes = getRegisterWord(features) * 4
  var options = "-cl-mad-enable -cl-fast-relaxed-math"
  options.add " -DMAX_MEM=" & $regBytes
  options.add " -DENABLE_CALLS=" & (if bfCalls in features: "1" else: "0")
  options.add " -DENABLE_MATRICES=" & (if bfMatrices in features: "1" else: "0")
  options.add " -DENABLE_VECTORMATH=" & (if bfVectorMath in features: "1" else: "0")
  options.add " -DENABLE_TRANSCENDENTALS=" & (if bfTranscendentals in features: "1" else: "0")
  options.add " -DENABLE_MIXING=" & (if bfMixing in features: "1" else: "0")

  var src = cstring(OpenClVmKernelSource)
  var lines = [src]
  var status: TClResult
  result.program = createProgramWithSource(ctx.context, 1, cast[cstringArray](addr lines), nil, addr status)
  check status

  var devList = [ctx.device]
  let buildRes = buildProgram(result.program, 1, addr devList[0], options.cstring, nil, nil)
  assert buildRes == TClResult.Success,
    "Échec de compilation du kernel OpenCL VM spécialisé:\n" & getBuildLog(result.program, ctx.device)

  result.kernel = createKernel(result.program, "runVM", addr status)
  check status
  result.features = features

proc getOrCreateVariant*(ctx: OpenClContext, features: set[BytecodeFeature]): OpenClVariant =
  let key = features.featureMask
  if key notin ctx.variants:
    ctx.variants[key] = ctx.buildVariant(features)
  return ctx.variants[key]

  # ###################################################################################################### #
 # ############################################# CONTEXT SETUP ########################################## #
# ###################################################################################################### #

proc initOpenClContext*(preferredDeviceType: Tdevice_type = DEVICE_TYPE_GPU,
                        platformIndex: int = -1, vendorSubstr: string = ""): OpenClContext =
  new(result)
  var numPlatforms: uint32 = 0
  check getPlatformIDs(0, nil, addr numPlatforms)
  assert numPlatforms > 0, "Aucune plateforme OpenCL trouvée sur ce système"

  var platforms = newSeq[Pplatform_id](numPlatforms)
  check getPlatformIDs(numPlatforms, addr platforms[0], nil)

  var chosenPlatform: Pplatform_id = nil
  var chosenDevice: Pdevice_id = nil
  var chosenDevName = ""
  var chosenPlatName = ""

  for idx, plat in platforms:
    if platformIndex >= 0 and idx != platformIndex:
      continue

    var pNameBuf = newString(256)
    var pNameLen: int = 0
    discard getPlatformInfo(plat, PLATFORM_NAME, 256, addr pNameBuf[0], addr pNameLen)
    let platName = if pNameLen > 0: pNameBuf[0 ..< pNameLen - 1] else: "Unknown Platform"

    if vendorSubstr.len > 0 and vendorSubstr.toLowerAscii notin platName.toLowerAscii:
      continue

    var numDevs: uint32 = 0
    var res = getDeviceIDs(plat, preferredDeviceType, 0, nil, addr numDevs)
    if res != TClResult.Success or numDevs == 0:
      res = getDeviceIDs(plat, DEVICE_TYPE_ALL, 0, nil, addr numDevs)

    if res == TClResult.Success and numDevs > 0:
      var devs = newSeq[Pdevice_id](numDevs)
      check getDeviceIDs(plat, DEVICE_TYPE_ALL, numDevs, addr devs[0], nil)
      chosenPlatform = plat
      chosenDevice = devs[0]
      chosenPlatName = platName

      var dNameBuf = newString(256)
      var dNameLen: int = 0
      discard getDeviceInfo(chosenDevice, DEVICE_NAME, 256, addr dNameBuf[0], addr dNameLen)
      chosenDevName = if dNameLen > 0: dNameBuf[0 ..< dNameLen - 1] else: "Unknown Device"
      break

  assert chosenDevice != nil, "Aucun device OpenCL disponible pour les critères demandés"

  result.platform = chosenPlatform
  result.device = chosenDevice
  result.platformName = chosenPlatName
  result.deviceName = chosenDevName
  result.variants = initTable[uint16, OpenClVariant]()

  var status: TClResult
  var devList = [chosenDevice]
  result.context = createContext(nil, 1, addr devList[0], nil, nil, addr status)
  check status

  result.queue = createCommandQueue(result.context, chosenDevice, 0, addr status)
  check status

  result.dummyBuffer = createBuffer(result.context, MEM_READ_WRITE, 64, nil, addr status)
  check status

  result.program = nil
  result.kernel = nil

  # ###################################################################################################### #
 # ############################################# OPENCL VM API ########################################## #
# ###################################################################################################### #

proc initOpenClVm*(context: OpenClContext = nil, preferredDeviceType: Tdevice_type = DEVICE_TYPE_GPU,
                   platformIndex: int = -1, vendorSubstr: string = ""): OpenClVm =
  if context != nil:
    result.ctx = context
  else:
    result.ctx = initOpenClContext(preferredDeviceType, platformIndex, vendorSubstr)

  result.uniform = @[]
  for i in 0 ..< MAX_BUFFERS:
    result.buffers[i] = result.ctx.dummyBuffer
    result.bufferSizes[i] = 0
    result.bufferHostPtrs[i] = nil

  result.progMem = nil
  result.progLen = 0
  result.uniMem = nil
  result.uniLen = 0
  result.activeKernel = result.ctx.kernel

proc prepareVariant*(vm: var OpenClVm, program: openArray[uint32]) =
  ## Pre-compile and cache the specialized VM kernel for the given bytecode profile.
  if program.len > 0:
    let profile = analyzeBytecode(program)
    discard vm.ctx.getOrCreateVariant(profile.features)

proc prepareVariants*(vm: var OpenClVm, programs: openArray[seq[uint32]]) =
  ## Pre-compile multiple bytecode variants ahead of time.
  for prog in programs:
    vm.prepareVariant(prog)

proc prepareVariants*(vm: var OpenClVm, configs: openArray[VmObjectConfig]) =
  ## Pre-compile variants for configs ahead of time.
  for cfg in configs:
    if cfg.bytecode.len > 0:
      vm.prepareVariant(cfg.bytecode)

proc setUniform*[T](vm: var OpenClVm, uniformId: int, val: T) =
  let wordCount = (sizeof(T) + sizeof(uint32) - 1) div sizeof(uint32)
  if vm.uniform.len < uniformId + wordCount:
    vm.uniform.setLen(uniformId + wordCount)
  var tmp = val
  copyMem(addr vm.uniform[uniformId], addr tmp, sizeof(T))

proc setUniforms*(vm: var OpenClVm, uniforms: seq[uint32]) =
  vm.uniform = uniforms

proc setBuffer*(vm: var OpenClVm, bufId: int, hostPtr: pointer, sizeInBytes: int,
                flags: Tmem_flags = MEM_READ_WRITE) =
  assert bufId >= 0 and bufId < MAX_BUFFERS,
    "bufId hors limites (0 .. " & $(MAX_BUFFERS - 1) & ")"

  if vm.buffers[bufId] != vm.ctx.dummyBuffer and vm.buffers[bufId] != nil:
    discard releaseMemObject(vm.buffers[bufId])

  var status: TClResult
  let actualSize = max(sizeInBytes, 16)
  let devBuf = createBuffer(vm.ctx.context, flags, actualSize, nil, addr status)
  check status

  vm.buffers[bufId] = devBuf
  vm.bufferSizes[bufId] = sizeInBytes
  vm.bufferHostPtrs[bufId] = hostPtr

  if hostPtr != nil and sizeInBytes > 0:
    check enqueueWriteBuffer(vm.ctx.queue, devBuf, CL_TRUE, 0, sizeInBytes, hostPtr, 0, nil, nil)

proc configure*(vm: var OpenClVm, config: VmObjectConfig) =
  ## Apply the shared uniforms and buffers.
  if config.uniforms.len > 0:
    vm.setUniforms(config.uniforms)
  elif config.vertexUniforms.len > 0:
    vm.setUniforms(config.vertexUniforms)
  elif config.fragmentUniforms.len > 0:
    vm.setUniforms(config.fragmentUniforms)
  var configured = [false, false, false, false, false, false, false, false]
  for buffer in config.buffers:
    let data = if buffer.bytes.len > 0: unsafeAddr buffer.bytes[0] else: nil
    vm.setBuffer(buffer.id, cast[pointer](data), buffer.bytes.len)
    configured[buffer.id] = true
  for bufferId in 0 ..< MAX_BUFFERS:
    if not configured[bufferId] and vm.buffers[bufferId] != vm.ctx.dummyBuffer:
      if vm.buffers[bufferId] != nil:
        discard releaseMemObject(vm.buffers[bufferId])
      vm.buffers[bufferId] = vm.ctx.dummyBuffer
      vm.bufferSizes[bufferId] = 0
      vm.bufferHostPtrs[bufferId] = nil

proc setBufferMem*(vm: var OpenClVm, bufId: int, mem: Pmem, sizeInBytes: int) =
  assert bufId >= 0 and bufId < MAX_BUFFERS,
    "bufId hors limites (0 .. " & $(MAX_BUFFERS - 1) & ")"
  vm.buffers[bufId] = mem
  vm.bufferSizes[bufId] = sizeInBytes
  vm.bufferHostPtrs[bufId] = nil

proc syncBufferToHost*(vm: var OpenClVm, bufId: int, destPtr: pointer = nil) =
  assert bufId >= 0 and bufId < MAX_BUFFERS, "bufId hors limites"
  let target = if destPtr != nil: destPtr else: vm.bufferHostPtrs[bufId]
  if target != nil and vm.bufferSizes[bufId] > 0 and vm.buffers[bufId] != vm.ctx.dummyBuffer:
    check enqueueReadBuffer(vm.ctx.queue, vm.buffers[bufId], CL_TRUE, 0, vm.bufferSizes[bufId], target, 0, nil, nil)

proc syncBufferToDevice*(vm: var OpenClVm, bufId: int, srcPtr: pointer = nil) =
  assert bufId >= 0 and bufId < MAX_BUFFERS, "bufId hors limites"
  let source = if srcPtr != nil: srcPtr else: vm.bufferHostPtrs[bufId]
  if source != nil and vm.bufferSizes[bufId] > 0 and vm.buffers[bufId] != vm.ctx.dummyBuffer:
    check enqueueWriteBuffer(vm.ctx.queue, vm.buffers[bufId], CL_TRUE, 0, vm.bufferSizes[bufId], source, 0, nil, nil)

proc loadProgram*(vm: var OpenClVm, program: openArray[uint32]) =
  ## Select specialized variant and upload program bytecode.
  if program.len > 0:
    let profile = analyzeBytecode(program)
    let variant = vm.ctx.getOrCreateVariant(profile.features)
    vm.activeKernel = variant.kernel
  else:
    let variant = vm.ctx.getOrCreateVariant(DEFAULT_VM_FEATURES)
    vm.activeKernel = variant.kernel

  if vm.progMem != nil and vm.progMem != vm.ctx.dummyBuffer:
    discard releaseMemObject(vm.progMem)
  if program.len > 0:
    var status: TClResult
    let progBytes = program.len * sizeof(uint32)
    vm.progMem = createBuffer(vm.ctx.context, MEM_READ_ONLY, progBytes, nil, addr status)
    check status
    check enqueueWriteBuffer(vm.ctx.queue, vm.progMem, CL_TRUE, 0, progBytes, unsafeAddr program[0], 0, nil, nil)
    vm.progLen = program.len
  else:
    vm.progMem = vm.ctx.dummyBuffer
    vm.progLen = 0

proc uploadUniforms*(vm: var OpenClVm) =
  if vm.uniMem != nil and vm.uniMem != vm.ctx.dummyBuffer:
    discard releaseMemObject(vm.uniMem)
  if vm.uniform.len > 0:
    var status: TClResult
    let uniBytes = vm.uniform.len * sizeof(uint32)
    vm.uniMem = createBuffer(vm.ctx.context, MEM_READ_ONLY, uniBytes, nil, addr status)
    check status
    check enqueueWriteBuffer(vm.ctx.queue, vm.uniMem, CL_TRUE, 0, uniBytes, addr vm.uniform[0], 0, nil, nil)
    vm.uniLen = vm.uniform.len
  else:
    vm.uniMem = vm.ctx.dummyBuffer
    vm.uniLen = 0

proc executeKernel*(vm: var OpenClVm, globalWorkSize: int, startPc: int = 0, localWorkSize: int = 0) =
  if globalWorkSize <= 0:
    return

  if vm.activeKernel == nil:
    let variant = vm.ctx.getOrCreateVariant(DEFAULT_VM_FEATURES)
    vm.activeKernel = variant.kernel
  let k = vm.activeKernel
  var sPc  = int32(startPc)
  var uLen = int32(vm.uniLen)
  var uniBuffer = if vm.uniMem != nil: vm.uniMem else: vm.ctx.dummyBuffer

  check setKernelArg(k, 0, sizeof(Pmem), addr vm.progMem)
  check setKernelArg(k, 1, sizeof(int32), addr sPc)
  check setKernelArg(k, 2, sizeof(Pmem), addr uniBuffer)
  check setKernelArg(k, 3, sizeof(int32), addr uLen)

  for i in 0 ..< MAX_BUFFERS:
    var b = vm.buffers[i]
    if b == nil: b = vm.ctx.dummyBuffer
    check setKernelArg(k, uint32(4 + i), sizeof(Pmem), addr b)

  var gws = [globalWorkSize]
  if localWorkSize > 0:
    var lws = [localWorkSize]
    check enqueueNDRangeKernel(vm.ctx.queue, k, 1, nil, addr gws[0], addr lws[0], 0, nil, nil)
  else:
    check enqueueNDRangeKernel(vm.ctx.queue, k, 1, nil, addr gws[0], nil, 0, nil, nil)

  check finish(vm.ctx.queue)

proc runVM*(vm: var OpenClVm, program: openArray[uint32], globalWorkSize: int = 32,
            startPc: int = 0, localWorkSize: int = 0) =
  vm.loadProgram(program)
  vm.uploadUniforms()
  vm.executeKernel(globalWorkSize, startPc, localWorkSize)

proc runVM*(vm: var OpenClVm, config: VmObjectConfig, globalWorkSize: int = 32,
            startPc: int = 0, localWorkSize: int = 0) =
  vm.configure(config)
  vm.runVM(config.bytecode, globalWorkSize, startPc, localWorkSize)

proc destroy*(vm: var OpenClVm) =
  for i in 0 ..< MAX_BUFFERS:
    if vm.buffers[i] != vm.ctx.dummyBuffer and vm.buffers[i] != nil:
      discard releaseMemObject(vm.buffers[i])
      vm.buffers[i] = vm.ctx.dummyBuffer

  if vm.progMem != nil and vm.progMem != vm.ctx.dummyBuffer:
    discard releaseMemObject(vm.progMem)
    vm.progMem = nil

  if vm.uniMem != nil and vm.uniMem != vm.ctx.dummyBuffer:
    discard releaseMemObject(vm.uniMem)
    vm.uniMem = nil

proc destroy*(ctx: OpenClContext) =
  for variant in ctx.variants.values:
    if variant.kernel != nil:
      discard releaseKernel(variant.kernel)
    if variant.program != nil:
      discard releaseProgram(variant.program)
  ctx.variants.clear()
  if ctx.kernel != nil:
    discard releaseKernel(ctx.kernel)
    ctx.kernel = nil
  if ctx.program != nil:
    discard releaseProgram(ctx.program)
    ctx.program = nil
  if ctx.dummyBuffer != nil:
    discard releaseMemObject(ctx.dummyBuffer)
    ctx.dummyBuffer = nil
  if ctx.queue != nil:
    discard releaseCommandQueue(ctx.queue)
    ctx.queue = nil
  if ctx.context != nil:
    discard releaseContext(ctx.context)
    ctx.context = nil
