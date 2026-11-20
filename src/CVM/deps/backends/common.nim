# Shared source-emission helpers for the text backends.

proc backendShortName(name: string): string =
  let parts = name.split('.')
  if parts.len == 0: name else: parts[0]

proc backendIsNativeType(name: string, opencl: bool): bool =
  if opencl:
    return name in ["void", "bool", "char", "uchar", "short", "ushort",
      "int", "uint", "long", "ulong", "float", "double", "float2", "float3",
      "float4", "float8", "float16", "int2", "int3", "int4", "uint2",
      "uint3", "uint4", "image2d_t", "sampler_t"]
  return name in ["void", "bool", "int", "uint", "float", "vec2", "vec3", "vec4",
    "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4", "mat2", "mat3",
    "mat4", "sampler2D"]

proc backendType(cache: TypeCache, sourceType: string, opencl: bool): string =
  let ty = cache.equivalences.getOrDefault(sourceType, sourceType)
  if cache.getType(ty).kind == EnumType:
    return "int"
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
  else: result = backendShortName(ty)

proc backendTypeId(cache: TypeCache, sourceType: string): int =
  let resolved = cache.equivalences.getOrDefault(sourceType, sourceType)
  result = cache.nameToId.getOrDefault(resolved, -1)
  if result < 0:
    result = cache.nameToId.getOrDefault(backendShortName(resolved), -1)

proc backendSupportsType(cache: TypeCache, sourceType: string, opencl: bool,
                         visiting: var seq[int]): bool =
  let resolved = cache.equivalences.getOrDefault(sourceType, sourceType)
  let targetType = backendType(cache, resolved, opencl)
  if backendIsNativeType(targetType, opencl): return true

  let typeId = cache.backendTypeId(resolved)
  if typeId < 0: return false
  let inst = cache.instances[typeId]
  case inst.kind
  of EnumType:
    return true
  of ObjectType:
    if inst.fields.len == 0: return false
    if typeId in visiting: return true
    visiting.add(typeId)
    for field in inst.fields:
      if not cache.backendSupportsType(field.ty, opencl, visiting): return false
    visiting.setLen(visiting.len - 1)
    return true
  else:
    return false

proc collectBackendStruct(cache: TypeCache, typeId: int, opencl: bool,
                          visiting: var seq[int], ordered: var seq[int]) =
  if typeId in ordered or typeId in visiting: return
  let inst = cache.instances[typeId]
  if inst.kind != ObjectType: return
  if backendIsNativeType(backendType(cache, inst.name, opencl), opencl): return
  var checkPath: seq[int] = @[]
  if not cache.backendSupportsType(inst.name, opencl, checkPath): return

  visiting.add(typeId)
  for field in inst.fields:
    let depId = cache.backendTypeId(field.ty)
    if depId >= 0:
      cache.collectBackendStruct(depId, opencl, visiting, ordered)
  visiting.setLen(visiting.len - 1)
  ordered.add(typeId)

proc emitBackendTypeDecls*(root: CIRNode, cache: TypeCache,
                           opencl: bool): string =
  result = ""
  var ordered: seq[int] = @[]
  var visiting: seq[int] = @[]
  for i, inst in cache.instances:
    if inst.kind == ObjectType:
      cache.collectBackendStruct(i, opencl, visiting, ordered)

  for typeId in ordered:
    let inst = cache.instances[typeId]
    let name = backendShortName(inst.name)
    if opencl:
      result.add("typedef struct " & name & " {\n")
    else:
      result.add("struct " & name & " {\n")
    for field in inst.fields:
      result.add("  " & backendType(cache, field.ty, opencl) & " " &
        backendShortName(field.name) & ";\n")
    if opencl:
      result.add("} " & name & ";\n\n")
    else:
      result.add("};\n\n")

  let items = if root.kind in {cnkStmtList, cnkSection}: root.args else: @[root]
  var sourceFunctions: seq[string] = @[]
  for item in items:
    if item.kind == cnkFuncDef and backendShortName(item.args[0].name) != "main":
      sourceFunctions.add(backendShortName(item.args[0].name))

  var emittedSignatures: seq[string] = @[]
  for inst in cache.instances:
    if inst.kind != ProcType or backendShortName(inst.name) notin sourceFunctions:
      continue
    let returnType = if inst.returnType.len == 0: "void" else: inst.returnType
    var checkPath: seq[int] = @[]
    var supported = cache.backendSupportsType(returnType, opencl, checkPath)
    var params: seq[string] = @[]
    for i, field in inst.fields:
      checkPath.setLen(0)
      if not cache.backendSupportsType(field.ty, opencl, checkPath):
        supported = false
      let paramName = if field.name.len == 0: "p" & $i else: backendShortName(field.name)
      params.add(backendType(cache, field.ty, opencl) & " " & paramName)
    if not supported: continue

    let protoName = backendShortName(inst.name)
    let signature = backendType(cache, returnType, opencl) & " " & protoName &
      "(" & (if params.len == 0: "void" else: params.join(", ")) & ");"
    if signature notin emittedSignatures:
      emittedSignatures.add(signature)
      result.add(signature & "\n")

  if result.len > 0: result.add("\n")

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
