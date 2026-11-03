## Bytecode generation from CIRNode.

type
  CIRField = object
    name: string
    ty: string

  CIRVariable = object
    allocation: CAllocation
    ty: string

  CIRGenCtx = object
    scopes: seq[Table[string, CIRVariable]]
    returnTypes: Table[string, string]
    typeSizes: Table[string, int]
    typeFields: Table[string, seq[CIRField]]
    fieldOffsets: Table[string, int]
    currentProc: string
    loopStarts: seq[int]
    breakPatches: seq[seq[int]]
    continuePatches: seq[seq[int]]

  CBytecode = object
    data: seq[uint32]
    allocator: CVramAllocator
    procTable: Table[string, int]
    callToPatch: Table[string, seq[int]]

proc primitiveTypeSize(name: string): int =
  case name
  of "bool", "char", "int8", "uint8": 1
  of "int16", "uint16": 2
  of "int64", "uint64", "float64": 8
  else: 4

proc newIRGenCtx(root: CIRNode): CIRGenCtx =
  result.scopes = @[initTable[string, CIRVariable]()]
  result.returnTypes = initTable[string, string]()
  result.typeSizes = initTable[string, int]()
  result.typeFields = initTable[string, seq[CIRField]]()
  result.fieldOffsets = initTable[string, int]()
  result.loopStarts = @[]
  result.breakPatches = @[]
  result.continuePatches = @[]
  let items = if root.kind in {cnkStmtList, cnkSection}: root.args else: @[root]
  for item in items:
    if item.kind == cnkTypeDef and item.args.len > 0 and item.args[0].kind == cnkSym:
      let name = item.args[0].name
      var fields: seq[CIRField] = @[]
      for fieldIndex in 1 ..< item.args.len:
        let fieldDef = item.args[fieldIndex]
        if fieldDef.kind == cnkSymDef and fieldDef.args.len >= 2:
          fields.add(CIRField(name: fieldDef.args[0].name, ty: fieldDef.args[1].name))
      result.typeFields[name] = fields
      result.typeSizes[name] = 1
    elif item.kind == cnkFuncDef and item.args.len >= 4 and item.args[0].kind == cnkSym:
      let name = item.args[0].name
      let retTy = if item.args[2].kind == cnkSym: item.args[2].name else: "void"
      result.returnTypes[name] = retTy
  # Resolve object sizes after all declarations have been collected. Repeated
  # passes handle fields whose types are declared later in the module.
  for _ in 0 ..< result.typeFields.len:
    for name, fields in result.typeFields:
      var size = 0
      for field in fields:
        size += result.typeSizes.getOrDefault(field.ty, primitiveTypeSize(field.ty))
      result.typeSizes[name] = max(1, size)
  for name, fields in result.typeFields:
    var offset = 0
    for field in fields:
      result.fieldOffsets[name & "." & field.name] = offset
      offset += result.typeSizes.getOrDefault(field.ty, primitiveTypeSize(field.ty))

proc typeSize(ctx: CIRGenCtx, name: string): int =
  ctx.typeSizes.getOrDefault(name, primitiveTypeSize(name))

proc pushScope(ctx: var CIRGenCtx) =
  ctx.scopes.add(initTable[string, CIRVariable]())

proc popScope(ctx: var CIRGenCtx) =
  if ctx.scopes.len > 1: ctx.scopes.setLen(ctx.scopes.len - 1)

proc lookupVar(ctx: CIRGenCtx, name: string): CIRVariable =
  for i in countdown(ctx.scopes.high, 0):
    if ctx.scopes[i].hasKey(name): return ctx.scopes[i][name]

proc bindVar(ctx: var CIRGenCtx, name: string, ty: string, allocation: CAllocation) =
  ctx.scopes[^1][name] = CIRVariable(allocation: allocation, ty: ty)

proc emitInst(code: var CBytecode, op: VMOpCode, dst, src: int) =
  doAssert dst >= 0 and dst <= 255, "CVM register address exceeds 8 bits"
  doAssert src >= 0 and src <= 255, "CVM register address exceeds 8 bits"
  code.data.add((uint32(op) shl 16) or (uint32(dst) shl 8) or uint32(src))

proc emitWord(code: var CBytecode, word: uint32) =
  code.data.add(word)

proc allocTemp(code: var CBytecode, ctx: CIRGenCtx, ty: string): CAllocation =
  code.allocator.alloc(max(1, ctx.typeSize(ty)))

proc allocVar(code: var CBytecode, ctx: var CIRGenCtx, name, ty: string): CAllocation =
  result = code.allocator.alloc(max(1, ctx.typeSize(ty)))
  result.isTemp = false
  ctx.bindVar(name, ty, result)

proc freeTemp(code: var CBytecode, allocation: CAllocation) =
  if allocation.isTemp and allocation.size > 0:
    code.allocator.free(allocation)

proc inferType(ctx: CIRGenCtx, node: CIRNode): string =
  case node.kind
  of cnkIntLit: "int"
  of cnkUintLit: "uint"
  of cnkFloatLit: "float"
  of cnkCharLit: "char"
  of cnkBoolLit: "bool"
  of cnkSym: ctx.lookupVar(node.name).ty
  of cnkInfix:
    if node.args.len >= 3:
      let op = node.args[0].name
      if op in ["==", "!=", "<", "<=", ">", ">="]: "bool"
      else: ctx.inferType(node.args[1])
    else: "int"
  of cnkPrefix:
    if node.args.len >= 2: ctx.inferType(node.args[1]) else: "int"
  of cnkCall:
    if node.args.len > 0 and node.args[0].kind == cnkSym:
      ctx.returnTypes.getOrDefault(node.args[0].name, if node.args.len > 1: ctx.inferType(node.args[1]) else: "int")
    else: "int"
  of cnkConv:
    if node.args.len > 0: node.args[0].name else: "int"
  else: "int"

proc opcodeFor(op: string, isFloat: bool): VMOpCode =
  case op
  of "+": if isFloat: vocAddf else: vocAddi
  of "-": if isFloat: vocSubf else: vocSubi
  of "*": if isFloat: vocMulf else: vocMuli
  of "/": if isFloat: vocDivf else: vocDivi
  of "%": vocMod
  of "and": vocAnd
  of "or": vocOr
  of "xor": vocXor
  of "==": if isFloat: vocEqf else: vocEqi
  of "!=": if isFloat: vocNeqf else: vocNeqi
  of "<": if isFloat: vocLtf else: vocLti
  of "<=": if isFloat: vocLef else: vocLei
  of ">": if isFloat: vocLtf else: vocLti
  of ">=": if isFloat: vocLef else: vocLei
  else: raise newException(ValueError, "Unsupported CIR binary operator: " & op)

proc genExpr(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode): CAllocation

proc genCall(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode): CAllocation =
  doAssert node.args.len > 0 and node.args[0].kind == cnkSym, "CIR call must start with a symbol"
  let procName = node.args[0].name
  let retTy = ctx.returnTypes.getOrDefault(procName, if node.args.len > 1: ctx.inferType(node.args[1]) else: "int")
  result = code.allocTemp(ctx, retTy)
  for i in 1 ..< node.args.len:
    let arg = code.genExpr(ctx, node.args[i])
    code.emitInst(vocPush, arg.pos, 0)
    code.freeTemp(arg)

  let builtin = toBuiltinCall(procName)
  let procPos = if builtin == boCustom: code.procTable.getOrDefault(procName, -1) else: 0
  code.emitInst(vocCall, builtin.int, result.pos)
  let targetPos = code.data.len
  code.emitWord(if procPos >= 0: uint32(procPos) else: 0'u32)
  if builtin == boCustom and procPos < 0:
    var patches = code.callToPatch.getOrDefault(procName, @[])
    patches.add(targetPos)
    code.callToPatch[procName] = patches

proc genExpr(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode): CAllocation =
  case node.kind
  of cnkIntLit:
    result = code.allocTemp(ctx, "int")
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(uint32(node.intVal))
  of cnkUintLit:
    result = code.allocTemp(ctx, "uint")
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(uint32(node.uintVal))
  of cnkFloatLit:
    result = code.allocTemp(ctx, "float")
    code.emitInst(vocLoadf, result.pos, 0)
    code.emitWord(cast[uint32](float32(node.floatVal)))
  of cnkCharLit:
    result = code.allocTemp(ctx, "char")
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(uint32(ord(node.charVal)))
  of cnkBoolLit:
    result = code.allocTemp(ctx, "bool")
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(if node.boolVal: 1'u32 else: 0'u32)
  of cnkSym:
    let v = ctx.lookupVar(node.name)
    doAssert v.allocation.size > 0, "Unknown CIR symbol: " & node.name
    result = v.allocation
  of cnkPar:
    doAssert node.args.len == 1
    result = code.genExpr(ctx, node.args[0])
  of cnkInfix:
    doAssert node.args.len >= 3, "Malformed CIR infix expression"
    let op = node.args[0].name
    let leftNode = node.args[1]
    let rightNode = node.args[2]
    let left = code.genExpr(ctx, leftNode)
    let right = code.genExpr(ctx, rightNode)
    let isComparison = op in ["==", "!=", "<", "<=", ">", ">="]
    let operandTy = ctx.inferType(leftNode)
    result = code.allocTemp(ctx, if isComparison: "bool" else: operandTy)
    if op in [">", ">="]:
      code.emitInst(vocMov, result.pos, right.pos)
      code.emitInst(opcodeFor(if op == ">": "<" else: "<=", operandTy.startsWith("float")), result.pos, left.pos)
    else:
      code.emitInst(vocMov, result.pos, left.pos)
      code.emitInst(opcodeFor(op, operandTy.startsWith("float")), result.pos, right.pos)
    code.freeTemp(left)
    code.freeTemp(right)
  of cnkPrefix:
    doAssert node.args.len >= 2, "Malformed CIR prefix expression"
    let op = node.args[0].name
    let operand = code.genExpr(ctx, node.args[1])
    let ty = ctx.inferType(node.args[1])
    result = code.allocTemp(ctx, ty)
    if op == "-":
      code.emitInst(if ty.startsWith("float"): vocNegf else: vocNegi, result.pos, operand.pos)
    elif op == "not":
      code.emitInst(vocNot, result.pos, operand.pos)
    else:
      raise newException(ValueError, "Unsupported CIR prefix operator: " & op)
    code.freeTemp(operand)
  of cnkCall:
    result = code.genCall(ctx, node)
  of cnkConv:
    doAssert node.args.len >= 2, "Malformed CIR conversion"
    let operand = code.genExpr(ctx, node.args[1])
    result = code.allocTemp(ctx, node.args[0].name)
    code.emitInst(vocMov, result.pos, operand.pos)
    code.freeTemp(operand)
  of cnkDotExpr:
    doAssert node.args.len >= 2 and node.args[0].kind == cnkSym, "Malformed CIR field access"
    let variable = ctx.lookupVar(node.args[0].name)
    doAssert variable.allocation.size > 0, "Unknown CIR field base: " & node.args[0].name
    var offset = 0
    var currentType = variable.ty
    for i in 1 ..< node.args.len:
      doAssert node.args[i].kind == cnkSym, "Malformed CIR field path"
      let fieldName = node.args[i].name
      let key = currentType & "." & fieldName
      doAssert ctx.fieldOffsets.hasKey(key), "Unknown CIR field: " & key
      offset += ctx.fieldOffsets[key]
      var fieldType = ""
      for field in ctx.typeFields.getOrDefault(currentType, @[]):
        if field.name == fieldName:
          fieldType = field.ty
          break
      doAssert fieldType.len > 0, "Unknown CIR field type: " & key
      currentType = fieldType
    result = CAllocation(pos: variable.allocation.pos + offset,
                         size: ctx.typeSize(currentType), isTemp: false)
  else:
    raise newException(ValueError, "Unsupported CIR expression: " & renderIR(node))

proc genVar(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode) =
  doAssert node.args.len >= 1 and node.args[0].kind == cnkSymDef and node.args[0].args.len >= 2,
    "Malformed CIR variable declaration"
  let symDef = node.args[0]
  let name = symDef.args[0].name
  let ty = symDef.args[1].name
  let target = code.allocVar(ctx, name, ty)
  if node.args.len > 1 and node.args[1].kind != cnkEmpty:
    let value = code.genExpr(ctx, node.args[1])
    if value.pos != target.pos: code.emitInst(vocMov, target.pos, value.pos)
    code.freeTemp(value)

proc genIf(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode) =
  var endPatches: seq[int] = @[]
  for branch in node.args:
    case branch.kind
    of cnkElifBranch:
      doAssert branch.args.len >= 2, "Malformed CIR elif branch"
      let cond = code.genExpr(ctx, branch.args[0])
      code.emitInst(vocJmpFalse, cond.pos, 0)
      let falsePatch = code.data.len
      code.emitWord(0'u32)
      code.freeTemp(cond)
      ctx.pushScope()
      code.genStmt(ctx, branch.args[1])
      ctx.popScope()
      code.emitInst(vocJmp, 0, 0)
      endPatches.add(code.data.len)
      code.emitWord(0'u32)
      code.data[falsePatch] = uint32(code.data.len)
    of cnkElse:
      if branch.args.len > 0:
        ctx.pushScope()
        code.genStmt(ctx, branch.args[0])
        ctx.popScope()
    else:
      raise newException(ValueError, "Unsupported CIR if branch: " & $branch.kind)
  let endTarget = uint32(code.data.len)
  for patch in endPatches: code.data[patch] = endTarget

proc genWhile(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode) =
  doAssert node.args.len >= 2, "Malformed CIR while statement"
  let loopStart = code.data.len
  let cond = code.genExpr(ctx, node.args[0])
  code.emitInst(vocJmpFalse, cond.pos, 0)
  let exitPatch = code.data.len
  code.emitWord(0'u32)
  code.freeTemp(cond)
  ctx.loopStarts.add(loopStart)
  ctx.breakPatches.add(@[])
  ctx.continuePatches.add(@[])
  ctx.pushScope()
  code.genStmt(ctx, node.args[1])
  ctx.popScope()
  let continueTarget = uint32(code.data.len)
  for patch in ctx.continuePatches[^1]: code.data[patch] = continueTarget
  code.emitInst(vocJmp, 0, 0)
  code.emitWord(uint32(loopStart))
  let endTarget = uint32(code.data.len)
  code.data[exitPatch] = endTarget
  for patch in ctx.breakPatches[^1]: code.data[patch] = endTarget
  ctx.loopStarts.setLen(ctx.loopStarts.len - 1)
  ctx.breakPatches.setLen(ctx.breakPatches.len - 1)
  ctx.continuePatches.setLen(ctx.continuePatches.len - 1)

proc genFor(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode) =
  doAssert node.args.len >= 3 and node.args[0].kind == cnkVarTy and node.args[1].kind == cnkInfix,
    "Malformed CIR for statement"
  let decl = node.args[0]
  let symDef = decl.args[0]
  let name = symDef.args[0].name
  let ty = if symDef.args.len > 1: symDef.args[1].name else: "int"
  let iter = node.args[1]
  
  ctx.pushScope()
  let loopVar = code.allocVar(ctx, name, ty)
  let startValue = code.genExpr(ctx, iter.args[1])
  
  code.emitInst(vocMov, loopVar.pos, startValue.pos)
  code.freeTemp(startValue)
  
  let stopValue = code.genExpr(ctx, iter.args[2])
  let exclusive = iter.args[0].name in ["..<", "<"]
  let loopStart = code.data.len
  let cond = code.allocTemp(ctx, "bool")
  
  code.emitInst(vocMov, cond.pos, loopVar.pos)
  code.emitInst(if exclusive: vocLti else: vocLei, cond.pos, stopValue.pos)
  code.emitInst(vocJmpFalse, cond.pos, 0)
  
  let exitPatch = code.data.len
  code.emitWord(0'u32)
  code.freeTemp(cond)
  ctx.loopStarts.add(loopStart)
  ctx.breakPatches.add(@[])
  ctx.continuePatches.add(@[])
  ctx.pushScope()
  code.genStmt(ctx, node.args[2])
  ctx.popScope()
  let stepTarget = uint32(code.data.len)
  for patch in ctx.continuePatches[^1]: code.data[patch] = stepTarget
  let one = code.allocTemp(ctx, "int")
  code.emitInst(vocLoadi, one.pos, 0)
  code.emitWord(1'u32)
  code.emitInst(vocAddi, loopVar.pos, one.pos)
  code.freeTemp(one)
  code.emitInst(vocJmp, 0, 0)
  code.emitWord(uint32(loopStart))
  let endTarget = uint32(code.data.len)
  code.data[exitPatch] = endTarget
  for patch in ctx.breakPatches[^1]: code.data[patch] = endTarget
  code.freeTemp(stopValue)
  ctx.loopStarts.setLen(ctx.loopStarts.len - 1)
  ctx.breakPatches.setLen(ctx.breakPatches.len - 1)
  ctx.continuePatches.setLen(ctx.continuePatches.len - 1)
  ctx.popScope()

proc genFunction(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode) =
  doAssert node.args.len >= 4 and node.args[0].kind == cnkSym, "Malformed CIR function"
  let name = node.args[0].name
  let params = node.args[1]
  code.procTable[name] = code.data.len
  if code.callToPatch.hasKey(name):
    for patch in code.callToPatch[name]: code.data[patch] = uint32(code.procTable[name])
    code.callToPatch.del(name)
  let previousProc = ctx.currentProc
  ctx.currentProc = name
  ctx.pushScope()
  var argOffset = 0
  if params.kind == cnkParams:
    for param in params.args:
      doAssert param.kind == cnkSymDef and param.args.len >= 2, "Malformed CIR parameter"
      let pName = param.args[0].name
      let pTy = param.args[1].name
      let pAlloc = code.allocVar(ctx, pName, pTy)
      code.emitInst(vocSMov, pAlloc.pos, argOffset)
      argOffset += pAlloc.size
  code.genStmt(ctx, node.args[3])
  code.emitInst(vocRet, 0, 0)
  ctx.popScope()
  ctx.currentProc = previousProc

proc genStmt(code: var CBytecode, ctx: var CIRGenCtx, node: CIRNode) =
  case node.kind
  of cnkNone, cnkEmpty, cnkTypeDef: discard
  of cnkStmtList, cnkSection:
    for child in node.args: code.genStmt(ctx, child)
  of cnkVarTy:
    code.genVar(ctx, node)
  of cnkAsgn:
    doAssert node.args.len >= 2
    let target = code.genExpr(ctx, node.args[0])
    doAssert target.size > 0, "Invalid CIR assignment target: " & renderIR(node.args[0])
    let value = code.genExpr(ctx, node.args[1])
    if value.pos != target.pos: code.emitInst(vocMov, target.pos, value.pos)
    code.freeTemp(value)
  of cnkIfStmt:
    code.genIf(ctx, node)
  of cnkWhileStmt:
    code.genWhile(ctx, node)
  of cnkForStmt:
    code.genFor(ctx, node)
  of cnkReturnStmt:
    if node.args.len > 0 and node.args[0].kind != cnkEmpty:
      let value = code.genExpr(ctx, node.args[0])
      code.emitInst(vocMov, 0, value.pos)
      code.freeTemp(value)
    code.emitInst(vocRet, 0, 0)
  of cnkCall:
    let value = code.genCall(ctx, node)
    code.freeTemp(value)
  of cnkDiscardStmt:
    if node.args.len > 0:
      let value = code.genExpr(ctx, node.args[0])
      code.freeTemp(value)
  of cnkBreakStmt:
    doAssert ctx.breakPatches.len > 0, "break outside loop"
    code.emitInst(vocJmp, 0, 0)
    ctx.breakPatches[^1].add(code.data.len)
    code.emitWord(0'u32)
  of cnkContinueStmt:
    doAssert ctx.continuePatches.len > 0, "continue outside loop"
    code.emitInst(vocJmp, 0, 0)
    ctx.continuePatches[^1].add(code.data.len)
    code.emitWord(0'u32)
  else:
    raise newException(ValueError, "Unsupported CIR statement: " & renderIR(node))

proc generateBytecodeFromIR*(root: CIRNode): seq[uint32] =
  var code = CBytecode(
    allocator: newVramAllocator(),
    procTable: initTable[string, int](),
    callToPatch: initTable[string, seq[int]](),
    data: @[]
  )
  var ctx = newIRGenCtx(root)
  let items = if root.kind in {cnkStmtList, cnkSection}: root.args else: @[root]
  for item in items:
    if item.kind == cnkFuncDef and item.args.len > 0:
      code.procTable[item.args[0].name] = -1
  for item in items:
    if item.kind == cnkFuncDef:
      code.genFunction(ctx, item)
    else:
      code.genStmt(ctx, item)
  doAssert code.callToPatch.len == 0, "Unresolved CIR procedure call(s)"
  doAssert ctx.breakPatches.len == 0 and ctx.continuePatches.len == 0
  result = code.data
