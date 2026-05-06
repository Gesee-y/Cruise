##########################################################################################################################################################
############################################################ TRANPILER NIM -> GLSL #######################################################################
##########################################################################################################################################################

import macros, tables, sets, strutils

## ── Uniform / buffer qualifier wrappers ───────────────────────────────────────
## Wrap a type in one of these to declare it as a GLSL qualified variable.
## The transpiler detects these wrappers in function signatures and variable
## declarations, then emits the correct layout line in the header.
##
## Example:
##   proc myKernel(a: Uniform[float32], buf: SSBO[float32], img: Image2D[float32])
##   # emits:
##   #   uniform float a;
##   #   layout(std430, binding=0) buffer { float buf[]; };
##   #   layout(rgba32f) writeonly uniform image2D img;
type
  Uniform*[T]       = distinct T  ## uniform T name;
  UniformReadOnly*[T]  = distinct T  ## layout(...) readonly buffer
  UniformWriteOnly*[T] = distinct T  ## layout(...) writeonly buffer
  SSBO*[T]          = distinct T  ## layout(std430) buffer { T name[]; };
  Image2D*[T]       = distinct T  ## layout(rgba32f) writeonly uniform image2D
  Sampler2D*        = object      ## uniform sampler2D name;

  GLSLContext = object
    header: string      ## Type definitions, struct declarations
    body: string        ## Main function body
    emittedTypes: HashSet[string] ## Already emitted type
    emittedFuncs: HashSet[string]

  CompiledShader = object
    glsl*: string
    bindings*: Table[string, int]

proc processNode(ctx: var GLSLContext,node: NimNode, depth: int = 0): string
proc processDeclaration(ctx: var GLSLContext, node: NimNode): string
proc emitStruct(ctx: var GLSLContext, ty: NimNode): string

var glslTypeTable {.compileTime.} = initTable[string, string]()
var glslFuncTable {.compileTime.} = initTable[string, string]()

var globalBindingTable {.compileTime.} = initTable[string, int]()
var nextBinding {.compileTime.} = 0

proc getBinding(name: string): int {.compileTime.} =
  ## Return a stable binding index for a named resource across all shaders.
  ## Same name always maps to the same binding point globally.
  if name in globalBindingTable:
    return globalBindingTable[name]
  result = nextBinding
  globalBindingTable[name] = result
  inc nextBinding

macro registerGLSLType(ty: typed, glslName: string): untyped =
  glslTypeTable[$ty.getTypeInst()] = glslName.strVal

macro registerGLSLFunc(nimFunc: typed, glslName: string): untyped =
  ## Register a mapping from a Nim function to a GLSL builtin name.
  ## Use this for functions from external libraries whose implementation
  ## should not be transpiled but mapped directly to a GLSL builtin.
  ##
  ## Example:
  ##   registerGLSLFunc(glm.dot, "dot")
  ##   registerGLSLFunc(myMath.fastSqrt, "sqrt")
  glslFuncTable[nimFunc.strVal] = glslName.strVal

proc initDefaultFuncMappings() {.compileTime.} =
  ## Pre-populate with standard GLSL builtins and CVectors library mappings.
  ## Functions listed here are never transpiled — they map directly to GLSL builtins.

  # ── Standard math builtins ──────────────────────────────────────────────────
  const mathBuiltins = [
    ("sin", "sin"), ("cos", "cos"), ("tan", "tan"),
    ("arcsin", "asin"), ("arccos", "acos"), ("arctan", "atan"),
    ("arctan2", "atan"),       ## atan(y, x) in GLSL
    ("sqrt", "sqrt"), ("pow", "pow"), ("exp", "exp"), ("log", "log"),
    ("abs", "abs"), ("sign", "sign"),
    ("floor", "floor"), ("ceil", "ceil"), ("round", "round"),
    ("min", "min"), ("max", "max"), ("clamp", "clamp"),
    ("mix", "mix"),            ## GLSL lerp
    ("fract", "fract"),
    ("mod", "mod"),
    ("step", "step"), ("smoothstep", "smoothstep"),
    ("length", "length"), ("normalize", "normalize"),
    ("dot", "dot"), ("cross", "cross"),
    ("reflect", "reflect"), ("refract", "refract"),
  ]
  for (nim, glsl) in mathBuiltins:
    glslFuncTable[nim] = glsl

  # ── CVectors → GLSL builtins ─────────────────────────────────────────────────
  # Most map 1:1 since GLSL has the same operations natively.
  # Ones that don't exist in GLSL are transpiled from their Nim body instead
  # (no entry here = fallback to transpilation).
  const cvecMappings = [
    # Arithmetic — handled by operators, not calls, but listed for completeness
    ("dot",           "dot"),
    ("cross",         "cross"),
    ("length",        "length"),
    ("normalize",     "normalize"),
    ("reflect",       "reflect"),
    ("refract",       "refract"),
    ("distance",      "distance"),
    ("abs",           "abs"),
    ("floor",         "floor"),
    ("ceil",          "ceil"),
    ("round",         "round"),
    ("fract",         "fract"),
    ("min",           "min"),
    ("max",           "max"),
    ("clamp",         "clamp"),
    ("mix",           "mix"),        ## lerp(a, b, t) → mix(a, b, t)
    ("smoothStep",    "smoothstep"),

    # No GLSL equivalent — will be transpiled from Nim body:
    # lengthSq, distanceSq, safeNormalize, project, reject,
    # perpendicular, faceForward, moveTowards, slerp,
    # lerpClamped, approxEq, isNormalized, isZero,
    # saturate, sum, minComponent, maxComponent,
    # angle, signedAngle, toAngle, rotate, rotateAround
  ]
  for (nim, glsl) in cvecMappings:
    glslFuncTable[nim] = glsl

  # ── CVectors type mappings ───────────────────────────────────────────────────
  # Concepts can't be registered directly — concrete types using them are.
  # The transpiler detects CVec2/3/4 satisfaction via field inspection.
  const cvecTypes = [
    ("CVec2f", "vec2"), ("CVec3f", "vec3"), ("CVec4f", "vec4"),
    ("CVec2i", "ivec2"), ("CVec3i", "ivec3"), ("CVec4i", "ivec4"),
  ]
  for (nim, glsl) in cvecTypes:
    glslTypeTable[nim] = glsl

static: initDefaultFuncMappings()

proc isWrapperType(typeName: string): bool {.compileTime.} =
  typeName.startsWith("Uniform[")      or
  typeName.startsWith("UniformReadOnly[") or
  typeName.startsWith("UniformWriteOnly[") or
  typeName.startsWith("SSBO[")         or
  typeName.startsWith("Image2D[")      or
  typeName == "Sampler2D"

proc getGLSLType(ctx: var GLSLContext, typeName: string): string {.compileTime.} =
  if typeName in ctx.emittedTypes: return typeName

  # Our known primitive types
  case typeName:
  of "int", "int32":   return "int"
  of "float", "float32": return "float"
  of "float64":        return "double"
  of "bool":           return "bool"
  of "uint32":         return "uint"
  else:
    if typeName in glslTypeTable:
      return glslTypeTable[typeName]

    return typeName

proc emitQualifiedVar(ctx: var GLSLContext, typeName: string,
                      paramName: string): string {.compileTime.} =
  ## Emit the correct GLSL header declaration for a qualified variable.
  ## typeName is the full Nim generic name e.g. "Uniform[float32]"

  let bid = getBinding(paramName)

  if typeName.startsWith("Uniform["):
    let inner = ctx.getGLSLType(typeName[8..^2])  ## strip "Uniform[" and "]"
    return "uniform " & inner & " " & paramName & ";\n"

  elif typeName.startsWith("SSBO["):
    let inner = ctx.getGLSLType(typeName[5..^2])
    return "layout(std430, binding = " & $bid & ") buffer " & paramName &
           "Block {\n  " & inner & " " & paramName & "[];\n};\n"

  elif typeName.startsWith("UniformReadOnly["):
    let inner = ctx.getGLSLType(typeName[16..^2])
    return "layout(std430) readonly buffer " & paramName &
           "Block {\n  " & inner & " " & paramName & "[];\n};\n"

  elif typeName.startsWith("UniformWriteOnly["):
    let inner = ctx.getGLSLType(typeName[17..^2])
    return "layout(std430) writeonly buffer " & paramName &
           "Block {\n  " & inner & " " & paramName & "[];\n};\n"

  elif typeName.startsWith("Image2D["):
    return "layout(rgba32f) writeonly uniform image2D " & paramName & ";\n"

  elif typeName == "Sampler2D":
    return "uniform sampler2D " & paramName & ";\n"

proc getGLSLType(ctx: var GLSLContext, node: NimNode): string =
  var sym = node.getTypeInst()
  if sym.kind == nnkVarTy: sym = sym[0]
  let typeName = sym.strVal
  let paramName = node.strVal

  if isWrapperType(typeName):
    if paramName notin ctx.emittedTypes:  ## guard by param name, not type
      ctx.emittedTypes.incl(paramName)
      ctx.header &= emitQualifiedVar(ctx, typeName, paramName)

  if typeName in ctx.emittedTypes: return typeName

  # Our known primitive types
  case typeName:
  of "int", "int32":   return "int"
  of "float", "float32": return "float"
  of "float64":        return "double"
  of "bool":           return "bool"
  of "uint32":         return "uint"
  else:
    if typeName in glslTypeTable:
      return glslTypeTable[typeName]

    for pragma in sym.getImpl()[4]:  # nnkPragma
      if pragma[0].strVal == "glslType":
        return pragma[1].strVal

    let s = emitStruct(ctx, sym)
    ctx.header.add(s)
    ctx.emittedTypes.incl(typeName)

    return typeName

proc emitStruct(ctx: var GLSLContext, ty: NimNode): string =
  ## Generate a GLSL type from a Nim object
  let impl = ty.getImpl()
  result = "struct " & ty.strVal & " {\n"
  for field in impl[2][2]:  # fields
    let fieldName = field[0].strVal
    let fieldType = getGLSLType(ctx, field[1])
    result &= "  " & fieldType & " " & fieldName & ";\n"
  result &= "};\n"

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

  # Emit dependencies first (recursive calls inside this func)
  # processNode will call remapFunc again for any calls found inside,
  # which will recursively emit their definitions before this one.
  var funcCtx = GLSLContext()  ## inherit type/func tables
  funcCtx.emittedTypes = ctx.emittedTypes
  funcCtx.emittedFuncs = ctx.emittedFuncs

  let glslBody = processNode(funcCtx, impl[6])
  ctx.emittedTypes = funcCtx.emittedTypes  ## propagate newly discovered types
  ctx.emittedFuncs = funcCtx.emittedFuncs

  # Build GLSL function signature
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

  # Emit to header BEFORE marking as done (handles mutual recursion guard)
  ctx.emittedFuncs.incl(name)
  ctx.header &= signature & " {\n" & glslBody & "\n}\n\n"

  return name

proc processDeclaration(ctx: var GLSLContext, node: NimNode): string =
  var res = ""
  let name = node[0].strVal
  let tyNode = if node[1].kind == nnkEmpty: node[0] else: node[1]

  let ty = getGLSLType(ctx, tyNode)
  let expr = processNode(ctx, node[2])

  res.add ty & " " & name
  if expr != "": res.add " = " & expr
  res

proc processNode(ctx: var GLSLContext, node: NimNode, depth: int = 0): string =
  ## Recursively transpile a Nim AST node to GLSL.
  ## Writes type/struct definitions to ctx.header,
  ## returns the GLSL expression/statement for the current node.
  let idnts = "    "
  let idnt = repeat(idnts, depth)
  case node.kind:
  of nnkStmtList:
    for n in node:
      result = processNode(ctx, n, depth+1) & ";\n"
      ctx.body &= result

  of nnkVarSection, nnkLetSection:
    for n in node:
      let tyNode = if n[1].kind == nnkEmpty: n[0] else: n[1]
      ## Detect fixed-size array declarations → header
      if tyNode.kind == nnkBracketExpr and
         tyNode.getTypeInst().kind == nnkBracketExpr and
         tyNode.getTypeInst()[0].strVal == "array":
        let name   = n[0].strVal
        let size   = tyNode.getTypeInst()[1].intVal
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
        result &= processNode(ctx, branch[1], depth+1) & "\n" & idnt & "}"
      elif branch.kind == nnkElse:
        result &= " else {\n" & processNode(ctx, branch[0], depth+1) & "\n" & idnt & "}"

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
    result &= processNode(ctx, node[2], depth+1) & "}"

  of nnkWhileStmt:
    ## while cond: body -> while (cond) { body }
    result = idnt & "while (" & processNode(ctx, node[0]) & ") {\n"
    result &= processNode(ctx, node[1], depth+1) & "}"

  of nnkReturnStmt:
    result = idnt & "return " & processNode(ctx, node[0])

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

    let innerTy = if isVar: tyNode[0] else: tyNode
    let typeName = innerTy.getTypeInst().strVal

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

macro compileToGLSL(fn: typed): CompiledShader =
  var ctx = GLSLContext()
  let impl = fn.getImpl
  let name = impl[0]
  let params = impl[3]
  let body = impl[6]

  let isCompute = ctx.processParams(params)
  discard processNode(ctx, body)

  ## Assemble final GLSL
  var header = "#version 430\n"
  if isCompute: header &= "layout(local_size_x = 64) in;\n\n"
  let glsl = header & ctx.header & "\nvoid main() {\n" & ctx.body & "}"

  let bindings = globalBindingTable
  
  return quote do: CompiledShader(glsl: `glsl`, bindings: `bindings`)

