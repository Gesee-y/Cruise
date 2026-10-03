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
    callToPatch: Table[string, int] # TODO: Reverse this to `Table[int, string]` as `int` are more precise
    currentPos: int

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

proc toOpcode(op: NimonyExpr, isFloat: bool): VMOpCode =
  ## Map a binary NimonyExpr tag to the matching VM opcode,
  ## choosing between the integer and float variant via `isFloat`.
  case op
  of AddX:  result = if isFloat: vocAddf else: vocAddi
  of SubX:  result = if isFloat: vocSubf else: vocSubi
  of MulX:  result = if isFloat: vocMulf else: vocMuli
  of DivX:  result = if isFloat: vocDivf else: vocDivi
  of ModX:  result = vocMod
  of AndX:  result = vocAnd
  of OrX:   result = vocOr
  of XorX:  result = vocXor
  of EqX:   result = if isFloat: vocEqf  else: vocEqi
  of NeqX:  result = if isFloat: vocNeqf else: vocNeqi
  of LtX:   result = if isFloat: vocLtf  else: vocLti
  of LeX:   result = if isFloat: vocLef  else: vocLei
  else:
    result = vocHalt

proc isFloatType(ty: TypeInst): bool {.inline.} =
  ## Returns true when `ty` is a floating-point primitive.
  ty.name.startsWith("float")

proc genInstruction(op: VMOpCode, dst, src: CMemLoc): uint32 {.inline.} =
  ## Encode a two-operand instruction into a single 32-bit word.
  (uint32(op) shl OPCODE_POS) or (uint32(dst) shl REGA_POS) or uint32(src)

proc emitInst(code: var CBytecode, op: VMOpCode, dst, src: CMemLoc) {.inline.} =
  ## Append a single instruction word and advance `currentPos`.
  code.data.add(genInstruction(op, dst, src))
  inc code.currentPos

proc emitWord(code: var CBytecode, word: uint32) {.inline.} =
  ## Append a raw 32-bit word (e.g. an immediate value or jump target).
  code.data.add(word)
  inc code.currentPos

proc freeIfTemp(code: var CBytecode, alloc: CAllocation) {.inline.} =
  ## Free `alloc` when it is a temporary scratch allocation.
  ## Named variable allocations (`isTemp = false`) are left untouched;
  ## they are reclaimed automatically by the allocator's tick mechanism.
  if alloc.isTemp and alloc.size > 0:
    code.allocator.free(alloc)

# ################################################################################################################################ #
# ##################################################### VARIABLE RESOLUTION ###################################################### #
# ################################################################################################################################ #

proc lookupVarAlloc(code: var CBytecode, v: Variable): CAllocation =
  ## Retrieve the named allocation for `v` using its birth position as key.
  ## Returns an empty CAllocation (size = 0) when the variable has no entry
  ## in the allocator table (e.g. an external or untracked symbol).
  let sp = lineCol(v.liveness.birth.info)
  code.allocator.lookup(sp.line, sp.col)

proc resolveSymbol(ctx: var CodeGenCtx, code: var CBytecode,
                   scopeId: int, c: NifCursor): CAllocation =
  ## Resolve a Symbol cursor to the CAllocation of the named variable.
  ## Searches the scope chain upward.  Returns an empty CAllocation on failure.
  let varName = c.symText
  let ownerId = ctx.getOwnerScope(ctx.scopes[scopeId], varName)
  if ownerId < 0:
    return CAllocation()
  let nodeId = ctx.scopes[ownerId].variables.fetchNode(varName)
  if nodeId < 0:
    return CAllocation()
  let v = ctx.scopes[ownerId].variables.nodes[nodeId].data
  result = lookupVarAlloc(code, v)

# ################################################################################################################################ #
# ############################################################# EXPRESSIONS ###################################################### #
# ################################################################################################################################ #

proc genExpr(ctx: var CodeGenCtx, code: var CBytecode,
             scopeId: int, ty: TypeInst, c: NifCursor): CAllocation =
  ## Generate code that evaluates the expression at `c` and returns the
  ## allocation holding the result.
  # Binary arithmetic / comparison ops (all carry a type annotation child T)
  let ek = c.exprKind
  result = default(CAllocation)
  case ek:
  of AddX, SubX, MulX, DivX, ModX,
             EqX, NeqX, LtX, LeX:
    # Navigation: (op T left right)
    var child = firstChild(c) 
    # For comparison ops the type annotation describes the *operand* type,
    # which may differ from the result type (bool).  Read it for opcode selection.
    let opTypeName = child.getTypeName
    let opIsFloat  = opTypeName.startsWith("float")
    skip child            # skip T
    let left = child
    var right = child
    skip right         # advance to right operand
    let opTy = ctx.cache.getType(opTypeName)

    result = code.allocator.alloc(opTy.size)

    let r1 = ctx.genExpr(code, scopeId, opTy, left)
    let r2 = ctx.genExpr(code, scopeId, opTy, right)

    code.emitInst(vocMov, result.pos, r1.pos)
    # TODO: Make op code take into account the type
    code.emitInst(toOpcode(ek, opIsFloat), result.pos, r2.pos)

    code.freeIfTemp(r1)
    code.freeIfTemp(r2)
    return

  # Boolean binary ops (and, or, xor) — no type annotation child
  of AndX, OrX, XorX:
    result = code.allocator.alloc(ty.size)
    var child = firstChild(c)
    let left  = child
    var rightCur = child
    skip rightCur
    let right = rightCur

    let r1 = ctx.genExpr(code, scopeId, ty, left)
    let r2 = ctx.genExpr(code, scopeId, ty, right)

    code.emitInst(vocMov, result.pos, r1.pos)
    code.emitInst(toOpcode(ek, false), result.pos, r2.pos)

    code.freeIfTemp(r1)
    code.freeIfTemp(r2)
    return

  # Unary boolean not — (not X), no type annotation
  of NotX:
    result = code.allocator.alloc(ty.size)
    var child = firstChild(c)
    let operand = ctx.genExpr(code, scopeId, ty, child)
    code.emitInst(vocNot, result.pos, operand.pos)
    code.freeIfTemp(operand)
    return

  # Unary negation — (neg T X)
  of NegX:
    result = code.allocator.alloc(ty.size)
    var child = firstChild(c)
    skip child              # skip T
    let operand = ctx.genExpr(code, scopeId, ty, child)
    let voc     = if isFloatType(ty): vocNegf else: vocNegi
    code.emitInst(voc, result.pos, operand.pos)
    code.freeIfTemp(operand)
    return

  # Field access — (dot obj field INTLIT? STRLIT?)
  of DotX, DdotX:
    var objCur = firstChild(c)   # object expression
    var fldCur = objCur
    skip fldCur                  # advance to field symbol

    if objCur.kind == Symbol:
      let baseName = objCur.symText.split(".")[0]
      let ownerId  = ctx.getOwnerScope(ctx.scopes[scopeId], baseName)
      if ownerId >= 0:
        let nodeId = ctx.scopes[ownerId].variables.fetchNode(baseName)
        if nodeId >= 0:
          let v         = ctx.scopes[ownerId].variables.nodes[nodeId].data
          let baseAlloc = lookupVarAlloc(code, v)
          if baseAlloc.size > 0:
            let fieldName = fldCur.symText.split(".")[0]
            let fieldId   = v.ty.nameToId.getOrDefault(fieldName, -1)
            let offset    = if fieldId >= 0: v.ty.fields[fieldId].offset else: 0
            # The returned allocation is a view into the parent object; it must
            # NOT be freed by the caller (the parent owns the memory).
            return CAllocation(pos: baseAlloc.pos + offset,
                               size: ty.size, isTemp: false)
    
    #error "Invalid field access `" & renderNode(c) & "`."
    
  # Function call — (call callee arg*)
  of CallX, CmdX:
    result = code.allocator.alloc(ty.size)
    var callee = firstChild(c)
    var argsToFree: seq[CAllocation] = @[]
    let procName = callee.symText.split(".")[0]
    skip callee                  # advance to first argument

    # Push arguments left-to-right onto the call stack.
    while callee.hasMore:
      # Use an unknown type approximation for argument types.
      let argAlloc = ctx.genExpr(code, scopeId, TypeInst(kind: UnknownType, size: 1), callee)
      code.emitInst(vocPush, argAlloc.pos, 0)
      argsToFree.add(argAlloc)
      skip callee

    for argAlloc in argsToFree:
      code.freeIfTemp(argAlloc)

    let bopCode = toBuiltinCall(procName)
    var procPos = 0
    
    if bopCode == boCustom:
      procPos = code.procTable.getOrDefault(procName, -1)

      # If the proc doesn't yet exist, we register it for backpatching
      if procPos < 0:
        code.callToPatch[procName] = code.data.len
    code.emitInst(vocCall, bopCode.int, result.pos)
    code.emitWord(uint32(procPos))
    return

  # Boolean literals
  of TrueX:
    result = code.allocator.alloc(CHAR_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(1u32)
    return

  of FalseX:
    result = code.allocator.alloc(CHAR_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(0u32)
    return

  else: discard "Unsupported expression `" & renderNode(c) & "`."

  # Atom cases: fall through to kind-based dispatch
  case c.kind
  of Symbol, SymbolDef:
    ## Resolve variable by birth-position key 
    let alloc = ctx.resolveSymbol(code, scopeId, c)
    if alloc.size > 0:
      return alloc

    # Unknown symbol: return an empty temp
    #error "Unknown symbol `" & renderNode(c) & "`." 

  of IntLit:
    result = code.allocator.alloc(INT_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(cast[uint32](c.intValue))

  of UIntLit:
    result = code.allocator.alloc(INT_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(cast[uint32](c.uintValue))

  of FloatLit:
    result = code.allocator.alloc(FLOAT_SIZE)
    code.emitInst(vocLoadf, result.pos, 0)
    code.emitWord(cast[uint32](c.floatValue))

  of CharLit:
    result = code.allocator.alloc(CHAR_SIZE)
    code.emitInst(vocLoadi, result.pos, 0)
    code.emitWord(uint32(ord(c.charLit)))

  else: discard

# ################################################################################################################################ #
# ############################################################## STATEMENTS ###################################################### #
# ################################################################################################################################ #

proc nextChildScope(ctx: var CodeGenCtx, scopeId: int): int =
  ## Consume and return the next child scope ID for `scopeId`.
  ## Must only be called when descending into a nested block whose scope
  ## was registered by `collectVarData`.
  let idx = ctx.scopes[scopeId].childScopeIdx
  if idx < ctx.scopes[scopeId].children.len:
    inc ctx.scopes[scopeId].childScopeIdx
    result = ctx.scopes[scopeId].children[idx]
  else:
    result = scopeId            # fallback: stay in current scope

proc genVar(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for a `var` or `let` declaration.
  ## Allocates virtual memory using the variable's birth and last-use positions
  ## so the allocator can reclaim the slot automatically.
  assert c.stmtKind in {VarS, LetS, TvarS, TletS},
    "genVar: expected var/let, got `" & renderNode(c) & "`."

  var sym = firstChild(c)   # SymbolDef
  if sym.kind != SymbolDef: return
  let name = sym.symText

  var nav = sym
  skip nav
  skip nav                  # E: export marker
  skip nav                  # P: pragmas
  let tyNode = nav          # T: type annotation
  skip nav                  # skip T
  # `nav` is now at the optional initializer (.X or expression)

  let ty = ctx.cache.getType(tyNode.getTypeName)

  # Retrieve the Variable entry built by collectVarData to read liveness.
  let nodeId = ctx.scopes[scopeId].variables.fetchNode(name)
  if nodeId < 0: return

  let v  = ctx.scopes[scopeId].variables.nodes[nodeId].data
  let bp = v.liveness.birth.info
  var lline = bp.line + 1
  var lcol  = bp.col
  if v.liveness.uses.len > 0:
    let lp = v.liveness.uses[^1].info
    lline = lp.line
    lcol  = lp.col

  # Named allocation: automatically freed when (lline, lcol) is passed.
  let alloc = code.allocator.alloc(max(1, ty.size), bp.line, bp.col, lline, lcol)

  # Emit initializer when present.
  if nav.kind != DotToken:
    let initAlloc = ctx.genExpr(code, scopeId, ty, nav)
    if initAlloc.pos != alloc.pos:
      code.emitInst(vocMov, alloc.pos, initAlloc.pos)
    code.freeIfTemp(initAlloc)

proc genAsgn(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for an assignment statement `(asgn LHS RHS)`.
  var lhsCur = firstChild(c)   # LHS
  var rhsCur = lhsCur
  skip rhsCur                   # RHS

  let lhsTy = ctx.getType(scopeId, lhsCur)
  let lhsAlloc = ctx.genExpr(code, scopeId, lhsTy, lhsCur)
  if lhsAlloc.size == 0: return       # unresolvable LHS — silently skip

  let ty = if lhsTy.kind != UnknownType: lhsTy
           else: TypeInst(kind: PrimitiveType, size: 1)

  let rhs = ctx.genExpr(code, scopeId, ty, rhsCur)
  if rhs.pos != lhsAlloc.pos:
    code.emitInst(vocMov, lhsAlloc.pos, rhs.pos)
  code.freeIfTemp(rhs)

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

proc genRet(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  ## Generate code for `(ret .X)`.
  ## When a return value is present it is moved into register 0 by convention.
  var child = firstChild(c)
  if child.kind != DotToken:
    let retTy    = ctx.cache.getType(ctx.currentProcName)
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

  assert c.stmtKind in {StmtsS, BlockS},
    "genStmt: expected stmts/block, got `" & renderNode(c) & "`."

  var n = c
  n.loopInto:
    case n.kind
    of DotToken: discard   # empty placeholder
    of TagLit:
      case n.stmtKind
      of StmtsS, BlockS:
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

      of RetS:
        ctx.genRet(code, scopeId, n)

      of DiscardS:
        ctx.genDiscard(code, scopeId, n)

      of CallS, CmdS:
        ctx.genCallStmt(code, scopeId, n)

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

  # Locate the body statement node among proc children dynamically
  var cur = firstChild(c)
  while cur.hasMore:
    if cur.stmtKind in {StmtsS, BlockS}:
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
