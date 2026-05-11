##########################################################################################################################################################
############################################################ TRANPILER NIM -> CRUISE IR ##################################################################
##########################################################################################################################################################

import sets, macros, tables, strutils, strformat

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
  
  CIRNode* = object
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
    typeDecl*: CIRNode
    forwardDecl*: CIRNode
    funcDef*: CIRNode
    body*: CIRNode
    emittedTypes*: HashSet[string] ## Already emitted type
    emittedFuncs*: HashSet[string]

##########################################################################################################################################################
################################################################## UTILITIES #############################################################################
##########################################################################################################################################################

proc newCIRNode*(kind: static CIRNodeKind): CIRNode = CIRNode(kind: kind)
proc add*(a: var CIRNode, b: CIRNode) = a.args.add(b)
proc newCIRSym*(name: string): CIRNode = CIRNode(kind: cnkSym, name: name)
proc newCIRIntLit*(i: int): CIRNode = CIRNode(kind: cnkIntLit, intVal: i)
proc newCIRFloatLit*(i: float): CIRNode = CIRNode(kind: cnkFloatLit, floatVal: i)

proc globalIndex[T](data: T): T = data
proc processNode(ctx: var CIRContext, node: NimNode, pc: ParsingContext= pcNone): CIRNode

proc isPrimitiveType(name: string): bool =
  name in ["int", "float", "string", "cstring", "seq", "set"]

var irTypeTable {.compileTime.} = initTable[string, string]()
var irFuncTable {.compileTime.} = initTable[string, string]()
var irUniformTable {.compileTime.} = initTable[string, string]()

macro registerUniformType*(ty: typed, glslName: string): untyped =
  irUniformTable[$ty] = glslName.strVal

macro registerIRType*(ty: typed, irName: string): untyped =
  irTypeTable[ty.repr] = irName.strVal

macro registerIRFunc*(nimFunc: typed, irName: string): untyped =
  irFuncTable[nimFunc.strVal] = irName.strVal

proc normalizeTypes(name: string): string =
  case name:
  of "int", "int32":   return "int"
  of "float", "float32": return "float"
  of "float64":        return "double"
  of "bool":           return "bool"
  of "uint32":         return "uint"
  else:
    if name in irTypeTable:
      return irTypeTable[name]
    else: ""

proc initDefaultFuncMappings() {.compileTime.} =
  const mappings = [
    ("sin",        "sin"),
    ("cos",        "cos"),
    ("tan",        "tan"),
    ("arcsin",     "asin"),
    ("arccos",     "acos"),
    ("arctan",     "atan"),
    ("arctan2",    "atan"),
    ("sqrt",       "sqrt"),
    ("pow",        "pow"),
    ("exp",        "exp"),
    ("log",        "log"),
    ("abs",        "abs"),
    ("sign",       "sign"),
    ("floor",      "floor"),
    ("ceil",       "ceil"),
    ("round",      "round"),
    ("mod",        "mod"),
    ("fract",      "fract"),
    ("min",        "min"),
    ("max",        "max"),
    ("clamp",      "clamp"),
    ("mix",        "mix"),
    ("step",       "step"),
    ("smoothstep", "smoothstep"),
    ("dot",        "dot"),
    ("cross",      "cross"),
    ("length",     "length"),
    ("distance",   "distance"),
    ("normalize",  "normalize"),
    ("reflect",    "reflect"),
    ("refract",    "refract"),
  ]
  for (nim, ir) in mappings:
    irFuncTable[nim] = ir

static: initDefaultFuncMappings()  
static: initDefaultFuncMappings()

proc getIRType(ctx: var CIRContext, typeName: string): CIRNode {.compileTime.} =
  if typeName in ctx.emittedTypes: return newCIRSym(typeName)

  let res = normalizeTypes(typeName)

  return newCIRSym(typeName)

proc isWrapperType(typeName: string): bool {.compileTime.} =
  typeName.startsWith("Uniform[")      or
  typeName.startsWith("UniformReadOnly[") or
  typeName.startsWith("UniformWriteOnly[") or
  typeName.startsWith("array") or
  typeName in irUniformTable or
  typeName == "Sampler2D"

proc emitQualifiedVar(ctx: var CIRContext, typeName: string,
                      paramName: string): CIRNode {.compileTime.} =
  ## Emit the correct GLSL header declaration for a qualified variable.
  ## typeName is the full Nim generic name e.g. "Uniform[float32]"

  let innerPos = typeName.find("[")
  let tyName = if innerPos != -1: typeName[0..<innerPos] else: typeName
  let irVal = if tyName in irUniformTable: irUniformTable[tyName] else: tyName
  let innerName = if innerPos != -1: typeName[(innerPos+1)..^2] else: ""

  if typeName.startsWith("Uniform["):
    let inner = ctx.getIRType(innerName)
    return CIRNode(kind: cnkUniform, args: @[CIRNode(kind: cnkEmpty), inner])
  elif typeName.startsWith("array"):
    let cm = innerName.split(",")
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
  ## Generate a IR type from a Nim object
  result = newCIRNode(cnkTypeDef)
  result.add(newCIRSym(ty.strVal))
  let impl = ty.getImpl()

  for field in impl[2][2]:  # fields
    var def = newCIRNode(cnkIdentDef)
    def.add(newCIRSym(field[0].strVal))

    var fieldType = ctx.getIRType(field[0].repr)
    def.add(newCIRSym(field[0].strVal))
    
    result.add def

proc getIRType(ctx: var CIRContext, node: NimNode): CIRNode =
  var sym = if node.kind == nnkSym: node.getTypeInst() else: node
  if sym.kind == nnkVarTy: sym = sym[0]
  let typeName = if sym.kind == nnkBracketExpr: sym[1].repr else: sym.repr
  let paramName = node.strVal

  if isWrapperType(typeName):
    if paramName notin ctx.emittedTypes:
      return emitQualifiedVar(ctx, typeName, paramName)

  if typeName in ctx.emittedTypes: return newCIRSym(typeName)

  # Our known primitive types
  case typeName:
  of "int", "int32":   return newCIRSym "int"
  of "float", "float32": return newCIRSym "float"
  of "float64":        return newCIRSym "double"
  of "bool":           return newCIRSym "bool"
  of "uint32":         return newCIRSym "uint"
  else:
    if typeName in irTypeTable:
      return newCIRSym irTypeTable[typeName]

    let symb = if sym.kind == nnkBracketExpr: sym[0] else: sym
    if not symb.strVal.isPrimitiveType:
      let s = emitStruct(ctx, sym)
      ctx.typeDecl.add(s)
      ctx.emittedTypes.incl(typeName)

    return newCIRSym typeName

proc ensureStmtList(node: NimNode): NimNode =
  if node.kind in {nnkStmtList, nnkStmtListExpr}:
    return node
  result = newNimNode(nnkStmtList)
  result.add(node)

proc remapFunc(ctx: var CIRContext, name: string, node: NimNode): CIRNode =
  ## Resolve a function call to its IR name.
  ## If the function is unknown, transpile its Nim implementation
  ## and emit it to the header (once).

  # 1. Explicit mapping registered by user
  if name in irFuncTable:
    return newCIRSym irFuncTable[name]

  # 2. Already emitted in a previous call, reuse
  if name in ctx.emittedFuncs:
    return newCIRSym name

  # 3. Unknown function: transpile its body and emit to header
  let impl = node.getImpl()
  if impl.isNil or impl.kind == nnkNilLit:
    error("Cruise IR Transpiler: unknown function '" & name & "' has no Nim implementation to transpile.\n" &
          "  Hint: add it to the function mapping table or provide a Nim implementation.", node)

  let params = impl[3]
  let returnType = if params[0].kind == nnkEmpty: newCIRSym "void"
                   else: ctx.getIRType(params[0])
  var signature = newCIRNode(cnkFuncSig)
  signature.add(newCIRSym name)
  signature.add(returnType)

  for i in 1..<params.len:
    let param = params[i]
    var idnt = newCIRNode(cnkIdentDef)
    let irType = ctx.getIRType(param[^2])
    for j in 0..<param.len - 2:  ## handle a, b: float32
      idnt.add(newCIRSym param[j].strVal)
      idnt.add(irType)

    signature.add(idnt)


  ctx.forwardDecl.add(signature)
  ctx.emittedFuncs.incl(name) # Include the name early to avoid infinite recursions
  # Emit dependencies first (recursive calls inside this func)
  # processNode will call remapFunc again for any calls found inside,
  # which will recursively emit their definitions before this one.
  var funcCtx = CIRContext()  ## inherit type/func tables
  funcCtx.emittedTypes = ctx.emittedTypes
  funcCtx.emittedFuncs = ctx.emittedFuncs

  var glslBody = ""
  var body = impl[6].ensureStmtList
  
  let irBody = processNode(funcCtx, body)
  ctx.typeDecl.args.add(funcCtx.typeDecl.args)
  ctx.forwardDecl.args.add(funcCtx.forwardDecl.args)
  ctx.funcDef.args.add(funcCtx.funcDef.args)
  
  ctx.emittedTypes = funcCtx.emittedTypes  ## propagate newly discovered types
  ctx.emittedFuncs = funcCtx.emittedFuncs
   
  var res = CIRNode(kind:cnkFuncDef, args: @[signature, irbody])

  return newCIRSym name

proc processDeclaration(ctx: var CIRContext, node: NimNode): CIRNode =
  var res = newCIRNode(cnkDecl)
  var idnt = newCIRNode(cnkIdentDef)
  let name = node[0].strVal
  let tyNode = if node[1].kind == nnkEmpty: node[0] else: node[1]

  let ty = getIRType(ctx, node[0])
  let expr = processNode(ctx, node[2])
  idnt.add(newCIRSym name)
  idnt.add(ty)
  res.add(idnt)
  res.add(expr)

  res

proc processNode(ctx: var CIRContext, node: NimNode, pc: ParsingContext= pcNone): CIRNode =
  ## Recursively transpile a Nim AST node to Cruise IR.
  ## Writes type/struct definitions to ctx.header,
  ## returns the GLSL expression/statement for the current node.
  case node.kind:
  of nnkStmtList:
    result = newCIRNode(cnkStmtList)
    for n in node:
      result.add processNode(ctx, n)

  of nnkVarSection, nnkLetSection:
    for n in node:
      result = ctx.processDeclaration(n)

  of nnkCall, nnkCommand:
    let nFuncName = node[0].strVal

    if nFuncName == "globalIndex":
      result = newCIRNode(cnkGlobalIndex)
      if node[1].kind != nnkSym:
        error("Cruise IR Transpiler: only identifiers are allowed in global indexing", node[1])
      result.add(ctx.getIRType(node[1])) 
    else:
      result = newCIRNode(cnkCall)
      let funcName = ctx.remapFunc(nFuncName, node[0])
      result.add(funcName)
      for i in 1..<node.len:
        result.add processNode(ctx, node[i])
  
  of nnkObjConstr:
    ## Object construction: MyVec(x: 1.0, y: 2.0) -> vec2(1.0, 2.0)
    result = newCIRNode(cnkCall)
    let irType = ctx.getIRType(node[0])

    result.add irType
    for i in 1..<node.len:
      result.add processNode(ctx, node[i][1])  # node[i] is nnkExprColonExpr

  of nnkBracketExpr:
    ## Array indexing: buf[i] -> buf[i]
    result = newCIRNode(cnkBracketExpr)
    result.add processNode(ctx, node[0])
    result.add processNode(ctx, node[1])
    
  of nnkDotExpr:
    ## Field access: pos.x -> pos.x
    result = newCIRNode(cnkDotExpr)
    result.add processNode(ctx, node[0])
    result.add newCIRSym(node[1].strVal)

  of nnkIfStmt, nnkIfExpr:
    ## if/elif/else
    result = newCIRNode(cnkIfStmt)
    for i, branch in node:
      var el: CIRNode
      if branch.kind == nnkElifBranch:
        el = newCIRNode(cnkElifBranch)
        el.add processNode(ctx, branch[0])
        el.add processNode(ctx, branch[1].ensureStmtList)
      elif branch.kind == nnkElse:
        el = newCIRNode(cnkElse)
        el.add processNode(ctx, branch[0].ensureStmtList)

      result.add(el)

  of nnkForStmt:
    ## for i in a..<b -> for(int i = a; i < b; i++)
    ## Only supports range iteration, rejects anything else
    result = newCIRNode(cnkForStmt)
    result.add newCIRSym(node[0].strVal)

    let iter = node[1]
    if iter.kind != nnkInfix or iter[0].strVal != "..<":
      error("Cruise IR Transpiler: only range iteration (a..<b) is supported in for loops", node)
    
    result.add processNode(ctx, iter[1])
    result.add processNode(ctx, iter[2])
    result.add processNode(ctx, node[2].ensureStmtList) 
    
  of nnkWhileStmt:
    ## while cond: body -> while (cond) { body }
    result = newCIRNode(cnkWhileStmt)

    result.add processNode(ctx, node[0])
    result.add processNode(ctx, node[1].ensureStmtList)

  of nnkReturnStmt:
    result = CIRNode(kind: cnkReturnStmt, args: @[processNode(ctx, node[0], pc=pcReturn)])

  of nnkSym, nnkIdent:
    result = newCIRSym node.strVal
  of nnkHiddenDeref:
    result = processNode(ctx, node[0])
  of nnkIntLit, nnkInt64Lit, nnkInt32Lit:    result = newCIRIntLit node.intVal
  of nnkFloatLit, nnkFloat64Lit, nnkFloat32Lit:  result = newCIRFloatLit node.floatVal
  of nnkInfix:
    result = newCIRNode(cnkInfix)
    result.add newCIRSym(node[0].strVal)
    result.add processNode(ctx, node[1])
    result.add processNode(ctx, node[2])
  of nnkPrefix:
    result = newCIRNode(cnkPrefix)
    result.add newCIRSym(node[0].strVal)
    result.add processNode(ctx, node[1])
  of nnkAsgn:
    if pc == pcReturn:
      result = processNode(ctx, node[1])
    else:
      result = newCIRNode(cnkAsgn)
      result.add processNode(ctx, node[0])
      result.add processNode(ctx, node[1])
  of nnkBreakStmt:
    result = newCIRNode(cnkBreakStmt)

  of nnkContinueStmt:
    result = newCIRNode(cnkContinueStmt)

  of nnkCast:
    ## cast[float32](x) → float(x)
    result = newCIRNode(cnkCast)
    let irTy = ctx.getIRType(node[0])
    result.add irTy
    result.add processNode(ctx, node[1])

  of nnkConv:
    ## float32(x) → float(x)
    result = newCIRNode(cnkConv)
    let irTy = ctx.getIRType(node[0])
    result.add irTy
    result.add processNode(ctx, node[1])

  of nnkBracket:
    ## Fixed-size array literal: [1.0, 2.0, 3.0]
    result = newCIRNode(cnkBracket)
    for elem in node:
      result.add processNode(ctx, elem)
  
  of nnkCaseStmt:
    ## case x:
    ##   of 1: ...
    ##   of 2: ...
    ##   else: ...
    ## → switch(x) { case 1: ... break; default: ... }
    result = newCIRNode(cnkCaseStmt)
    result.add processNode(ctx, node[0])
    for i in 1..<node.len:
      let branch = node[i]
      case branch.kind:
      of nnkOfBranch:
        var ob = newCIRNode(cnkOfBranch)
        ## May have multiple values: of 1, 2: ...
        for j in 0..<branch.len - 1:
          ob.add processNode(ctx, branch[j])
        ob.add processNode(ctx, branch[^1].ensureStmtList)
        result.add ob
      of nnkElse:
        var el = newCIRNode(cnkDefaultBranch)
        el.add processNode(ctx, branch[0].ensureStmtList)
        result.add el
      else:
        error("Cruise IR Transpiler: unsupported case branch kind: " & $branch.kind, branch)

  of nnkHiddenStdConv:
    ## Implicit standard type conversion e.g. int literal → float32
    ## The actual value is in node[1], node[0] is the target type
    result = processNode(ctx, node[1])

  of nnkHiddenSubConv:
    ## Implicit subtype conversion — same treatment
    result = processNode(ctx, node[1])

  of nnkHiddenCallConv:
    ## Implicit conversion via a constructor call e.g. SomeType(x)
    ## node[0] is the constructor, node[1..] are the args
    result = newCIRNode(cnkHiddenCallConv)
    let irTy = ctx.getIRType(node[0])
    result.add irTy
    result.add processNode(ctx, node[1])
  of nnkStmtListExpr:
    ## A statement list used as an expression — the last node is the value.
    ## Generated by template expansion, e.g:
    ##   template foo(x): float32 =
    ##     let tmp = x * 2.0  ## statement
    ##     tmp                 ## ← returned value
    ##
    ## Emit all statements except the last, then return the last as expression.
    result = newCIRNode(cnkStmtListExpr)
    for i in 0..<node.len - 1:
      result.add processNode(ctx, node[i])
    
    ## Last node is the expression value
    result.add processNode(ctx, node[^1])
  of nnkEmpty: result = newCIRNode(cnkEmpty)
  of nnkDiscardStmt: result = newCIRNode(cnkDiscardStmt)
  else:
    error("Unsupported AST node in Cruise IR Transpiler: " & $node.kind & "\n" &
          "  This Nim construct cannot be transpiled to IR.", node)

proc processParams(ctx: var CIRContext, params: NimNode): seq[CIRNode] =
  var firstVar = true
  var isCompute = true

  for i in 1..<params.len:   ## skip [0] which is return type
    var current: CIRNode
    let identDef = params[i]
    let paramName = identDef[0].strVal
    let tyNode    = identDef[1]           ## [1] is type, [0] is name
    let isVar     = tyNode.kind == nnkVarTy

    let innerTy = identDef[0]
    let typeName = innerTy.getTypeInst().repr

    for j in 0..<identDef.len - 2:  ## handle a, b: float32
      var res = newCIRNode(cnkIdentDef)
      res.add(newCIRSym identDef[j].strVal)

      if isWrapperType(typeName):
        ## Uniform[T], SSBO[T] etc. — emitQualifiedVar handles the header line
        current = emitQualifiedVar(ctx, typeName, identDef[j].strVal)
      else:
        ## Plain T → uniform in variable
        let irTy = ctx.getIRType(innerTy)
        current = irTy

      if isVar:
        var v = newCIRNode(cnkVarTy)
        v.add current
        current = v
    
      res.add(current)

      result.add(res)

macro compileToIR*(fn: typed): CIRContext =
  var ctx = CIRContext()
  let impl = fn.getImpl
  let name = impl[0]
  let params = impl[3]
  var body = impl[6]

  var irMain = newCIRNode(cnkFuncDef)
  var signature = newCIRNode(cnkFuncSig)
  signature.add(newCIRSym name.strVal)
  signature.add(newCIRNode(cnkEmpty))

  let args = ctx.processParams(params)
  signature.args.add(args)

  body = body.ensureStmtList
  
  let irBody = processNode(ctx, body)

  irMain.add signature
  irMain.add irBody

  ctx.body = irMain

  return quote do: `ctx`

