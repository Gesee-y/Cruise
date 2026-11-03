  # ###################################################################################################################################### #
 # ########################################################## CODE GENERATOR ############################################################ #
# ###################################################################################################################################### #

# ################################################################################################################################ #
# ############################################################ TYPES ############################################################# #
# ################################################################################################################################ #

type
  CMemLoc = int ## Virtual-memory address (word index).

  CBytecode = object
    data:       seq[uint32]
    allocator:  CVramAllocator
    ## Maps each proc name to its starting word index in `data`.
    ## Entries start at -1 (placeholder) and are backpatched by `genFunc`.
    procTable:  Table[string, int]
    callToPatch: Table[string, seq[int]]
    currentPos: int

  CodeGenCtx = object
    cache: TypeCache
    code: CBytecode

# ################################################################################################################################ #
# ############################################################ CONSTANTS ######################################################### #
# ################################################################################################################################ #

const
  INT_SIZE = 4
  FLOAT_SIZE = 4
  CHAR_SIZE = 1
  OPCODE_BITS = 8
  REGA_BITS   = 8
  REGB_BITS   = 8
  REGA_POS    = REGB_BITS           ##  8: shift for the destination field
  OPCODE_POS  = REGA_POS + REGA_BITS ## 16: shift for the opcode field
  # TODO: Add unused byte constant

# ################################################################################################################################ #
# ########################################################## HELPER PROCS ######################################################## #
# ################################################################################################################################ #

proc opcodeFor(op: string, isFloat: bool): VMOpCode =
  case op
  of "+": if isFloat: vocAddf else: vocAddi
  of "-": if isFloat: vocSubf else: vocSubi
  of "*": if isFloat: vocMulf else: vocMuli
  of "/": if isFloat: vocDivf else: vocDivi
  of "mod": vocMod
  of "and": vocAnd
  of "or": vocOr
  of "xor": vocXor
  of "==": if isFloat: vocEqf else: vocEqi
  of "!=": if isFloat: vocNeqf else: vocNeqi
  of "<": if isFloat: vocLtf else: vocLti
  of "<=": if isFloat: vocLef else: vocLei
  of ">": if isFloat: vocLtf else: vocLti
  of ">=": if isFloat: vocLef else: vocLei
  else: assert false, "Unsupported CIR binary operator: " & op

proc prefixOpcodeFor(op: string, isFloat: bool): VMOpCode =
  case op
  of "not": vocNot
  of "-": if isFloat: vocNegf else: vocNegi
  else: assert false, "Unsupported CIR unary operator: " & op

proc isFloatType(ty: TypeInst): bool {.inline.} =
  ## Returns true when `ty` is a floating-point primitive.
  ty.name.startsWith("float")

proc genInstruction(op: VMOpCode, dst, src: CMemLoc): uint32 {.inline.} =
  ## Encode a two-operand instruction into a single 32-bit word.
  (uint32(op) shl OPCODE_POS) or (uint32(dst) shl REGA_POS) or uint32(src)

proc emitInst(ctx: var CodeGenCtx, op: VMOpCode, dst, src: CMemLoc) {.inline.} =
  ## Append a single instruction word and advance `currentPos`.
  ctx.code.data.add(genInstruction(op, dst, src))
  inc ctx.code.currentPos

proc emitWord(ctx: var CodeGenCtx, word: uint32) {.inline.} =
  ## Append a raw 32-bit word (e.g. an immediate value or jump target).
  ctx.code.data.add(word)
  inc ctx.code.currentPos

proc freeIfTemp(ctx: var CodeGenCtx, alloc: CAllocation) {.inline.} =
  ## Free `alloc` when it is a temporary scratch allocation.
  ## Named variable allocations (`isTemp = false`) are left untouched;
  ## they are reclaimed automatically by the allocator's tick mechanism.
  if alloc.isTemp and alloc.size > 0:
    ctx.code.allocator.free(alloc)

# ################################################################################################################################ #
# ##################################################### VARIABLE RESOLUTION ###################################################### #
# ################################################################################################################################ #

proc lookupVarAlloc(ctx: var CodeGenCtx, l: CLiveness): CAllocation =
  ## Retrieve the named allocation for `v` using its birth position as key.
  ## Returns an empty CAllocation (size = 0) when the variable has no entry
  ## in the allocator table (e.g. an external or untracked symbol).
  let sp = lineCol(l.birth.info)
  ctx.code.allocator.lookup(sp.line, sp.col)

proc resolveSymbol(ctx: var CodeGenCtx, c: CIRNode): CAllocation =
  ## Resolve a Symbol cursor to the CAllocation of the named variable.
  ## Searches the scope chain upward.  Returns an empty CAllocation on failure.
  let varName = c.name
  result = lookupVarAlloc(code, ctx.cache.liveness.getOrDefault(varName))

# ################################################################################################################################ #
# ############################################################# EXPRESSIONS ###################################################### #
# ################################################################################################################################ #

proc genExpr(ctx: var CodeGenCtx, c: CIRNode): CAllocation =
  ## Generate code that evaluates the expression at `c` and returns the
  ## allocation holding the result.
  result = default(CAllocation)
  case c.kind:
  of cnkInfix:
    let opName = c.args[0].name
    let opTypeName = ctx.cache.inferType(c)
    let opIsFloat  = opTypeName.startsWith("float")
    let opTy = ctx.cache.getType(opTypeName)

    result = code.allocator.alloc(opTy.size)

    let r1 = ctx.genExpr(code, scopeId, c.args[1])
    let r2 = ctx.genExpr(code, scopeId, c.args[2])

    code.emitInst(vocMov, result.pos, r1.pos)
    code.emitInst(opcodeFor(opName, opIsFloat), result.pos, r2.pos)

    code.freeIfTemp(r1)
    code.freeIfTemp(r2)
    return

  # Unary boolean not — (not X), no type annotation
  of cnkPrefix:
    let opName = c.args[0].name
    let opTypeName = ctx.cache.inferType(c)
    let opIsFloat  = opTypeName.startsWith("float")
    let opTy = ctx.cache.getType(opTypeName)
    let operand = ctx.genExpr(code, scopeId, child)
    
    result = code.allocator.alloc(opTy.size)
    code.emitInst(prefixOpcodeFor(opName, opIsFloat), result.pos, operand.pos)
    code.freeIfTemp(operand)
    return

  # Field access — (dot obj field INTLIT? STRLIT?)
  of cnkDotExpr:
    result = ctx.genExpr(n.args[0])

    var offset = 0
    var basetype = ctx.cache.inferType(n.args[0])
    var currentType = basetype
    var current = node.args[1]
    var fields: seq[string] = @[]

    while current.kind == cnkDotExpr:
      let f = current.args[0].name
      let fid = ctx.cache.getType(currentType).nameToId.getOrDefault(f)
      current = current.args[1]

      result.pos += ctx.cache.getType(currentType).fields[fid].offset
      currentType = ctx.cache.getType(currentType).name
      fields.add(f)
    
    fields.add(current.name)
    result.pos += offset
    result.size = ctx.cache.getType(basetype, fields).size
    
  # Function call — (call callee arg*)
  of cnkCall:
    result = ctx.code.allocator.alloc(ty.size)
    var argsToFree: seq[CAllocation] = @[]
    let procName = c.args[0].symText.split(".")[0]

    # Push arguments left-to-right onto the call stack.
    for i in 1..<c.args.len:
      # Use an unknown type approximation for argument types.
      let argAlloc = ctx.genExpr(c.args[i])
      code.emitInst(vocPush, argAlloc.pos, 0)
      argsToFree.add(argAlloc)

    for argAlloc in argsToFree:
      code.freeIfTemp(argAlloc)

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

  # Boolean literals
  of cnkBoolLit:
    result = code.allocator.alloc(CHAR_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(uint32(c.boolVal))
    return

  of cnkSym:
    ## Resolve variable by birth-position key 
    let alloc = ctx.resolveSymbol(c)
    return alloc

  of cnkIntLit:
    result = code.allocator.alloc(INT_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(cast[uint32](c.intVal))

  of cnkUintLit:
    result = code.allocator.alloc(INT_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(cast[uint32](c.uintVal))

  of cnkFloatLit:
    result = code.allocator.alloc(FLOAT_SIZE)
    code.emitInst(vocLoadf, result.pos, 0)
    code.emitWord(cast[uint32](c.floatVal))

  of cnkCharLit:
    result = code.allocator.alloc(CHAR_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(uint32(ord(c.charVal)))
  else: discard "Unsupported expression `" & renderIR(c) & "`."

# ################################################################################################################################ #
# ############################################################## STATEMENTS ###################################################### #
# ################################################################################################################################ #

proc genVar(ctx: var CodeGenCtx, c: CIRNode) =
  ## Generate code for a `var` or `let` declaration.
  ## Allocates virtual memory using the variable's birth and last-use positions
  ## so the allocator can reclaim the slot automatically.

  var sym = c.args[0]
  let ty = ctx.cache.getType(sym.args[1])

  let l = ctx.cache.liveness.getOrDefault(sym.args[0].name)
  var bp = l.birth
  var lline = l.dead.line
  var lcol  = l.dead.col

  # Named allocation: automatically freed when (lline, lcol) is passed.
  let alloc = ctx.code.allocator.alloc(max(1, ty.size), bp.line, bp.col, lline, lcol)

  # Emit initializer when present.
  let initAlloc = ctx.genExpr(c.args[1])
  ctx.emitInst(vocMov, alloc.pos, initAlloc.pos)
  ctx.freeIfTemp(initAlloc)

proc genAsgn(ctx: var CodeGenCtx, c: CIRNode) =
  let lhsAlloc = ctx.genExpr(c.args[0])
  let rhs = ctx.genExpr(c.args[1])
  ctx.emitInst(vocMov, lhsAlloc.pos, rhs.pos)
  ctx.freeIfTemp(rhs)

proc genIf(ctx: var CodeGenCtx, c: CIRNode) =
  ## Generate code for `(if (elif cond body)+ (else body)?)`.
  ## Uses two-word jump instructions: the instruction word encodes the
  ## opcode and condition register; the following word holds the target address.
  ## All forward jump targets are backpatched after the full if/else chain.
  var endPatches: seq[int] = @[]   # positions of the "jump to end" target words
  var i = 0

  while i < ctx.args.len and c.args[i].kind == cnkElifBranch:
    let condAlloc = ctx.genExpr(code, c.args[0])
    ctx.emitInst(vocJmpFalse, condAlloc.pos, 0)
    
    let falsePatch = code.data.len
    ctx.emitWord(0u32)
    ctx.freeIfTemp(condAlloc)

    # Generate the elif body in a fresh child scope.
    ctx.genStmt(c.args[1])
    ctx.emitInst(vocJmp, 0, 0)

    let endPatch = code.data.len
    ctx.emitWord(0u32)
    endPatches.add(endPatch)

    # Backpatch false-jump to land here (start of next branch / else / end).
    ctx.code.data[falsePatch] = uint32(ctx.code.data.len)
    inc i

  # Optional else branch.
  if i < c.args.len:
    ctx.genStmt(c.args[^1])

  # Backpatch all end-of-if jumps.
  let endTarget = uint32(ctx.code.data.len)
  for pos in endPatches:
    ctx.code.data[pos] = endTarget

proc genWhile(ctx: var CodeGenCtx, c: CIRNode) =
  ## Generate code for `(while cond body)`.
  let loopStart = ctx.code.data.len
  let condAlloc = ctx.genExpr(c.args[0])

  # Exit the loop when condition is false.
  ctx.emitInst(vocJmpFalse, condAlloc.pos, 0)
  let exitPatch = code.data.len
  ctx.emitWord(0u32)
  ctx.freeIfTemp(condAlloc)

  ctx.genStmt(c.args[1])

  # Jump back to condition evaluation.
  ctx.emitInst(vocJmp, 0, 0)
  ctx.emitWord(uint32(loopStart))

  # Backpatch exit.
  ctx.code.data[exitPatch] = uint32(ctx.code.data.len)

proc genFor(ctx: var CodeGenCtx, c: CIRNode) =
  ## Generate code for `(for iter vars body)`.
  ctx.genVar(c.args[0].args[0])
  let sym = c.args[0].args[0].args[0]
  let varName = sym.args[0].name

  # 2. Parse iterator expression: (infix op start stop) or (call op start stop)
  var isExclusive = true
  var iter = c.args[1]
  var hasExplicitStart = false

  var ic = firstChild(iterCur)
  let opStr = iter.args[0].name
  if opStr.contains("<"):
    isExclusive = true
  elif opStr.contains("..") or opStr.contains("\2E."):
    isExclusive = false
  else:
    isExclusive = true

  # 3. Initialize loop variable with start value
  let startAlloc = ctx.genExpr(iter.args[1])
  ctx.emitInst(vocMov, varAlloc.pos, startAlloc.pos)
  ctx.freeIfTemp(startAlloc)
  
  # 4. Evaluate upper bound (stop) once into an allocation
  let stopAlloc = ctx.genExpr(iter.args[2])

  # 5. Loop condition check
  let loopStart = ctx.code.data.len
  let cmpOp = if isExclusive: vocLti else: vocLei

  let condAlloc = ctx.code.allocator.alloc(1)
  ctx.emitInst(vocMov, condAlloc.pos, varAlloc.pos)
  ctx.emitInst(cmpOp, condAlloc.pos, stopAlloc.pos)

  ctx.emitInst(vocJmpFalse, condAlloc.pos, 0)
  let exitPatch = ctx.code.data.len
  ctx.emitWord(0u32)
  ctx.freeIfTemp(condAlloc)
  ctx.genStmt(c.args[2])

  # 7. Step / Increment: varAlloc += 1
  let oneAlloc = ctx.code.allocator.alloc(1)
  ctx.emitInst(vocLoadi, oneAlloc.pos, 0)
  ctx.emitWord(1u32)
  ctx.emitInst(vocAddi, varAlloc.pos, oneAlloc.pos)
  ctx.freeIfTemp(oneAlloc)

  # 8. Jump back to condition
  ctx.emitInst(vocJmp, 0, 0)
  ctx.emitWord(uint32(loopStart))

  # 9. Backpatch exit jump
  ctx.code.data[exitPatch] = uint32(ctx.code.data.len)

  # 10. Free stopAlloc if it was temporary
  ctx.freeIfTemp(stopAlloc)

proc genRet(ctx: var CodeGenCtx, c: CIRNode) =
  ## Generate code for `(ret .X)`.
  ## When a return value is present it is moved into register 0 by convention.
  if c.args[0].kind != cnkEmpty:
    let retAlloc = ctx.genExpr(c.args[0])
    ctx.emitInst(vocMov, 0, retAlloc.pos)
    ctx.freeIfTemp(retAlloc)
  ctx.emitInst(vocRet, 0, 0)

proc genDiscard(ctx: var CodeGenCtx, c: CIRNode) =
  ## Generate code for `(discard .X)`: evaluate the expression for side effects
  ## and immediately discard the result.
  if c.args[0].kind != cnkEmpty:
    let disAlloc = ctx.genExpr(c.args[0])
    ctx.emitInst(vocMov, 0, disAlloc.pos)
    ctx.freeIfTemp(disAlloc)

proc genCallStmt(ctx: var CodeGenCtx, c: CIRNode) =
  ## Generate code for a call used as a statement (result discarded).
  let alloc = ctx.genExpr(c)
  code.freeIfTemp(alloc)

proc genStmt(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Dispatch one block of statements.
  ## `c` must point to a `stmts` or `block` node (or DotToken for empty body).
  for n in c.args
    case n.kind
    of cnkEmpty: discard   # empty placeholder
    of StmtsS, BlockS, ScopeS:
      ## Nested block — consume the next child scope.
      let childScopeId = ctx.nextChildScope(scopeId)
      ctx.genStmt(code, childScopeId, n)

    of cnkVarTy:
      ctx.genVar(n)

    of cnkAsgn:
      ctx.genAsgn(n)

    of cnkIf:
      ctx.genIf(n)

    of cnkWhileStmt:
      ctx.genWhile(n)

    of cnkForStmt:
      ctx.genFor(n)

    of cnkReturnStmt:
      ctx.genRet(n)

    of cnkDiscardStmt:
      ctx.genDiscard(n)

    of cnkCall:
      ctx.genCallStmt(n)

    of cnkContinueStmt, cnkBreakStmt: discard

    of cnkSection:
      ## Tuple unpacking: treat each inner var/let individually.
      var inner = firstChild(n)
      for arg in c.args:
        if inner.stmtKind in {VarS, LetS}:
          ctx.genVar(inner)
    skip n

proc genFunc(ctx: var CodeGenCtx, code: var CBytecode, c: NifCursor) =
  ## Generate code for a proc or func declaration.
  assert c.stmtKind in {ProcS, FuncS},
    "genFunc: expected proc/func, got `" & renderNode(c) & "`."

  var symNode = firstChild(c)   # SymbolDef
  if symNode.kind != SymbolDef: return

  let name = symNode.symText
  let ty   = ctx.cache.getType(name)
  var offset = 0
  var ownerScope = addr ctx.scopes[ty.scopeId]
  
  # For a function, the fields are it's arguments
  for field in ty.fields:
    # We get the scope and the variable for each arguments
    let fid = ownerScope.variables.fetchNode(field.name)
    let v  = addr ownerScope.variables.nodes[fid].data

    # Getting liveness information for the allocations
    let bp = v.liveness.birth.info
    var lline = bp.line + 1
    var lcol  = bp.col
    if v.liveness.uses.len > 0:
      let lp = v.liveness.uses[^1].info
      lline = lp.line
      lcol  = lp.col

    # Allocate the variable, then emitting a move to get the effective value of the variable from the stack
    let fsize = ctx.cache.getType(field.ty).size
    let allc = code.allocator.alloc(fsize, bp.line, bp.col, lline, lcol)
    code.emitInst(vocSMov, allc.pos, offset)

    # Updating the offset so we can fetch the next argument
    offset += fsize

  # Record the real starting address (backpatch the placeholder set by
  # predeclareFunctions).
  code.procTable[name] = code.currentPos
  ctx.currentProcName  = name

  if code.callToPatch.hasKey(name):
    let patchList = code.callToPatch.getOrDefault(name, @[])
    for patchPos in patchList:
      code.data[patchPos] = uint32(code.currentPos)
    code.callToPatch.del(name)

  # Locate the body statement node among proc children dynamically
  var cur = firstChild(c)
  while cur.hasMore:
    if cur.stmtKind in {StmtsS, BlockS, ScopeS}:
      ctx.genStmt(code, ty.scopeId, cur)
      break
    skip cur

  # Implicit return at the end of every proc.
  code.emitInst(vocRet, 0, 0)

proc predeclareFunctions(code: var CBytecode, root: NifCursor) =
  ## Pre-register all top-level procs in `procTable` with a -1 placeholder.
  ## Forward calls can then emit a reference that is backpatched by `genFunc`.
  var n = root
  n.loopInto:
    if n.stmtKind in {ProcS, FuncS}:
      var sym = firstChild(n)
      if sym.kind == SymbolDef:
        code.procTable[sym.symText] = -1
    n.skip()
