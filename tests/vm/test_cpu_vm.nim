import std/[syncio, assertions, math]
import ../../src/CVM/deps/vmops
import ../../src/CVM/vms/cpu

proc encodeInst(op: VMOpCode, dst, src: int, size: int = 1): uint32 =
  (uint32(size and 0xFF) shl 24) or (uint32(ord(op) and 0xFF) shl 16) or (uint32(dst and 0xFF) shl 8) or uint32(src and 0xFF)

proc testBasicArithmetic() =
  echo "[TEST] Basic Arithmetic..."
  var vm = initCpuVm()
  var prog: seq[uint32] = @[
    encodeInst(vocLoadi, 0, 0, 4), 10u32,
    encodeInst(vocLoadi, 4, 0, 4), 25u32,
    encodeInst(vocAddi, 0, 4, 4),
    encodeInst(vocLoadi, 12, 0, 4), 2u32,
    encodeInst(vocMov, 8, 0, 4),
    encodeInst(vocMuli, 8, 12, 4),
    encodeInst(vocHalt, 0, 0, 0)
  ]
  vm.runVM(prog)
  let resR0 = cast[ptr int32](addr vm.memory[0])[]
  let resR8 = cast[ptr int32](addr vm.memory[8])[]
  assert resR0 == 35, "Expected R0 == 35, got " & $resR0
  assert resR8 == 70, "Expected R8 == 70, got " & $resR8
  echo "  -> OK (R0=35, R8=70)"

proc testFloatArithmetic() =
  echo "[TEST] Float Arithmetic..."
  var vm = initCpuVm()
  let f1 = cast[uint32](3.5'f32)
  let f2 = cast[uint32](2.0'f32)
  var prog: seq[uint32] = @[
    encodeInst(vocLoadf, 0, 0, 4), f1,
    encodeInst(vocLoadf, 4, 0, 4), f2,
    encodeInst(vocMulf, 0, 4, 4),
    encodeInst(vocHalt, 0, 0, 0)
  ]
  vm.runVM(prog)
  let res = cast[ptr float32](addr vm.memory[0])[]
  assert abs(res - 7.0'f32) < 0.0001, "Expected 7.0, got " & $res
  echo "  -> OK (3.5 * 2.0 = 7.0)"

proc testIntegerFma() =
  echo "[TEST] Integer fused multiply-add..."
  var vm = initCpuVm()
  let program = @[
    encodeInst(vocLoadi, 0, 0, 4), 2'u32,
    encodeInst(vocLoadi, 4, 0, 4), 3'u32,
    encodeInst(vocLoadi, 8, 0, 4), 4'u32,
    encodeInst(vocMaddi, 12, 0, 4), 4'u32 or (8'u32 shl 8),
    encodeInst(vocHalt, 0, 0, 0)
  ]
  vm.runVM(program)
  let result = cast[ptr int32](addr vm.memory[12])[]
  assert result == 10, "Expected integer FMA result 10, got " & $result

  # Exercise the narrow integer path as well.
  var vm8 = initCpuVm()
  let program8 = @[
    encodeInst(vocLoadi, 0, 0, 1), cast[uint32](-10'i32),
    encodeInst(vocLoadi, 1, 0, 1), 3'u32,
    encodeInst(vocLoadi, 2, 0, 1), 1'u32,
    encodeInst(vocMaddi, 3, 0, 1), 1'u32 or (2'u32 shl 8),
    encodeInst(vocHalt, 0, 0, 0)
  ]
  vm8.runVM(program8)
  let narrowResult = cast[ptr int8](addr vm8.memory[3])[]
  assert narrowResult == -29, "Expected int8 FMA result -29, got " & $narrowResult
  echo "  -> int32 and int8 results preserved"

proc testLoopsAndBranches() =
  echo "[TEST] Loops and Conditional Jumps..."
  var vm = initCpuVm()
  var prog: seq[uint32] = @[
    encodeInst(vocLoadi, 0, 0, 4), 0u32,
    encodeInst(vocLoadi, 4, 0, 4), 0u32,
    encodeInst(vocLoadi, 8, 0, 4), 10u32,
    encodeInst(vocLoadi, 16, 0, 4), 1u32,
    encodeInst(vocMov, 12, 4, 4),
    encodeInst(vocLti, 12, 8, 4),
    encodeInst(vocJmpFalse, 12, 0, 1), 16u32,
    encodeInst(vocAddi, 0, 4, 4),
    encodeInst(vocAddi, 4, 16, 4),
    encodeInst(vocJmp, 0, 0, 1), 8u32,
    encodeInst(vocHalt, 0, 0, 0)
  ]
  vm.runVM(prog)
  let sum = cast[ptr int32](addr vm.memory[0])[]
  let i = cast[ptr int32](addr vm.memory[4])[]
  assert sum == 45, "Expected sum == 45, got " & $sum
  assert i == 10, "Expected i == 10, got " & $i
  echo "  -> OK (sum=45, i=10)"

proc testProcedureCall() =
  echo "[TEST] Procedure Call & Return..."
  var vm = initCpuVm()
  var prog: seq[uint32] = @[
    encodeInst(vocLoadi, 0, 0, 4), 5u32,
    encodeInst(vocLoadi, 4, 0, 4), 12u32,
    encodeInst(vocPush, 0, 0, 4),
    encodeInst(vocPush, 4, 0, 4),
    encodeInst(vocCall, 0, 0, 0), 9u32,
    encodeInst(vocHalt, 0, 0, 0),
    encodeInst(vocPop, 8, 0, 4),
    encodeInst(vocPop, 12, 0, 4),
    encodeInst(vocAddi, 8, 12, 4),
    encodeInst(vocRet, 0, 0, 0)
  ]
  vm.runVM(prog)
  let res = cast[ptr int32](addr vm.memory[8])[]
  assert res == 17, "Expected R8 == 17, got " & $res
  echo "  -> OK (call & ret returned 17)"

proc testMemoryModel() =
  echo "[TEST] Memory Model (Uniforms, SSBO, GlobalID)..."
  var buf = @[0'i32, 0'i32, 0'i32, 0'i32, 0'i32]
  var vm = initCpuVm(
    globalId = 42,
    uniforms = @[100u32, 200u32],
    buffers = @[cast[pointer](addr buf[0])]
  )

  var prog: seq[uint32] = @[
    encodeInst(vocLoadGI, 0, 0, 4),
    encodeInst(vocLoadUni, 4, 0, 4),
    encodeInst(vocLoadUni, 8, 1, 4),
    encodeInst(vocAddi, 4, 0, 4),
    encodeInst(vocLoadi, 12, 0, 4), 2u32,
    encodeInst(vocStoreBuf, 4, 0, 4),
    encodeInst(vocNoOp, 12, 0, 0),
    encodeInst(vocLoadBuf, 16, 0, 4),
    encodeInst(vocNoOp, 12, 0, 0),
    encodeInst(vocHalt, 0, 0, 0)
  ]

  vm.runVM(prog)
  let r0 = cast[ptr int32](addr vm.memory[0])[]
  let r4 = cast[ptr int32](addr vm.memory[4])[]
  let r8 = cast[ptr int32](addr vm.memory[8])[]
  let r16 = cast[ptr int32](addr vm.memory[16])[]

  assert r0 == 42, "Expected GI == 42, got " & $r0
  assert r4 == 142, "Expected R4 == 142, got " & $r4
  assert r8 == 200, "Expected U1 == 200, got " & $r8
  assert buf[2] == 142, "Expected buf[2] == 142, got " & $buf[2]
  assert r16 == 142, "Expected R16 == 142, got " & $r16
  echo "  -> OK (GI=42, U1=200, buf[2]=142, R16=142)"

proc testGeneratedObjAndLoopsBytecode() =
  echo "[TEST] Real Compiled Bytecode (test_obj_and_loops.cbc)..."
  var f = open("test_obj_and_loops.cbc", fmRead)
  var data: seq[uint32] = @[]
  var buf: uint32 = 0
  while f.readBuffer(addr buf, sizeof(uint32)) == sizeof(uint32):
    data.add(buf)
  close(f)
  assert data.len > 0, "test_obj_and_loops.cbc is empty"

  # Run testObjConstr starting at address 2
  var vmObj = initCpuVm()
  vmObj.pc = 2
  vmObj.runVM(data)
  # Vec3(x: 10, y: 20, z: 30) -> x at R0, y at R8, z at R16
  # z is copied into R24
  let zVal = cast[ptr int32](addr vmObj.memory[24])[]
  assert zVal == 30, "Expected z == 30, got " & $zVal
  echo "  -> testObjConstr OK (v.z = 30 in R24)"

  # Run testLoops starting at address 10 (0x000A)
  var vmLoop = initCpuVm()
  vmLoop.pc = 10
  vmLoop.runVM(data)
  # In testLoops:
  # while loop runs first: 'a' is at R0. At break, a == 8.
  # then for loop runs:
  # 0x0027: sum = 0 is loaded into R0!
  # for i in 0 ..< 10:
  #   if i == 2: continue
  #   if i == 7: break
  #   sum += i
  # i takes values 0, 1, (2 skip), 3, 4, 5, 6, (7 break)
  # sum = 0 + 1 + 3 + 4 + 5 + 6 = 19 !
  let finalR0 = cast[ptr int32](addr vmLoop.memory[0])[]
  assert finalR0 == 19, "Expected sum == 19, got " & $finalR0
  echo "  -> testLoops OK (for loop sum = 19 in R0 with continue and break)"

proc testVectorAddShader() =
  echo "[TEST] Vector Add Shader with SSBOs & Uniforms (test_vector_add.cbc)..."
  var f = open("test_vector_add.cbc", fmRead)
  var program: seq[uint32] = @[]
  var bufWord: uint32 = 0
  while f.readBuffer(addr bufWord, sizeof(uint32)) == sizeof(uint32):
    program.add(bufWord)
  close(f)
  assert program.len > 0, "test_vector_add.cbc is empty"

  const N = 8
  var a = newSeq[int](N)
  var b = newSeq[int](N)
  var c = newSeq[int](N)

  for i in 0 ..< N:
    a[i] = (i + 1) * 10    # 10, 20, 30, ...
    b[i] = (i + 1) * 5     # 5, 10, 15, ...
    c[i] = 0

  # Simulate dispatching GPU threads: globalId from 0 to N-1
  for gid in 0 ..< N:
    var vm = initCpuVm(globalId = gid)
    # Set uniform length = N (using setUniform helper)
    vm.setUniform(0, N)
    # Bind buffers: 0 = a, 1 = b, 2 = c
    vm.setBuffer(0, cast[pointer](addr a[0]))
    vm.setBuffer(1, cast[pointer](addr b[0]))
    vm.setBuffer(2, cast[pointer](addr c[0]))

    # Run from entry point (program starts with jmp to main at word 0)
    vm.runVM(program)

  # Check results in buffer C: c[i] == a[i] + b[i]
  for i in 0 ..< N:
    let expected = a[i] + b[i]
    assert c[i] == expected, "Index " & $i & ": expected " & $expected & " but got " & $c[i]

  echo "  -> Vector Add OK across " & $N & " simulated GPU threads:"
  for i in 0 ..< N:
    echo "     c[" & $i & "] = " & $a[i] & " + " & $b[i] & " = " & $c[i]

proc testFmaGeneratedBytecode() =
  echo "[TEST] FMA rewrite from test_fma_opt_probe.nim..."
  var f = open("test_fma_opt_probe.cbc", fmRead)
  var program: seq[uint32] = @[]
  var word: uint32
  while f.readBuffer(addr word, sizeof(uint32)) == sizeof(uint32):
    program.add(word)
  close(f)
  assert program.len > 0, "test_fma_opt_probe.cbc is empty"

  # Decode instruction boundaries so an immediate/branch target cannot be
  # mistaken for the FMA opcode.
  var pc = 0
  var fmaCount = 0
  var foundIntegerFma = false
  var foundNegate = false
  while pc < program.len:
    var op: VMOpCode
    var dst, src: uint8
    var size: int
    decodeWord(program[pc], op, dst, src, size)
    if op == vocMaddf:
      inc fmaCount
    elif op == vocMaddi:
      foundIntegerFma = true
    elif op in {vocNegi, vocNegf}:
      foundNegate = true
    inc pc
    case op
    of vocLoadi, vocLoadf, vocCall, vocJmp, vocJmpFalse, vocMaddf, vocMaddi,
       vocLoadBuf, vocStoreBuf, vocLoadAt, vocStoreAt:
      inc pc
    else:
      discard
  assert fmaCount >= 2, "Both FMA operand orders should emit vocMaddf"
  assert foundIntegerFma, "Integer FMA pattern did not emit vocMaddi"
  assert not foundNegate, "Negation rewrite left a redundant negate instruction"

  const N = 4
  var a = @[1.5'f32, 2.0'f32, -3.0'f32, 4.25'f32]
  var b = @[2.0'f32, 3.5'f32, 0.5'f32, -2.0'f32]
  var c = newSeq[float32](N)
  for gid in 0 ..< N:
    var vm = initCpuVm(globalId = gid)
    vm.setUniform(0, N)
    vm.setBuffer(0, cast[pointer](addr a[0]))
    vm.setBuffer(1, cast[pointer](addr b[0]))
    vm.setBuffer(2, cast[pointer](addr c[0]))
    vm.runVM(program)

  for i in 0 ..< N:
    let expected = 2 * a[i] * b[i] + 4 * a[i] + b[i]
    assert abs(c[i] - expected) < 0.0001'f32,
      "FMA/rewrite result at index " & $i & ": expected " & $expected & " got " & $c[i]
  echo "  -> FMA and negation rewrites match expected results"

proc testBuiltinOpcodes() =
  echo "[TEST] Builtin math opcodes..."
  var f = open("test_builtin.cbc", fmRead)
  var program: seq[uint32] = @[]
  var word: uint32
  while f.readBuffer(addr word, sizeof(uint32)) == sizeof(uint32):
    program.add(word)
  close(f)
  assert program.len > 0, "test_builtin.cbc is empty"

  var foundAbs, foundAbsInt, foundMin, foundMinInt = false
  var foundMax, foundMaxInt, foundSqrt, foundRsqrt, foundCall = false
  var pc = 0
  while pc < program.len:
    var op: VMOpCode
    var dst, src: uint8
    var size: int
    decodeWord(program[pc], op, dst, src, size)
    case op
    of vocAbsf: foundAbs = true
    of vocAbsi: foundAbsInt = true
    of vocMinf: foundMin = true
    of vocMini: foundMinInt = true
    of vocMaxf: foundMax = true
    of vocMaxi: foundMaxInt = true
    of vocSqrtf: foundSqrt = true
    of vocRsqrtf: foundRsqrt = true
    of vocCall: foundCall = true
    else: discard
    inc pc
    case op
    of vocLoadi, vocLoadf, vocCall, vocJmp, vocJmpFalse, vocMaddf, vocMaddi,
       vocLoadBuf, vocStoreBuf, vocLoadAt, vocStoreAt:
      inc pc
    else:
      discard

  assert foundAbs, "abs should use a dedicated opcode"
  assert foundAbsInt, "integer abs should use a dedicated opcode"
  assert foundMin, "min should use a dedicated opcode"
  assert foundMinInt, "integer min should use a dedicated opcode"
  assert foundMax, "max should use a dedicated opcode"
  assert foundMaxInt, "integer max should use a dedicated opcode"
  assert foundSqrt, "sqrt should use a dedicated opcode"
  assert foundRsqrt, "1 / sqrt(x) should rewrite to rsqrt"
  assert not foundCall, "Builtin calls should not emit generic vocCall instructions"

  var a = @[-4.0'f32, 9.0'f32, -1.0'f32, 2.25'f32]
  var b = @[1.0'f32, -16.0'f32, 4.0'f32, -1.0'f32]
  var c = newSeq[float32](a.len)
  var ia = @[-7'i64, 2'i64, -1'i64, 8'i64]
  var ib = @[3'i64, -4'i64, 5'i64, -2'i64]
  var ic = newSeq[int64](ia.len)
  for gid in 0 ..< a.len:
    var vm = initCpuVm(globalId = gid)
    vm.setBuffer(0, cast[pointer](addr a[0]))
    vm.setBuffer(1, cast[pointer](addr b[0]))
    vm.setBuffer(2, cast[pointer](addr c[0]))
    vm.setBuffer(3, cast[pointer](addr ia[0]))
    vm.setBuffer(4, cast[pointer](addr ib[0]))
    vm.setBuffer(5, cast[pointer](addr ic[0]))
    vm.runVM(program)

  for i in 0 ..< a.len:
    let expected = abs(a[i]) + min(a[i], b[i]) + max(a[i], b[i]) +
                   sqrt(abs(b[i])) + 1.0'f32 / sqrt(abs(a[i]))
    assert abs(c[i] - expected) < 0.0001'f32,
      "Builtin result at index " & $i & ": expected " & $expected & " got " & $c[i]
    let expectedInt = abs(ia[i]) + min(ia[i], ib[i]) + max(ia[i], ib[i])
    assert ic[i] == expectedInt,
      "Integer builtin result at index " & $i & ": expected " & $expectedInt & " got " & $ic[i]
  echo "  -> abs/min/max/sqrt/rsqrt opcodes and results verified"

proc main() =
  echo "==================== CPU VM TEST SUITE ===================="
  testBasicArithmetic()
  testFloatArithmetic()
  testIntegerFma()
  testLoopsAndBranches()
  testProcedureCall()
  testMemoryModel()
  testGeneratedObjAndLoopsBytecode()
  testVectorAddShader()
  testFmaGeneratedBytecode()
  testBuiltinOpcodes()
  echo "================ ALL TESTS PASSED SUCCESSFULLY ================"

main()
