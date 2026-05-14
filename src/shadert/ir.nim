##########################################################################################################################################################
############################################################ TRANSPILER NIM -> CRUISE IR #################################################################
##########################################################################################################################################################

import sets, macros, tables, strutils, strformat

##########################################################################################################################################################
################################################################## TYPES #################################################################################
##########################################################################################################################################################

type
  ParsingContext* = enum
    pcNone, pcReturn, pcWhile, pcFor, pcIf

  CIRNodeKind* = enum
    cnkStmtList
    cnkDecl, cnkFuncSig, cnkFuncDef
    cnkCall
    cnkObjConstr
    cnkBracketExpr
    cnkDotExpr
    cnkIfStmt, cnkElifBranch
    cnkForStmt
    cnkWhileStmt
    cnkReturnStmt
    cnkSym, cnkUniform, cnkBuffer, cnkSampler, cnkImage, cnkArray
    cnkHiddenDeref
    cnkIntLit
    cnkFloatLit
    cnkInfix
    cnkPrefix
    cnkAsgn
    cnkBreakStmt
    cnkContinueStmt
    cnkCast
    cnkConv
    cnkBracket
    cnkConstDef, cnkTypeDef, cnkIdentDef
    cnkCaseStmt
    cnkOfBranch, cnkDefaultBranch
    cnkElse
    cnkHiddenStdConv
    cnkHiddenSubConv
    cnkHiddenCallConv
    cnkStmtListExpr
    cnkEmpty
    cnkDiscardStmt
    cnkWritOnly, cnkReadOnly
    cnkVarTy, cnkGlobalIndex

  NodePos* = object
    ## Source position within the IR, used for liveness analysis.
    ##
    ## `line` identifies the top-level statement index inside the enclosing
    ## cnkStmtList (incremented once per direct child of a statement list).
    ## This maps roughly to a source line.
    ##
    ## `pos` is a DFS pre-order counter that is incremented for every node
    ## visited within a single statement. It gives a total ordering of all
    ## sub-expressions inside a statement, which is required for precise
    ## liveness: a variable's last use inside `x = a + b + c + d` can be
    ## pinned to the exact operand position rather than the whole statement.
    ##
    ## Together (line, pos) define a lexicographic order that matches the
    ## order in which opcodes will be emitted by the bytecode backend.
    line*: int
    pos*:  int

  CIRNode* = object
    ## A single node in the Cruise IR tree.
    ##
    ## Every node carries a `src` field populated during transpilation so
    ## that later passes (liveness analysis, register allocation) can
    ## operate directly on the tree without flattening it first.
    src*: NodePos          ## source position assigned during processNode
    case kind*: CIRNodeKind
    of cnkSym:
      name*: string
    of cnkIntLit:
      intVal*: int
    of cnkFloatLit:
      floatVal*: float
    of cnkDiscardStmt, cnkEmpty, cnkContinueStmt, cnkWritOnly, cnkReadOnly: discard
    else:
      args*: seq[CIRNode]

  CIRContext* = object
    ## Accumulates all IR nodes produced during a single `compileToIR` invocation.
    ##
    ## The context is threaded through every recursive call so that helper
    ## procedures can append type definitions, forward declarations and
    ## function bodies discovered along the way.
    typeDecl*:     CIRNode          ## struct / type definitions (emitted first)
    forwardDecl*:  CIRNode          ## function forward declarations
    funcDef*:      CIRNode          ## full function definitions (helpers)
    body*:         CIRNode          ## the main shader entry-point function
    emittedTypes*: HashSet[string]  ## guard: avoid re-emitting the same type
    emittedFuncs*: HashSet[string]  ## guard: avoid re-emitting the same function

##########################################################################################################################################################
################################################################## UTILITIES #############################################################################
##########################################################################################################################################################

proc newCIRNode*(kind: static CIRNodeKind): CIRNode = CIRNode(kind: kind)
proc add*(a: var CIRNode, b: CIRNode) = a.args.add(b)
proc newCIRSym*(name: string): CIRNode = CIRNode(kind: cnkSym, name: name)
proc newCIRIntLit*(i: int): CIRNode   = CIRNode(kind: cnkIntLit,   intVal:   i)
proc newCIRFloatLit*(i: float): CIRNode = CIRNode(kind: cnkFloatLit, floatVal: i)

proc `<`*(a, b: NodePos): bool =
  a.line < b.line or (a.line == b.line and a.pos < b.pos)
proc `<=`*(a, b: NodePos): bool = a < b or a == b
proc `>`*(a, b: NodePos): bool  = b < a

## Forward declarations required by mutual recursion between processNode / remapFunc.
proc processNode(ctx: var CIRContext, node: NimNode,
                 pc: ParsingContext = pcNone,
                 line: int = 0, pos: var int): CIRNode

proc isPrimitiveType(name: string): bool =
  name in ["int", "float", "string", "cstring", "seq", "set"]

## Compile-time tables that map Nim identifiers to their IR / GLSL equivalents.
var irTypeTable    {.compileTime.} = initTable[string, string]()
var irFuncTable    {.compileTime.} = initTable[string, string]()
var irUniformTable {.compileTime.} = initTable[string, string]()

macro registerUniformType*(ty: typed, glslName: string): untyped =
  ## Map a Nim wrapper type (e.g. `SSBO`) to its GLSL storage qualifier name.
  irUniformTable[$ty] = glslName.strVal

macro registerIRType*(ty: typed, irName: string): untyped =
  ## Map a Nim type to its IR / GLSL type name (e.g. `Vec4` → `"vec4"`).
  irTypeTable[ty.repr] = irName.strVal

macro registerIRFunc*(nimFunc: typed, irName: string): untyped =
  ## Map a Nim function to its IR / GLSL built-in name (e.g. `arcsin` → `"asin"`).
  irFuncTable[nimFunc.strVal] = irName.strVal

proc normalizeTypes(name: string): string =
  ## Convert a Nim primitive type name to its canonical IR name.
  case name:
  of "int", "int32":     return "int"
  of "float", "float32": return "float"
  of "float64":          return "double"
  of "bool":             return "bool"
  of "uint32":           return "uint"
  else:
    if name in irTypeTable: return irTypeTable[name]
    else: ""

proc initDefaultFuncMappings() {.compileTime.} =
  ## Populate `irFuncTable` with the standard math built-ins that have
  ## a direct GLSL counterpart.  Called once via `static:` below.
  const mappings = [
    ("sin",        "sin"),   ("cos",        "cos"),   ("tan",        "tan"),
    ("arcsin",     "asin"),  ("arccos",     "acos"),  ("arctan",     "atan"),
    ("arctan2",    "atan"),  ("sqrt",       "sqrt"),  ("pow",        "pow"),
    ("exp",        "exp"),   ("log",        "log"),   ("abs",        "abs"),
    ("sign",       "sign"),  ("floor",      "floor"), ("ceil",       "ceil"),
    ("round",      "round"), ("mod",        "mod"),   ("fract",      "fract"),
    ("min",        "min"),   ("max",        "max"),   ("clamp",      "clamp"),
    ("mix",        "mix"),   ("step",       "step"),  ("smoothstep", "smoothstep"),
    ("dot",        "dot"),   ("cross",      "cross"), ("length",     "length"),
    ("distance",   "distance"), ("normalize", "normalize"),
    ("reflect",    "reflect"),  ("refract",   "refract"),
  ]
  for (nim, ir) in mappings:
    irFuncTable[nim] = ir

static: initDefaultFuncMappings()

##########################################################################################################################################################
################################################################## TYPE HELPERS ##########################################################################
##########################################################################################################################################################

proc getIRType(ctx: var CIRContext, typeName: string): CIRNode {.compileTime.} =
  ## Look up a type by name and return the corresponding CIRNode.
  ## If the type has already been emitted (i.e. it is in `emittedTypes`)
  ## we simply return a symbol reference to avoid duplicate definitions.
  if typeName in ctx.emittedTypes: return newCIRSym(typeName)
  discard normalizeTypes(typeName)   # side-effect-free normalisation for now
  return newCIRSym(typeName)

proc isWrapperType(typeName: string): bool {.compileTime.} =
  ## Returns true for Nim types that map to GLSL resource qualifiers
  ## (uniforms, SSBOs, images, samplers) rather than plain value types.
  typeName.startsWith("Uniform[")         or
  typeName.startsWith("UniformReadOnly[") or
  typeName.startsWith("UniformWriteOnly[") or
  typeName.startsWith("array")            or
  typeName in irUniformTable              or
  typeName == "Sampler2D"

proc emitQualifiedVar(ctx: var CIRContext, typeName: string,
                      paramName: string): CIRNode {.compileTime.} =
  ## Produce the IR node that represents a GLSL resource-qualified variable
  ## (uniform, SSBO, image, sampler, or array).
  ## `typeName` is the full Nim generic spelling, e.g. `"Uniform[float32]"`.
  let innerPos  = typeName.find("[")
  let tyName    = if innerPos != -1: typeName[0..<innerPos] else: typeName
  let irVal     = if tyName in irUniformTable: irUniformTable[tyName] else: tyName
  let innerName = if innerPos != -1: typeName[(innerPos+1)..^2] else: ""

  if typeName.startsWith("Uniform["):
    let inner = ctx.getIRType(innerName)
    return CIRNode(kind: cnkUniform, args: @[CIRNode(kind: cnkEmpty), inner])

  elif typeName.startsWith("array"):
    let cm  = innerName.split(",")
    let val = newCIRIntLit((&"{cm[0][^1]}").parseInt + 1)
    let inner = ctx.getIRType(cm[1])
    return CIRNode(kind: cnkArray, args: @[val, inner])

  elif irVal == "SSBO":
    let inner = ctx.getIRType(innerName)
    return CIRNode(kind: cnkBuffer, args: @[CIRNode(kind: cnkEmpty), inner])

  elif typeName.startsWith("UniformReadOnly["):
    let inner = ctx.getIRType(innerName)
    return CIRNode(kind: cnkUniform, args: @[CIRNode(kind: cnkReadOnly), inner])

  elif typeName.startsWith("UniformWriteOnly["):
    let inner = ctx.getIRType(innerName)
    return CIRNode(kind: cnkUniform, args: @[CIRNode(kind: cnkWritOnly), inner])

  elif typeName.startsWith("Image2D["):
    let inner = ctx.getIRType(innerName)
    return CIRNode(kind: cnkImage, args: @[newCIRIntLit(2), inner])

  elif typeName == "Sampler2D":
    return CIRNode(kind: cnkSampler, args: @[newCIRIntLit(2)])

  else: return

proc emitStruct(ctx: var CIRContext, ty: NimNode): CIRNode =
  ## Transpile a Nim `object` type declaration to a `cnkTypeDef` IR node.
  result = newCIRNode(cnkTypeDef)
  result.add(newCIRSym(ty.strVal))
  let impl = ty.getImpl()
  for field in impl[2][2]:
    var def = newCIRNode(cnkIdentDef)
    def.add(newCIRSym(field[0].strVal))
    var fieldType = ctx.getIRType(field[0].repr)
    def.add(newCIRSym(field[0].strVal))
    result.add def

proc getIRType(ctx: var CIRContext, node: NimNode): CIRNode =
  ## Resolve the IR type for a Nim AST node that represents a type or
  ## a typed symbol.  Emits struct definitions on first encounter.
  var sym = if node.kind == nnkSym: node.getTypeInst() else: node
  if sym.kind == nnkVarTy: sym = sym[0]
  let typeName  = if sym.kind == nnkBracketExpr: sym[1].repr else: sym.repr
  let paramName = node.strVal

  if isWrapperType(typeName):
    if paramName notin ctx.emittedTypes:
      return emitQualifiedVar(ctx, typeName, paramName)

  if typeName in ctx.emittedTypes: return newCIRSym(typeName)

  case typeName:
  of "int", "int32":     return newCIRSym "int"
  of "float", "float32": return newCIRSym "float"
  of "float64":          return newCIRSym "double"
  of "bool":             return newCIRSym "bool"
  of "uint32":           return newCIRSym "uint"
  else:
    if typeName in irTypeTable:
      return newCIRSym irTypeTable[typeName]

    let symb = if sym.kind == nnkBracketExpr: sym[0] else: sym
    if not symb.strVal.isPrimitiveType:
      let s = emitStruct(ctx, sym)
      ctx.typeDecl.add(s)
      ctx.emittedTypes.incl(typeName)

    return newCIRSym typeName

##########################################################################################################################################################
################################################################## POSITION TRACKING #####################################################################
##########################################################################################################################################################

proc stamp(node: var CIRNode, line: int, pos: var int) =
  ## Assign a `NodePos` to `node` and increment `pos`.
  ##
  ## This is called once per node during processNode, giving every IR node a
  ## unique (line, pos) coordinate.  The `line` component is held fixed for
  ## the entire top-level statement being processed; `pos` is a mutable
  ## counter that advances with each node visited in DFS pre-order.
  ##
  ## Liveness analysis later uses these coordinates as a total order:
  ##   (l1, p1) < (l2, p2)  iff  l1 < l2  or  (l1 == l2 and p1 < p2)
  node.src = NodePos(line: line, pos: pos)
  inc pos

##########################################################################################################################################################
################################################################## FUNCTION RESOLUTION ###################################################################
##########################################################################################################################################################

proc ensureStmtList(node: NimNode): NimNode =
  if node.kind in {nnkStmtList, nnkStmtListExpr}: return node
  result = newNimNode(nnkStmtList)
  result.add(node)

proc remapFunc(ctx: var CIRContext, name: string, node: NimNode,
               line: int, pos: var int): CIRNode =
  ## Resolve a Nim function call to its IR name.
  ##
  ## Resolution order:
  ##   1. Explicit user mapping via `registerIRFunc`.
  ##   2. Already-emitted helper function (reuse the symbol).
  ##   3. Unknown function: recursively transpile its Nim body and emit it
  ##      as a helper to `ctx.funcDef` (only once, guarded by `emittedFuncs`).
  ##
  ## The `line` and `pos` parameters are forwarded so that nodes produced
  ## during recursive transpilation of helper bodies receive valid positions.

  # 1. Explicit mapping.
  if name in irFuncTable:
    return newCIRSym irFuncTable[name]

  # 2. Already emitted.
  if name in ctx.emittedFuncs:
    return newCIRSym name

  # 3. Transpile the body.
  let impl = node.getImpl()
  if impl.isNil or impl.kind == nnkNilLit:
    error("Cruise IR Transpiler: unknown function '" & name & "' has no Nim implementation.\n" &
          "  Hint: register it with registerIRFunc or provide a Nim body.", node)

  let params     = impl[3]
  let returnType = if params[0].kind == nnkEmpty: newCIRSym "void"
                   else: ctx.getIRType(params[0])

  var signature = newCIRNode(cnkFuncSig)
  signature.add(newCIRSym name)
  signature.add(returnType)

  for i in 1..<params.len:
    let param  = params[i]
    var idnt   = newCIRNode(cnkIdentDef)
    let irType = ctx.getIRType(param[^2])
    for j in 0..<param.len - 2:
      idnt.add(newCIRSym param[j].strVal)
      idnt.add(irType)
    signature.add(idnt)

  ctx.forwardDecl.add(signature)

  # Mark as emitted early to break potential recursion cycles.
  ctx.emittedFuncs.incl(name)

  var funcCtx = CIRContext()
  funcCtx.emittedTypes = ctx.emittedTypes
  funcCtx.emittedFuncs = ctx.emittedFuncs

  var body    = impl[6].ensureStmtList
  var helperPos = 0   # helper bodies start their own position counter at 0
  let irBody  = processNode(funcCtx, body, line = 0, pos = helperPos)

  # Propagate any newly discovered types / functions back to the parent context.
  ctx.typeDecl.args.add(funcCtx.typeDecl.args)
  ctx.forwardDecl.args.add(funcCtx.forwardDecl.args)
  ctx.funcDef.args.add(funcCtx.funcDef.args)
  ctx.emittedTypes = funcCtx.emittedTypes
  ctx.emittedFuncs = funcCtx.emittedFuncs

  ctx.funcDef.add(CIRNode(kind: cnkFuncDef, args: @[signature, irBody]))

  return newCIRSym name

##########################################################################################################################################################
################################################################## CORE TRANSPILER #######################################################################
##########################################################################################################################################################

proc processDeclaration(ctx: var CIRContext, node: NimNode,
                        line: int, pos: var int): CIRNode =
  ## Transpile a single `var` / `let` binding to a `cnkDecl` IR node.
  var res  = newCIRNode(cnkDecl)
  var idnt = newCIRNode(cnkIdentDef)
  let name = node[0].strVal
  let ty   = getIRType(ctx, node[0])
  let expr = processNode(ctx, node[2], line = line, pos = pos)
  idnt.add(newCIRSym name)
  idnt.stamp(line, pos) 
  idnt.add(ty)
  res.add(idnt)
  res.add(expr)
  res.stamp(line, pos)
  res

proc processNode(ctx: var CIRContext, node: NimNode,
                 pc: ParsingContext = pcNone,
                 line: int = 0, pos: var int): CIRNode =
  ## Recursively transpile a Nim AST node to a Cruise IR node.
  ##
  ## `line` is the index of the enclosing top-level statement and is held
  ## constant while descending into sub-expressions.
  ##
  ## `pos` is a mutable DFS counter incremented once per node visited; it
  ## provides sub-statement resolution for liveness analysis.
  ##
  ## Every produced CIRNode has its `src` field set via `stamp` so that
  ## downstream passes can determine the exact position of any node without
  ## needing to flatten the tree first.

  case node.kind:

  of nnkStmtList:
    ## Each direct child of a statement list gets its own `line` index.
    ## The `pos` counter resets to 0 at the start of each statement so
    ## that (line, pos) pairs are compact and do not grow unboundedly.
    result = newCIRNode(cnkStmtList)
    result.stamp(line, pos)
    for i, n in node:
      var stmtPos = 0
      result.add processNode(ctx, n, line = line + i, pos = stmtPos)

  of nnkVarSection, nnkLetSection:
    var stmtPos = 0
    for n in node:
      result = ctx.processDeclaration(n, line = line, pos = stmtPos)

  of nnkCall, nnkCommand:
    let nFuncName = node[0].strVal
    result = newCIRNode(cnkCall)
    result.stamp(line, pos)
    if nFuncName == "globalIndex":
      result = newCIRNode(cnkGlobalIndex)
      result.stamp(line, pos)
      if node[1].kind != nnkSym:
        error("Cruise IR Transpiler: only identifiers are allowed in globalIndex", node[1])
      result.add(ctx.getIRType(node[1]))
    else:
      let funcName = ctx.remapFunc(nFuncName, node[0], line, pos)
      result.add(funcName)
      for i in 1..<node.len:
        result.add processNode(ctx, node[i], line = line, pos = pos)

  of nnkObjConstr:
    ## Object construction: `MyVec(x: 1.0, y: 2.0)` → `vec2(1.0, 2.0)`
    result = newCIRNode(cnkCall)
    result.stamp(line, pos)
    let irType = ctx.getIRType(node[0])
    result.add irType
    for i in 1..<node.len:
      result.add processNode(ctx, node[i][1], line = line, pos = pos)

  of nnkBracketExpr:
    ## Array indexing: `buf[i]` → `buf[i]`
    result = newCIRNode(cnkBracketExpr)
    result.stamp(line, pos)
    result.add processNode(ctx, node[0], line = line, pos = pos)
    result.add processNode(ctx, node[1], line = line, pos = pos)

  of nnkDotExpr:
    ## Field access: `pos.x` → `pos.x`
    result = newCIRNode(cnkDotExpr)
    result.stamp(line, pos)
    result.add processNode(ctx, node[0], line = line, pos = pos)
    result.add newCIRSym(node[1].strVal)

  of nnkIfStmt, nnkIfExpr:
    result = newCIRNode(cnkIfStmt)
    result.stamp(line, pos)
    for branch in node:
      var el: CIRNode
      if branch.kind == nnkElifBranch:
        el = newCIRNode(cnkElifBranch)
        el.stamp(line, pos)
        el.add processNode(ctx, branch[0], line = line, pos = pos)
        el.add processNode(ctx, branch[1].ensureStmtList, line = line, pos = pos)
      elif branch.kind == nnkElse:
        el = newCIRNode(cnkElse)
        el.stamp(line, pos)
        el.add processNode(ctx, branch[0].ensureStmtList, line = line, pos = pos)
      result.add(el)

  of nnkForStmt:
    ## Only range iteration (`a..<b`) is supported.
    result = newCIRNode(cnkForStmt)
    result.stamp(line, pos)
    
    var loopVar = newCIRSym(node[0].strVal)
    loopVar.stamp(line, pos)
    result.add loopVar
    
    let iter = node[1]
    if iter.kind != nnkInfix or iter[0].strVal != "..<":
      error("Cruise IR Transpiler: only range iteration (a..<b) is supported in for loops", node)
    result.add processNode(ctx, iter[1], line = line, pos = pos)
    result.add processNode(ctx, iter[2], line = line, pos = pos)
    result.add processNode(ctx, node[2].ensureStmtList, line = line, pos = pos)

  of nnkWhileStmt:
    result = newCIRNode(cnkWhileStmt)
    result.stamp(line, pos)
    result.add processNode(ctx, node[0], line = line, pos = pos)
    result.add processNode(ctx, node[1].ensureStmtList, line = line, pos = pos)

  of nnkReturnStmt:
    result = CIRNode(kind: cnkReturnStmt,
                     args: @[processNode(ctx, node[0], pc = pcReturn,
                                         line = line, pos = pos)])
    result.stamp(line, pos)

  of nnkSym, nnkIdent:
    result = newCIRSym node.strVal
    result.stamp(line, pos)

  of nnkHiddenDeref:
    result = processNode(ctx, node[0], line = line, pos = pos)

  of nnkIntLit, nnkInt64Lit, nnkInt32Lit:
    result = newCIRIntLit node.intVal
    result.stamp(line, pos)

  of nnkFloatLit, nnkFloat64Lit, nnkFloat32Lit:
    result = newCIRFloatLit node.floatVal
    result.stamp(line, pos)

  of nnkInfix:
    ## Binary operator: `a + b`, `a * b`, etc.
    var sym = newCIRSym(node[0].strVal)
    sym.stamp(line, pos)
    result = newCIRNode(cnkInfix)
    result.stamp(line, pos)
    result.add newCIRSym(node[0].strVal)
    result.add processNode(ctx, node[1], line = line, pos = pos)
    result.add processNode(ctx, node[2], line = line, pos = pos)

  of nnkPrefix:
    ## Unary operator: `-x`, `not x`, etc.
    result = newCIRNode(cnkPrefix)
    result.stamp(line, pos)
    result.add newCIRSym(node[0].strVal)
    result.add processNode(ctx, node[1], line = line, pos = pos)

  of nnkAsgn:
    if pc == pcReturn:
      result = processNode(ctx, node[1], line = line, pos = pos)
    else:
      result = newCIRNode(cnkAsgn)
      result.stamp(line, pos)
      result.add processNode(ctx, node[0], line = line, pos = pos)
      result.add processNode(ctx, node[1], line = line, pos = pos)

  of nnkBreakStmt:
    result = newCIRNode(cnkBreakStmt)
    result.stamp(line, pos)

  of nnkContinueStmt:
    result = newCIRNode(cnkContinueStmt)
    result.stamp(line, pos)

  of nnkCast:
    ## `cast[float32](x)` → `float(x)`
    result = newCIRNode(cnkCast)
    result.stamp(line, pos)
    result.add ctx.getIRType(node[0])
    result.add processNode(ctx, node[1], line = line, pos = pos)

  of nnkConv:
    ## `float32(x)` → `float(x)`
    result = newCIRNode(cnkConv)
    result.stamp(line, pos)
    result.add ctx.getIRType(node[0])
    result.add processNode(ctx, node[1], line = line, pos = pos)

  of nnkBracket:
    ## Fixed-size array literal: `[1.0, 2.0, 3.0]`
    result = newCIRNode(cnkBracket)
    result.stamp(line, pos)
    for elem in node:
      result.add processNode(ctx, elem, line = line, pos = pos)

  of nnkCaseStmt:
    ## `case x of 1: ... else: ...` → `switch(x) { case 1: ... default: ... }`
    result = newCIRNode(cnkCaseStmt)
    result.stamp(line, pos)
    result.add processNode(ctx, node[0], line = line, pos = pos)
    for i in 1..<node.len:
      let branch = node[i]
      case branch.kind:
      of nnkOfBranch:
        var ob = newCIRNode(cnkOfBranch)
        ob.stamp(line, pos)
        for j in 0..<branch.len - 1:
          ob.add processNode(ctx, branch[j], line = line, pos = pos)
        ob.add processNode(ctx, branch[^1].ensureStmtList, line = line, pos = pos)
        result.add ob
      of nnkElse:
        var el = newCIRNode(cnkDefaultBranch)
        el.stamp(line, pos)
        el.add processNode(ctx, branch[0].ensureStmtList, line = line, pos = pos)
        result.add el
      else:
        error("Cruise IR Transpiler: unsupported case branch: " & $branch.kind, branch)

  of nnkHiddenStdConv:
    ## Implicit standard conversion (e.g. int literal → float32).
    ## The value is in node[1]; node[0] carries only the target type.
    result = processNode(ctx, node[1], line = line, pos = pos)

  of nnkHiddenSubConv:
    ## Implicit subtype conversion — same treatment as HiddenStdConv.
    result = processNode(ctx, node[1], line = line, pos = pos)

  of nnkHiddenCallConv:
    ## Implicit conversion via constructor call, e.g. `SomeType(x)`.
    result = newCIRNode(cnkHiddenCallConv)
    result.stamp(line, pos)
    result.add ctx.getIRType(node[0])
    result.add processNode(ctx, node[1], line = line, pos = pos)

  of nnkStmtListExpr:
    ## Statement list used as an expression (produced by template expansion).
    ## All nodes except the last are statements; the last is the result value.
    result = newCIRNode(cnkStmtListExpr)
    result.stamp(line, pos)
    for i in 0..<node.len - 1:
      var stmtPos = 0
      result.add processNode(ctx, node[i], line = line+i, pos = stmtPos)

    var stmtPos = 0
    result.add processNode(ctx, node[^1], line = line, pos = stmtPos)

  of nnkEmpty:
    result = newCIRNode(cnkEmpty)
    result.stamp(line, pos)

  of nnkDiscardStmt:
    result = newCIRNode(cnkDiscardStmt)
    result.stamp(line, pos)

  else:
    error("Cruise IR Transpiler: unsupported AST node " & $node.kind & "\n" &
          "  This Nim construct has no IR equivalent.", node)

##########################################################################################################################################################
################################################################## PARAMETER PROCESSING ##################################################################
##########################################################################################################################################################

proc processParams(ctx: var CIRContext, params: NimNode): seq[CIRNode] =
  ## Transpile a function's formal parameter list to a sequence of
  ## `cnkIdentDef` IR nodes, handling both plain types and resource-qualified
  ## wrapper types (Uniform, SSBO, Image2D, Sampler2D, array).
  for i in 1..<params.len:   # skip params[0] which is the return type
    let identDef  = params[i]
    let tyNode    = identDef[1]
    let isVar     = tyNode.kind == nnkVarTy
    let innerTy   = identDef[0]
    let typeName  = innerTy.getTypeInst().repr

    for j in 0..<identDef.len - 2:
      var res     = newCIRNode(cnkIdentDef)
      var current : CIRNode
      res.add(newCIRSym identDef[j].strVal)

      if isWrapperType(typeName):
        current = emitQualifiedVar(ctx, typeName, identDef[j].strVal)
      else:
        current = ctx.getIRType(innerTy)

      if isVar:
        var v = newCIRNode(cnkVarTy)
        v.add current
        current = v

      res.add(current)
      result.add(res)

##########################################################################################################################################################
################################################################## ENTRY POINT ###########################################################################
##########################################################################################################################################################

macro compileToIR*(fn: typed): CIRContext =
  ## Main entry point.  Annotate a Nim procedure with this macro to
  ## transpile it to a `CIRContext` at compile time.
  ##
  ## Example:
  ##   ```nim
  ##   proc myShader(col: Uniform[Vec4]): Vec4 = col * 2.0
  ##   const ir = compileToIR(myShader)
  ##   ```
  ##
  ## The returned `CIRContext` contains the full IR tree with source
  ## positions on every node, ready for liveness analysis and bytecode
  ## emission.
  var ctx  = CIRContext()
  let impl = fn.getImpl
  let name = impl[0]
  let params = impl[3]
  var body   = impl[6].ensureStmtList

  var irMain    = newCIRNode(cnkFuncDef)
  var signature = newCIRNode(cnkFuncSig)
  signature.add(newCIRSym name.strVal)
  signature.add(newCIRNode(cnkEmpty))

  let args = ctx.processParams(params)
  signature.args.add(args)

  var rootPos = 0
  let irBody  = processNode(ctx, body, line = 0, pos = rootPos)

  irMain.add signature
  irMain.add irBody
  ctx.body = irMain

  return quote do: `ctx`

include "irOps.nim"

