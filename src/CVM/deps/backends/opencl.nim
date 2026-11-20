proc emitOpenCL*(root: CIRNode, cache: TypeCache): string =
  result = "// OpenCL C 1.2 source generated from rewritten CVM IR.\n\n"
  result.add(emitBackendTypeDecls(root, cache, true))
  let items = if root.kind in {cnkStmtList, cnkSection}: root.args else: @[root]
  var entry = newCIRNode(default(LineInfo), cnkEmpty)
  var uniforms: seq[CIRNode] = @[]
  var textures: seq[CIRNode] = @[]
  for item in items:
    if item.kind == cnkUniform: uniforms.add(item)
    if item.kind == cnkTexture: textures.add(item)
    if item.kind == cnkFuncDef and backendShortName(item.args[0].name) == "main": entry = item

  for item in items:
    if item.kind == cnkFuncDef and backendShortName(item.args[0].name) != "main":
      result.add(backendFunction(cache, item, true, false) & "\n\n")

  if entry.kind != cnkEmpty:
    var params: seq[string] = @[]
    for param in entry.args[1].args:
      let name = backendShortName(param.args[0].name)
      let ty = param.args[1].name
      case param.kind
      of cnkGlobalIndex: discard
      of cnkSSBO:
        let elemType = cache.getType(ty).returnType
        params.add("__global " & backendType(cache, elemType, true) & "* " & name)
      of cnkTexture:
        params.add("read_only image2d_t " & name)
      else:
        params.add(backendType(cache, ty, true) & " " & name)
    for uniform in uniforms:
      let def = uniform.args[0]
      params.add(backendType(cache, def.args[1].name, true) & " " & backendShortName(def.args[0].name))
    for texture in textures:
      let def = texture.args[0]
      params.add("read_only image2d_t " & backendShortName(def.args[0].name))

    result.add("__kernel void main(" & params.join(", ") & ") {\n")
    for param in entry.args[1].args:
      if param.kind == cnkGlobalIndex:
        let name = backendShortName(param.args[0].name)
        let ty = backendType(cache, param.args[1].name, true)
        result.add("  " & ty & " " & name & " = (" & ty & ")get_global_id(0);\n")
    result.add(backendBlock(cache, entry.args[3], true, 1) & "\n}\n")
