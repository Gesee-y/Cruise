  # ######################################################################################################################## #
 # #################################################### CODE GENERATOR #################################################### #
# ######################################################################################################################## #

type
  CBytecode = object
    data: seq[uint32]
    procTable: Table[string, int] # A correspondence between proc name and their begin in the bytecode
    currentPos: int

const
  OPCODE_BITS = 8
  REGA_BITS = 8
  REGB_BITS = 8

# ######################################################################################################################## #
# ####################################################### FUNCTIONS ###################################################### #
# ######################################################################################################################## #

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
        # TODO
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


