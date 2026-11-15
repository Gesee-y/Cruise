  # ###################################################################################################################################### #
 # ########################################################## CODE GENERATOR ############################################################ #
# ###################################################################################################################################### #

# ################################################################################################################################ #
# ############################################################ TYPES ############################################################# #
# ################################################################################################################################ #

type
  CMemLoc = int ## Virtual-memory byte address.

  # Function call data
  # The position to the function + the current stack size will get patched in the call
  CallPatch = object
    targetPos: int
    frameInfoPos: int

  CBytecode = object
    data: seq[uint32]
    allocator: CVramAllocator
    ## Maps each proc name to its starting word index in `data`.
    ## Entries start at -1 (placeholder) and are backpatched by `genFunc`.
    procTable: Table[string, int]
    callToPatch: Table[string, seq[CallPatch]]
    frameSizes: Table[string, int]
    currentPos: int

  LoopContext = object
    continueTarget: int        ## Target word index for continue (if >= 0)
    continuePatches: seq[int]   ## Positions to backpatch for continue jumps
    breakPatches: seq[int]   ## Positions to backpatch for break jumps

  CodeGenCtx = object
    cache: TypeCache
    code: CBytecode
    entryPoint: int
    currentProcName: string
    loops: seq[LoopContext]

# ################################################################################################################################ #
# ############################################################ CONSTANTS ######################################################### #
# ################################################################################################################################ #

const
  INT_SIZE    = 4
  FLOAT_SIZE  = 4
  CHAR_SIZE   = 1
  OPCODE_BITS = 8
  REGA_BITS   = 8
  REGB_BITS   = 8
  REGA_POS    = REGB_BITS            ##  8: shift for the destination field
  OPCODE_POS  = REGA_POS + REGA_BITS ## 16: shift for the opcode field
  SIZE_POS    = 24                   ## 24: shift for the size field (unused 8 bits)
  REG_MASK    = 0xFF

# ################################################################################################################################ #
# ########################################################## HELPER PROCS ######################################################## #
# ################################################################################################################################ #

# Translate a string op to a vm opcode
# Mostly just arithmethics for infix
# Pretty straight forward
proc opcodeFor(op: string, isFloat: bool): VMOpCode =
  case op
  of "+":
    if isFloat: return vocAddf 
    else: return vocAddi
  of "-":
    if isFloat: return vocSubf 
    else: return vocSubi
  of "*":
    if isFloat: return vocMulf 
    else: return vocMuli
  of "/":
    if isFloat: return vocDivf 
    else: return vocDivi
  of "%", "mod":
    vocMod
  of "and":
    vocAnd
  of "or":
    vocOr
  of "xor":
    vocXor
  of "==":
    if isFloat: return vocEqf 
    else: return vocEqi
  of "!=":
    if isFloat: return vocNeqf 
    else: return vocNeqi
  # There is no `>` and `>=` in nimony since their are just template
  # For `a > b` it just generate `b < a`
  of "<":
    if isFloat: return vocLtf 
    else: return vocLti
  of "<=":
    if isFloat: return vocLef 
    else: return vocLei

  # This path is almost impossible the get to, since the check is done before entering the function so.
  else: assert false, "Failed to get infix opcode for `" & op & "`."

# Get the opcode but for immediate values
proc immediateOpcodeFor(op: string, isFloat: bool): VMOpCode =
  case op
  of "+":
    if isFloat: vocAddCf else: vocAddCi
  of "-":
    if isFloat: vocSubCf else: vocSubCi
  of "*":
    if isFloat: vocMulCf else: vocMulCi
  else: assert false, "No immediate opcode for `" & op & "`."

# Same but fetch opcode for prefix operations
proc prefixOpcodeFor(op: string, isFloat: bool): VMOpCode =
  case op
  of "not":
    vocNot
  of "-":
    if isFloat: return vocNegf 
    else: return vocNegi
  else: assert false, "Failed to get prefix opcode for `" & op & "`."

# Get us the conversion selector for a cnkConv when used on a runtime value
proc conversionType(cache: TypeCache, typeName: string): VMConvType =
  let name = cache.equivalences.getOrDefault(typeName, typeName).split(".")[0]
  case name
  of "int", "int32": vctInt32
  of "int8": vctInt8
  of "int16": vctInt16
  of "int64": vctInt64
  of "uint", "uint8", "char": vctUInt8
  of "uint16": vctUInt16
  of "uint32": vctUInt32
  of "uint64": vctUInt64
  of "float", "float32": vctFloat32
  of "float64": vctFloat64
  of "bool": vctBool
  else: assert false, "Unsupported conversion type: " & typeName

# Generate one intruction of any kind
# The layout is [size - 1 byte] [op - 1 byte] [reg1 - one byte] [reg2 - one byte] 
proc genInstruction(op: VMOpCode, dst, src: CMemLoc, size: int = 1): uint32 {.inline.} =
  (uint32(size and 0xFF) shl SIZE_POS) or (uint32(op) shl OPCODE_POS) or (uint32(dst and 0xFF) shl REGA_POS) or uint32(src and 0xFF)

proc emitInst(ctx: var CodeGenCtx, op: VMOpCode, dst, src: CMemLoc, size: int = 1) {.inline.} =
  ctx.code.data.add(genInstruction(op, dst, src, size))
  inc ctx.code.currentPos

proc emitWord(ctx: var CodeGenCtx, word: uint32) {.inline.} =
  ctx.code.data.add(word)
  inc ctx.code.currentPos

# Fetch a literal value under all the potential wrapper it could have
proc unwrapLiteral(node: CIRNode): CIRNode =
  result = node
  while result.kind in {cnkConv, cnkCast} and result.args.len > 0:
    result = result.args[^1]

proc isImmediateLiteral(node: CIRNode): bool =
  unwrapLiteral(node).isLit

# Get the bits of an immediate value
proc immediateBits(node: CIRNode, isFloat: bool, size: int): uint64 =
  let literal = unwrapLiteral(node)
  if isFloat:
    var value: float64
    case literal.kind
    # Integers needs a conversion to float first because they aren't represented in the same way as float
    of cnkIntLit: value = float64(literal.intVal)
    of cnkUintLit: value = float64(literal.uintVal)
    of cnkFloatLit: value = literal.floatVal
    else: assert false, "Expected numeric immediate literal"
    if size <= 4:
      return uint64(cast[uint32](float32(value)))
    return cast[uint64](value)

  case literal.kind
  of cnkIntLit: cast[uint64](int64(literal.intVal))
  of cnkUintLit: uint64(literal.uintVal)
  else: assert false, "Expected integer immediate literal"

# Emit instructions for an immediate value
# Immediates can't be greater than 4 bytes (needed to make them fit in the bytecode)
proc emitImmediate(ctx: var CodeGenCtx, op: VMOpCode, dst: CMemLoc,
                   value: uint64, size: int) =
  ctx.emitInst(op, dst, 0, size)
  ctx.emitWord(uint32(value and 0xFFFF_FFFF'u64))

# If an allocation is a temporary one, it should get freed
proc freeIfTemp(ctx: var CodeGenCtx, alloc: CAllocation) {.inline.} =
  if alloc.isTemp:
    ctx.code.allocator.free(alloc)

# Directly emit instruction for builtin functions
proc builtinOpcode(name, typeName: string): VMOpCode =
  let isFloat = typeName.isFloatName
  let isUnsigned = typeName.isUintName
  case name
  of "abs":
    if isFloat: vocAbsf
    elif isUnsigned: vocAbsu
    else: vocAbsi
  of "min":
    if isFloat: vocMinf
    elif isUnsigned: vocMinu
    else: vocMini
  of "max":
    if isFloat: vocMaxf
    elif isUnsigned: vocMaxu
    else: vocMaxi
  of "sqrt": vocSqrtf
  of "rsqrt", "inversesqrt": vocRsqrtf
  of "cos": vocCosf
  of "sin": vocSinf
  of "floor": vocFloorf
  of "fract": vocFractf
  of "sample": vocSample2D
  else: assert false, "Unsupported builtin opcode: " & name

proc unaryMathSelector(name: string): VMMathSelector =
  case name
  of "tan": vmsTan
  of "asin": vmsAsin
  of "acos": vmsAcos
  of "atan": vmsAtan
  of "exp": vmsExp
  of "log": vmsLog
  of "exp2": vmsExp2
  of "log2": vmsLog2
  of "ceil": vmsCeil
  of "trunc": vmsTrunc
  of "round": vmsRound
  of "sign": vmsSign
  of "radians": vmsRadians
  of "degrees": vmsDegrees
  of "sinh": vmsSinh
  of "cosh": vmsCosh
  of "tanh": vmsTanh
  of "asinh": vmsAsinh
  of "acosh": vmsAcosh
  of "atanh": vmsAtanh
  of "abs": vmsAbs
  of "inversesqrt": vmsInversesqrt
  else: assert false, "Unsupported unary shading function: " & name

# ################################################################################################################################ #
# ##################################################### VARIABLE RESOLUTION ###################################################### #
# ################################################################################################################################ #

# Try to get the allocation for a symbol node
proc resolveSymbol(ctx: var CodeGenCtx, c: CIRNode): CAllocation =
  if c.name in ctx.cache.liveness:
    let l = ctx.cache.liveness.getOrDefault(c.name)
    return ctx.code.allocator.lookup(l.birth.line, l.birth.col)
  else:
    return CAllocation(pos: -1)

# Fetch the allocation for the field path (a.x.y.z) or a node
proc getFieldReg(ctx: var CodeGenCtx, baseReg: CAllocation, c: CIRNode): CAllocation =
  result = baseReg
  var offset = 0
  var dummyArg0 = c.args[0]
  var basetype = ctx.cache.inferType(dummyArg0)
  var currentType = basetype
  var current = c.args[1]

  # We just successively fetch fields and add their offset to the result
  while current.kind == cnkDotExpr:
    let f = current.args[0].name.split(".")[0]
    let fid = ctx.cache.getType(currentType).nameToId.getOrDefault(f, -1)
    current = current.args[1]

    if fid >= 0:
      let field = addr ctx.cache.getType(currentType).fields[fid]
      offset += field.offset
      currentType = field.ty
  
  # Getting the last field
  let f = current.name.split(".")[0]
  let fid = ctx.cache.getType(currentType).nameToId.getOrDefault(f, -1)
  if fid >= 0:
    let field = ctx.cache.getType(currentType).fields[fid]
    offset += field.offset
    currentType = field.ty
  result.pos += offset
  result.size = ctx.cache.getType(currentType).size
  result.isTemp = false # Should not be freed, only the master register can get freed

# ################################################################################################################################ #
# ############################################################# EXPRESSIONS ###################################################### #
# ################################################################################################################################ #

proc getMatVecMulCode(op, lhsTyName, rhsTyName: string): VMOpCode =
  result = vocNoOp
  if op == "*" and lhsTyName.startsWith("mat") and rhsTyName.startsWith("vec"):
    if lhsTyName == "mat2f" and rhsTyName == "vec2f": 
      result = vocMmatvec2f
    elif lhsTyName == "mat2i" and rhsTyName == "vec2i": 
      result = vocMmatvec2i
    elif lhsTyName == "mat3f" and rhsTyName == "vec3f": 
      result = vocMmatvec3f
    elif lhsTyName == "mat3i" and rhsTyName == "vec3i": 
      result = vocMmatvec3i
    elif lhsTyName == "mat4f" and (rhsTyName == "vec4f" or rhsTyName == "vec3f"): 
      result = vocMmatvec4f
    elif lhsTyName == "mat4i" and (rhsTyName == "vec4i" or rhsTyName == "vec3i"): 
      result = vocMmatvec4i

proc getMatMulCode(op, lhsTyName, rhsTyName: string): VMOpCode =
  result = vocNoOp
  if op == "*" and lhsTyName.startsWith("mat") and rhsTyName.startsWith("mat"):
    if lhsTyName == "mat2f" and rhsTyName == "mat2f": result = vocMmat2f
    elif lhsTyName == "mat2i" and rhsTyName == "mat2i": result = vocMmat2i
    elif lhsTyName == "mat3f" and rhsTyName == "mat3f": result = vocMmat3f
    elif lhsTyName == "mat3i" and rhsTyName == "mat3i": result = vocMmat3i
    elif lhsTyName == "mat4f" and rhsTyName == "mat4f": result = vocMmat4f
    elif lhsTyName == "mat4i" and rhsTyName == "mat4i": result = vocMmat4i

proc getVecScalarMulCode(op, lhsTyName, rhsTyName: string): tuple[code: VMOpCode, size: int] =
  result = (vocNoOp, 0)
  let isLhsVec = lhsTyName.startsWith("vec")
  let isRhsVec = rhsTyName.startsWith("vec")
  if (isLhsVec and not isRhsVec) or (isRhsVec and not isLhsVec):
    let vecTyName = if isLhsVec: lhsTyName else: rhsTyName
    let vecDim = if vecTyName.contains("2"): 2 elif vecTyName.contains("3"): 3 else: 4
    let opIsFloat = vecTyName.endsWith("f")
    result.size = vecDim * 4
    
    case op
    of "*": result.code = if opIsFloat: vocVecMulf else: vocVecMuli
    of "+": result.code = if opIsFloat: vocVecAddf else: vocVecAddi
    of "-": result.code = if opIsFloat: vocVecSubf else: vocVecSubi
    else: discard

# Generate the bytecode for a given expression in the register `target` if valid
proc genExpr(ctx: var CodeGenCtx, c: CIRNode, target: CAllocation = CAllocation(pos: -1)): CAllocation =
  result = default(CAllocation)
  case c.kind
  of cnkInfix:
    let opName = c.args[0].name
    let opTypeName = ctx.cache.inferType(c)
    let isCmp = opName in ["<", "<=", "==", "!="]
    let operandTyName = ctx.cache.inferType(c.args[1])
    let opIsFloat  = operandTyName.isFloatName or
      (operandTyName.startsWith("vec") and operandTyName.endsWith("f"))
    let operandTy = ctx.cache.getType(operandTyName)
    let opSize = operandTy.size
    let retSize = ctx.cache.getType(opTypeName).size

    var lhsNode = c.args[1]
    var rhsNode = c.args[2]

    let lhsTyName = ctx.cache.inferType(lhsNode)
    let rhsTyName = ctx.cache.inferType(rhsNode)

    var mmatvecOp = getMatVecMulCode(opName, lhsTyName, rhsTyName)
    if mmatvecOp != vocNoOp:
      let r1 = ctx.genExpr(lhsNode)
      let r2 = ctx.genExpr(rhsNode)
      result = if target.size >= retSize: target else: ctx.code.allocator.alloc(retSize)
      if result.pos != r2.pos:
        ctx.emitInst(vocMov, result.pos, r2.pos, r2.size)
      ctx.emitInst(mmatvecOp, result.pos, r1.pos, r2.size)
      ctx.freeIfTemp(r1)
      ctx.freeIfTemp(r2)
      return

    var mmatOp = getMatMulCode(opName, lhsTyName, rhsTyName)
    if mmatOp != vocNoOp:
      let r1 = ctx.genExpr(lhsNode)
      let r2 = ctx.genExpr(rhsNode)
      let retSize = max(1, operandTy.size)
      result = if target.size >= retSize: target else: ctx.code.allocator.alloc(retSize)
      if result.pos != r1.pos:
        ctx.emitInst(vocMov, result.pos, r1.pos, retSize)
      ctx.emitInst(mmatOp, result.pos, r2.pos, retSize)
      ctx.freeIfTemp(r1)
      ctx.freeIfTemp(r2)
      return


    let vecMulResult = getVecScalarMulCode(opName, lhsTyName, rhsTyName)
    let vecOp = vecMulResult.code
    let vecSize = vecMulResult.size
    if vecOp != vocNoOp:
      let rVec = ctx.genExpr(lhsNode)
      let rScalar = ctx.genExpr(rhsNode)
      let vecDim = vecSize div 4
      result = if target.size >= vecSize: target else: ctx.code.allocator.alloc(vecSize)
      if result.pos != rVec.pos:
        ctx.emitInst(vocMov, result.pos, rVec.pos, vecSize)
      ctx.emitInst(vecOp, result.pos, rScalar.pos, vecDim)
      ctx.freeIfTemp(rVec)
      ctx.freeIfTemp(rScalar)
      return

    # Addition and multiplication are commutative, so put a literal on the
    # immediate side regardless of which operand it appeared on.
    if opName in ["+", "*"] and lhsNode.isImmediateLiteral and
       not rhsNode.isImmediateLiteral:
      swap(lhsNode, rhsNode)

    # Generate immediate operations instead of a load + op we do a variant with the second operand as a constant
    if opName in ["+", "-", "*"] and rhsNode.isImmediateLiteral:
      let lhs = ctx.genExpr(lhsNode)
      result = if target.pos != -1: target else: ctx.code.allocator.alloc(opSize)
      if result.pos != lhs.pos:
        ctx.emitInst(vocMov, result.pos, lhs.pos, opSize)
      let imm = immediateBits(rhsNode, opIsFloat, opSize)
      ctx.emitImmediate(immediateOpcodeFor(opName, opIsFloat), result.pos, imm, opSize)
      ctx.freeIfTemp(lhs)
      return

    # Generating regular opcode
    # Use `load` for constant
    # etc etc 
    let r1 = ctx.genExpr(lhsNode)
    let r2 = ctx.genExpr(rhsNode)

    if target.pos != -1:
      result = target
    else:
      result = ctx.code.allocator.alloc(opSize)

    if result.pos == r1.pos:
      ctx.emitInst(opcodeFor(opName, opIsFloat), result.pos, r2.pos, opSize)
    elif result.pos == r2.pos and opName in ["+", "*", "and", "or", "xor", "==", "!="]:
      ctx.emitInst(opcodeFor(opName, opIsFloat), result.pos, r1.pos, opSize)
    else:
      ctx.emitInst(vocMov, result.pos, r1.pos, opSize)
      ctx.emitInst(opcodeFor(opName, opIsFloat), result.pos, r2.pos, opSize)

    ctx.freeIfTemp(r1)
    ctx.freeIfTemp(r2)
    return

  of cnkFma:
    # The instruction size carries the scalar/vector byte size. The trailing
    # word carries only the two additional source registers.
    var lhsNode = c.args[0]
    let tyName = ctx.cache.inferType(lhsNode)
    let ty = ctx.cache.getType(tyName)
    let opSize = max(1, ty.size)
    let isVector = tyName.startsWith("vec")
    let isFloat = tyName.startsWith("float") or
      (isVector and tyName.endsWith("f"))

    let lhs = ctx.genExpr(c.args[0])
    let rhs = ctx.genExpr(c.args[1])
    let addend = ctx.genExpr(c.args[2])
    result = if target.size >= opSize: target else: ctx.code.allocator.alloc(opSize)

    ctx.emitInst(if isFloat: vocMaddf else: vocMaddi,
                 result.pos, lhs.pos, opSize)
    ctx.emitWord(uint32(rhs.pos and REG_MASK) or
                 (uint32(addend.pos and REG_MASK) shl 8))

    if target.pos != -1 and result.pos != target.pos:
      ctx.emitInst(vocMov, target.pos, result.pos, opSize)
      ctx.code.allocator.free(result)
      result = target

    ctx.freeIfTemp(lhs)
    ctx.freeIfTemp(rhs)
    ctx.freeIfTemp(addend)
    return

  of cnkRsqrt:
    # Reciprocal square root, almost never explicitly written by the user
    # Result from the term rewriter
    var argNode = c.args[0]
    let typeName = ctx.cache.inferType(argNode)
    let size = max(1, ctx.cache.getType(typeName).size)
    let arg = ctx.genExpr(c.args[0])
    result = if target.size >= size: target else: ctx.code.allocator.alloc(size)
    ctx.emitInst(vocRsqrtf, result.pos, arg.pos, size)
    ctx.freeIfTemp(arg)
    return

  of cnkPrefix:
    # Prefix operations, those use only one register as both source and destination (this is `unary` in general)
    let opName = c.args[0].name
    var dummyNode = c
    let opTypeName = ctx.cache.inferType(dummyNode)
    let opIsFloat  = opTypeName.startsWith("float")
    let opTy = ctx.cache.getType(opTypeName)
    let opSize = max(1, opTy.size)
    let operand = ctx.genExpr(c.args[1])

    if opName == "-" and opTypeName.startsWith("vec"):
      result = if target.size >= opSize: target
               else: ctx.code.allocator.alloc(opSize)
      if result.pos != operand.pos:
        ctx.emitInst(vocMov, result.pos, operand.pos, opSize)
      let dim = opSize div sizeof(float32)
      let op = if opTypeName.endsWith("f"): vocVecNegf else: vocVecNegi
      ctx.emitInst(op, result.pos, 0, dim)
      ctx.freeIfTemp(operand)
      return
    
    if target.size >= opSize:
      result = target
    else:
      result = ctx.code.allocator.alloc(opSize)

    ctx.emitInst(prefixOpcodeFor(opName, opIsFloat), result.pos, operand.pos, opSize)
    ctx.freeIfTemp(operand)
    return

  of cnkDotExpr:
    # Field access, a solved problem since 100 loc
    let base = ctx.genExpr(c.args[0])
    let fieldAlloc = ctx.getFieldReg(base, c)
    if target.size > 0 and target.pos != fieldAlloc.pos:
      let wordsToCopy = max(1, min(target.size, fieldAlloc.size))
      ctx.emitInst(vocMov, target.pos, fieldAlloc.pos, wordsToCopy)
      result = target
    else:
      result = fieldAlloc
    return

  of cnkCall:
    # Functions calls
    # If we encounter a predefined unary ops, then we generate the generic VMop for it
    let procName = c.args[0].name
    if procName in ["tan", "asin", "acos", "atan", "exp", "log", "exp2",
                    "log2", "ceil", "trunc", "round", "sign", "radians",
                    "degrees", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
                    "inversesqrt"] and c.args.len == 2:
      let arg = ctx.genExpr(c.args[1])
      let tyName = ctx.cache.inferType(c.args[1])
      let argSize = max(4, ctx.cache.getType(tyName).size)
      let lanes = argSize div 4
      result = if target.size >= argSize: target else: ctx.code.allocator.alloc(argSize)
      ctx.emitInst(vocUnaryMathf, result.pos, arg.pos, lanes)
      ctx.emitWord(uint32(unaryMathSelector(procName)))
      ctx.freeIfTemp(arg)
      return

    # If we encounter a variant of `abs` (the vectorial one)
    if procName == "abs" and c.args.len == 2 and
       ctx.cache.inferType(c.args[1]).startsWith("vec"):
      let arg = ctx.genExpr(c.args[1])
      let tyName = ctx.cache.inferType(c.args[1])
      let argSize = max(4, ctx.cache.getType(tyName).size)
      result = if target.size >= argSize: target else: ctx.code.allocator.alloc(argSize)
      ctx.emitInst(vocUnaryMathf, result.pos, arg.pos, argSize div 4)
      ctx.emitWord(uint32(unaryMathSelector("abs")))
      ctx.freeIfTemp(arg)
      return

    # If we encounter vectorial binary ops
    if procName in ["atan", "mod", "min", "max"] and c.args.len == 3 and
       (procName in ["atan", "mod"] or ctx.cache.inferType(c.args[1]).startsWith("vec")):
      let lhs = ctx.genExpr(c.args[1])
      let rhs = ctx.genExpr(c.args[2])
      let tyName = ctx.cache.inferType(c.args[1])
      let resultSize = max(4, ctx.cache.getType(tyName).size)
      let lanes = resultSize div 4
      result = if target.size >= resultSize: target else: ctx.code.allocator.alloc(resultSize)
      if result.pos != lhs.pos:
        ctx.emitInst(vocMov, result.pos, lhs.pos, resultSize)
      let selector = case procName
        of "atan": 0'u32
        of "mod": 1'u32
        of "min": 2'u32
        else: 3'u32
      let broadcast = lanes > 1 and rhs.size == 4
      ctx.emitInst(vocBinaryMathf, result.pos, rhs.pos, lanes)
      ctx.emitWord(selector or (if broadcast: 0x100'u32 else: 0'u32))
      ctx.freeIfTemp(lhs)
      ctx.freeIfTemp(rhs)
      return

    if procName == "faceforward":
      let normal = ctx.genExpr(c.args[1])
      let incident = ctx.genExpr(c.args[2])
      let refNormal = ctx.genExpr(c.args[3])
      let tyName = ctx.cache.inferType(c.args[1])
      let size = max(8, ctx.cache.getType(tyName).size)
      let lanes = size div 4
      result = if target.size >= size: target else: ctx.code.allocator.alloc(size)
      if result.pos != normal.pos:
        ctx.emitInst(vocMov, result.pos, normal.pos, size)
      ctx.emitInst(vocFaceforward, result.pos, incident.pos, lanes)
      ctx.emitWord(uint32(refNormal.pos and REG_MASK))
      ctx.freeIfTemp(normal)
      ctx.freeIfTemp(incident)
      ctx.freeIfTemp(refNormal)
      return

    if procName in ["abs", "sqrt", "rsqrt", "inversesqrt", "sin", "cos", "floor", "fract"]:
      var argNode = c.args[1]
      let typeName = ctx.cache.inferType(argNode)
      let size = max(1, ctx.cache.getType(typeName).size)
      let arg = ctx.genExpr(c.args[1])
      result = if target.size >= size: target else: ctx.code.allocator.alloc(size)
      let op = builtinOpcode(procName, typeName)
      if op == vocAbsu:
        if result.pos != arg.pos:
          ctx.emitInst(vocMov, result.pos, arg.pos, size)
      else:
        let opSize = if op in {vocFloorf, vocFractf}: max(1, size div 4) else: size
        ctx.emitInst(op, result.pos, arg.pos, opSize)
      ctx.freeIfTemp(arg)
      return

    if procName in ["mix", "lerp", "smoothstep", "step", "clamp"]:
      let resultArgIndex = if procName == "step": 2
                           elif procName == "smoothstep": 3
                           else: 1
      let resultNode = c.args[resultArgIndex]
      let resultTy = ctx.cache.inferType(resultNode)
      let resultSize = max(4, ctx.cache.getType(resultTy).size)
      let lanes = max(1, resultSize div 4)
      let value = ctx.genExpr(resultNode, target = target)
      result = value
      var descriptor = 0'u32
      var secondOperand = CAllocation(pos: -1)
      var thirdOperand = CAllocation(pos: -1)
      var op = vocNoOp

      case procName
      of "step":
        op = vocStepf
        secondOperand = ctx.genExpr(c.args[1]) # edge
        if ctx.cache.getType(ctx.cache.inferType(c.args[1])).size == 4 and lanes > 1:
          descriptor = descriptor or 0x100'u32
      of "smoothstep":
        op = vocSmoothstepf
        secondOperand = ctx.genExpr(c.args[1]) # edge0
        thirdOperand = ctx.genExpr(c.args[2]) # edge1
        descriptor = uint32(thirdOperand.pos and REG_MASK)
        if ctx.cache.getType(ctx.cache.inferType(c.args[1])).size == 4 and lanes > 1:
          descriptor = descriptor or 0x100'u32
        if ctx.cache.getType(ctx.cache.inferType(c.args[2])).size == 4 and lanes > 1:
          descriptor = descriptor or 0x200'u32
      of "mix", "lerp":
        op = vocMixf
        secondOperand = ctx.genExpr(c.args[2]) # y
        thirdOperand = ctx.genExpr(c.args[3]) # factor
        descriptor = uint32(thirdOperand.pos and REG_MASK)
        if ctx.cache.getType(ctx.cache.inferType(c.args[3])).size == 4 and lanes > 1:
          descriptor = descriptor or 0x100'u32
      of "clamp":
        op = vocClampf
        secondOperand = ctx.genExpr(c.args[2]) # lower bound
        thirdOperand = ctx.genExpr(c.args[3]) # upper bound
        descriptor = uint32(thirdOperand.pos and REG_MASK)
        if ctx.cache.getType(ctx.cache.inferType(c.args[2])).size == 4 and lanes > 1:
          descriptor = descriptor or 0x100'u32
        if ctx.cache.getType(ctx.cache.inferType(c.args[3])).size == 4 and lanes > 1:
          descriptor = descriptor or 0x200'u32
      else:
        discard

      ctx.emitInst(op, result.pos, secondOperand.pos, lanes)
      ctx.emitWord(descriptor)
      ctx.freeIfTemp(secondOperand)
      ctx.freeIfTemp(thirdOperand)
      return

    if procName in ["min", "max"]:
      var leftNode = c.args[1]
      let typeName = ctx.cache.inferType(leftNode)
      let size = max(1, ctx.cache.getType(typeName).size)
      let left = ctx.genExpr(c.args[1])
      let right = ctx.genExpr(c.args[2])
      result = if target.size >= size: target else: ctx.code.allocator.alloc(size)
      let op = builtinOpcode(procName, typeName)
      if result.pos == left.pos:
        ctx.emitInst(op, result.pos, right.pos, size)
      elif result.pos == right.pos:
        ctx.emitInst(op, result.pos, left.pos, size)
      else:
        ctx.emitInst(vocMov, result.pos, left.pos, size)
        ctx.emitInst(op, result.pos, right.pos, size)
      ctx.freeIfTemp(left)
      ctx.freeIfTemp(right)
      return

    if procName == "sample":
      let texName = c.args[1].name
      let texId = ctx.cache.shaderParams.textureToId.getOrDefault(texName, 0)
      let uvAlloc = ctx.genExpr(c.args[2])
      let size = 16 # vec4f output
      result = if target.pos != -1: target else: ctx.code.allocator.alloc(size)
      ctx.emitInst(vocSample2D, result.pos, uvAlloc.pos, size)
      ctx.emitWord(uint32(texId))
      ctx.freeIfTemp(uvAlloc)
      return

    if procName in ["sampleLod", "textureLod"]:
      let texName = c.args[1].name
      let texId = ctx.cache.shaderParams.textureToId.getOrDefault(texName, 0)
      let uvAlloc = ctx.genExpr(c.args[2])
      let lodAlloc = ctx.genExpr(c.args[3])
      result = if target.size >= 16: target else: ctx.code.allocator.alloc(16)
      ctx.emitInst(vocSampleLod, result.pos, uvAlloc.pos, 4)
      ctx.emitWord(uint32(texId and 0xFF) or (uint32(lodAlloc.pos and 0xFF) shl 8))
      ctx.freeIfTemp(uvAlloc)
      ctx.freeIfTemp(lodAlloc)
      return

    if procName in ["newVec2", "newVec2f", "newVec3", "newVec3f", "newVec4", "newVec4f"]:
      let totalWords = if procName in ["newVec2", "newVec2f"]: 2
                       elif procName in ["newVec3", "newVec3f"]: 3
                       else: 4
      let totalBytes = totalWords * 4
      result = if target.size >= totalBytes: target else: ctx.code.allocator.alloc(totalBytes)
      var currentOffset = 0
      for i in 1 ..< c.args.len:
        if currentOffset >= totalBytes: break
        let arg = c.args[i]
        var argTyName = ctx.cache.inferType(arg)
        let argSize = max(4, ctx.cache.getType(argTyName).size)
        let copySize = min(argSize, totalBytes - currentOffset)
        let subTarget = CAllocation(pos: result.pos + currentOffset, size: copySize, isTemp: false)
        let argAlloc = ctx.genExpr(arg, target = subTarget)
        if argAlloc.pos != subTarget.pos:
          ctx.emitInst(vocMov, subTarget.pos, argAlloc.pos, copySize)
        ctx.freeIfTemp(argAlloc)
        currentOffset += copySize
      return

    if procName == "dot":
      let arg0 = c.args[1]
      let tyName = ctx.cache.inferType(arg0)
      let r1 = ctx.genExpr(c.args[1])
      let r2 = ctx.genExpr(c.args[2])
      result = if target.size >= 4: target else: ctx.code.allocator.alloc(4)
      let op = if tyName.contains("2"): vocDot2
               elif tyName.contains("4"): vocDot4
               else: vocDot3
      ctx.emitInst(op, result.pos, r1.pos, r2.pos)
      ctx.freeIfTemp(r1)
      ctx.freeIfTemp(r2)
      return

    if procName == "normalize":
      let arg0 = c.args[1]
      let tyName = ctx.cache.inferType(arg0)
      let dim = if tyName.contains("2"): 2 elif tyName.contains("4"): 4 else: 3
      let size = dim * 4
      let arg = ctx.genExpr(c.args[1])
      result = if target.size >= size: target else: ctx.code.allocator.alloc(size)
      ctx.emitInst(vocNormalize, result.pos, arg.pos, dim)
      ctx.freeIfTemp(arg)
      return

    if procName == "reflect":
      let arg0 = c.args[1]
      let tyName = ctx.cache.inferType(arg0)
      let is3D = not tyName.contains("2")
      let size = if is3D: 12 else: 8
      let r1 = ctx.genExpr(c.args[1])
      let r2 = ctx.genExpr(c.args[2])
      result = if target.size >= size: target else: ctx.code.allocator.alloc(size)
      let op = if is3D: vocReflect3 else: vocReflect2
      ctx.emitInst(op, result.pos, r1.pos, r2.pos)
      ctx.freeIfTemp(r1)
      ctx.freeIfTemp(r2)
      return

    if procName == "distance":
      let a = ctx.genExpr(c.args[1])
      let b = ctx.genExpr(c.args[2])
      let vecSize = a.size
      let delta = ctx.code.allocator.alloc(vecSize)
      result = if target.size >= 4: target else: ctx.code.allocator.alloc(4)
      if delta.pos != a.pos:
        ctx.emitInst(vocMov, delta.pos, a.pos, vecSize)
      ctx.emitInst(vocSubf, delta.pos, b.pos, vecSize)
      if vecSize == 4:
        ctx.emitInst(vocAbsf, result.pos, delta.pos, 4)
      else:
        ctx.emitInst(vocLengthf, result.pos, delta.pos, vecSize div 4)
      ctx.code.allocator.free(delta)
      ctx.freeIfTemp(a)
      ctx.freeIfTemp(b)
      return

    if procName == "cross":
      let lhs = ctx.genExpr(c.args[1])
      let rhs = ctx.genExpr(c.args[2])
      result = if target.size >= 12: target else: ctx.code.allocator.alloc(12)
      if result.pos != lhs.pos:
        ctx.emitInst(vocMov, result.pos, lhs.pos, 12)
      ctx.emitInst(vocCross3, result.pos, rhs.pos, 3)
      ctx.freeIfTemp(lhs)
      ctx.freeIfTemp(rhs)
      return

    if procName == "length":
      let arg = ctx.genExpr(c.args[1])
      let tyName = ctx.cache.inferType(c.args[1])
      result = if target.size >= 4: target else: ctx.code.allocator.alloc(4)
      let argSize = ctx.cache.getType(tyName).size
      if argSize == 4:
        ctx.emitInst(vocAbsf, result.pos, arg.pos, 4)
      else:
        ctx.emitInst(vocLengthf, result.pos, arg.pos, argSize div 4)
      ctx.freeIfTemp(arg)
      return

    if procName == "refract":
      let incident = ctx.genExpr(c.args[1])
      let normal = ctx.genExpr(c.args[2])
      let eta = ctx.genExpr(c.args[3])
      let tyName = ctx.cache.inferType(c.args[1])
      let bytes = max(8, ctx.cache.getType(tyName).size)
      let lanes = bytes div 4
      result = if target.size >= bytes: target else: ctx.code.allocator.alloc(bytes)
      if result.pos != incident.pos:
        ctx.emitInst(vocMov, result.pos, incident.pos, bytes)
      ctx.emitInst(vocRefractf, result.pos, normal.pos, lanes)
      ctx.emitWord(uint32(eta.pos and 0xFF))
      ctx.freeIfTemp(incident)
      ctx.freeIfTemp(normal)
      ctx.freeIfTemp(eta)
      return

    if procName == "pow":
      let arg0 = c.args[1]
      let tyName = ctx.cache.inferType(arg0)
      let isFloat = tyName.startsWith("float") or tyName.startsWith("vec")
      let count = max(1, ctx.cache.getType(tyName).size div 4)
      let r1 = ctx.genExpr(c.args[1])
      let r2 = ctx.genExpr(c.args[2])
      result = if target.size >= r1.size: target else: ctx.code.allocator.alloc(r1.size)
      if result.pos != r1.pos:
        ctx.emitInst(vocMov, result.pos, r1.pos, r1.size)
      let op = if isFloat: vocPowf else: vocPowi
      ctx.emitInst(op, result.pos, r2.pos, count)
      ctx.freeIfTemp(r1)
      ctx.freeIfTemp(r2)
      return

    if procName == "matrixCompMult":
      let tyName = ctx.cache.inferType(c.args[1])
      let matrixSize = max(16, ctx.cache.getType(tyName).size)
      let lhs = ctx.genExpr(c.args[1])
      let rhs = ctx.genExpr(c.args[2])
      result = if target.size >= matrixSize: target else: ctx.code.allocator.alloc(matrixSize)
      if result.pos != lhs.pos:
        ctx.emitInst(vocMov, result.pos, lhs.pos, matrixSize)
      ctx.emitInst(vocMatrixCompMult, result.pos, rhs.pos, matrixSize div 4)
      ctx.freeIfTemp(lhs)
      ctx.freeIfTemp(rhs)
      return

    if procName == "determinant":
      let tyName = ctx.cache.inferType(c.args[1])
      let dim = if tyName.contains("2"): 2 elif tyName.contains("3"): 3 else: 4
      let matrix = ctx.genExpr(c.args[1])
      result = if target.size >= 4: target else: ctx.code.allocator.alloc(4)
      ctx.emitInst(vocDeterminantf, result.pos, matrix.pos, dim)
      ctx.freeIfTemp(matrix)
      return

    if procName == "transpose":
      let tyName = ctx.cache.inferType(c.args[1])
      let (op, size) = if tyName.contains("2"): (vocTranspose2, 16)
                       elif tyName.contains("3"): (vocTranspose3, 36)
                       else: (vocTranspose4, 64)
      let arg = ctx.genExpr(c.args[1])
      result = if target.size >= size: target else: ctx.code.allocator.alloc(size)
      ctx.emitInst(op, result.pos, arg.pos, size)
      ctx.freeIfTemp(arg)
      return

    if procName in ["inverse", "invert"]:
      let tyName = ctx.cache.inferType(c.args[1])
      let (op, size) = if tyName.contains("2"): (vocInvert2, 16)
                       elif tyName.contains("3"): (vocInvert3, 36)
                       else: (vocInvert4, 64)
      let arg = ctx.genExpr(c.args[1])
      result = if target.size >= size: target else: ctx.code.allocator.alloc(size)
      ctx.emitInst(op, result.pos, arg.pos, size)
      ctx.freeIfTemp(arg)
      return

    let returnTypeName = ctx.cache.inferType(c)
    let returnSize = if returnTypeName in ["", "void", "auto"]: 0
                     else: max(0, ctx.cache.getType(returnTypeName).size)
    result = if returnSize == 0: CAllocation(pos: 0, size: 0)
             elif target.size >= returnSize: target
             else: ctx.code.allocator.alloc(returnSize)
    # The call header has one byte for a register-file offset (memory is 256
    # bytes). A saturated frame will be rejected by the VM's frame-size check.
    let frameOffset = min(255, ctx.code.allocator.highWaterMark)
    var argsToFree: seq[CAllocation] = @[]
    var argumentBytes = 0

    for i in 1 ..< c.args.len:
      let argAlloc = ctx.genExpr(c.args[i])
      ctx.emitInst(vocPush, argAlloc.pos, 0, argAlloc.size)
      argumentBytes += argAlloc.size
      argsToFree.add(argAlloc)

    for argAlloc in argsToFree:
      ctx.freeIfTemp(argAlloc)

    let procPos = ctx.code.procTable.getOrDefault(procName, -1)

    ctx.emitInst(vocCall, frameOffset, result.pos, returnSize)
    let targetPos = ctx.code.data.len
    ctx.emitWord(if procPos >= 0: uint32(procPos) else: 0u32)
    let frameInfoPos = ctx.code.data.len
    let calleeFrameSize = ctx.code.frameSizes.getOrDefault(procName, -1)
    let packedFrameInfo = (uint32(max(0, calleeFrameSize)) shl 16) or
                          uint32(argumentBytes and 0xFFFF)
    ctx.emitWord(packedFrameInfo)

    if procPos < 0 or calleeFrameSize < 0:
      var list = ctx.code.callToPatch.getOrDefault(procName, @[])
      list.add(CallPatch(targetPos: targetPos, frameInfoPos: frameInfoPos))
      ctx.code.callToPatch[procName] = list
    return

  of cnkConv:
    let targetTypeName = ctx.cache.equivalences.getOrDefault(
      c.args[0].name.split(".")[0], c.args[0].name.split(".")[0])
    let sourceTypeName = ctx.cache.inferType(c.args[1])
    let targetType = conversionType(ctx.cache, targetTypeName)
    let sourceType = conversionType(ctx.cache, sourceTypeName)
    let targetSize = max(1, ctx.cache.getType(targetTypeName).size)

    if sourceType == targetType:
      return ctx.genExpr(c.args[1], target = target)

    let source = ctx.genExpr(c.args[1])
    result = if target.size >= targetSize: target
             else: ctx.code.allocator.alloc(targetSize)
    ctx.emitInst(vocConv, result.pos, source.pos, targetSize)
    let descriptor = uint32(ord(sourceType)) or
      (uint32(ord(targetType)) shl 8)
    ctx.emitWord(descriptor)
    if source.isTemp and source.pos != result.pos:
      ctx.freeIfTemp(source)
    return

  of cnkBoolLit:
    result = if target.pos != -1: target else: ctx.code.allocator.alloc(1)
    ctx.emitInst(vocMovCi, result.pos, 0)
    ctx.emitWord(if c.boolVal: 1u32 else: 0u32)
    return

  of cnkSym, cnkRSym:
    let localAlloc = ctx.resolveSymbol(c)
    if localAlloc.size > 0:
      if target.size > 0 and target.pos != localAlloc.pos:
        let wordsToCopy = max(1, min(target.size, localAlloc.size))
        ctx.emitInst(vocMov, target.pos, localAlloc.pos, wordsToCopy)
        result = target
      else:
        result = localAlloc
      return

    # Uniforms: load via vocLoadUni
    if c.name in ctx.cache.shaderParams.uniformToId:
      let uOffset = ctx.cache.shaderParams.uniformToId.getOrDefault(c.name, 0)
      let tyId = ctx.cache.variables.getOrDefault(c.name, -1)
      let uSize = if tyId >= 0: max(1, ctx.cache.instances[tyId].size) else: 1
      result = 
        if target.size >= uSize: 
          target 
        else: 
          let l = ctx.cache.liveness.getOrDefault(c.name)
          let bp = l.birth
          var lline = l.dead.line
          var lcol  = l.dead.col
          ctx.code.allocator.alloc(uSize, bp.line, bp.col, lline, lcol)
      
      ctx.emitInst(vocLoadUni, result.pos, uOffset, uSize)
      return

    # Global index fallback if not bound to a local register
    if c.name == ctx.cache.shaderParams.globalIndex.name:
      let gSize = ctx.cache.instances[ctx.cache.shaderParams.globalIndex.tid].size
      result = if target.size >= gSize: target else: ctx.code.allocator.alloc(gSize)
      ctx.emitInst(vocLoadGI, result.pos, 0, gSize)
      return

    result = localAlloc
    return

  of cnkArrAt:
    var dummyNode = c.args[0]
    let containerTypeName = ctx.cache.inferType(dummyNode)
    let containerTy = ctx.cache.getType(containerTypeName)
    let elemTypeName = containerTy.returnType
    let elemSize = max(1, ctx.cache.getType(elemTypeName).size)

    let indexAlloc = ctx.genExpr(c.args[1])
    let dest = if target.size >= elemSize: target else: ctx.code.allocator.alloc(elemSize)

    if c.args[0].name in ctx.cache.shaderParams.ssboToId:
      let bufId = ctx.cache.shaderParams.ssboToId.getOrDefault(c.args[0].name, 0)
      ctx.emitInst(vocLoadBuf, dest.pos, bufId, elemSize)
      ctx.emitInst(vocNoOp, indexAlloc.pos, 0, max(1, indexAlloc.size))
    else:
      let arrAlloc = ctx.genExpr(c.args[0])
      ctx.emitInst(vocLoadAt, dest.pos, arrAlloc.pos, elemSize)
      ctx.emitInst(vocNoOp, indexAlloc.pos, 0, max(1, indexAlloc.size))
      ctx.freeIfTemp(arrAlloc)

    ctx.freeIfTemp(indexAlloc)
    return dest

  of cnkArrAsgnAt:
    ctx.genArrAsgn(c)
    return

  of cnkIntLit:
    result = if target.size >= INT_SIZE: target else: ctx.code.allocator.alloc(INT_SIZE)
    ctx.emitInst(vocMovCi, result.pos, 0, INT_SIZE)
    ctx.emitWord(cast[uint32](c.intVal))
    return

  of cnkUintLit:
    result = if target.size >= INT_SIZE: target else: ctx.code.allocator.alloc(INT_SIZE)
    ctx.emitInst(vocMovCi, result.pos, 0, INT_SIZE)
    ctx.emitWord(cast[uint32](c.uintVal))
    return

  of cnkFloatLit:
    result = if target.size >= FLOAT_SIZE: target else: ctx.code.allocator.alloc(FLOAT_SIZE)
    ctx.emitInst(vocMovCf, result.pos, 0, FLOAT_SIZE)
    ctx.emitWord(cast[uint32](float32(c.floatVal)))
    return

  of cnkCharLit:
    result = if target.size >= CHAR_SIZE: target else: ctx.code.allocator.alloc(CHAR_SIZE)
    ctx.emitInst(vocMovCi, result.pos, 0)
    ctx.emitWord(uint32(ord(c.charVal)))
    return

  of cnkObjConstr:
    let typeName = c.args[0].name
    let typeInst = ctx.cache.getType(typeName)
    let totalSize = max(1, typeInst.size)
    if target.size >= totalSize:
      result = target
    else:
      result = ctx.code.allocator.alloc(totalSize)

    for i in 1 ..< c.args.len:
      let kv = c.args[i]
      let fieldName = kv.args[0].name
      let fid = typeInst.nameToId.getOrDefault(fieldName, -1)
      let field = typeInst.fields[fid]
      let fsize = max(1, ctx.cache.getType(field.ty).size)
      let fieldTarget = CAllocation(pos: result.pos + field.offset, size: fsize, isTemp: false)
      let valAlloc = ctx.genExpr(kv.args[1], target = fieldTarget)
      if valAlloc.pos != fieldTarget.pos:
        let copyWords = min(fsize, max(1, valAlloc.size))
        ctx.emitInst(vocMov, fieldTarget.pos, valAlloc.pos, copyWords)
      ctx.freeIfTemp(valAlloc)
  
    return

  else:
    discard

# ################################################################################################################################ #
# ############################################################## STATEMENTS ###################################################### #
# ################################################################################################################################ #

proc genVar(ctx: var CodeGenCtx, c: CIRNode) =
  let symDef = c.args[0]
  let varName = symDef.args[0].name
  let typeName = symDef.args[1].name
  let ty = ctx.cache.getType(typeName)

  let l = ctx.cache.liveness.getOrDefault(varName)
  let bp = l.birth
  var lline = l.dead.line
  var lcol  = l.dead.col

  let alloc = ctx.code.allocator.alloc(max(1, ty.size), bp.line, bp.col, lline, lcol)
  if c.args.len > 1:
    let initAlloc = ctx.genExpr(c.args[1], target = alloc)
    if initAlloc.pos != alloc.pos:
      let wordsToCopy = max(1, min(alloc.size, max(1, initAlloc.size)))
      ctx.emitInst(vocMov, alloc.pos, initAlloc.pos, wordsToCopy)
    ctx.freeIfTemp(initAlloc)

proc genAsgn(ctx: var CodeGenCtx, c: CIRNode) =
  let lhsAlloc = ctx.genExpr(c.args[0])
  let rhs = ctx.genExpr(c.args[1], target = lhsAlloc)
  if lhsAlloc.size > 0 and rhs.pos != lhsAlloc.pos:
    let wordsToCopy = max(1, min(lhsAlloc.size, max(1, rhs.size)))
    ctx.emitInst(vocMov, lhsAlloc.pos, rhs.pos, wordsToCopy)
  ctx.freeIfTemp(rhs)

proc genIf(ctx: var CodeGenCtx, c: CIRNode) =
  var endPatches: seq[int] = @[]
  let hasElse = c.args.len > 0 and c.args[^1].kind == cnkElse

  for i, branch in c.args:
    case branch.kind
    of cnkElifBranch:
      let condAlloc = ctx.genExpr(branch.args[0])
      ctx.emitInst(vocJmpFalse, condAlloc.pos, 0)
      let falsePatch = ctx.code.data.len
      ctx.emitWord(0u32)
      ctx.freeIfTemp(condAlloc)

      ctx.genStmt(branch.args[1])

      let isLast = (i == c.args.len - 1) and not hasElse
      if not isLast:
        ctx.emitInst(vocJmp, 0, 0)
        let endPatch = ctx.code.data.len
        ctx.emitWord(0u32)
        endPatches.add(endPatch)

      ctx.code.data[falsePatch] = uint32(ctx.code.data.len)

    of cnkElse:
      ctx.genStmt(branch.args[0])

    else: discard

  let endTarget = uint32(ctx.code.data.len)
  for pos in endPatches:
    ctx.code.data[pos] = endTarget

proc genBreak(ctx: var CodeGenCtx, c: CIRNode) =
  if ctx.loops.len == 0:
    return
  ctx.emitInst(vocJmp, 0, 0)
  let patch = ctx.code.data.len
  ctx.emitWord(0u32)
  ctx.loops[^1].breakPatches.add(patch)

proc genContinue(ctx: var CodeGenCtx, c: CIRNode) =
  if ctx.loops.len == 0:
    return
  ctx.emitInst(vocJmp, 0, 0)
  if ctx.loops[^1].continueTarget >= 0:
    ctx.emitWord(uint32(ctx.loops[^1].continueTarget))
  else:
    let patch = ctx.code.data.len
    ctx.emitWord(0u32)
    ctx.loops[^1].continuePatches.add(patch)

proc genWhile(ctx: var CodeGenCtx, c: CIRNode) =
  let loopStart = ctx.code.data.len
  let condAlloc = ctx.genExpr(c.args[0])

  ctx.emitInst(vocJmpFalse, condAlloc.pos, 0)
  let exitPatch = ctx.code.data.len
  ctx.emitWord(0u32)
  ctx.freeIfTemp(condAlloc)

  ctx.loops.add(LoopContext(continueTarget: loopStart, continuePatches: @[], breakPatches: @[]))

  ctx.genStmt(c.args[1])

  let loopCtx = ctx.loops.pop()

  ctx.emitInst(vocJmp, 0, 0)
  ctx.emitWord(uint32(loopStart))

  let exitTarget = uint32(ctx.code.data.len)
  ctx.code.data[exitPatch] = exitTarget
  for patch in loopCtx.breakPatches:
    ctx.code.data[patch] = exitTarget

proc genFor(ctx: var CodeGenCtx, c: CIRNode) =
  # c.args[0] = cnkSection containing cnkVarTy for the loop variable
  # c.args[1] = cnkInfix (iterator)
  # c.args[2] = body
  let loopVarNode = c.args[0].args[0]
  ctx.genVar(loopVarNode)

  let symDef = loopVarNode.args[0]
  let varName = symDef.args[0].name
  let varAlloc = ctx.resolveSymbol(symDef.args[0])

  let iter = c.args[1]
  let opStr = iter.args[0].name
  let isExclusive = opStr.contains("<")

  # Start value
  let startAlloc = ctx.genExpr(iter.args[1], target = varAlloc)
  if startAlloc.pos != varAlloc.pos:
    ctx.emitInst(vocMov, varAlloc.pos, startAlloc.pos)
  ctx.freeIfTemp(startAlloc)

  # Stop value
  let stopAlloc = ctx.genExpr(iter.args[2])

  let loopStart = ctx.code.data.len
  let cmpOp = if isExclusive: vocLti else: vocLei

  let condAlloc = ctx.code.allocator.alloc(1)
  ctx.emitInst(vocMov, condAlloc.pos, varAlloc.pos)
  ctx.emitInst(cmpOp, condAlloc.pos, stopAlloc.pos)

  ctx.emitInst(vocJmpFalse, condAlloc.pos, 0)
  let exitPatch = ctx.code.data.len
  ctx.emitWord(0u32)
  ctx.freeIfTemp(condAlloc)

  ctx.loops.add(LoopContext(continueTarget: -1, continuePatches: @[], breakPatches: @[]))

  # Body
  ctx.genStmt(c.args[2])

  let loopCtx = ctx.loops.pop()

  # Step target: where continue jumps
  let stepTarget = uint32(ctx.code.data.len)
  for patch in loopCtx.continuePatches:
    ctx.code.data[patch] = stepTarget

  # Increment: varAlloc += 1
  let oneAlloc = ctx.code.allocator.alloc(1)
  ctx.emitInst(vocMovCi, oneAlloc.pos, 0)
  ctx.emitWord(1u32)
  ctx.emitInst(vocAddi, varAlloc.pos, oneAlloc.pos)
  ctx.freeIfTemp(oneAlloc)

  # Jump back to condition
  ctx.emitInst(vocJmp, 0, 0)
  ctx.emitWord(uint32(loopStart))

  # Backpatch exit
  let exitTarget = uint32(ctx.code.data.len)
  ctx.code.data[exitPatch] = exitTarget
  for patch in loopCtx.breakPatches:
    ctx.code.data[patch] = exitTarget

  ctx.freeIfTemp(stopAlloc)

proc genRet(ctx: var CodeGenCtx, c: CIRNode) =
  if c.args[0].kind != cnkEmpty:
    let retTarget = CAllocation(pos: 0, size: 1, isTemp: false)
    let retAlloc = ctx.genExpr(c.args[0], target = retTarget)
    if retAlloc.pos != 0:
      ctx.emitInst(vocMov, 0, retAlloc.pos, max(1, retAlloc.size))
    ctx.freeIfTemp(retAlloc)
  ctx.emitInst(vocRet, 0, 0)

proc genDiscard(ctx: var CodeGenCtx, c: CIRNode) =
  if c.args[0].kind != cnkEmpty:
    let disAlloc = ctx.genExpr(c.args[0])
    ctx.freeIfTemp(disAlloc)

proc genCallStmt(ctx: var CodeGenCtx, c: CIRNode) =
  let alloc = ctx.genExpr(c)
  ctx.freeIfTemp(alloc)

proc genArrAsgn(ctx: var CodeGenCtx, c: CIRNode) =
  var dummyNode = c.args[0]
  let containerTypeName = ctx.cache.inferType(dummyNode)
  let containerTy = ctx.cache.getType(containerTypeName)
  let elemTypeName = containerTy.returnType
  let elemSize = ctx.cache.getType(elemTypeName).size

  let indexAlloc = ctx.genExpr(c.args[1])
  let valAlloc = ctx.genExpr(c.args[2])

  if c.args[0].kind in {cnkSym, cnkRSym} and c.args[0].name in ctx.cache.shaderParams.ssboToId:
    let bufId = ctx.cache.shaderParams.ssboToId.getOrDefault(c.args[0].name, 0)
    ctx.emitInst(vocStoreBuf, valAlloc.pos, bufId, elemSize)
    ctx.emitInst(vocNoOp, indexAlloc.pos, 0, max(1, indexAlloc.size))
  else:
    let arrAlloc = ctx.genExpr(c.args[0])
    ctx.emitInst(vocStoreAt, valAlloc.pos, arrAlloc.pos, elemSize)
    ctx.emitInst(vocNoOp, indexAlloc.pos, 0, max(1, indexAlloc.size))
    ctx.freeIfTemp(arrAlloc)

  ctx.freeIfTemp(valAlloc)
  ctx.freeIfTemp(indexAlloc)

proc allocShaderParam(ctx: var CodeGenCtx, param: CIRNode): CAllocation =
  let name = param.args[0].name
  let typeName = param.args[1].name
  let ty = ctx.cache.getType(typeName)
  let live = ctx.cache.liveness.getOrDefault(name)
  let birth = live.birth
  var deadLine = live.dead.line
  var deadCol = live.dead.col
  result = ctx.code.allocator.alloc(max(1, ty.size), birth.line, birth.col,
                                    deadLine, deadCol)

proc shaderBlockOffset(items: seq[ShaderBlockItem], name: string): int =
  for item in items:
    if item.name == name:
      return item.offset
  return 0

proc genFunc(ctx: var CodeGenCtx, c: CIRNode) =
  let name = c.args[0].name
  var isMainEntry = false # Keeps track of wheteher it's the main function
  if name.split(".")[0] == MAIN_ENTRY_NAME:
    isMainEntry = true # Yup it is
    ctx.entryPoint = ctx.code.currentPos
  ctx.currentProcName = name
  ctx.code.procTable[name] = ctx.code.currentPos
  let parentAllocator = ctx.code.allocator
  ctx.code.allocator = newVramAllocator()
  
  # Stack offset, yeah could have a better name but who cares ?
  var offset = 0
  if c.args[1].kind == cnkParams:
    for param in c.args[1].args:
      if param.kind in {cnkSSBO, cnkTexture}:
        # SSBO and Texture parameters are bound as buffers / samplers, not passed on stack or loaded into registers
        continue
      elif param.kind == cnkGlobalIndex:
        # this is when encountering the global index used in compute shaders and stuffs
        # We just load it (and kill it immediately if not used) at the start of the function
        let paramName = param.args[0].name
        let paramTyName = param.args[1].name
        let paramTy = ctx.cache.getType(paramTyName)
        
        # Just fetching some liveness info obviously
        let l = ctx.cache.liveness.getOrDefault(paramName)
        let bp = l.birth
        var lline = l.dead.line
        var lcol  = l.dead.col
          

        let fsize = paramTy.size
        let alloc = ctx.code.allocator.alloc(fsize, bp.line, bp.col, lline, lcol)
        ctx.emitInst(vocLoadGI, alloc.pos, 0, fsize)
      elif param.kind in {cnkVertexInput, cnkFragmentInput}:
        # When writing regular shader, here we handle vertex and fragment inputs
        let alloc = ctx.allocShaderParam(param)
        let inputOp = if param.kind == cnkVertexInput:
          vocLoadVertexInput else: vocLoadFragmentInput
        let inputOffset = if param.kind == cnkVertexInput:
          ctx.cache.shaderParams.vertInputs.shaderBlockOffset(param.args[0].name)
        else:
          ctx.cache.shaderParams.fragInputs.shaderBlockOffset(param.args[0].name)
        ctx.emitInst(inputOp, alloc.pos, inputOffset, alloc.size)
      elif param.kind in {cnkVertexOutput, cnkVertexVarying, cnkFragmentOutput}:
        # Here it's just about the output of the shader
        # Pretty straight forward
        if param.kind in {cnkVertexOutput, cnkFragmentOutput}:
          try:
            var dead = c.args[3].args[^1].info
            dead.line += 1
            ctx.cache.liveness[param.args[0].name].dead = dead
          except: discard
        discard ctx.allocShaderParam(param)
      else:
        let paramName = param.args[0].name
        let paramTyName = param.args[1].name
        let paramTy = ctx.cache.getType(paramTyName)
        
        let l = ctx.cache.liveness.getOrDefault(paramName)
        let bp = l.birth
        var lline = l.dead.line
        var lcol  = l.dead.col
          
        let fsize = max(1, paramTy.size)
        let alloc = ctx.code.allocator.alloc(fsize, bp.line, bp.col, lline, lcol)
        ctx.emitInst(vocSMov, alloc.pos, offset, fsize)
        offset += fsize

  if ctx.code.callToPatch.hasKey(name):
    let patchList = ctx.code.callToPatch.getOrDefault(name, @[])
    for patch in patchList:
      ctx.code.data[patch.targetPos] = uint32(ctx.code.currentPos)

  ctx.genStmt(c.args[3])

  if isMainEntry:
    # Here we will try to set the shader output
    # It's better to do it once and for all at the end of the shader
    # Since it would be way more cumbersome to do it with the output itself (to much edge case)
    for param in c.args[1].args:
      if param.kind in {cnkVertexOutput, cnkVertexVarying, cnkFragmentOutput}:
        let paramName = param.args[0].name
        let live = ctx.cache.liveness.getOrDefault(paramName)
        let output = ctx.code.allocator.lookup(live.birth.line, live.birth.col)
        case param.kind
        of cnkVertexOutput:
          ctx.emitInst(vocStoreVertexOutput, output.pos, 0, output.size)
        of cnkVertexVarying:
          let outputOffset = ctx.cache.shaderParams.vertVaryings
            .shaderBlockOffset(paramName)
          ctx.emitInst(vocStoreVertexVarying, output.pos,
                       outputOffset, output.size)
        of cnkFragmentOutput:
          ctx.emitInst(vocStoreFragmentOutput, output.pos, 0, output.size)
        else: discard

  ctx.emitInst(vocRet, 0, 0)

  let frameSize = ctx.code.allocator.highWaterMark
  ctx.code.frameSizes[name] = frameSize
  for patch in ctx.code.callToPatch.getOrDefault(name, @[]):
    ctx.code.data[patch.targetPos] = uint32(ctx.code.procTable.getOrDefault(name, 0))
    ctx.code.data[patch.frameInfoPos] = (uint32(frameSize) shl 16) or
      (ctx.code.data[patch.frameInfoPos] and 0xFFFF'u32)
  if ctx.code.callToPatch.hasKey(name):
    ctx.code.callToPatch.del(name)
  ctx.code.allocator = parentAllocator

proc genStmt*(ctx: var CodeGenCtx, c: CIRNode) =
  case c.kind
  of cnkEmpty: discard
  of cnkStmtList, cnkSection:
    for n in c.args:
      ctx.genStmt(n)
  of cnkUniform, cnkTexture:
    # Uniform and Texture declarations are handled by shader params; no code emitted
    discard
  of cnkVarTy:
    ctx.genVar(c)
  of cnkAsgn:
    ctx.genAsgn(c)
  of cnkArrAsgnAt:
    ctx.genArrAsgn(c)
  of cnkIfStmt:
    ctx.genIf(c)
  of cnkWhileStmt:
    ctx.genWhile(c)
  of cnkForStmt:
    ctx.genFor(c)
  of cnkReturnStmt:
    ctx.genRet(c)
  of cnkDiscardStmt:
    ctx.genDiscard(c)
  of cnkCall:
    ctx.genCallStmt(c)
  of cnkFuncDef:
    ctx.genFunc(c)
  of cnkBreakStmt:
    ctx.genBreak(c)
  of cnkContinueStmt:
    ctx.genContinue(c)
  of cnkObjConstr:
    let alloc = ctx.genExpr(c)
    ctx.freeIfTemp(alloc)
  else:
    discard

proc predeclareFunctions(ctx: var CodeGenCtx, root: CIRNode) =
  let items = if root.kind in {cnkStmtList, cnkSection}: root.args else: @[root]
  for item in items:
    if item.kind == cnkFuncDef:
      let fnName = item.args[0].name
      ctx.code.procTable[fnName] = -1
