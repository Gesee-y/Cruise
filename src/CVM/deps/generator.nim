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

    ctx.code.emitInst(vocCall, bopCode.int, result.pos)
    let patchPos = ctx.code.data.len
    ctx.code.emitWord(if procPos >= 0: uint32(procPos) else: 0u32)

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
  ctx.code.emitInst(vocMov, alloc.pos, initAlloc.pos)
  ctx.code.freeIfTemp(initAlloc)

proc genAsgn(ctx: var CodeGenCtx, c: CIRNode) =
  let lhsAlloc = ctx.genExpr(c.args[0])
  let rhs = ctx.genExpr(c.args[1])
  ctx.code.emitInst(vocMov, lhsAlloc.pos, rhs.pos)
  ctx.code.freeIfTemp(rhs)

proc genIf(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for `(if (elif cond body)+ (else body)?)`.
  ## Uses two-word jump instructions: the instruction word encodes the
  ## opcode and condition register; the following word holds the target address.
  ## All forward jump targets are backpatched after the full if/else chain.
  var child       = firstChild(c)
  let boolTy      = ctx.cache.getType("bool")
  var endPatches: seq[int] = @[]   # positions of the "jump to end" target words

  while child.hasMore and child.otherKind == ElifU:
    var elifChild = firstChild(child)
    let condCur   = firstChild(elifChild)        # condition expression
    var bodyCur   = elifChild
    skip bodyCur                     # body (stmts)

    let condAlloc = ctx.genExpr(code, scopeId, boolTy, condCur)

    # Conditional jump: vocJmpFalse + target placeholder
    code.emitInst(vocJmpFalse, condAlloc.pos, 0)
    let falsePatch = code.data.len
    code.emitWord(0u32)
    code.freeIfTemp(condAlloc)

    # Generate the elif body in a fresh child scope.
    let childScopeId = ctx.nextChildScope(scopeId)
    ctx.genStmt(code, childScopeId, bodyCur)

    # Unconditional jump past remaining branches + else.
    code.emitInst(vocJmp, 0, 0)
    let endPatch = code.data.len
    code.emitWord(0u32)
    endPatches.add(endPatch)

    # Backpatch false-jump to land here (start of next branch / else / end).
    code.data[falsePatch] = uint32(code.data.len)

    skip child

  # Optional else branch.
  if child.hasMore and child.otherKind == ElseU:
    var elseBody = firstChild(child)
    let childScopeId = ctx.nextChildScope(scopeId)
    ctx.genStmt(code, childScopeId, elseBody)

  # Backpatch all end-of-if jumps.
  let endTarget = uint32(code.data.len)
  for pos in endPatches:
    code.data[pos] = endTarget

proc genWhile(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for `(while cond body)`.
  var child   = firstChild(c)
  let condCur = child
  var bodyCur = child
  skip bodyCur

  let loopStart = code.data.len
  let boolTy    = ctx.cache.getType("bool")

  let condAlloc = ctx.genExpr(code, scopeId, boolTy, condCur)

  # Exit the loop when condition is false.
  code.emitInst(vocJmpFalse, condAlloc.pos, 0)
  let exitPatch = code.data.len
  code.emitWord(0u32)
  code.freeIfTemp(condAlloc)

  # Loop body.
  let childScopeId = ctx.nextChildScope(scopeId)
  ctx.genStmt(code, childScopeId, bodyCur)

  # Jump back to condition evaluation.
  code.emitInst(vocJmp, 0, 0)
  code.emitWord(uint32(loopStart))

  # Backpatch exit.
  code.data[exitPatch] = uint32(code.data.len)

proc genFor(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for `(for iter vars body)`.
  var child = firstChild(c)
  let iterCur = child
  skip child
  var varsCur = child
  skip child
  let bodyCur = child

  # 1. Parse loop variable name and type
  var varName = ""
  var ty = ctx.cache.getType("int") # default to int

  if varsCur.kind == TagLit and varsCur.otherKind == UnpackflatU:
    var vchild = firstChild(varsCur)
    while vchild.hasMore:
      if vchild.stmtKind in {VarS, LetS}:
        var symNode = firstChild(vchild)
        if symNode.kind in {Symbol, SymbolDef}:
          varName = symNode.symText
          var typ = symNode
          skip typ # export
          skip typ # pragmas
          ty = ctx.cache.getType(typ.getTypeName)
          break
      skip vchild
  elif varsCur.kind in {Symbol, SymbolDef}:
    varName = varsCur.symText

  # Enter the child scope created for this loop
  let forScopeId = ctx.nextChildScope(scopeId)

  # Allocate loop variable using its liveness information
  var varAlloc = CAllocation()
  let nodeId = ctx.scopes[forScopeId].variables.fetchNode(varName)
  if nodeId >= 0:
    let v = ctx.scopes[forScopeId].variables.nodes[nodeId].data
    let bp = v.liveness.birth.info
    var lline = bp.line + 1
    var lcol = bp.col
    if v.liveness.uses.len > 0:
      let lp = v.liveness.uses[^1].info
      lline = lp.line
      lcol = lp.col
    varAlloc = code.allocator.alloc(max(1, ty.size), bp.line, bp.col, lline, lcol)
  else:
    varAlloc = code.allocator.alloc(max(1, ty.size))

  # 2. Parse iterator expression: (infix op start stop) or (call op start stop)
  var isExclusive = true
  var startCur = iterCur
  var stopCur = iterCur
  var hasExplicitStart = false

  if iterCur.kind == TagLit and iterCur.exprKind in {InfixX, CallX, CmdX}:
    var ic = firstChild(iterCur)
    let opStr = if ic.kind in {Symbol, SymbolDef}: ic.symText else: ""
    if opStr.contains("<"):
      isExclusive = true
    elif opStr.contains("..") or opStr.contains("\2E."):
      isExclusive = false
    else:
      isExclusive = true

    skip ic # skip op to start operand
    if ic.hasMore:
      startCur = ic
      skip ic # skip start operand to stop operand
      if ic.hasMore:
        stopCur = ic
        hasExplicitStart = true

  # 3. Initialize loop variable with start value
  if hasExplicitStart:
    let startAlloc = ctx.genExpr(code, scopeId, ty, startCur)
    if startAlloc.pos != varAlloc.pos:
      code.emitInst(vocMov, varAlloc.pos, startAlloc.pos)
    code.freeIfTemp(startAlloc)
  else:
    let zeroAlloc = code.allocator.alloc(1)
    code.emitInst(vocLoadi, zeroAlloc.pos, 0)
    code.emitWord(0u32)
    code.emitInst(vocMov, varAlloc.pos, zeroAlloc.pos)
    code.freeIfTemp(zeroAlloc)

  # 4. Evaluate upper bound (stop) once into an allocation
  let stopAlloc = ctx.genExpr(code, scopeId, ty, stopCur)

  # 5. Loop condition check
  let loopStart = code.data.len
  let cmpOp = if isExclusive: vocLti else: vocLei

  let condAlloc = code.allocator.alloc(1)
  code.emitInst(vocMov, condAlloc.pos, varAlloc.pos)
  code.emitInst(cmpOp, condAlloc.pos, stopAlloc.pos)

  code.emitInst(vocJmpFalse, condAlloc.pos, 0)
  let exitPatch = code.data.len
  code.emitWord(0u32)
  code.freeIfTemp(condAlloc)

  # 6. Generate body
  if bodyCur.kind != DotToken:
    let bodyScopeId = ctx.nextChildScope(forScopeId)
    ctx.genStmt(code, bodyScopeId, bodyCur)

  # 7. Step / Increment: varAlloc += 1
  let oneAlloc = code.allocator.alloc(1)
  code.emitInst(vocLoadi, oneAlloc.pos, 0)
  code.emitWord(1u32)
  code.emitInst(vocAddi, varAlloc.pos, oneAlloc.pos)
  code.freeIfTemp(oneAlloc)

  # 8. Jump back to condition
  code.emitInst(vocJmp, 0, 0)
  code.emitWord(uint32(loopStart))

  # 9. Backpatch exit jump
  code.data[exitPatch] = uint32(code.data.len)

  # 10. Free stopAlloc if it was temporary
  code.freeIfTemp(stopAlloc)

proc genRet(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for `(ret .X)`.
  ## When a return value is present it is moved into register 0 by convention.
  var child = firstChild(c)
  if child.kind != DotToken:
    let procInst = ctx.cache.getType(ctx.currentProcName)
    let retTy    = if procInst.returnType != "": ctx.cache.getType(procInst.returnType)
                   else: TypeInst(kind: PrimitiveType, size: 1)
    let retAlloc = ctx.genExpr(code, scopeId, retTy, child)
    code.emitInst(vocMov, 0, retAlloc.pos)
    code.freeIfTemp(retAlloc)
  code.emitInst(vocRet, 0, 0)

proc genDiscard(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for `(discard .X)`: evaluate the expression for side effects
  ## and immediately discard the result.
  var child = firstChild(c)
  if child.kind != DotToken:
    let ty    = TypeInst(kind: UnknownType, size: 1)
    let alloc = ctx.genExpr(code, scopeId, ty, child)
    code.freeIfTemp(alloc)

proc genCallStmt(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for a call used as a statement (result discarded).
  let ty    = TypeInst(kind: UnknownType, size: 1)
  let alloc = ctx.genExpr(code, scopeId, ty, c)
  code.freeIfTemp(alloc)

proc genStmt(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Dispatch one block of statements.
  ## `c` must point to a `stmts` or `block` node (or DotToken for empty body).
  if c.kind == DotToken: return

  assert c.stmtKind in {StmtsS, BlockS, ScopeS},
    "genStmt: expected stmts/block/scope, got `" & renderNode(c) & "`."

  var n = c
  n.loopInto:
    case n.kind
    of DotToken: discard   # empty placeholder
    of TagLit:
      case n.stmtKind
      of StmtsS, BlockS, ScopeS:
        ## Nested block — consume the next child scope.
        let childScopeId = ctx.nextChildScope(scopeId)
        ctx.genStmt(code, childScopeId, n)

      of VarS, LetS, TvarS, TletS:
        ctx.genVar(code, scopeId, n)

      of AsgnS:
        ctx.genAsgn(code, scopeId, n)

      of IfS:
        ctx.genIf(code, scopeId, n)

      of WhenS:
        ctx.genIf(code, scopeId, n)   # treat `when` identically for now

      of WhileS:
        ctx.genWhile(code, scopeId, n)

      of ForS:
        ctx.genFor(code, scopeId, n)

      of RetS:
        ctx.genRet(code, scopeId, n)

      of DiscardS:
        ctx.genDiscard(code, scopeId, n)

      of CallS, CmdS:
        ctx.genCallStmt(code, scopeId, n)

      of AssumeS, AssertS, LabS, ContinueS, BreakS:
        discard

      of UnpackdeclS:
        ## Tuple unpacking: treat each inner var/let individually.
        var inner = firstChild(n)
        while inner.hasMore:
          if inner.stmtKind in {VarS, LetS}:
            ctx.genVar(code, scopeId, inner)
          skip inner

      of TypeS, ImportS, CommentS:
        discard    # not relevant to code generation

      else:
        ## Propagate into substructures (elif, else, etc.).
        case n.otherKind
        of ElifU, ElseU, OfU:
          discard   # handled by their parent statement
        else:
          discard

    else:
      discard   # raw tokens at statement level are ignored
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
