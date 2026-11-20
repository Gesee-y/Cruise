# Shared source-emission helpers for the text backends.

proc backendShortName(name: string): string =
  let parts = name.split('.')
  if parts.len == 0: name else: parts[^1]

proc backendType(cache: TypeCache, sourceType: string, opencl: bool): string =
  let ty = cache.equivalences.getOrDefault(sourceType, sourceType)
  case ty
  of "void": result = "void"
  of "bool": result = "bool"
  of "int", "int32": result = "int"
  of "uint", "uint32": result = "uint"
  of "float", "float32": result = "float"
  of "double", "float64": result = "double"
  of "int64":
    if opencl: result = "long" else: result = "int64_t"
  of "uint64":
    if opencl: result = "ulong" else: result = "uint64_t"
  of "vec2f":
    if opencl: result = "float2" else: result = "vec2"
  of "vec3f":
    if opencl: result = "float3" else: result = "vec3"
  of "vec4f":
    if opencl: result = "float4" else: result = "vec4"
  of "vec2i":
    if opencl: result = "int2" else: result = "ivec2"
  of "vec3i":
    if opencl: result = "int3" else: result = "ivec3"
  of "vec4i":
    if opencl: result = "int4" else: result = "ivec4"
  of "vec2u":
    if opencl: result = "uint2" else: result = "uvec2"
  of "vec3u":
    if opencl: result = "uint3" else: result = "uvec3"
  of "vec4u":
    if opencl: result = "uint4" else: result = "uvec4"
  of "mat2f":
    if opencl: result = "float2x2" else: result = "mat2"
  of "mat3f":
    if opencl: result = "float3x3" else: result = "mat3"
  of "mat4f":
    if opencl: result = "float4x4" else: result = "mat4"
  of "sampler2D":
    if opencl: result = "image2d_t" else: result = "sampler2D"
  else: result = ty

proc backendExpr(cache: TypeCache, node: CIRNode, opencl: bool): string

proc backendCallName(name: string, opencl: bool): string =
  result = backendShortName(name)
  if result.startsWith("newVec") and result.len >= 7:
    let dim = result[6]
    let family = result[^1]
    if opencl:
      result = (if family == 'i': "int" elif family == 'u': "uint" else: "float") & $dim
    else:
      result = (if family == 'i': "ivec" elif family == 'u': "uvec" else: "vec") & $dim
    return
  case result
  of "lerp": result = "mix"
  of "ln": result = "log"
  of "arctan": result = "atan"
  of "arctan2": result = "atan2"
  of "float32", "float": result = "float"
  of "int32", "int": result = "int"
  of "uint32", "uint": result = "uint"
  of "bool": result = "bool"
  of "sample", "sampleLod":
    if not opencl: result = "texture"
  else: discard

proc backendExpr(cache: TypeCache, node: CIRNode, opencl: bool): string =
  result = ""
  case node.kind
  of cnkSym, cnkRSym:
    result = backendShortName(node.name)
    if not opencl and result == "gl_pos": result = "gl_Position"
  of cnkIntLit:
    result = $node.intVal
  of cnkUintLit:
    result = $node.uintVal & "u"
  of cnkFloatLit:
    result = $node.floatVal
    if '.' notin result and 'e' notin result and 'E' notin result: result.add(".0")
  of cnkCharLit:
    result = $ord(node.charVal)
  of cnkBoolLit:
    result = if node.boolVal: "true" else: "false"
  of cnkInfix:
    if node.args.len == 3:
      let op = node.args[0].name
      let translated = if op == "and": "&&" elif op == "or": "||" elif op == "xor": "^" else: op
      result = "(" & backendExpr(cache, node.args[1], opencl) & " " & translated & " " &
        backendExpr(cache, node.args[2], opencl) & ")"
    else: result = "0"
  of cnkPrefix:
    if node.args.len >= 2:
      let op = if node.args[0].name == "not": "!" else: node.args[0].name
      result = "(" & op & backendExpr(cache, node.args[1], opencl) & ")"
    else: result = "0"
  of cnkCall:
    var args: seq[string] = @[]
    for i in 1 ..< node.args.len:
      args.add(backendExpr(cache, node.args[i], opencl))
    result = backendCallName(node.args[0].name, opencl) & "(" & args.join(", ") & ")"
  of cnkFma:
    result = "fma(" & backendExpr(cache, node.args[0], opencl) & ", " &
      backendExpr(cache, node.args[1], opencl) & ", " & backendExpr(cache, node.args[2], opencl) & ")"
  of cnkRsqrt:
    result = (if opencl: "rsqrt(" else: "inversesqrt(") & backendExpr(cache, node.args[0], opencl) & ")"
  of cnkConv, cnkCast, cnkHiddenStdConv, cnkHiddenSubConv:
    if node.args.len >= 2:
      result = backendType(cache, node.args[0].name, opencl) & "(" & backendExpr(cache, node.args[1], opencl) & ")"
    else: result = "0"
  of cnkDotExpr:
    if node.args.len == 2:
      result = backendExpr(cache, node.args[0], opencl) & "." & backendShortName(node.args[1].name)
    else: result = "0"
  of cnkArrAt:
    result = backendExpr(cache, node.args[0], opencl) & "[" & backendExpr(cache, node.args[1], opencl) & "]"
  of cnkObjConstr:
    var args: seq[string] = @[]
    for i in 1 ..< node.args.len:
      args.add(backendExpr(cache, node.args[i].args[1], opencl))
    result = backendType(cache, node.args[0].name, opencl) & "(" & args.join(", ") & ")"
  else:
    reportIRError node.info, "Source backend does not support expression node `" & $node.kind & "`."
    result = "0"

proc backendIndent(level: int): string = repeat("  ", level)

proc backendStmt(cache: TypeCache, node: CIRNode, opencl: bool, level: int): string

proc backendBlock(cache: TypeCache, node: CIRNode, opencl: bool, level: int): string =
  result = ""
  if node.kind in {cnkStmtList, cnkSection}:
    for child in node.args:
      let line = backendStmt(cache, child, opencl, level)
      if line.len > 0:
        if result.len > 0: result.add("\n")
        result.add(line)
  else:
    result = backendStmt(cache, node, opencl, level)

proc backendStmt(cache: TypeCache, node: CIRNode, opencl: bool, level: int): string =
  result = ""
  let ind = backendIndent(level)
  case node.kind
  of cnkEmpty, cnkDiscardStmt, cnkShaderName, cnkTypeEqv, cnkTriggerCLTranspilation,
     cnkTriggerGLSL33Transpilation, cnkUniform, cnkTexture:
    result = ""
  of cnkStmtList, cnkSection:
    result = backendBlock(cache, node, opencl, level)
  of cnkVarTy:
    let def = node.args[0]
    if def.args.len >= 2:
      result = ind & backendType(cache, def.args[1].name, opencl) & " " & backendShortName(def.args[0].name)
      if node.args.len >= 2 and node.args[1].kind != cnkEmpty:
        result.add(" = " & backendExpr(cache, node.args[1], opencl))
      result.add(";")
  of cnkAsgn:
    result = ind & backendExpr(cache, node.args[0], opencl) & " = " & backendExpr(cache, node.args[1], opencl) & ";"
  of cnkArrAsgnAt:
    result = ind & backendExpr(cache, node.args[0], opencl) & "[" & backendExpr(cache, node.args[1], opencl) & "] = " & backendExpr(cache, node.args[2], opencl) & ";"
  of cnkInfix:
    if node.args[0].name.endsWith("=") and node.args[0].name.len == 2:
      result = ind & backendExpr(cache, node.args[1], opencl) & " " & node.args[0].name & " " & backendExpr(cache, node.args[2], opencl) & ";"
    else:
      result = ind & backendExpr(cache, node, opencl) & ";"
  of cnkCall:
    result = ind & backendExpr(cache, node, opencl) & ";"
  of cnkReturnStmt:
    result = ind & "return"
    if node.args.len > 0 and node.args[0].kind != cnkEmpty:
      result.add(" " & backendExpr(cache, node.args[0], opencl))
    result.add(";")
  of cnkBreakStmt: result = ind & "break;"
  of cnkContinueStmt: result = ind & "continue;"
  of cnkIfStmt:
    for i, branch in node.args:
      if branch.kind == cnkElse:
        result.add(ind & "else {\n" & backendBlock(cache, branch.args[0], opencl, level + 1) & "\n" & ind & "}")
      elif branch.kind == cnkElifBranch:
        result.add(ind & (if i == 0: "if" else: "else if") & " (" & backendExpr(cache, branch.args[0], opencl) & ") {\n")
        result.add(backendBlock(cache, branch.args[1], opencl, level + 1) & "\n" & ind & "}")
      if i < node.args.len - 1: result.add("\n")
  of cnkWhileStmt:
    result = ind & "while (" & backendExpr(cache, node.args[0], opencl) & ") {\n" &
      backendBlock(cache, node.args[1], opencl, level + 1) & "\n" & ind & "}"
  of cnkForStmt:
    let declarations = node.args[0]
    let iter = node.args[1]
    let name = backendShortName(declarations.args[0].args[0].name)
    let start = backendExpr(cache, iter.args[1], opencl)
    let stop = backendExpr(cache, iter.args[2], opencl)
    let op = if iter.args[0].name == "..": " <= " else: " < "
    result = ind & "for (int " & name & " = " & start & "; " & name & op & stop & "; ++" & name & ") {\n" &
      backendBlock(cache, node.args[2], opencl, level + 1) & "\n" & ind & "}"
  of cnkFuncDef:
    result = ""
  else:
    reportIRError node.info, "Source backend does not support statement node `" & $node.kind & "`."
    result = ""

proc backendFunction(cache: TypeCache, node: CIRNode, opencl, isEntry: bool): string =
  result = ""
  let name = backendShortName(node.args[0].name)
  let retType = backendType(cache, node.args[2].name, opencl)
  var params: seq[string] = @[]
  for param in node.args[1].args:
    if isEntry and param.kind in {cnkGlobalIndex, cnkVertexInput, cnkVertexOutput,
        cnkVertexVarying, cnkFragmentInput, cnkFragmentOutput}:
      continue
    let ty = param.args[1].name
    let pname = backendShortName(param.args[0].name)
    if param.kind == cnkSSBO:
      let elemTy = cache.getType(ty).returnType
      params.add("__global " & backendType(cache, elemTy, true) & "* " & pname)
    else:
      params.add(backendType(cache, ty, opencl) & " " & pname)
  let fnName = if isEntry and not opencl: "main" else: name
  let resultType = if isEntry and not opencl: "void" else: retType
  result = resultType & " " & fnName & "(" & params.join(", ") & ") {\n"
  if isEntry and opencl:
    for param in node.args[1].args:
      if param.kind == cnkGlobalIndex:
        let varName = backendShortName(param.args[0].name)
        let ty = backendType(cache, param.args[1].name, true)
        result.add("  " & ty & " " & varName & " = (" & ty & ")get_global_id(0);\n")
  result.add(backendBlock(cache, node.args[3], opencl, 1))
  result.add("\n}")
