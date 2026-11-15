import std/[math]
import ../deps/vmops

const
  MAX_MEM* = 256
  SIZE_POS   = 24
  OPCODE_POS = 16
  REGA_POS   = 8

type
  CallFrame = object
    returnPc: int
    parentRegisterBase: int
    parentStackBase: int
    argsBase: int
    returnDst: int
    returnSize: int
    calleeRegisterBase: int

  CpuVm* = object
    pc*: int
    globalId*: int
    uniform*: seq[uint32]
    memory* {.align: 8.}: array[MAX_MEM, uint8]
    buffers*: seq[pointer]
    callStack*: seq[CallFrame]
    stack*: seq[uint8]
    registerBase: int
    stackBase: int
    halted*: bool

proc initCpuVm*(globalId: int = 0, uniforms: seq[uint32] = @[], buffers: seq[pointer] = @[]): CpuVm =
  result.pc = 0
  result.globalId = globalId
  result.uniform = uniforms
  result.buffers = buffers
  result.callStack = @[]
  result.stack = @[]
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

proc runVM*(vm: var CpuVm, program: openArray[uint32]) =
  while vm.pc < program.len and not vm.halted:
    let word = program[vm.pc]
    var op: VMOpCode
    var dst, src: uint8
    var size: int

    decodeWord(word, op, dst, src, size)
    inc vm.pc

    # Function bytecode uses register addresses local to its own frame.
    # Address fields that encode immediates, stack slots, IO offsets, or IDs
    # are deliberately excluded here and handled by their opcode case.
    let dstIsRegister = op notin {vocHalt, vocCall, vocJmp, vocRet, vocNoOp}
    let srcIsRegister = op notin {vocHalt, vocLoadi, vocLoadf, vocMovCi,
      vocMovCf, vocRet, vocJmp, vocJmpFalse, vocSMov,
      vocLoadUni, vocLoadBuf, vocStoreBuf, vocLoadVertexInput,
      vocLoadFragmentInput, vocStoreVertexVarying, vocNoOp, vocLoadGI}
    if dstIsRegister: dst = uint8(int(dst) + vm.registerBase)
    if srcIsRegister: src = uint8(int(src) + vm.registerBase)

    case op
    of vocHalt:
      vm.halted = true
      break

    of vocLoadi, vocMovCi:
      let imm = program[vm.pc]
      inc vm.pc
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] = int64(cast[int32](imm))
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] = cast[int32](imm)
      else:
        vm.writeMemInt(int(dst), size, int64(cast[int32](imm)))

    of vocLoadf, vocMovCf:
      let imm = program[vm.pc]
      inc vm.pc
      let fval = cast[float32](imm)
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] = fval
      else:
        vm.writeMemFloat(int(dst), size, float64(fval))

    of vocConv:
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
      vm.writeMemInt(int(dst), size, abs(vm.readMemInt(int(src), size)))

    of vocAbsf:
      vm.writeMemFloat(int(dst), size, abs(vm.readMemFloat(int(src), size)))

    of vocAbsu:
      if dst != src:
        copyMem(addr vm.memory[dst], unsafeAddr vm.memory[src], size)

    of vocMini:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, if a < b: a else: b)

    of vocMaxi:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, if a > b: a else: b)

    of vocMinf:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, if a < b: a else: b)

    of vocMaxf:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, if a > b: a else: b)

    of vocMinu:
      let a = vm.readMemUInt(int(dst), size)
      let b = vm.readMemUInt(int(src), size)
      vm.writeMemUInt(int(dst), size, if a < b: a else: b)

    of vocMaxu:
      let a = vm.readMemUInt(int(dst), size)
      let b = vm.readMemUInt(int(src), size)
      vm.writeMemUInt(int(dst), size, if a > b: a else: b)

    of vocSqrtf:
      vm.writeMemFloat(int(dst), size, sqrt(vm.readMemFloat(int(src), size)))

    of vocRsqrtf:
      vm.writeMemFloat(int(dst), size, 1.0 / sqrt(vm.readMemFloat(int(src), size)))

    of vocSinf:
      vm.writeMemFloat(int(dst), size, sin(vm.readMemFloat(int(src), size)))

    of vocCosf:
      vm.writeMemFloat(int(dst), size, cos(vm.readMemFloat(int(src), size)))

    of vocAddCi, vocSubCi, vocMulCi:
      var immediate = uint64(program[vm.pc])
      inc vm.pc
      if size > 4:
        immediate = immediate or (uint64(program[vm.pc]) shl 32)
        inc vm.pc
      let value = vm.readMemUInt(int(dst), size)
      case op
      of vocAddCi: vm.writeMemUInt(int(dst), size, value + immediate)
      of vocSubCi: vm.writeMemUInt(int(dst), size, value - immediate)
      of vocMulCi: vm.writeMemUInt(int(dst), size, value * immediate)
      else: discard

    of vocAddCf, vocSubCf, vocMulCf:
      var immediate: float64
      let low = program[vm.pc]
      inc vm.pc
      if size > 4:
        let high = program[vm.pc]
        inc vm.pc
        immediate = cast[float64](uint64(low) or (uint64(high) shl 32))
      else:
        immediate = float64(cast[float32](low))
      let value = vm.readMemFloat(int(dst), size)
      case op
      of vocAddCf: vm.writeMemFloat(int(dst), size, value + immediate)
      of vocSubCf: vm.writeMemFloat(int(dst), size, value - immediate)
      of vocMulCf: vm.writeMemFloat(int(dst), size, value * immediate)
      else: discard

    of vocAddi:
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] += cast[ptr int64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] += cast[ptr int32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a + b)

    of vocSubi:
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] -= cast[ptr int64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] -= cast[ptr int32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a - b)

    of vocMuli:
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] *= cast[ptr int64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] *= cast[ptr int32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a * b)

    of vocDivi:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      if b != 0:
        vm.writeMemInt(int(dst), size, a div b)

    of vocMod:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      if b != 0:
        vm.writeMemInt(int(dst), size, a mod b)

    of vocAddf:
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] += cast[ptr float32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemFloat(int(dst), size)
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, a + b)

    of vocSubf:
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] -= cast[ptr float32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemFloat(int(dst), size)
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, a - b)

    of vocMulf:
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] *= cast[ptr float32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemFloat(int(dst), size)
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, a * b)

    of vocMaddf:
      let packedSources = program[vm.pc]
      inc vm.pc
      let mulReg = int(src)
      let rhsReg = int(packedSources and 0xFF'u32) + vm.registerBase
      let addReg = int((packedSources shr 8) and 0xFF'u32) + vm.registerBase
      if size > 4:
        for offset in countup(0, size - 4, 4):
          let lhs = cast[ptr float32](unsafeAddr vm.memory[mulReg + offset])[]
          let rhs = cast[ptr float32](unsafeAddr vm.memory[rhsReg + offset])[]
          let addend = cast[ptr float32](unsafeAddr vm.memory[addReg + offset])[]
          cast[ptr float32](addr vm.memory[int(dst) + offset])[] = lhs * rhs + addend
      elif size == 4:
        let product = cast[ptr float32](unsafeAddr vm.memory[mulReg])[] *
                      cast[ptr float32](unsafeAddr vm.memory[rhsReg])[]
        let addend = cast[ptr float32](unsafeAddr vm.memory[addReg])[]
        cast[ptr float32](addr vm.memory[dst])[] = product + addend
      else:
        let product = vm.readMemFloat(mulReg, size) * vm.readMemFloat(rhsReg, size)
        let addend = vm.readMemFloat(addReg, size)
        vm.writeMemFloat(int(dst), size, product + addend)

    of vocMaddi:
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
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] /= cast[ptr float32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemFloat(int(dst), size)
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, a / b)

    of vocNegi:
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] = -cast[ptr int64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] = -cast[ptr int32](unsafeAddr vm.memory[src])[]
      else:
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, -b)

    of vocNegf:
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] = -cast[ptr float32](unsafeAddr vm.memory[src])[]
      else:
        let b = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(dst), size, -b)

    of vocAnd:
      if size == 8:
        cast[ptr uint64](addr vm.memory[dst])[] = cast[ptr uint64](unsafeAddr vm.memory[dst])[] and cast[ptr uint64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr uint32](addr vm.memory[dst])[] = cast[ptr uint32](unsafeAddr vm.memory[dst])[] and cast[ptr uint32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a and b)

    of vocOr:
      if size == 8:
        cast[ptr uint64](addr vm.memory[dst])[] = cast[ptr uint64](unsafeAddr vm.memory[dst])[] or cast[ptr uint64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr uint32](addr vm.memory[dst])[] = cast[ptr uint32](unsafeAddr vm.memory[dst])[] or cast[ptr uint32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a or b)

    of vocXor:
      if size == 8:
        cast[ptr uint64](addr vm.memory[dst])[] = cast[ptr uint64](unsafeAddr vm.memory[dst])[] xor cast[ptr uint64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr uint32](addr vm.memory[dst])[] = cast[ptr uint32](unsafeAddr vm.memory[dst])[] xor cast[ptr uint32](unsafeAddr vm.memory[src])[]
      else:
        let a = vm.readMemInt(int(dst), size)
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, a xor b)

    of vocNot:
      if size == 8:
        cast[ptr uint64](addr vm.memory[dst])[] = not cast[ptr uint64](unsafeAddr vm.memory[src])[]
      elif size == 4:
        cast[ptr uint32](addr vm.memory[dst])[] = not cast[ptr uint32](unsafeAddr vm.memory[src])[]
      else:
        let b = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(dst), size, not b)

    of vocEqi:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), 1, if a == b: 1 else: 0)

    of vocNeqi:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), 1, if a != b: 1 else: 0)

    of vocLti:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), 1, if a < b: 1 else: 0)

    of vocLei:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), 1, if a <= b: 1 else: 0)

    of vocEqf:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemInt(int(dst), 1, if a == b: 1 else: 0)

    of vocNeqf:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemInt(int(dst), 1, if a != b: 1 else: 0)

    of vocLtf:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemInt(int(dst), 1, if a < b: 1 else: 0)

    of vocLef:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemInt(int(dst), 1, if a <= b: 1 else: 0)

    of vocJmp:
      let target = program[vm.pc]
      vm.pc = int(target)

    of vocJmpFalse:
      let target = program[vm.pc]
      inc vm.pc
      let cond = vm.memory[dst]
      if cond == 0:
        vm.pc = int(target)

    of vocCall:
      if vm.pc + 1 >= program.len:
        vm.halted = true
        break
      let target = int(program[vm.pc])
      let frameInfo = program[vm.pc + 1]
      vm.pc += 2
      let argumentBytes = int(frameInfo and 0xFFFF'u32)
      let frameBytes = int(frameInfo shr 16)
      let argsBase = vm.stack.len - argumentBytes
      let calleeBase = vm.registerBase + int(dst)
      if argsBase < 0 or calleeBase + frameBytes > MAX_MEM:
        vm.halted = true
        break
      vm.callStack.add(CallFrame(returnPc: vm.pc,
        parentRegisterBase: vm.registerBase, parentStackBase: vm.stackBase,
        argsBase: argsBase, returnDst: int(src), returnSize: size,
        calleeRegisterBase: calleeBase))
      vm.registerBase = calleeBase
      vm.stackBase = argsBase
      vm.pc = target

    of vocRet:
      if vm.callStack.len > 0:
        let frame = vm.callStack.pop()
        if frame.returnSize > 0:
          copyMem(addr vm.memory[frame.returnDst],
            unsafeAddr vm.memory[frame.calleeRegisterBase], frame.returnSize)
        vm.stack.setLen(frame.argsBase)
        vm.registerBase = frame.parentRegisterBase
        vm.stackBase = frame.parentStackBase
        vm.pc = frame.returnPc
      else:
        vm.halted = true
        break

    of vocPush:
      let reg = if dst != 0: dst else: src
      let startIdx = vm.stack.len
      vm.stack.setLen(startIdx + size)
      copyMem(addr vm.stack[startIdx], unsafeAddr vm.memory[reg], size)

    of vocPop:
      let popSize = min(size, vm.stack.len)
      if popSize > 0:
        let startIdx = vm.stack.len - popSize
        copyMem(addr vm.memory[dst], unsafeAddr vm.stack[startIdx], popSize)
        vm.stack.setLen(startIdx)

    of vocSMov:
      let offset = vm.stackBase + int(src)
      if offset + size <= vm.stack.len:
        copyMem(addr vm.memory[dst], unsafeAddr vm.stack[offset], size)

    of vocLoad:
      let addrReg = vm.memory[src]
      copyMem(addr vm.memory[dst], unsafeAddr vm.memory[addrReg], size)

    of vocStore:
      let addrReg = vm.memory[dst]
      copyMem(addr vm.memory[addrReg], unsafeAddr vm.memory[src], size)

    of vocLoadUni:
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
      let bufId = int(src)
      let nextW = program[vm.pc]
      inc vm.pc
      var noopOp: VMOpCode
      var idxReg, dummySrc: uint8
      var idxSize: int
      decodeWord(nextW, noopOp, idxReg, dummySrc, idxSize)
      idxReg = uint8(int(idxReg) + vm.registerBase)
      let index = vm.readMemInt(int(idxReg), idxSize)
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
      let bufId = int(src)
      let nextW = program[vm.pc]
      inc vm.pc
      var noopOp: VMOpCode
      var idxReg, dummySrc: uint8
      var idxSize: int
      decodeWord(nextW, noopOp, idxReg, dummySrc, idxSize)
      idxReg = uint8(int(idxReg) + vm.registerBase)
      let index = vm.readMemInt(int(idxReg), idxSize)
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
      let arrBase = int(src)
      let nextW = program[vm.pc]
      inc vm.pc
      var noopOp: VMOpCode
      var idxReg, dummySrc: uint8
      var dummySize: int
      decodeWord(nextW, noopOp, idxReg, dummySrc, dummySize)
      idxReg = uint8(int(idxReg) + vm.registerBase)
      let index = int(vm.readMemInt(int(idxReg), 4))
      let elemAddr = arrBase + index * size
      copyMem(addr vm.memory[dst], unsafeAddr vm.memory[elemAddr], size)

    of vocStoreAt:
      let arrBase = int(src)
      let nextW = program[vm.pc]
      inc vm.pc
      var noopOp: VMOpCode
      var idxReg, dummySrc: uint8
      var dummySize: int
      decodeWord(nextW, noopOp, idxReg, dummySrc, dummySize)
      idxReg = uint8(int(idxReg) + vm.registerBase)
      let index = int(vm.readMemInt(int(idxReg), 4))
      let elemAddr = arrBase + index * size
      copyMem(addr vm.memory[elemAddr], unsafeAddr vm.memory[dst], size)

    of vocLoadGI:
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
      discard # Stage I/O is provided by the GLSL VM, not the CPU interpreter.

    of vocSample2D:
      inc vm.pc # texture id follows; sampling itself is GPU-only

    of vocSampleLod:
      inc vm.pc # packed texture id and LOD register follow; GPU-only

    of vocMmatvec2f:
      let vx = cast[ptr float32](unsafeAddr vm.memory[dst])[]
      let vy = cast[ptr float32](unsafeAddr vm.memory[dst + 4])[]
      let c0x = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let c0y = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let c1x = cast[ptr float32](unsafeAddr vm.memory[src + 8])[]
      let c1y = cast[ptr float32](unsafeAddr vm.memory[src + 12])[]
      cast[ptr float32](addr vm.memory[dst])[] = c0x * vx + c1x * vy
      cast[ptr float32](addr vm.memory[dst + 4])[] = c0y * vx + c1y * vy

    of vocMmatvec2i:
      let vx = cast[ptr int32](unsafeAddr vm.memory[dst])[]
      let vy = cast[ptr int32](unsafeAddr vm.memory[dst + 4])[]
      let c0x = cast[ptr int32](unsafeAddr vm.memory[src])[]
      let c0y = cast[ptr int32](unsafeAddr vm.memory[src + 4])[]
      let c1x = cast[ptr int32](unsafeAddr vm.memory[src + 8])[]
      let c1y = cast[ptr int32](unsafeAddr vm.memory[src + 12])[]
      cast[ptr int32](addr vm.memory[dst])[] = c0x * vx + c1x * vy
      cast[ptr int32](addr vm.memory[dst + 4])[] = c0y * vx + c1y * vy

    of vocMmatvec3f:
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
      let count = max(1, size)
      let sVal = cast[ptr int32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr int32](addr vm.memory[int(dst) + i * 4])[] += sVal

    of vocVecAddf:
      let count = max(1, size)
      let sVal = cast[ptr float32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] += sVal

    of vocVecSubi:
      let count = max(1, size)
      let sVal = cast[ptr int32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr int32](addr vm.memory[int(dst) + i * 4])[] -= sVal

    of vocVecSubf:
      let count = max(1, size)
      let sVal = cast[ptr float32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] -= sVal

    of vocVecMuli:
      let count = max(1, size)
      let sVal = cast[ptr int32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr int32](addr vm.memory[int(dst) + i * 4])[] *= sVal

    of vocVecMulf:
      let count = max(1, size)
      let sVal = cast[ptr float32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] *= sVal

    of vocNormalize:
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
      let ax = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let ay = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let bx = cast[ptr float32](unsafeAddr vm.memory[size])[]
      let by = cast[ptr float32](unsafeAddr vm.memory[size + 4])[]
      cast[ptr float32](addr vm.memory[dst])[] = ax * bx + ay * by

    of vocDot3:
      let ax = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let ay = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let az = cast[ptr float32](unsafeAddr vm.memory[src + 8])[]
      let bx = cast[ptr float32](unsafeAddr vm.memory[size])[]
      let by = cast[ptr float32](unsafeAddr vm.memory[size + 4])[]
      let bz = cast[ptr float32](unsafeAddr vm.memory[size + 8])[]
      cast[ptr float32](addr vm.memory[dst])[] = ax * bx + ay * by + az * bz

    of vocDot4:
      var sum = 0.0'f32
      for i in 0..<4:
        sum += cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[] *
               cast[ptr float32](unsafeAddr vm.memory[int(size) + i * 4])[]
      cast[ptr float32](addr vm.memory[dst])[] = sum

    of vocTranspose2:
      var res: array[4, float32]
      for c in 0..<2:
        for r in 0..<2:
          res[c * 2 + r] = cast[ptr float32](unsafeAddr vm.memory[int(src) + (r * 2 + c) * 4])[]
      copyMem(addr vm.memory[dst], addr res[0], 16)

    of vocTranspose3:
      var res: array[9, float32]
      for c in 0..<3:
        for r in 0..<3:
          res[c * 3 + r] = cast[ptr float32](unsafeAddr vm.memory[int(src) + (r * 3 + c) * 4])[]
      copyMem(addr vm.memory[dst], addr res[0], 36)

    of vocTranspose4:
      var res: array[16, float32]
      for c in 0..<4:
        for r in 0..<4:
          res[c * 4 + r] = cast[ptr float32](unsafeAddr vm.memory[int(src) + (r * 4 + c) * 4])[]
      copyMem(addr vm.memory[dst], addr res[0], 64)

    of vocInvert2:
      let a = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let b = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let c = cast[ptr float32](unsafeAddr vm.memory[src + 8])[]
      let d = cast[ptr float32](unsafeAddr vm.memory[src + 12])[]
      let det = a * d - b * c
      let invDet = if abs(det) > 1e-6'f32: 1.0'f32 / det else: 0.0'f32
      var res = [d * invDet, -b * invDet, -c * invDet, a * invDet]
      copyMem(addr vm.memory[dst], addr res[0], 16)

    of vocInvert3, vocInvert4:
      # Copy through for fallback if general 4x4 inverse not needed on CPU
      copyMem(addr vm.memory[dst], unsafeAddr vm.memory[src], if op == vocInvert3: 36 else: 64)

    of vocReflect2:
      let ix = cast[ptr float32](unsafeAddr vm.memory[dst])[]
      let iy = cast[ptr float32](unsafeAddr vm.memory[dst + 4])[]
      let nx = cast[ptr float32](unsafeAddr vm.memory[src])[]
      let ny = cast[ptr float32](unsafeAddr vm.memory[src + 4])[]
      let dotProd = ix * nx + iy * ny
      cast[ptr float32](addr vm.memory[dst])[] = ix - 2.0'f32 * dotProd * nx
      cast[ptr float32](addr vm.memory[dst + 4])[] = iy - 2.0'f32 * dotProd * ny

    of vocReflect3:
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
      var sumSq = 0.0'f32
      for i in 0..<max(2, size):
        let v = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        sumSq += v * v
      cast[ptr float32](addr vm.memory[dst])[] = sqrt(sumSq)

    of vocRefractf:
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
      for i in 0..<max(1, size):
        let address = int(dst) + i * 4
        let rhs = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        cast[ptr float32](addr vm.memory[address])[] *= rhs

    of vocDeterminantf:
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
      let count = max(1, size)
      let expVal = int(cast[ptr int32](unsafeAddr vm.memory[src])[])
      for i in 0..<count:
        let baseVal = cast[ptr int32](unsafeAddr vm.memory[int(dst) + i * 4])[]
        var r = 1'i32
        for p in 0..<expVal: r *= baseVal
        cast[ptr int32](addr vm.memory[int(dst) + i * 4])[] = r

    of vocPowf:
      let count = max(1, size)
      let expVal = cast[ptr float32](unsafeAddr vm.memory[src])[]
      for i in 0..<count:
        let baseVal = cast[ptr float32](unsafeAddr vm.memory[int(dst) + i * 4])[]
        cast[ptr float32](addr vm.memory[int(dst) + i * 4])[] = pow(baseVal, expVal)

    of vocVecNegf:
      for i in 0..<max(1, size):
        let address = int(dst) + i * sizeof(float32)
        cast[ptr float32](addr vm.memory[address])[] =
          -cast[ptr float32](unsafeAddr vm.memory[address])[]

    of vocVecNegi:
      for i in 0..<max(1, size):
        let address = int(dst) + i * sizeof(int32)
        cast[ptr int32](addr vm.memory[address])[] =
          -cast[ptr int32](unsafeAddr vm.memory[address])[]

    of vocFloorf, vocFractf:
      for i in 0..<max(1, size):
        let address = int(dst) + i * 4
        let value = cast[ptr float32](unsafeAddr vm.memory[int(src) + i * 4])[]
        cast[ptr float32](addr vm.memory[address])[] =
          if op == vocFloorf: floor(value).float32 else: value - floor(value).float32

    of vocStepf, vocSmoothstepf, vocMixf, vocClampf:
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
