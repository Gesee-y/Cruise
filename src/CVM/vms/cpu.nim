import std/[math]
import ../deps/vmops
import ./object_config

const
  MAX_MEM* = 256
  SIZE_POS   = 24
  OPCODE_POS = 16
  REGA_POS   = 8

type
  CpuVm* = object
    pc*: int
    globalId*: int
    uniform*: seq[uint32]
    memory*: array[MAX_MEM, uint8]
    buffers*: seq[pointer]
    stack*: seq[uint8]
    registerBase: int
    stackBase: int
    callFrameBase: int
    halted*: bool

proc initCpuVm*(globalId: int = 0, uniforms: seq[uint32] = @[], buffers: seq[pointer] = @[]): CpuVm =
  result.pc = 0
  result.globalId = globalId
  result.uniform = uniforms
  result.buffers = buffers
  result.stack = @[]
  result.callFrameBase = -1
  result.halted = false

proc setUniform*[T](vm: var CpuVm, uniformId: int, val: T) =
  let wordCount = (sizeof(T) + sizeof(uint32) - 1) div sizeof(uint32)
  if vm.uniform.len < uniformId + wordCount:
    vm.uniform.setLen(uniformId + wordCount)
  var tmp = val
  copyMem(addr vm.uniform[uniformId], addr tmp, sizeof(T))

proc setUniforms*(vm: var CpuVm, uniforms: seq[uint32]) =
  vm.uniform = uniforms

proc setBuffer*(vm: var CpuVm, bufId: int, bufPtr: pointer) =
  if vm.buffers.len <= bufId:
    vm.buffers.setLen(bufId + 1)
  vm.buffers[bufId] = bufPtr

proc configure*(vm: var CpuVm, config: VmObjectConfig) =
  ## Apply backend-neutral uniforms and input buffers. Keep `config` alive while
  ## the VM may read its buffers; the CPU VM stores their addresses directly.
  if config.uniforms.len > 0:
    vm.setUniforms(config.uniforms)
  elif config.vertexUniforms.len > 0:
    vm.setUniforms(config.vertexUniforms)
  elif config.fragmentUniforms.len > 0:
    vm.setUniforms(config.fragmentUniforms)
  var bufferCount = 0
  for buffer in config.buffers:
    bufferCount = max(bufferCount, buffer.id + 1)
  vm.buffers.setLen(bufferCount)
  for index in 0 ..< bufferCount:
    vm.buffers[index] = nil
  for buffer in config.buffers:
    let data = if buffer.bytes.len > 0: unsafeAddr buffer.bytes[0] else: nil
    vm.setBuffer(buffer.id, cast[pointer](data))

proc runVM*(vm: var CpuVm, program: openArray[uint32])

proc runVM*(vm: var CpuVm, config: VmObjectConfig) =
  vm.configure(config)
  vm.runVM(config.bytecode)

proc decodeWord*(word: uint32, op: var VMOpCode, dst, src: var uint8, size: var int) {.inline.} =
  op   = VMOpCode((word shr OPCODE_POS) and 0xFF'u32)
  size = int((word shr SIZE_POS) and 0xFF'u32)
  if size == 0 and op != vocCall: size = 1
  dst  = uint8((word shr REGA_POS) and 0xFF'u32)
  src  = uint8(word and 0xFF'u32)

proc conversionSize(kind: VMConvType): int {.inline.} =
  case kind
  of vctInt8, vctUInt8, vctBool: 1
  of vctInt16, vctUInt16: 2
  of vctInt32, vctUInt32, vctFloat32: 4
  of vctInt64, vctUInt64, vctFloat64: 8
  of vctInvalid: 0

proc isFloatConversion(kind: VMConvType): bool {.inline.} =
  kind in {vctFloat32, vctFloat64}

proc isUnsignedConversion(kind: VMConvType): bool {.inline.} =
  kind in {vctUInt8, vctUInt16, vctUInt32, vctUInt64, vctBool}

# Helper memory read/write procs
template readMemInt(vm: CpuVm, address: int, size: int): int64 =
  case size
  of 8: cast[ptr int64](unsafeAddr vm.memory[address])[]
  of 4: int64(cast[ptr int32](unsafeAddr vm.memory[address])[])
  of 2: int64(cast[ptr int16](unsafeAddr vm.memory[address])[])
  of 1: int64(cast[ptr int8](unsafeAddr vm.memory[address])[])
  else:
    var tmp: int64 = 0
    copyMem(addr tmp, unsafeAddr vm.memory[address], min(size, 8))
    tmp

template writeMemInt(vm: var CpuVm, address: int, size: int, val: int64) =
  case size
  of 8: cast[ptr int64](addr vm.memory[address])[] = val
  of 4: cast[ptr int32](addr vm.memory[address])[] = int32(val)
  of 2: cast[ptr int16](addr vm.memory[address])[] = int16(val)
  of 1: cast[ptr int8](addr vm.memory[address])[] = int8(val)
  else:
    var tmp = val
    copyMem(addr vm.memory[address], addr tmp, min(size, 8))

template readMemUInt(vm: CpuVm, address: int, size: int): uint64 =
  case size
  of 8: cast[ptr uint64](unsafeAddr vm.memory[address])[]
  of 4: uint64(cast[ptr uint32](unsafeAddr vm.memory[address])[])
  of 2: uint64(cast[ptr uint16](unsafeAddr vm.memory[address])[])
  of 1: uint64(vm.memory[address])
  else:
    var tmp: uint64 = 0
    copyMem(addr tmp, unsafeAddr vm.memory[address], min(size, 8))
    tmp

template writeMemUInt(vm: var CpuVm, address: int, size: int, val: uint64) =
  case size
  of 8: cast[ptr uint64](addr vm.memory[address])[] = val
  of 4: cast[ptr uint32](addr vm.memory[address])[] = uint32(val)
  of 2: cast[ptr uint16](addr vm.memory[address])[] = uint16(val)
  of 1: vm.memory[address] = uint8(val)
  else:
    var tmp = val
    copyMem(addr vm.memory[address], addr tmp, min(size, 8))

template readMemFloat(vm: CpuVm, address: int, size: int): float64 =
  if size == 8:
    cast[ptr float64](unsafeAddr vm.memory[address])[]
  else:
    float64(cast[ptr float32](unsafeAddr vm.memory[address])[])

template writeMemFloat(vm: var CpuVm, address: int, size: int, val: float64) =
  if size == 8:
    cast[ptr float64](addr vm.memory[address])[] = val
  else:
    cast[ptr float32](addr vm.memory[address])[] = float32(val)

template readFloatWord(vm: CpuVm, wordIndex: int): float32 =
  cast[ptr UncheckedArray[float32]](unsafeAddr vm.memory[0])[wordIndex]

template writeFloatWord(vm: var CpuVm, wordIndex: int, value: float32) =
  cast[ptr UncheckedArray[float32]](addr vm.memory[0])[wordIndex] = value

proc runVM*(vm: var CpuVm, program: openArray[uint32]) =
  while not vm.halted:
    let word = program[vm.pc]
    var op: VMOpCode
    var dst, src: uint8
    var size: int

    decodeWord(word, op, dst, src, size)
    inc vm.pc

    case op
    of vocHalt:
      vm.halted = true
      break

    of vocLoadi, vocMovCi:
      dst = uint8(int(dst) + vm.registerBase)
      let imm = program[vm.pc]
      inc vm.pc
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] = int64(cast[int32](imm))
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] = cast[int32](imm)
      else:
        vm.writeMemInt(int(dst), size, int64(cast[int32](imm)))

    of vocLoadf, vocMovCf:
      dst = uint8(int(dst) + vm.registerBase)
      let imm = program[vm.pc]
      inc vm.pc
      let fval = cast[float32](imm)
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] = fval
      else:
        vm.writeMemFloat(int(dst), size, float64(fval))

    of vocConv:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let descriptor = program[vm.pc]
      inc vm.pc
      let sourceType = VMConvType(descriptor and 0xFF'u32)
      let targetType = VMConvType((descriptor shr 8) and 0xFF'u32)
      let sourceSize = sourceType.conversionSize
      let targetSize = targetType.conversionSize
      if sourceSize > 0 and targetSize > 0:
        if targetType == vctBool:
          let nonZero =
            if sourceType.isFloatConversion:
              vm.readMemFloat(int(src), sourceSize) != 0.0
            elif sourceType.isUnsignedConversion:
              vm.readMemUInt(int(src), sourceSize) != 0'u64
            else:
              vm.readMemInt(int(src), sourceSize) != 0
          vm.writeMemUInt(int(dst), 1, if nonZero: 1'u64 else: 0'u64)
        elif targetType.isFloatConversion:
          let value =
            if sourceType.isFloatConversion:
              vm.readMemFloat(int(src), sourceSize)
            elif sourceType.isUnsignedConversion:
              float64(vm.readMemUInt(int(src), sourceSize))
            else:
              float64(vm.readMemInt(int(src), sourceSize))
          vm.writeMemFloat(int(dst), targetSize, value)
        elif isUnsignedConversion(targetType):
          let value =
            if sourceType.isFloatConversion:
              cast[uint64](int64(vm.readMemFloat(int(src), sourceSize)))
            elif sourceType.isUnsignedConversion:
              vm.readMemUInt(int(src), sourceSize)
            else:
              cast[uint64](vm.readMemInt(int(src), sourceSize))
          vm.writeMemUInt(int(dst), targetSize, value)
        else:
          let value =
            if sourceType.isFloatConversion:
              int64(vm.readMemFloat(int(src), sourceSize))
            elif sourceType.isUnsignedConversion:
              cast[int64](vm.readMemUInt(int(src), sourceSize))
            else:
              vm.readMemInt(int(src), sourceSize)
          vm.writeMemInt(int(dst), targetSize, value)

    of vocMov:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      case size
      of 8:
        cast[ptr uint64](addr vm.memory[dst])[] = cast[ptr uint64](unsafeAddr vm.memory[src])[]
      of 4:
        cast[ptr uint32](addr vm.memory[dst])[] = cast[ptr uint32](unsafeAddr vm.memory[src])[]
      of 1:
        vm.memory[dst] = vm.memory[src]
      else:
        copyMem(addr vm.memory[dst], unsafeAddr vm.memory[src], size)

    of vocAbsi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      vm.writeMemInt(int(dst), size, abs(vm.readMemInt(int(src), size)))

    of vocAbsf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      vm.writeMemFloat(int(dst), size, abs(vm.readMemFloat(int(src), size)))

    of vocAbsu:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if dst != src:
        copyMem(addr vm.memory[dst], unsafeAddr vm.memory[src], size)

    of vocMini:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, if a < b: a else: b)

    of vocMaxi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, if a > b: a else: b)

    of vocMinf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, if a < b: a else: b)

    of vocMaxf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, if a > b: a else: b)

    of vocMinu:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemUInt(int(dst), size)
      let b = vm.readMemUInt(int(src), size)
      vm.writeMemUInt(int(dst), size, if a < b: a else: b)

    of vocMaxu:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemUInt(int(dst), size)
      let b = vm.readMemUInt(int(src), size)
      vm.writeMemUInt(int(dst), size, if a > b: a else: b)

    of vocSqrtf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      vm.writeMemFloat(int(dst), size, sqrt(vm.readMemFloat(int(src), size)))

    of vocRsqrtf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      vm.writeMemFloat(int(dst), size, 1.0 / sqrt(vm.readMemFloat(int(src), size)))

    of vocSinf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      vm.writeMemFloat(int(dst), size, sin(vm.readMemFloat(int(src), size)))

    of vocCosf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      vm.writeMemFloat(int(dst), size, cos(vm.readMemFloat(int(src), size)))

    of vocAddCi, vocSubCi, vocMulCi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let immediate = uint64(program[vm.pc])
      inc vm.pc
      let value = vm.readMemUInt(int(dst), size)
      case op
      of vocAddCi: vm.writeMemUInt(int(dst), size, value + immediate)
      of vocSubCi: vm.writeMemUInt(int(dst), size, value - immediate)
      of vocMulCi: vm.writeMemUInt(int(dst), size, value * immediate)
      else: discard

    of vocAddCf, vocSubCf, vocMulCf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var immediate: float64
      let low = program[vm.pc]
      inc vm.pc
      immediate = float64(cast[float32](low))
      let value = vm.readMemFloat(int(dst), size)
      case op
      of vocAddCf: vm.writeMemFloat(int(dst), size, value + immediate)
      of vocSubCf: vm.writeMemFloat(int(dst), size, value - immediate)
      of vocMulCf: vm.writeMemFloat(int(dst), size, value * immediate)
      else: discard

    of vocAddi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] += cast[ptr int64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] += cast[ptr int32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a + b)

    of vocSubi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] -= cast[ptr int64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] -= cast[ptr int32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a - b)

    of vocMuli:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] *= cast[ptr int64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] *= cast[ptr int32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a * b)

    of vocDivi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      if b != 0:
        vm.writeMemInt(int(dst), size, a div b)

    of vocMod:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      if b != 0:
        vm.writeMemInt(int(dst), size, a mod b)

    of vocAddf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 4:
        let dstWord = int(dst) shr 2
        let srcWord = int(src) shr 2
        vm.writeFloatWord(dstWord, vm.readFloatWord(dstWord) + vm.readFloatWord(srcWord))
      else:
        let a = vm.readMemFloat(int(dst), size)
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, a + b)

    of vocSubf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 4:
        let dstWord = int(dst) shr 2
        let srcWord = int(src) shr 2
        vm.writeFloatWord(dstWord, vm.readFloatWord(dstWord) - vm.readFloatWord(srcWord))
      else:
        let a = vm.readMemFloat(int(dst), size)
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, a - b)

    of vocMulf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 4:
        let dstWord = int(dst) shr 2
        let srcWord = int(src) shr 2
        vm.writeFloatWord(dstWord, vm.readFloatWord(dstWord) * vm.readFloatWord(srcWord))
      else:
        let a = vm.readMemFloat(int(dst), size)
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, a * b)

    of vocMaddf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let packedSources = program[vm.pc]
      inc vm.pc
      let mulReg = int(src)
      let rhsReg = int(packedSources and 0xFF'u32) + vm.registerBase
      let addReg = int((packedSources shr 8) and 0xFF'u32) + vm.registerBase
      if size > 4:
        let mulWord = mulReg shr 2
        let rhsWord = rhsReg shr 2
        let addWord = addReg shr 2
        let dstWord = int(dst) shr 2
        for lane in 0 ..< (size shr 2):
          let lhs = vm.readFloatWord(mulWord + lane)
          let rhs = vm.readFloatWord(rhsWord + lane)
          let addend = vm.readFloatWord(addWord + lane)
          vm.writeFloatWord(dstWord + lane, lhs * rhs + addend)
      elif size == 4:
        let product = vm.readFloatWord(mulReg shr 2) * vm.readFloatWord(rhsReg shr 2)
        let addend = vm.readFloatWord(addReg shr 2)
        vm.writeFloatWord(int(dst) shr 2, product + addend)
      else:
        let product = vm.readMemFloat(mulReg, size) * vm.readMemFloat(rhsReg, size)
        let addend = vm.readMemFloat(addReg, size)
        vm.writeMemFloat(int(dst), size, product + addend)

    of vocMaddi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let packedSources = program[vm.pc]
      inc vm.pc
      let mulReg = int(src)
      let rhsReg = int(packedSources and 0xFF'u32) + vm.registerBase
      let addReg = int((packedSources shr 8) and 0xFF'u32) + vm.registerBase
      let product = vm.readMemInt(mulReg, size) * vm.readMemInt(rhsReg, size)
      # Preserve intermediate-width truncation for narrow scalar integers.
      vm.writeMemInt(int(dst), size, product)
      let truncatedProduct = vm.readMemInt(int(dst), size)
      let addend = vm.readMemInt(addReg, size)
      vm.writeMemInt(int(dst), size, truncatedProduct + addend)

    of vocDivf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 4:
        let dstWord = int(dst) shr 2
        let srcWord = int(src) shr 2
        vm.writeFloatWord(dstWord, vm.readFloatWord(dstWord) / vm.readFloatWord(srcWord))
      else:
        let a = vm.readMemFloat(int(dst), size)
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, a / b)

    of vocNegi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] = -cast[ptr int64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] = -cast[ptr int32](unsafeAddr vm.memory[src])[]
      else:
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, -b)

    of vocNegf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] = -cast[ptr float32](unsafeAddr vm.memory[src])[]
      else:
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, -b)

    of vocAnd:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 8:
        cast[ptr uint64](addr vm.memory[dst])[] = cast[ptr uint64](unsafeAddr vm.memory[dst])[] and cast[ptr uint64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr uint32](addr vm.memory[dst])[] = cast[ptr uint32](unsafeAddr vm.memory[dst])[] and cast[ptr uint32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a and b)

    of vocOr:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 8:
        cast[ptr uint64](addr vm.memory[dst])[] = cast[ptr uint64](unsafeAddr vm.memory[dst])[] or cast[ptr uint64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr uint32](addr vm.memory[dst])[] = cast[ptr uint32](unsafeAddr vm.memory[dst])[] or cast[ptr uint32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a or b)

    of vocXor:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 8:
        cast[ptr uint64](addr vm.memory[dst])[] = cast[ptr uint64](unsafeAddr vm.memory[dst])[] xor cast[ptr uint64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr uint32](addr vm.memory[dst])[] = cast[ptr uint32](unsafeAddr vm.memory[dst])[] xor cast[ptr uint32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a xor b)

    of vocNot:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      if size == 8:
        cast[ptr uint64](addr vm.memory[dst])[] = not cast[ptr uint64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr uint32](addr vm.memory[dst])[] = not cast[ptr uint32](unsafeAddr vm.memory[src])[]
      else:
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, not b)

    of vocEqi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), 1, if a == b: 1 else: 0)

    of vocNeqi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), 1, if a != b: 1 else: 0)

    of vocLti:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), 1, if a < b: 1 else: 0)

    of vocLei:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), 1, if a <= b: 1 else: 0)

    of vocEqf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemInt(int(dst), 1, if a == b: 1 else: 0)

    of vocNeqf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemInt(int(dst), 1, if a != b: 1 else: 0)

    of vocLtf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemInt(int(dst), 1, if a < b: 1 else: 0)

    of vocLef:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemInt(int(dst), 1, if a <= b: 1 else: 0)

    of vocJmp:
      let target = program[vm.pc]
      vm.pc = int(target)

    of vocJmpFalse:
      dst = uint8(int(dst) + vm.registerBase)
      let target = program[vm.pc]
      inc vm.pc
      let cond = vm.memory[dst]
      if cond == 0:
        vm.pc = int(target)

    of vocCall:
      src = uint8(int(src) + vm.registerBase)
      let target = int(program[vm.pc])
      let frameInfo = program[vm.pc + 1]
      vm.pc += 2
      let argumentBytes = int(frameInfo and 0xFFFF'u32)
      let frameBytes = int(frameInfo shr 16)
      let argsBase = vm.stack.len - argumentBytes
      let calleeBase = vm.registerBase + int(dst)
      if argsBase < 0 or vm.stack.len > int(high(uint16)) or
          vm.stackBase > int(high(uint16)) or vm.callFrameBase > int(high(uint16)) or
          calleeBase + frameBytes > MAX_MEM:
        vm.halted = true
        break
      let frameBase = vm.stack.len
      let previousFrame = if vm.callFrameBase < 0: int(high(uint16)) else: vm.callFrameBase
      let frame = [uint32(vm.pc),
        uint32(vm.registerBase) or (uint32(vm.stackBase) shl 16),
        uint32(previousFrame) or (uint32(argsBase) shl 16),
        uint32(src) or (uint32(size) shl 8) or (uint32(calleeBase) shl 16)]
      vm.stack.setLen(frameBase + sizeof(frame))
      copyMem(addr vm.stack[frameBase], unsafeAddr frame[0], sizeof(frame))
      vm.callFrameBase = frameBase
      vm.registerBase = calleeBase
      vm.stackBase = argsBase
      vm.pc = target

    of vocRet:
      if vm.callFrameBase >= 0 and vm.callFrameBase + 16 <= vm.stack.len:
        var frame: array[4, uint32]
        copyMem(addr frame[0], unsafeAddr vm.stack[vm.callFrameBase], sizeof(frame))
        let parentRegisterBase = int(frame[1] and 0xFFFF'u32)
        let parentStackBase = int(frame[1] shr 16)
        let previousFrame = int(frame[2] and 0xFFFF'u32)
        let argsBase = int(frame[2] shr 16)
        let returnDst = int(frame[3] and 0xFF'u32)
        let returnSize = int((frame[3] shr 8) and 0xFF'u32)
        let calleeBase = int(frame[3] shr 16)
        if returnSize > 0:
          copyMem(addr vm.memory[returnDst], unsafeAddr vm.memory[calleeBase], returnSize)
        vm.stack.setLen(argsBase)
        vm.registerBase = parentRegisterBase
        vm.stackBase = parentStackBase
        vm.callFrameBase = if previousFrame == high(uint16).int: -1 else: previousFrame
        vm.pc = int(frame[0])
      else:
        vm.halted = true
        break

    of vocPush:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let reg = if dst != 0: dst else: src
      let startIdx = vm.stack.len
      vm.stack.setLen(startIdx + size)
      copyMem(addr vm.stack[startIdx], unsafeAddr vm.memory[reg], size)

    of vocPop:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let popSize = min(size, vm.stack.len)
      if popSize > 0:
        let startIdx = vm.stack.len - popSize
        copyMem(addr vm.memory[dst], unsafeAddr vm.stack[startIdx], popSize)
        vm.stack.setLen(startIdx)

    of vocSMov:
      dst = uint8(int(dst) + vm.registerBase)
      let offset = vm.stackBase + int(src)
      if offset + size <= vm.stack.len:
        copyMem(addr vm.memory[dst], unsafeAddr vm.stack[offset], size)

    of vocLoad:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let addrReg = vm.memory[src]
      copyMem(addr vm.memory[dst], unsafeAddr vm.memory[addrReg], size)

    of vocStore:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let addrReg = vm.memory[dst]
      copyMem(addr vm.memory[addrReg], unsafeAddr vm.memory[src], size)

    of vocLoadUni:
      dst = uint8(int(dst) + vm.registerBase)
      let uIdx = int(src)
      if uIdx < vm.uniform.len:
        if size == 8 and uIdx + 2 <= vm.uniform.len:
          cast[ptr int64](addr vm.memory[dst])[] = cast[ptr int64](unsafeAddr vm.uniform[uIdx])[]
        elif size == 4:
          cast[ptr uint32](addr vm.memory[dst])[] = vm.uniform[uIdx]
        else:
          let totalAvailBytes = (vm.uniform.len - uIdx) * sizeof(uint32)
          let copyBytes = min(size, totalAvailBytes)
          let uBytes = unsafeAddr vm.uniform[uIdx]
          copyMem(addr vm.memory[dst], uBytes, copyBytes)

    of vocLoadBuf:
      dst = uint8(int(dst) + vm.registerBase)
      let bufId = int(src)
      let idxReg = int(program[vm.pc]) + vm.registerBase
      inc vm.pc
      let index = vm.readMemInt(idxReg, 4)
      let basePtr = cast[uint](vm.buffers[bufId])
      let elemPtr = cast[pointer](basePtr + uint(index * int64(size)))
      case size
      of 8:
        cast[ptr int64](addr vm.memory[dst])[] = cast[ptr int64](elemPtr)[]
      of 4:
        cast[ptr int32](addr vm.memory[dst])[] = cast[ptr int32](elemPtr)[]
      of 1:
        vm.memory[dst] = cast[ptr uint8](elemPtr)[]
      else:
        copyMem(addr vm.memory[dst], elemPtr, size)

    of vocStoreBuf:
      dst = uint8(int(dst) + vm.registerBase)
      let bufId = int(src)
      let idxReg = int(program[vm.pc]) + vm.registerBase
      inc vm.pc
      let index = vm.readMemInt(idxReg, 4)
      let basePtr = cast[uint](vm.buffers[bufId])
      let elemPtr = cast[pointer](basePtr + uint(index * int64(size)))
      case size
      of 8:
        cast[ptr int64](elemPtr)[] = cast[ptr int64](addr vm.memory[dst])[]
      of 4:
        cast[ptr int32](elemPtr)[] = cast[ptr int32](addr vm.memory[dst])[]
      of 1:
        cast[ptr uint8](elemPtr)[] = vm.memory[dst]
      else:
        copyMem(elemPtr, unsafeAddr vm.memory[dst], size)

    of vocLoadAt:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let arrBase = int(src)
      let idxReg = int(program[vm.pc]) + vm.registerBase
      inc vm.pc
      let index = int(vm.readMemInt(idxReg, 4))
      let elemAddr = arrBase + index * size
      copyMem(addr vm.memory[dst], unsafeAddr vm.memory[elemAddr], size)

    of vocStoreAt:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let arrBase = int(src)
      let idxReg = int(program[vm.pc]) + vm.registerBase
      inc vm.pc
      let index = int(vm.readMemInt(idxReg, 4))
      let elemAddr = arrBase + index * size
      copyMem(addr vm.memory[elemAddr], unsafeAddr vm.memory[dst], size)

    of vocLoadGI:
      dst = uint8(int(dst) + vm.registerBase)
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] = int64(vm.globalId)
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] = int32(vm.globalId)
      else:
        vm.writeMemInt(int(dst), size, int64(vm.globalId))

    of vocNoOp:
      discard

    of vocLoadVertexInput, vocLoadFragmentInput, vocStoreVertexOutput,
       vocStoreVertexVarying, vocStoreFragmentOutput:
      dst = uint8(int(dst) + vm.registerBase)
      discard # Stage I/O is provided by the GLSL VM, not the CPU interpreter.

    of vocSample2D:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      inc vm.pc # texture id follows; sampling itself is GPU-only

    of vocSampleLod:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      inc vm.pc # packed texture id and LOD register follow; GPU-only

    of vocMmatvec2f:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let vx = cast[ptr float32](unsafeAddr vm.memory[dst])[]
      let vy = cast[ptr float32](unsafeAddr vm.memory[dst + 4])[]
      let c0x = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let c0y = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let c1x = cast[ptr float32](unsafeAddr vm.memory[src + 8])[]
      let c1y = cast[ptr float32](unsafeAddr vm.memory[src + 12])[]
      cast[ptr float32](addr vm.memory[dst])[] = c0x * vx + c1x * vy
      cast[ptr float32](addr vm.memory[dst + 4])[] = c0y * vx + c1y * vy

    of vocMmatvec2i:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let vx = cast[ptr int32](unsafeAddr vm.memory[dst])[]
      let vy = cast[ptr int32](unsafeAddr vm.memory[dst + 4])[]
      let c0x = cast[ptr int32](unsafeAddr vm.memory[src])[]
      let c0y = cast[ptr int32](unsafeAddr vm.memory[src + 4])[]
      let c1x = cast[ptr int32](unsafeAddr vm.memory[src + 8])[]
      let c1y = cast[ptr int32](unsafeAddr vm.memory[src + 12])[]
      cast[ptr int32](addr vm.memory[dst])[] = c0x * vx + c1x * vy
      cast[ptr int32](addr vm.memory[dst + 4])[] = c0y * vx + c1y * vy

    of vocMmatvec3f:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let vx = cast[ptr float32](unsafeAddr vm.memory[dst])[]
      let vy = cast[ptr float32](unsafeAddr vm.memory[dst + 4])[]
      let vz = if size >= 12: cast[ptr float32](unsafeAddr vm.memory[dst + 8])[] else: 1.0'f32
      var res: array[3, float32]
      for col in 0..<3:
        let vVal = if col == 0: vx elif col == 1: vy else: vz
        for row in 0..<3:
          let mVal = cast[ptr float32](unsafeAddr vm.memory[int(src) + (col * 3 + row) * 4])[]
          res[row] += mVal * vVal
      copyMem(addr vm.memory[dst], addr res[0], 12)

    of vocMmatvec3i:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let vx = cast[ptr int32](unsafeAddr vm.memory[dst])[]
      let vy = cast[ptr int32](unsafeAddr vm.memory[dst + 4])[]
      let vz = if size >= 12: cast[ptr int32](unsafeAddr vm.memory[dst + 8])[] else: 1'i32
      var res: array[3, int32]
      for col in 0..<3:
        let vVal = if col == 0: vx elif col == 1: vy else: vz
        for row in 0..<3:
          let mVal = cast[ptr int32](unsafeAddr vm.memory[int(src) + (col * 3 + row) * 4])[]
          res[row] += mVal * vVal
      copyMem(addr vm.memory[dst], addr res[0], 12)

    of vocMmatvec4f:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let vx = cast[ptr float32](unsafeAddr vm.memory[dst])[]
      let vy = cast[ptr float32](unsafeAddr vm.memory[dst + 4])[]
      let vz = if size >= 12: cast[ptr float32](unsafeAddr vm.memory[dst + 8])[] else: 0.0'f32
      let vw = if size >= 16: cast[ptr float32](unsafeAddr vm.memory[dst + 12])[] else: 1.0'f32
      var res: array[4, float32]
      for col in 0..<4:
        let vVal = if col == 0: vx elif col == 1: vy elif col == 2: vz else: vw
        for row in 0..<4:
          let mVal = cast[ptr float32](unsafeAddr vm.memory[int(src) + (col * 4 + row) * 4])[]
          res[row] += mVal * vVal
      copyMem(addr vm.memory[dst], addr res[0], 16)

    of vocMmatvec4i:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let vx = cast[ptr int32](unsafeAddr vm.memory[dst])[]
      let vy = cast[ptr int32](unsafeAddr vm.memory[dst + 4])[]
      let vz = if size >= 12: cast[ptr int32](unsafeAddr vm.memory[dst + 8])[] else: 0'i32
      let vw = if size >= 16: cast[ptr int32](unsafeAddr vm.memory[dst + 12])[] else: 1'i32
      var res: array[4, int32]
      for col in 0..<4:
        let vVal = if col == 0: vx elif col == 1: vy elif col == 2: vz else: vw
        for row in 0..<4:
          let mVal = cast[ptr int32](unsafeAddr vm.memory[int(src) + (col * 4 + row) * 4])[]
          res[row] += mVal * vVal
      copyMem(addr vm.memory[dst], addr res[0], 16)

    of vocMmat2f:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[4, float32]
      for c in 0..<2:
        for r in 0..<2:
          var sum = 0.0'f32
          for k in 0..<2:
            let a = cast[ptr float32](unsafeAddr vm.memory[int(dst) + (k * 2 + r) * 4])[]
            let b = cast[ptr float32](unsafeAddr vm.memory[int(src) + (c * 2 + k) * 4])[]
            sum += a * b
          res[c * 2 + r] = sum
      copyMem(addr vm.memory[dst], addr res[0], 16)

    of vocMmat2i:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[4, int32]
      for c in 0..<2:
        for r in 0..<2:
          var sum = 0'i32
          for k in 0..<2:
            let a = cast[ptr int32](unsafeAddr vm.memory[int(dst) + (k * 2 + r) * 4])[]
            let b = cast[ptr int32](unsafeAddr vm.memory[int(src) + (c * 2 + k) * 4])[]
            sum += a * b
          res[c * 2 + r] = sum
      copyMem(addr vm.memory[dst], addr res[0], 16)

    of vocMmat3f:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[9, float32]
      for c in 0..<3:
        for r in 0..<3:
          var sum = 0.0'f32
          for k in 0..<3:
            let a = cast[ptr float32](unsafeAddr vm.memory[int(dst) + (k * 3 + r) * 4])[]
            let b = cast[ptr float32](unsafeAddr vm.memory[int(src) + (c * 3 + k) * 4])[]
            sum += a * b
          res[c * 3 + r] = sum
      copyMem(addr vm.memory[dst], addr res[0], 36)

    of vocMmat3i:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[9, int32]
      for c in 0..<3:
        for r in 0..<3:
          var sum = 0'i32
          for k in 0..<3:
            let a = cast[ptr int32](unsafeAddr vm.memory[int(dst) + (k * 3 + r) * 4])[]
            let b = cast[ptr int32](unsafeAddr vm.memory[int(src) + (c * 3 + k) * 4])[]
            sum += a * b
          res[c * 3 + r] = sum
      copyMem(addr vm.memory[dst], addr res[0], 36)

    of vocMmat4f:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[16, float32]
      for c in 0..<4:
        for r in 0..<4:
          var sum = 0.0'f32
          for k in 0..<4:
            let a = cast[ptr float32](unsafeAddr vm.memory[int(dst) + (k * 4 + r) * 4])[]
            let b = cast[ptr float32](unsafeAddr vm.memory[int(src) + (c * 4 + k) * 4])[]
            sum += a * b
          res[c * 4 + r] = sum
      copyMem(addr vm.memory[dst], addr res[0], 64)

    of vocMmat4i:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[16, int32]
      for c in 0..<4:
        for r in 0..<4:
          var sum = 0'i32
          for k in 0..<4:
            let a = cast[ptr int32](unsafeAddr vm.memory[int(dst) + (k * 4 + r) * 4])[]
            let b = cast[ptr int32](unsafeAddr vm.memory[int(src) + (c * 4 + k) * 4])[]
            sum += a * b
          res[c * 4 + r] = sum
      copyMem(addr vm.memory[dst], addr res[0], 64)

    of vocVecAddi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let count = max(1, size)
      let sVal = cast[ptr int32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr int32](addr vm.memory[int(dst) + i * 4])[] += sVal

    of vocVecAddf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let count = max(1, size)
      let sVal = cast[ptr float32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] += sVal

    of vocVecSubi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let count = max(1, size)
      let sVal = cast[ptr int32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr int32](addr vm.memory[int(dst) + i * 4])[] -= sVal

    of vocVecSubf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let count = max(1, size)
      let sVal = cast[ptr float32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] -= sVal

    of vocVecMuli:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let count = max(1, size)
      let sVal = cast[ptr int32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr int32](addr vm.memory[int(dst) + i * 4])[] *= sVal

    of vocVecMulf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let count = max(1, size)
      let sVal = cast[ptr float32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] *= sVal

    of vocNormalize:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let dim = max(2, size)
      var sumSq = 0.0'f32
      for i in 0..<dim:
        let val = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        sumSq += val * val
      let lenVal = sqrt(sumSq)
      let invLen = if lenVal > 1e-6'f32: 1.0'f32 / lenVal else: 0.0'f32
      for i in 0..<dim:
        let val = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] = val * invLen

    of vocDot2:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let ax = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let ay = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let bx = cast[ptr float32](unsafeAddr vm.memory[size])[]
      let by = cast[ptr float32](unsafeAddr vm.memory[size + 4])[]
      cast[ptr float32](addr vm.memory[dst])[] = ax * bx + ay * by

    of vocDot3:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let ax = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let ay = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let az = cast[ptr float32](unsafeAddr vm.memory[src + 8])[]
      let bx = cast[ptr float32](unsafeAddr vm.memory[size])[]
      let by = cast[ptr float32](unsafeAddr vm.memory[size + 4])[]
      let bz = cast[ptr float32](unsafeAddr vm.memory[size + 8])[]
      cast[ptr float32](addr vm.memory[dst])[] = ax * bx + ay * by + az * bz

    of vocDot4:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var sum = 0.0'f32
      for i in 0..<4:
        sum += cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[] *
               cast[ptr float32](unsafeAddr vm.memory[int(size) + i * 4])[]
      cast[ptr float32](addr vm.memory[dst])[] = sum

    of vocTranspose2:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[4, float32]
      for c in 0..<2:
        for r in 0..<2:
          res[c * 2 + r] = cast[ptr float32](unsafeAddr vm.memory[int(src) + (r * 2 + c) * 4])[]
      copyMem(addr vm.memory[dst], addr res[0], 16)

    of vocTranspose3:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[9, float32]
      for c in 0..<3:
        for r in 0..<3:
          res[c * 3 + r] = cast[ptr float32](unsafeAddr vm.memory[int(src) + (r * 3 + c) * 4])[]
      copyMem(addr vm.memory[dst], addr res[0], 36)

    of vocTranspose4:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var res: array[16, float32]
      for c in 0..<4:
        for r in 0..<4:
          res[c * 4 + r] = cast[ptr float32](unsafeAddr vm.memory[int(src) + (r * 4 + c) * 4])[]
      copyMem(addr vm.memory[dst], addr res[0], 64)

    of vocInvert2:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let a = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let b = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let c = cast[ptr float32](unsafeAddr vm.memory[src + 8])[]
      let d = cast[ptr float32](unsafeAddr vm.memory[src + 12])[]
      let det = a * d - b * c
      let invDet = if abs(det) > 1e-6'f32: 1.0'f32 / det else: 0.0'f32
      var res = [d * invDet, -b * invDet, -c * invDet, a * invDet]
      copyMem(addr vm.memory[dst], addr res[0], 16)

    of vocInvert3, vocInvert4:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      # Copy through for fallback if general 4x4 inverse not needed on CPU
      copyMem(addr vm.memory[dst], unsafeAddr vm.memory[src], if op == vocInvert3: 36 else: 64)

    of vocReflect2:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let ix = cast[ptr float32](unsafeAddr vm.memory[dst])[]
      let iy = cast[ptr float32](unsafeAddr vm.memory[dst + 4])[]
      let nx = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let ny = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let dotProd = ix * nx + iy * ny
      cast[ptr float32](addr vm.memory[dst])[] = ix - 2.0'f32 * dotProd * nx
      cast[ptr float32](addr vm.memory[dst + 4])[] = iy - 2.0'f32 * dotProd * ny

    of vocReflect3:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let ix = cast[ptr float32](unsafeAddr vm.memory[dst])[]
      let iy = cast[ptr float32](unsafeAddr vm.memory[dst + 4])[]
      let iz = cast[ptr float32](unsafeAddr vm.memory[dst + 8])[]
      let nx = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let ny = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let nz = cast[ptr float32](unsafeAddr vm.memory[src + 8])[]
      let dotProd = ix * nx + iy * ny + iz * nz
      cast[ptr float32](addr vm.memory[dst])[] = ix - 2.0'f32 * dotProd * nx
      cast[ptr float32](addr vm.memory[dst + 4])[] = iy - 2.0'f32 * dotProd * ny
      cast[ptr float32](addr vm.memory[dst + 8])[] = iz - 2.0'f32 * dotProd * nz

    of vocCross3:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let ax = cast[ptr float32](unsafeAddr vm.memory[dst])[]
      let ay = cast[ptr float32](unsafeAddr vm.memory[dst + 4])[]
      let az = cast[ptr float32](unsafeAddr vm.memory[dst + 8])[]
      let bx = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let by = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let bz = cast[ptr float32](unsafeAddr vm.memory[src + 8])[]
      cast[ptr float32](addr vm.memory[dst])[] = ay * bz - az * by
      cast[ptr float32](addr vm.memory[dst + 4])[] = az * bx - ax * bz
      cast[ptr float32](addr vm.memory[dst + 8])[] = ax * by - ay * bx

    of vocLengthf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      var sumSq = 0.0'f32
      for i in 0..<max(2, size):
        let v = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        sumSq += v * v
      cast[ptr float32](addr vm.memory[dst])[] = sqrt(sumSq)

    of vocRefractf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let etaReg = int(program[vm.pc] and 0xFF'u32) + vm.registerBase
      inc vm.pc
      let count = max(2, size)
      var dotNI = 0.0'f32
      for i in 0..<count:
        let iVal = cast[ptr float32](unsafeAddr vm.memory[int(dst) + i * 4])[]
        let nVal = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        dotNI += nVal * iVal
      let eta = cast[ptr float32](unsafeAddr vm.memory[etaReg])[]
      let k = 1.0'f32 - eta * eta * (1.0'f32 - dotNI * dotNI)
      for i in 0..<count:
        let iVal = cast[ptr float32](unsafeAddr vm.memory[int(dst) + i * 4])[]
        let nVal = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] =
          if k < 0.0'f32: 0.0'f32
          else: eta * iVal - (eta * dotNI + sqrt(k)) * nVal

    of vocUnaryMathf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let selector = program[vm.pc]
      inc vm.pc
      for i in 0..<max(1, size):
        let address = int(src) + i * 4
        let value = cast[ptr float32](unsafeAddr vm.memory[address])[]
        var output: float32
        case selector
        of 0: output = sin(value) / cos(value)
        of 1: output = arcsin(value)
        of 2: output = arccos(value)
        of 3: output = arctan(value)
        of 4: output = exp(value)
        of 5: output = ln(value)
        of 6: output = pow(2.0'f32, value)
        of 7: output = ln(value) / ln(2.0'f32)
        of 8: output = -floor(-value).float32
        of 9: output = (if value < 0.0'f32: -1.0'f32 else: 1.0'f32) * floor(abs(value)).float32
        of 10: output = (if value < 0.0'f32: -1.0'f32 else: 1.0'f32) * floor(abs(value) + 0.5'f32).float32
        of 11: output = if value > 0.0'f32: 1.0'f32 elif value < 0.0'f32: -1.0'f32 else: 0.0'f32
        of 12: output = value * 0.017453292519943295'f32
        of 13: output = value * 57.29577951308232'f32
        of 14: output = (exp(value) - exp(-value)) * 0.5'f32
        of 15: output = (exp(value) + exp(-value)) * 0.5'f32
        of 16:
          let e = exp(2.0'f32 * value)
          output = (e - 1.0'f32) / (e + 1.0'f32)
        of 17: output = ln(value + sqrt(value * value + 1.0'f32))
        of 18: output = ln(value + sqrt(value * value - 1.0'f32))
        of 19: output = 0.5'f32 * ln((1.0'f32 + value) / (1.0'f32 - value))
        of 20: output = abs(value)
        of 21: output = 1.0'f32 / sqrt(value)
        else: output = value
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] = output

    of vocBinaryMathf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let descriptor = program[vm.pc]
      inc vm.pc
      let selector = descriptor and 0xFF'u32
      let broadcast = (descriptor and 0x100'u32) != 0
      for i in 0..<max(1, size):
        let leftAddr = int(dst) + i * 4
        let rightAddr = int(src) + (if broadcast: 0 else: i * 4)
        let left = cast[ptr float32](unsafeAddr vm.memory[leftAddr])[]
        let right = cast[ptr float32](unsafeAddr vm.memory[rightAddr])[]
        let output =
          case selector
          of 0: arctan2(left, right).float32
          of 1: left - right * floor(left / right).float32
          of 2: min(left, right)
          of 3: max(left, right)
          else: left
        cast[ptr float32](addr vm.memory[leftAddr])[] = output

    of vocFaceforward:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let refNormal = int(program[vm.pc] and 0xFF'u32) + vm.registerBase
      inc vm.pc
      var dotProduct = 0.0'f32
      for i in 0..<max(2, size):
        dotProduct += cast[ptr float32](unsafeAddr vm.memory[refNormal + i * 4])[] *
                      cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
      let sign = if dotProduct < 0.0'f32: 1.0'f32 else: -1.0'f32
      for i in 0..<max(2, size):
        let address = int(dst) + i * 4
        cast[ptr float32](addr vm.memory[address])[] *= sign

    of vocMatrixCompMult:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      for i in 0..<max(1, size):
        let address = int(dst) + i * 4
        let rhs = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        cast[ptr float32](addr vm.memory[address])[] *= rhs

    of vocDeterminantf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let dim = max(2, size)
      var matrix: array[16, float32]
      for i in 0..<(dim * dim):
        matrix[i] = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
      var determinant = 1.0'f32
      for col in 0..<dim:
        var pivot = col
        for row in (col + 1)..<dim:
          if abs(matrix[row * dim + col]) > abs(matrix[pivot * dim + col]):
            pivot = row
        let pivotValue = matrix[pivot * dim + col]
        if abs(pivotValue) <= 1e-20'f32:
          determinant = 0.0'f32
          break
        if pivot != col:
          for j in 0..<dim:
            swap(matrix[col * dim + j], matrix[pivot * dim + j])
          determinant = -determinant
        let diagonal = matrix[col * dim + col]
        determinant *= diagonal
        for row in (col + 1)..<dim:
          let factor = matrix[row * dim + col] / diagonal
          for j in (col + 1)..<dim:
            matrix[row * dim + j] -= factor * matrix[col * dim + j]
      cast[ptr float32](addr vm.memory[dst])[] = determinant

    of vocPowi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let count = max(1, size)
      let expVal = int(cast[ptr int32](unsafeAddr vm.memory[src])[])
      for i in 0..<count:
        let baseVal = cast[ptr int32](unsafeAddr vm.memory[int(dst) + i * 4])[]
        var r = 1'i32
        for p in 0..<expVal: r *= baseVal
        cast[ptr int32](addr vm.memory[int(dst) + i * 4])[] = r

    of vocPowf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let count = max(1, size)
      let expVal = cast[ptr float32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        let baseVal = cast[ptr float32](unsafeAddr vm.memory[int(dst) + i * 4])[]
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] = pow(baseVal, expVal)

    of vocVecNegf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      for i in 0..<max(1, size):
        let address = int(dst) + i * sizeof(float32)
        cast[ptr float32](addr vm.memory[address])[] =
          -cast[ptr float32](unsafeAddr vm.memory[address])[]

    of vocVecNegi:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      for i in 0..<max(1, size):
        let address = int(dst) + i * sizeof(int32)
        cast[ptr int32](addr vm.memory[address])[] =
          -cast[ptr int32](unsafeAddr vm.memory[address])[]

    of vocFloorf, vocFractf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      for i in 0..<max(1, size):
        let address = int(dst) + i * 4
        let value = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        cast[ptr float32](addr vm.memory[address])[] =
          if op == vocFloorf: floor(value).float32 else: value - floor(value).float32

    of vocStepf, vocSmoothstepf, vocMixf, vocClampf:
      dst = uint8(int(dst) + vm.registerBase)
      src = uint8(int(src) + vm.registerBase)
      let descriptor = program[vm.pc]
      inc vm.pc
      let count = max(1, size)
      let firstBroadcast = (descriptor and 0x100'u32) != 0
      let secondBroadcast = (descriptor and 0x200'u32) != 0
      let thirdSrc = int(descriptor and 0xFF'u32) + vm.registerBase
      for i in 0..<count:
        let outAddr = int(dst) + i * 4
        let secondAddr = int(src) + (if firstBroadcast: 0 else: i * 4)
        let x = cast[ptr float32](unsafeAddr vm.memory[outAddr])[]
        let y = cast[ptr float32](unsafeAddr vm.memory[secondAddr])[]
        var value: float32
        case op
        of vocStepf:
          value = if y < x: 0.0'f32 else: 1.0'f32
        of vocSmoothstepf:
          let edge1Addr = thirdSrc + (if secondBroadcast: 0 else: i * 4)
          let edge1 = cast[ptr float32](unsafeAddr vm.memory[edge1Addr])[]
          let t = min(1.0'f32, max(0.0'f32, (x - y) / (edge1 - y)))
          value = t * t * (3.0'f32 - 2.0'f32 * t)
        of vocMixf:
          let factorAddr = thirdSrc + (if firstBroadcast: 0 else: i * 4)
          let factor = cast[ptr float32](unsafeAddr vm.memory[factorAddr])[]
          value = x * (1.0'f32 - factor) + y * factor
        of vocClampf:
          let upperAddr = thirdSrc + (if secondBroadcast: 0 else: i * 4)
          let upper = cast[ptr float32](unsafeAddr vm.memory[upperAddr])[]
          value = min(upper, max(y, x))
        else:
          value = x
        cast[ptr float32](addr vm.memory[outAddr])[] = value
