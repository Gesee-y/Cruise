  # ###################################################################################################################################### #
 # ########################################################## CODE GENERATOR ############################################################ #
# ###################################################################################################################################### #

# ################################################################################################################################ #
# ############################################################ TYPES ############################################################# #
# ################################################################################################################################ #

type
  CMemLoc = int ## Virtual-memory address (word index).

  CBytecode = object
    data:        seq[uint32]
    allocator:   CVramAllocator
    ## Maps each proc name to its starting word index in `data`.
    ## Entries start at -1 (placeholder) and are backpatched by `genFunc`.
    procTable:   Table[string, int]
    callToPatch: Table[string, seq[int]]
    currentPos:  int

  LoopContext = object
    continueTarget:  int        ## Target word index for continue (if >= 0)
    continuePatches: seq[int]   ## Positions to backpatch for continue jumps
    breakPatches:    seq[int]   ## Positions to backpatch for break jumps

  CodeGenCtx = object
    cache:           TypeCache
    code:            CBytecode
    currentProcName: string
    loops:           seq[LoopContext]

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

# ################################################################################################################################ #
# ########################################################## HELPER PROCS ######################################################## #
# ################################################################################################################################ #

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
  of "<":
    if isFloat: return vocLtf 
    else: return vocLti
  of "<=":
    if isFloat: return vocLef 
    else: return vocLei
  of ">":
    if isFloat: return vocLtf 
    else: return vocLti
  of ">=":
    if isFloat: return vocLef 
    else: return vocLei
  else: assert false, "Failed to get infix opcode for `" & op & "`."

proc prefixOpcodeFor(op: string, isFloat: bool): VMOpCode =
  case op
  of "not":
    vocNot
  of "-":
    if isFloat: return vocNegf 
    else: return vocNegi
  else: assert false, "Failed to get prefix opcode for `" & op & "`."

proc isFloatType(ty: TypeInst): bool {.inline.} =
  ty.name.startsWith("float")

proc genInstruction(op: VMOpCode, dst, src: CMemLoc, size: int = 1): uint32 {.inline.} =
  (uint32(size and 0xFF) shl SIZE_POS) or (uint32(op) shl OPCODE_POS) or (uint32(dst and 0xFF) shl REGA_POS) or uint32(src and 0xFF)

proc emitInst(ctx: var CodeGenCtx, op: VMOpCode, dst, src: CMemLoc, size: int = 1) {.inline.} =
  ctx.code.data.add(genInstruction(op, dst, src, size))
  inc ctx.code.currentPos

proc emitWord(ctx: var CodeGenCtx, word: uint32) {.inline.} =
  ctx.code.data.add(word)
  inc ctx.code.currentPos

proc freeIfTemp(ctx: var CodeGenCtx, alloc: CAllocation) {.inline.} =
  if alloc.isTemp and alloc.size > 0:
    ctx.code.allocator.free(alloc)

# ################################################################################################################################ #
# ##################################################### VARIABLE RESOLUTION ###################################################### #
# ################################################################################################################################ #

proc resolveSymbol(ctx: var CodeGenCtx, c: CIRNode): CAllocation =
  if c.name in ctx.cache.liveness:
    let l = ctx.cache.liveness.getOrDefault(c.name)
    return ctx.code.allocator.lookup(l.birth.line, l.birth.col)
  else:
    return CAllocation()

proc getFieldReg(ctx: var CodeGenCtx, baseReg: CAllocation, c: CIRNode): CAllocation =
  result = baseReg
  var offset = 0
  var dummyArg0 = c.args[0]
  var basetype = ctx.cache.inferType(dummyArg0)
  var currentType = basetype
  var current = c.args[1]
  var fields: seq[string] = @[]

  while current.kind == cnkDotExpr:
    let f = current.args[0].name
    let fid = ctx.cache.getType(currentType).nameToId.getOrDefault(f, -1)
    current = current.args[1]

    if fid >= 0:
      offset += ctx.cache.getType(currentType).fields[fid].offset
      currentType = ctx.cache.getType(currentType).fields[fid].ty
    fields.add(f)
  
  let f = current.name
  let fid = ctx.cache.getType(currentType).nameToId.getOrDefault(f, -1)
  if fid >= 0:
    offset += ctx.cache.getType(currentType).fields[fid].offset
  fields.add(f)
  result.pos += offset
  result.size = ctx.cache.getType(basetype, fields).size
  result.isTemp = false

# ################################################################################################################################ #
# ############################################################# EXPRESSIONS ###################################################### #
# ################################################################################################################################ #

proc genExpr(ctx: var CodeGenCtx, c: CIRNode): CAllocation =
  result = default(CAllocation)
  case c.kind
  of cnkInfix:
    let opName = c.args[0].name
    var dummyNode = c
    let opTypeName = ctx.cache.inferType(dummyNode)
    let opIsFloat  = opTypeName.startsWith("float")
    let opTy = ctx.cache.getType(opTypeName)
    let opSize = max(1, opTy.size)

    result = ctx.code.allocator.alloc(opSize)

    let r1 = ctx.genExpr(c.args[1])
    let r2 = ctx.genExpr(c.args[2])

    ctx.emitInst(vocMov, result.pos, r1.pos, opSize)
    ctx.emitInst(opcodeFor(opName, opIsFloat), result.pos, r2.pos, opSize)

    ctx.freeIfTemp(r1)
    ctx.freeIfTemp(r2)
    return

  of cnkPrefix:
    let opName = c.args[0].name
    var dummyNode = c
    let opTypeName = ctx.cache.inferType(dummyNode)
    let opIsFloat  = opTypeName.startsWith("float")
    let opTy = ctx.cache.getType(opTypeName)
    let opSize = max(1, opTy.size)
    let operand = ctx.genExpr(c.args[1])
    
    result = ctx.code.allocator.alloc(opSize)
    ctx.emitInst(prefixOpcodeFor(opName, opIsFloat), result.pos, operand.pos, opSize)
    ctx.freeIfTemp(operand)
    return

  of cnkDotExpr:
    result = ctx.genExpr(c.args[0])
    result = ctx.getFieldReg(result, c)

    return

  of cnkCall:
    let procName = c.args[0].name
    var retSize = 1
    let procInst = ctx.cache.getType(procName)
    if procInst.returnType != "":
      retSize = ctx.cache.getType(procInst.returnType).size

    result = ctx.code.allocator.alloc(max(1, retSize))
    var argsToFree: seq[CAllocation] = @[]

    for i in 1 ..< c.args.len:
      let argAlloc = ctx.genExpr(c.args[i])
      ctx.emitInst(vocPush, argAlloc.pos, 0)
      argsToFree.add(argAlloc)

    for argAlloc in argsToFree:
      ctx.freeIfTemp(argAlloc)

    let bopCode = toBuiltinCall(procName)
    var procPos = 0
    
    if bopCode == boCustom:
      procPos = ctx.code.procTable.getOrDefault(procName, -1)

    ctx.emitInst(vocCall, bopCode.int, result.pos)
    let patchPos = ctx.code.data.len
    ctx.emitWord(if procPos >= 0: uint32(procPos) else: 0u32)

    if bopCode == boCustom and procPos < 0:
      var list = ctx.code.callToPatch.getOrDefault(procName, @[])
      list.add(patchPos)
      ctx.code.callToPatch[procName] = list
    return

  of cnkConv:
    if c.args.len > 1:
      return ctx.genExpr(c.args[1])
    return default(CAllocation)

  of cnkBoolLit:
    result = ctx.code.allocator.alloc(CHAR_SIZE)
    ctx.emitInst(vocLoadi, result.pos, 0)
    ctx.emitWord(if c.boolVal: 1u32 else: 0u32)
    return

  of cnkSym, cnkRSym:
    let alloc = ctx.resolveSymbol(c)
    return alloc

  of cnkIntLit:
    result = ctx.code.allocator.alloc(INT_SIZE)
    ctx.emitInst(vocLoadi, result.pos, 0)
    ctx.emitWord(cast[uint32](c.intVal))
    return

  of cnkUintLit:
    result = ctx.code.allocator.alloc(INT_SIZE)
    ctx.emitInst(vocLoadi, result.pos, 0)
    ctx.emitWord(cast[uint32](c.uintVal))
    return

  of cnkFloatLit:
    result = ctx.code.allocator.alloc(FLOAT_SIZE)
    ctx.emitInst(vocLoadf, result.pos, 0)
    ctx.emitWord(cast[uint32](c.floatVal))
    return

  of cnkCharLit:
    result = ctx.code.allocator.alloc(CHAR_SIZE)
    ctx.emitInst(vocLoadi, result.pos, 0)
    ctx.emitWord(uint32(ord(c.charVal)))
    return

  of cnkObjConstr:
    let typeName = c.args[0].name
    let typeInst = ctx.cache.getType(typeName)
    let totalSize = max(1, typeInst.size)
    result = ctx.code.allocator.alloc(totalSize)

    for i in 1 ..< c.args.len:
      let kv = c.args[i]
      if kv.kind == cnkKv and kv.args.len >= 2:
        let fieldName = kv.args[0].name
        let fid = typeInst.nameToId.getOrDefault(fieldName, -1)
        let valAlloc = ctx.genExpr(kv.args[1])
        if fid >= 0:
          let field = typeInst.fields[fid]
          let fsize = max(1, ctx.cache.getType(field.ty).size)
          let copyWords = min(fsize, max(1, valAlloc.size))
          ctx.emitInst(vocMov, result.pos + field.offset, valAlloc.pos, copyWords)
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
  if lline == 0 and lcol == 0:
    lline = bp.line + 1
    lcol  = bp.col

  let alloc = ctx.code.allocator.alloc(max(1, ty.size), bp.line, bp.col, lline, lcol)

  if c.args.len > 1 and c.args[1].kind != cnkEmpty:
    let initAlloc = ctx.genExpr(c.args[1])
    if initAlloc.pos != alloc.pos:
      let wordsToCopy = max(1, min(alloc.size, max(1, initAlloc.size)))
      ctx.emitInst(vocMov, alloc.pos, initAlloc.pos, wordsToCopy)
    ctx.freeIfTemp(initAlloc)

proc genAsgn(ctx: var CodeGenCtx, c: CIRNode) =
  let lhsAlloc = ctx.genExpr(c.args[0])
  let rhs = ctx.genExpr(c.args[1])
  if lhsAlloc.size > 0 and rhs.pos != lhsAlloc.pos:
    let wordsToCopy = max(1, min(lhsAlloc.size, max(1, rhs.size)))
    ctx.emitInst(vocMov, lhsAlloc.pos, rhs.pos, wordsToCopy)
  ctx.freeIfTemp(rhs)

proc genIf(ctx: var CodeGenCtx, c: CIRNode) =
  var endPatches: seq[int] = @[]

  for branch in c.args:
    case branch.kind
    of cnkElifBranch:
      let condAlloc = ctx.genExpr(branch.args[0])
      ctx.emitInst(vocJmpFalse, condAlloc.pos, 0)
      let falsePatch = ctx.code.data.len
      ctx.emitWord(0u32)
      ctx.freeIfTemp(condAlloc)

      ctx.genStmt(branch.args[1])

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
  let startAlloc = ctx.genExpr(iter.args[1])
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
  ctx.emitInst(vocLoadi, oneAlloc.pos, 0)
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
    let retAlloc = ctx.genExpr(c.args[0])
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

proc genFunc(ctx: var CodeGenCtx, c: CIRNode) =
  let name = c.args[0].name
  ctx.currentProcName = name
  ctx.loops = @[]
  
  var offset = 0
  if c.args[1].kind == cnkParams:
    for param in c.args[1].args:
      let paramName = param.args[0].name
      let paramTyName = param.args[1].name
      let paramTy = ctx.cache.getType(paramTyName)
      
      let l = ctx.cache.liveness.getOrDefault(paramName)
      let bp = l.birth
      var lline = l.dead.line
      var lcol  = l.dead.col
      if lline == 0 and lcol == 0:
        lline = bp.line + 1
        lcol  = bp.col
        
      let fsize = max(1, paramTy.size)
      let alloc = ctx.code.allocator.alloc(fsize, bp.line, bp.col, lline, lcol)
      ctx.emitInst(vocSMov, alloc.pos, offset, fsize)
      offset += fsize

  ctx.code.procTable[name] = ctx.code.currentPos

  if ctx.code.callToPatch.hasKey(name):
    let patchList = ctx.code.callToPatch.getOrDefault(name, @[])
    for patchPos in patchList:
      ctx.code.data[patchPos] = uint32(ctx.code.currentPos)
    ctx.code.callToPatch.del(name)

  ctx.genStmt(c.args[3])
  ctx.emitInst(vocRet, 0, 0)

proc genStmt*(ctx: var CodeGenCtx, c: CIRNode) =
  case c.kind
  of cnkEmpty: discard
  of cnkStmtList, cnkSection:
    for n in c.args:
      ctx.genStmt(n)
  of cnkVarTy:
    ctx.genVar(c)
  of cnkAsgn:
    ctx.genAsgn(c)
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
