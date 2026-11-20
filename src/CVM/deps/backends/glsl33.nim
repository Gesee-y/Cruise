proc emitGLSL33*(root: CIRNode, cache: TypeCache): string =
  result = "#version 330 core\n\n"
  let items = if root.kind in {cnkStmtList, cnkSection}: root.args else: @[root]
  var entry = newCIRNode(default(LineInfo), cnkEmpty)
  for item in items:
    if item.kind == cnkUniform:
      let def = item.args[0]
      result.add("uniform " & backendType(cache, def.args[1].name, false) & " " &
        backendShortName(def.args[0].name) & ";\n")
    elif item.kind == cnkTexture:
      let def = item.args[0]
      result.add("uniform sampler2D " & backendShortName(def.args[0].name) & ";\n")
    elif item.kind == cnkFuncDef and backendShortName(item.args[0].name) == "main":
      entry = item
  if result[^1] != '\n': result.add("\n")

  if entry.kind != cnkEmpty:
    var inputLocation = 0
    var varyingLocation = 0
    var outputLocation = 0
    for param in entry.args[1].args:
      let name = backendShortName(param.args[0].name)
      let ty = backendType(cache, param.args[1].name, false)
      case param.kind
      of cnkVertexInput:
        result.add("layout(location = " & $inputLocation & ") in " & ty & " " & name & ";\n")
        inc inputLocation
      of cnkVertexVarying:
        result.add("layout(location = " & $varyingLocation & ") out " & ty & " " & name & ";\n")
        inc varyingLocation
      of cnkFragmentInput:
        result.add("layout(location = " & $inputLocation & ") in " & ty & " " & name & ";\n")
        inc inputLocation
      of cnkFragmentOutput:
        result.add("layout(location = " & $outputLocation & ") out " & ty & " " & name & ";\n")
        inc outputLocation
      else: discard
    result.add("\n")

  for item in items:
    if item.kind == cnkFuncDef and backendShortName(item.args[0].name) != "main":
      result.add(backendFunction(cache, item, false, false) & "\n\n")
  if entry.kind != cnkEmpty:
    result.add(backendFunction(cache, entry, false, true) & "\n")
