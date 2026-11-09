import std/[math]
import ../deps/vmops

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
    memory* {.align: 8.}: array[MAX_MEM, uint8]
    buffers*: seq[pointer]
    callStack*: seq[int]
    stack*: seq[uint8]
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
  size = int((word shr SIZE_POS) and 0xFF'u32)
  if size == 0: size = 1
  op   = VMOpCode((word shr OPCODE_POS) and 0xFF'u32)
  dst  = uint8((word shr REGA_POS) and 0xFF'u32)
  src  = uint8(word and 0xFF'u32)

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

    case op
    of vocHalt:
      vm.halted = true
      break

    of vocLoadi:
      let imm = program[vm.pc]
      inc vm.pc
      if size == 8:
        cast[ptr int64](addr vm.memory[dst])[] = int64(cast[int32](imm))
      elif size == 4:
        cast[ptr int32](addr vm.memory[dst])[] = cast[int32](imm)
      else:
        vm.writeMemInt(int(dst), size, int64(cast[int32](imm)))

    of vocLoadf:
      let imm = program[vm.pc]
      inc vm.pc
      let fval = cast[float32](imm)
      if size == 4:
        cast[ptr float32](addr vm.memory[dst])[] = fval
      else:
        vm.writeMemFloat(int(dst), size, float64(fval))

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
      let rhsReg = int(packedSources and 0xFF'u32)
      let addReg = int((packedSources shr 8) and 0xFF'u32)
      if size == 4:
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
      let rhsReg = int(packedSources and 0xFF'u32)
      let addReg = int((packedSources shr 8) and 0xFF'u32)
      let product = vm.readMemInt(mulReg, size) * vm.readMemInt(rhsReg, size)
      # Preserve the intermediate-width truncation of separate multiply/add
      # instructions for int8 and int16 values.
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
      let target = program[vm.pc]
      inc vm.pc
      vm.callStack.add(vm.pc)
      vm.pc = int(target)

    of vocRet:
      if vm.callStack.len > 0:
        vm.pc = vm.callStack.pop()
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
      let offset = int(src)
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
