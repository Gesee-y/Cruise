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
    memory*: array[MAX_MEM, uint8]
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
  of 1: int64(cast[ptr int8](unsafeAddr vm.memory[address])[])
  of 2: int64(cast[ptr int16](unsafeAddr vm.memory[address])[])
  of 4: int64(cast[ptr int32](unsafeAddr vm.memory[address])[])
  of 8: cast[ptr int64](unsafeAddr vm.memory[address])[]
  else:
    var tmp: int64 = 0
    copyMem(addr tmp, unsafeAddr vm.memory[address], min(size, 8))
    tmp

template writeMemInt(vm: var CpuVm, address: int, size: int, val: int64) =
  case size
  of 1: cast[ptr int8](addr vm.memory[address])[] = int8(val)
  of 2: cast[ptr int16](addr vm.memory[address])[] = int16(val)
  of 4: cast[ptr int32](addr vm.memory[address])[] = int32(val)
  of 8: cast[ptr int64](addr vm.memory[address])[] = val
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
      # If size is 8, the 32-bit immediate is sign-extended or written
      vm.writeMemInt(int(dst), size, int64(cast[int32](imm)))

    of vocLoadf:
      let imm = program[vm.pc]
      inc vm.pc
      let fval = cast[float32](imm)
      vm.writeMemFloat(int(dst), size, float64(fval))

    of vocMov:
      copyMem(addr vm.memory[dst], unsafeAddr vm.memory[src], size)

    of vocAddi:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, a + b)

    of vocSubi:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, a - b)

    of vocMuli:
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
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, a + b)

    of vocSubf:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, a - b)

    of vocMulf:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, a * b)

    of vocDivf:
      let a = vm.readMemFloat(int(dst), size)
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, a / b)

    of vocNegi:
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, -b)

    of vocNegf:
      let b = vm.readMemFloat(int(src), size)
      vm.writeMemFloat(int(dst), size, -b)

    of vocAnd:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, a and b)

    of vocOr:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, a or b)

    of vocXor:
      let a = vm.readMemInt(int(dst), size)
      let b = vm.readMemInt(int(src), size)
      vm.writeMemInt(int(dst), size, a xor b)

    of vocNot:
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
      let cond = vm.readMemInt(int(dst), 1)
      if cond == 0:
        vm.pc = int(target)

    of vocCall:
      # BuiltinOp is dst, target/procPos is program[vm.pc]
      let bop = BuiltinOp(dst)
      let target = program[vm.pc]
      inc vm.pc
      case bop
      of boCustom:
        vm.callStack.add(vm.pc)
        vm.pc = int(target)
      of boAbs:
        let val = vm.readMemInt(int(src), size)
        vm.writeMemInt(int(src), size, abs(val))
      of boMin:
        # Arguments pushed or in registers; handled according to call convention
        discard
      of boMax:
        discard
      of boSqrt:
        let val = vm.readMemFloat(int(src), size)
        vm.writeMemFloat(int(src), size, sqrt(val))

    of vocRet:
      if vm.callStack.len > 0:
        vm.pc = vm.callStack.pop()
      else:
        vm.halted = true
        break

    of vocPush:
      # Push size bytes from memory[dst] (or memory[src])
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
      # Copy from stack parameter at offset src into dst
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
        let totalAvailBytes = (vm.uniform.len - uIdx) * sizeof(uint32)
        let copyBytes = min(size, totalAvailBytes)
        let uBytes = unsafeAddr vm.uniform[uIdx]
        copyMem(addr vm.memory[dst], uBytes, copyBytes)

    of vocLoadBuf:
      let bufId = int(src)
      # Followed by vocNoOp with index register
      let nextW = program[vm.pc]
      inc vm.pc
      var noopOp: VMOpCode
      var idxReg, dummySrc: uint8
      var idxSize: int
      decodeWord(nextW, noopOp, idxReg, dummySrc, idxSize)
      let index = vm.readMemInt(int(idxReg), idxSize)
      let basePtr = cast[uint](vm.buffers[bufId])
      let elemPtr = cast[pointer](basePtr + uint(index * int64(size)))
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
      vm.writeMemInt(int(dst), size, int64(vm.globalId))

    of vocNoOp:
      discard