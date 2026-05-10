##########################################################################################################################################################
############################################################ TRANPILER NIM -> CRUISE IR ##################################################################
##########################################################################################################################################################

type 
  CIRNodeKind = enum
    cnkStmtList
    cnkDecl
    cnkCall
    cnkObjConstr
    cnkBracketExpr
    cnkDotExpr
    cnkIfStmt
    cnkForStmt
    cnkWhileStmt
    cnkReturnStmt
    cnkSym
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
    cnkOfBranch
    cnkElse
    cnkHiddenStdConv
    cnkHiddenSubConv 
    cnkHiddenCallConv
    cnkStmtListExpr
    cnkEmpty
    cnkDiscardStmt
  
  CIRNode = object
    case kind: CIRNodeKind
    of cnkSym:
      name: string
    of cnkIntLit:
      intVal: int
    of cnkFloatLit:
      floatVal: float
    of cnkDiscardStmt, cnkEmpty, cnkContinueStmt, cnkReturnStmt: discard
    else:
      args: seq[CIRNode]

  CIRContext = object
    types: CIRNode
    forwardDecl: CIRNode
    funcDef: CIRNode
    body: CIRNode

##########################################################################################################################################################
################################################################## UTILITIES #############################################################################
##########################################################################################################################################################

proc normalizeTypes(name: string): string =
  
  

proc newCIRNode*(kind: static CIRNodeKind): CIRNode = CIRNode(kind: kind)
proc add*(a: var CIRNode, b: CIRNode) = a.args.add(b)
proc newCIRSym(name: string): CIRNode = CIRNode(kind: cnkSym, name: name)

proc emitStruct(ctx: var CIRContext, ty: NimNode): CIRNode =
  ## Generate a GLSL type from a Nim object
  result = newCIRNode(cnkTypeDef)
  result.add(newCIRSym(ty.strVal))
  let impl = ty.getImpl()

  for field in impl[2][2]:  # fields
    var def = newCIRNode(cnkIdentDef)
    def.add(newCIRSym(field[0].strVal))
    def.add(newCIRSym(field[0].strVal))
    
    let fieldName = field[0].strVal
    let fieldType = getGLSLType(ctx, field[1])
    result &= "  " & fieldType & " " & fieldName & ";\n"
  result &= "};\n"

proc ensureStmtList(node: NimNode): NimNode =
  if node.kind in {nnkStmtList, nnkStmtListExpr}:
    return node
  result = newNimNode(nnkStmtList)
  result.add(node)

proc remapFunc(ctx: var GLSLContext, name: string, node: NimNode): string =
  ## Resolve a function call to its GLSL name.
  ## If the function is unknown, transpile its Nim implementation
  ## and emit it to the header (once).

  # 1. Explicit mapping registered by user
  if name in glslFuncTable:
    return glslFuncTable[name]

  # 2. Already emitted in a previous call, reuse
  if name in ctx.emittedFuncs:
    return name

  # 3. Unknown function: transpile its body and emit to header
  let impl = node.getImpl()
  if impl.isNil or impl.kind == nnkNilLit:
    error("GLSL Transpiler: unknown function '" & name & "' has no Nim implementation to transpile.\n" &
          "  Hint: add it to the function mapping table or provide a Nim implementation.", node)

  let params = impl[3]
  let returnType = if params[0].kind == nnkEmpty: "void"
                   else: ctx.getGLSLType(params[0])

  var args: seq[string]
  for i in 1..<params.len:
    let param = params[i]
    let glslType = ctx.getGLSLType(param[^2])
    for j in 0..<param.len - 2:  ## handle a, b: float32
      args.add(glslType & " " & param[j].strVal)

  let signature = returnType & " " & name & "(" & args.join(", ") & ")"

  ctx.forwardDecl = signature & ";\n" & ctx.forwardDecl
  ctx.emittedFuncs.incl(name) # Include the name early to avoid infinite recursions
  # Emit dependencies first (recursive calls inside this func)
  # processNode will call remapFunc again for any calls found inside,
  # which will recursively emit their definitions before this one.
  var funcCtx = GLSLContext()  ## inherit type/func tables
  funcCtx.emittedTypes = ctx.emittedTypes
  funcCtx.emittedFuncs = ctx.emittedFuncs

  var glslBody = ""
  var body = impl[6].ensureStmtList
  
  let fbody = processNode(funcCtx, body)
  ctx.typeDecl &= funcCtx.typeDecl
  ctx.forwardDecl = funcCtx.forwardDecl & "\n" & ctx.forwardDecl
  ctx.funcDef &= funcCtx.funcDef
  glslBody &= funcCtx.body
  
  case impl[6].kind:
    of nnkStmtList, nnkStmtListExpr: discard
    else: glslBody = "   " & fbody

  ## Last expression → return result
  #if returnType != "void":
  #  glslBody &= "\n  return result;\n"

  ctx.emittedTypes = funcCtx.emittedTypes  ## propagate newly discovered types
  ctx.emittedFuncs = funcCtx.emittedFuncs

  # Emit to header BEFORE marking as done (handles mutual recursion guard)
  ctx.funcDef &= signature & " {\n" & glslBody & "\n}\n"

  return name

proc processDeclaration(ctx: var GLSLContext, node: NimNode): string =
  var res = ""
  let name = node[0].strVal
  let tyNode = if node[1].kind == nnkEmpty: node[0] else: node[1]

  let ty = getGLSLType(ctx, node[0])
  let expr = processNode(ctx, node[2])

  res.add ty & " " & name
  if expr != "": res.add " = " & expr
  res

proc processNode(ctx: var GLSLContext, node: NimNode, depth: int = 0, pc: ParsingContext= pcNone): string =
  ## Recursively transpile a Nim AST node to GLSL.
  ## Writes type/struct definitions to ctx.header,
  ## returns the GLSL expression/statement for the current node.
  let idnts = "    "
  let idnt = repeat(idnts, depth)
  case node.kind:
  of nnkStmtList:
    for n in node:
      result &= processNode(ctx, n, depth+1) & ";\n"
      ctx.body &= result

  of nnkVarSection, nnkLetSection:
    for n in node:
      let tyNode = if n[1].kind == nnkEmpty: n[0] else: n[1]
      ## Detect fixed-size array declarations → header
      if tyNode.kind == nnkBracketExpr and
         tyNode.getTypeInst().kind == nnkBracketExpr and
         tyNode.getTypeInst()[0].strVal == "array":
        let name   = n[0].strVal
        
        let size   = tyNode[1].intVal
        let glslTy = ctx.getGLSLType(tyNode.getTypeInst()[2])
        let expr   = if n[2].kind != nnkEmpty: " = " & processNode(ctx, n[2], depth) else: ""
        ## Local fixed arrays stay in body, global ones go to header
        result = idnt & glslTy & " " & name & "[" & $size & "]" & expr
      else:
        result = idnt & ctx.processDeclaration(n)

  of nnkCall, nnkCommand:
    ## Function call: remap name if needed, recurse on args
    let funcName = ctx.remapFunc(node[0].strVal, node[0])  ## e.g. "abs" -> "abs", custom -> mapped
    var args: seq[string]
    for i in 1..<node.len:
      args.add processNode(ctx, node[i])
    result = funcName & "(" & args.join(", ") & ")"

  of nnkObjConstr:
    ## Object construction: MyVec(x: 1.0, y: 2.0) -> vec2(1.0, 2.0)
    let glslType = ctx.getGLSLType(node[0])
    var args: seq[string]
    for i in 1..<node.len:
      args.add processNode(ctx, node[i][1])  ## node[i] is nnkExprColonExpr
    result = glslType & "(" & args.join(", ") & ")"

  of nnkBracketExpr:
    ## Array indexing: buf[i] -> buf[i]
    result = processNode(ctx, node[0]) & "[" & processNode(ctx, node[1]) & "]"

  of nnkDotExpr:
    ## Field access: pos.x -> pos.x
    result = processNode(ctx, node[0]) & "." & node[1].strVal

  of nnkIfStmt, nnkIfExpr:
    ## if/elif/else
    for i, branch in node:
      if branch.kind == nnkElifBranch:
        let keyword = if i == 0: "if" else: "else if"
        result &= idnt & keyword & " (" & processNode(ctx, branch[0]) & ") {\n"
        result &= processNode(ctx, branch[1].ensureStmtList, depth) & "\n" & idnt & "}"
      elif branch.kind == nnkElse:
        result &= " else {\n" & processNode(ctx, branch[0].ensureStmtList, depth) & "\n" & idnt & "}"

  of nnkForStmt:
    ## for i in a..<b -> for(int i = a; i < b; i++)
    ## Only supports range iteration, rejects anything else
    let iter = node[1]
    if iter.kind != nnkInfix or iter[0].strVal != "..<":
      error("GLSL Transpiler: only range iteration (a..<b) is supported in for loops", node)
    let varName = node[0].strVal
    let lo = processNode(ctx, iter[1])
    let hi = processNode(ctx, iter[2])
    result = idnt & "for (int " & varName & " = " & lo & "; " &
             varName & " < " & hi & "; " & varName & "++) {\n"
    result &= processNode(ctx, node[2].ensureStmtList, depth) & "\n" & idnt & "}"

  of nnkWhileStmt:
    ## while cond: body -> while (cond) { body }
    result = idnt & "while (" & processNode(ctx, node[0]) & ") {\n"
    result &= processNode(ctx, node[1].ensureStmtList, depth) & "\n" & idnt & "}"

  of nnkReturnStmt:
    result = idnt & "return " & processNode(ctx, node[0], pc=pcReturn)

  of nnkSym, nnkIdent:
    result = node.strVal
  of nnkHiddenDeref:
    result = processNode(ctx, node[0])
  of nnkIntLit:    result = $node.intVal
  of nnkFloatLit:  result = $node.floatVal
  of nnkInfix:
    result = processNode(ctx, node[1]) & " " & node[0].strVal & " " & processNode(ctx, node[2])
  of nnkPrefix:
    result = node[0].strVal & processNode(ctx, node[1])
  of nnkAsgn:
    if pc == pcReturn:
      result = processNode(ctx, node[1])
    else:
      result = idnt & processNode(ctx, node[0]) & " = " & processNode(ctx, node[1])
  of nnkBreakStmt:
    result = idnt & "break"

  of nnkContinueStmt:
    result = idnt & "continue"

  of nnkCast:
    ## cast[float32](x) → float(x)
    let glslTy = ctx.getGLSLType(node[0])
    result = glslTy & "(" & processNode(ctx, node[1], depth) & ")"

  of nnkConv:
    ## float32(x) → float(x)
    let glslTy = ctx.getGLSLType(node[0])
    result = glslTy & "(" & processNode(ctx, node[1], depth) & ")"

  of nnkBracket:
    ## Fixed-size array literal: [1.0, 2.0, 3.0]
    var elems: seq[string]
    for elem in node:
      elems.add processNode(ctx, elem, depth)
    result = "{" & elems.join(", ") & "}"

  of nnkConstDef, nnkTypeDef:
    ## Fixed-size array type declaration → goes to header, not body
    ## array[N, T] → const T name[N];
    let name = node[0].strVal
    let tyNode = node[1]
    if tyNode.kind == nnkBracketExpr and tyNode[0].strVal == "array":
      let size    = processNode(ctx, tyNode[1], depth)  ## N
      let glslTy  = ctx.getGLSLType(tyNode[2])          ## T
      ## Array declarations belong in the header, not the body
      ctx.header &= "const " & glslTy & " " & name & "[" & size & "];\n"
    else:
      error("GLSL Transpiler: only fixed-size array types are supported at top level", node)

  of nnkCaseStmt:
    ## case x:
    ##   of 1: ...
    ##   of 2: ...
    ##   else: ...
    ## → switch(x) { case 1: ... break; default: ... }
    result = idnt & "switch (" & processNode(ctx, node[0], depth) & ") {\n"
    for i in 1..<node.len:
      let branch = node[i]
      case branch.kind:
      of nnkOfBranch:
        ## May have multiple values: of 1, 2: ...
        for j in 0..<branch.len - 1:
          result &= idnt & "  case " & processNode(ctx, branch[j], depth) & ":\n"
        result &= processNode(ctx, branch[^1], depth + 1)
        result &= idnt & "    break;\n"
      of nnkElse:
        result &= idnt & "  default:\n"
        result &= processNode(ctx, branch[0], depth + 1)
        result &= idnt & "    break;\n"
      else:
        error("GLSL Transpiler: unsupported case branch kind: " & $branch.kind, branch)
    result &= idnt & "}"
  of nnkHiddenStdConv:
    ## Implicit standard type conversion e.g. int literal → float32
    ## The actual value is in node[1], node[0] is the target type
    result = processNode(ctx, node[1], depth)

  of nnkHiddenSubConv:
    ## Implicit subtype conversion — same treatment
    result = processNode(ctx, node[1], depth)

  of nnkHiddenCallConv:
    ## Implicit conversion via a constructor call e.g. SomeType(x)
    ## node[0] is the constructor, node[1..] are the args
    let glslTy = ctx.getGLSLType(node[0])
    result = glslTy & "(" & processNode(ctx, node[1], depth) & ")"
  of nnkStmtListExpr:
    ## A statement list used as an expression — the last node is the value.
    ## Generated by template expansion, e.g:
    ##   template foo(x): float32 =
    ##     let tmp = x * 2.0  ## statement
    ##     tmp                 ## ← returned value
    ##
    ## Emit all statements except the last, then return the last as expression.
    for i in 0..<node.len - 1:
      let stmt = processNode(ctx, node[i], depth)
      if stmt != "":
        ctx.body &= idnt & stmt & ";\n"
    ## Last node is the expression value
    result = processNode(ctx, node[^1], depth)
  of nnkEmpty: discard
  of nnkDiscardStmt: result = "discard"
  else:
    error("Unsupported AST node in GLSL Transpiler: " & $node.kind & "\n" &
          "  This Nim construct cannot be transpiled to GLSL.", node)

proc processParams(ctx: var GLSLContext, params: NimNode): bool =
  ## Parse function parameters and emit GLSL header declarations.
  ## - var T parameters    → writeonly SSBO / out variable
  ## - Uniform[T]          → uniform declaration
  ## - SSBO[T]             → shader storage buffer
  ## - plain T             → in variable (read-only)
  ##
  ## First var parameter is treated as the output buffer by convention.

  var firstVar = true
  var isCompute = true

  for i in 1..<params.len:   ## skip [0] which is return type
    let identDef = params[i]
    let paramName = identDef[0].strVal
    let tyNode    = identDef[1]           ## [1] is type, [0] is name
    let isVar     = tyNode.kind == nnkVarTy

    let innerTy = identDef[0]
    let typeName = innerTy.getTypeInst().repr

    if isWrapperType(typeName):
      ## Uniform[T], SSBO[T] etc. — emitQualifiedVar handles the header line
      ctx.header &= emitQualifiedVar(ctx, typeName, paramName)
    elif isVar:
      ## var T → output buffer
      ## First var param gets binding 0 by convention
      let glslTy = ctx.getGLSLType(innerTy)
      let bid = getBinding(paramName)
      if firstVar:
        ctx.header &= "layout(std430, binding = " & $bid & ") buffer OutBlock {\n" &
                      "  " & glslTy & " " & paramName & "[];\n};\n"
        if glslTy == "vec4": isCompute = false
        firstVar = false
      else:
        ctx.header &= "layout(std430, binding = " & $bid & ") buffer Block" &
                      $bid & " {\n  " & glslTy & " " & paramName & "[];\n};\n"
    else:
      ## Plain T → uniform in variable
      let glslTy = ctx.getGLSLType(innerTy)
      if not isWrapperType(typeName):
        ctx.header &= "uniform " & glslTy & " " & paramName & ";\n"

  return isCompute

  

