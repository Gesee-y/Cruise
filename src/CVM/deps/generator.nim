  # ###################################################################################################################################### #
 # ########################################################## CODE GENERATOR ############################################################ #
# ###################################################################################################################################### #

type
  CMemLoc = int # Just an alias to make code more readable
  CBytecode = object
    data: seq[uint32]
    allocator: CVramAllocator
    procTable: Table[string, int] # A correspondence between proc name and their begin in the bytecode
    currentPos: int

const
  OPCODE_BITS = 8
  REGA_BITS = 8
  REGB_BITS = 8
  REGA_POS = REGB_BITS
  OPCODE_POS = REGA_POS + REGA_BITS

# ###################################################################################################################################### #
# ############################################################ FUNCTIONS ############################################################### #
# ###################################################################################################################################### #

proc isValidRHS(c: NifCursor): bool = 
  c.stmtKind in {InfixS, PrefixS, CallS, CommandS} or n.exprKind in {DotX, DdotX, HderefX}

proc toOpcode(s: string, ty: string): VMOpCode =
  assert ty.startsWith("int") or ty.startsWith("float"), "Invalid Type for"
  case s
  of "+": vocAdd
  of "-": vocSub
  of "*": vocMul
  of "/": vocDiv
  of "%": vocMod
  of "and": vocAnd
  of "or": vocOr
  of "not": vocNot
  of "xor": vocXor
  else: error "No opCode for `" & s & "`."

proc genIntruction(op: VMOpCode, dst, src: CMemLoc): uint32 =
  (uint32(op) shl OPCODE_POS) or (uint32(dst) shl REGA_BITS) or uint32(src)

proc genExpr(ctx: var CodeGenCtx, code: var CBytecode, scopeId: int, ty: TypeInst, c: NifCursor): CMemLoc =
  var lineInfo = c.info
  var size = ty.size
  result = ctx.allocator.alloc(size)
  case c.exprKind
  of InfixX:
    var sym = firstChild(c) # Name
    var opCode = toOpcode(c.symText)
    var left = sym 
    skip left # Second child is the left expression
    var right = left
    skip right # Go to the right expression
    let r1 = ctx.genExpr(code, scopeId, ty, left)
    let r2 = ctx.genExpr(code, scopeId, ty, right)

    # Now We generate 1 move and one op
    code.data.add(genIntruction(vocMov, result, r1))
    code.data.add(genIntruction(opCode, result, r2))
    code.currentPos += 2

    ctx.allocator.free(r1, size)
    ctx.allocator.free(r2, size)
  of PrefixX:
    var sym = firstChild(c) # Name
    var opCode = toOpcode(c.symText)
    var left = sym 
    skip left # Second child is the expression

    let r = ctx.genExpr(code, scopeId, ty, left)

    # Now We generate 1 move and one op
    code.data.add(genIntruction(opCode, result, r))

    ctx.allocator.free(r, size)
  of 

proc genRHS(ctx: CodeGenCtx, code: var CBytecode, scopeId: int, ty: TypeInst, c: NifCursor) =
  assert c.isValidRHS, "Unable to generate Right Hand Statement. Got `" & asNimCode(c) & "`."

  case c.stmtKind
  of InfixX:
    # todo


proc genVar(ctx: CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  assert c.stmtKind in {VarS, LetS}, "Unable to generate variable. Got `" & asNimCode(c) & "`."
  let symNode = firstChild(c)
  if symNode.kind == SymbolDef:
    var name = symNode.symText
    let rv = ownerScope.variables.fetchNode(name)

    skip symNode
    skip symNode
    skip symNode
    skip symNode

    ctx.genRHS(code, scopeId, symNode)


# Generate a statement, it's the main dispatcher of our generation process.
proc genStmt(ctx: CodeGenCtx, code: var CBytecode, scopeId: int, c: NifCursor) =
  assert c.stmtKind in {StmtsS, BlockS}, "Unable to generate statement. Got `" & asNimCode(c) & "`."
  var n = c
  var scopeCurrentChild = 0
  
  # First we take care of literals
  n.loopInto:
    case n.kind

    # If we have literals, we can just cast them to uint32 safely
    # Those are the only kind of literal we have to support.
    of IntLit:
      code.data.add(0) # We add the null pointer at first to know if we are dealing with an immediate.
      code.data.add(cast[uint32](c.intValue))
      inc code.currentPos
    of FloatLit:
      code.data.add(0)
      code.data.add(cast[uint32](c.floatValue))
      inc code.currentPos
    of DotToken: discard
    of Symbol, SymbolDef: error "Uncontextualized Symbol. Got `" & asNimCode(n) & "`."
    of TagLit:
      case n.stmtKind
      of StmtsS:
        ctx.genStmt(code, ctx.scopes[scopeId].children[scopeCurrentChild], n)
        inc scopeCurrentChild
      of VarS, LetS:
        ctx.genVar(code, scopeId, n)
      of TypeS, ImportS: discard
      else: discard
    else: error "Unknow node. Got `" & asNimCode(n) & "`."
    inc n

# Genenerate a function in the bytecode
proc genFunc(ctx: CodeGenCtx, code: var CBytecode, c: NifCursor) =
  assert c.typeKind == ProcT, "Unable to generate function. Got `" & asNimCode(c) & "`."

  # First we fetch the function name, so we can get it from the type cache
  var symNode = firstChild(c) # Definition of the proc
  if symNode.kind == SymbolDef:
    let name = symNode.symText
    let ty = ctx.cache.getType(name)

    # We link the proc in our table know where it is in memory
    code.procTable[name] = code.currentPos

    # Skipping directly to the proc body
    skip symNode
    skip symNode
    skip symNode
    skip symNode
    skip symNode

    ctx.genStmt(code, ty.scopeId, symNode)


