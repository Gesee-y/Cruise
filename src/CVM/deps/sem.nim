  # ###################################################################################################################################### #
 # ############################################################ SEMANTIC PASS ########################################################### #
# ###################################################################################################################################### #

proc resolveSymbol(cache: var TypeCache, n: CIRNode) =
  let isType = n.name in cache.functions or n.name in cache.nameToId or n.name in cache.equivalences
  if cache.variables.getOrDefault(n.name, -1) < 0 and not isType:
    reportSemError n.info, """Unable to resolve symbol `""" & n.name & """`. May be a symbol inaccessible from the current module or not natively supported by GPU"""

  if isType:
    if cache.getType(n.name).kind == RefType:
      reportSemError n.info, "Ref types are not allowed on GPU: `" & n.name & "`."

    return
  try:
    cache.liveness[n.name].dead = n.info
  except:
    discard

proc isValidDefinition(cache: var TypeCache, n: CIRNode): bool =
  result = true
  let ty = n.args[1].name
  let vname = n.args[0].name
  let tyName = cache.equivalences.getOrDefault(ty, ty)
  var typeId = cache.nameToId.getOrDefault(tyName, -1)
  if typeId < 0:
    let shortName = ty.split(".")[0]
    let shortEq = cache.equivalences.getOrDefault(shortName, shortName)
    typeId = cache.nameToId.getOrDefault(shortEq, -1)
  if typeId < 0:
    reportSemError n.info, "Unknown type `" & tyName & "` for variable/uniform `" & vname  & "`. Maybe the type is not native to GPU or undeclared in the current module."
    return false

  if cache.instances[typeId].kind in {ProcType, RefType}:
    reportSemError n.info, "Can't declare variable `" & vname & "` of type `" & tyName & "` `ref` or `proc` because pointers are unsupported."
    return false

proc getTypeName(cache: TypeCache, n: CIRNode): string =
  result = cache.equivalences.getOrDefault(n.name, n.name)

proc getTypeId(cache: TypeCache, n: CIRNode): int =
  result = cache.nameToId.getOrDefault(cache.getTypeName(n), -1)

proc registerDefinition(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.getTypeId(n.args[1])
    cache.variables[vname] = typeId
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)

proc registerUniform(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].args[0].name
  if cache.isValidDefinition(n.args[0]):
    let typeId = cache.getTypeId(n.args[0].args[1])
    cache.variables[vname] = typeId
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)
    cache.addUniform(vname, typeId)

proc registerFragment(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].name
  let tyName = cache.getTypeName(n.args[1])
  if tyName != "vec4f":
    reportSemError n.info, "Fragment shader output should be a `vec4f`"
  if cache.isValidDefinition(n):
    let typeId = cache.getTypeId(n.args[1])
    cache.variables[vname] = typeId
    cache.shaderParams.fragOut = vname
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)

proc addShaderBlockItem(items: var seq[ShaderBlockItem], name, typeName: string,
                        size: int, info: LineInfo) =
  var offset = 0
  for item in items:
    offset = max(offset, item.offset + item.size)
  if offset + size > 128:
    reportSemError info, "Shader input/output block exceeds 128 bytes"
    return
  items.add ShaderBlockItem(name: name, typeName: typeName,
                            offset: offset, size: size)

proc registerVertex(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.getTypeId(n.args[1])
    cache.variables[vname] = typeId
    cache.shaderParams.vertOut = vname
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)

proc registerVertexVarying(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.getTypeId(n.args[1])
    cache.variables[vname] = typeId
    let size = max(1, cache.getType(typeId).size)
    addShaderBlockItem(cache.shaderParams.vertVaryings, vname, cache.getTypeName(n.args[1]), size, n.info)
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)

proc registerFragmentInput(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.getTypeId(n.args[1])
    cache.variables[vname] = typeId
    let size = max(1, cache.getType(typeId).size)
    addShaderBlockItem(cache.shaderParams.fragInputs, vname, cache.getTypeName(n.args[1]), size, n.info)
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)

proc registerVertexInput(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.getTypeId(n.args[1])
    cache.variables[vname] = typeId
    let size = max(1, cache.getType(typeId).size)
    addShaderBlockItem(cache.shaderParams.vertInputs, vname, cache.getTypeName(n.args[1]), size, n.info)
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)

proc registerSSBO(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.getTypeId(n.args[1])
    cache.variables[vname] = typeId
    cache.addSSBO(vname, typeId)

proc registerTexture(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].args[0].name
  if cache.isValidDefinition(n.args[0]):
    let typeId = cache.nameToId.getOrDefault("sampler2D", -1)
    cache.variables[vname] = typeId
    cache.addTexture(vname, typeId)

proc registerGlobalIndex(cache: var TypeCache, n: CIRNode) =
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.getTypeId(n.args[1])
    cache.variables[vname] = typeId
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)
    cache.addGlobalIndex(vname, typeId)

proc isWildCardType(ty: string): bool =
  return ty == "int" or ty == "float" or ty == "uint"

proc isInplaceOperator(op: string): bool =
  op.startsWith("+=") or op.startsWith("-=") or
    op.startsWith("*=") or op.startsWith("/=")

proc inplaceBaseOperator(op: string): string =
  if op.isInplaceOperator: $op[0] else: ""

proc isVectorTypeName(typeName: string): bool =
  typeName in ["vec2f", "vec3f", "vec4f", "vec2i", "vec3i", "vec4i"]

proc isSameNumericFamily(lhsType, rhsType: string): bool =
  (lhsType.startsWith("float") and rhsType.startsWith("float")) or
  (lhsType.startsWith("int") and rhsType.startsWith("int")) or
  (lhsType.startsWith("uint") and rhsType.startsWith("uint"))

proc isInplaceTypeCompatible(cache: TypeCache, lhsType, rhsType: string): bool =
  result = false
  if lhsType == rhsType:
    return true
  if isSameNumericFamily(lhsType, rhsType):
    return cache.getType(lhsType).size == cache.getType(rhsType).size
  if lhsType.isVectorTypeName:
    let component = lhsType[^1]
    return cache.getType(rhsType).size == 4 and
           ((component == 'f' and rhsType.startsWith("float")) or
            (component == 'i' and rhsType.startsWith("int")))

proc findSimilar(p: ProcOverloadNode, ty: string, info: LineInfo, pos: int): string =
  result = ty
  var tys: seq[string] = @[]
  for k in p.children.keys:
    if k.startsWith(ty):
      tys.add k

  if tys.len > 0:
    result = tys[0]

    if tys.len > 1:
      if pos == 0: 
        result = tys[^1]
        return
      let tyStr = tys.join(" | ")
      reportSemError info, "Multiple type for call argument at `" & $pos & "`: `" & tyStr  & "`."

proc inferTypeOrAdd*(cache: var TypeCache, node: var CIRNode): string =
  result = "auto"
  case node.kind
  of cnkIntLit: 
    result = "int"
  of cnkUintLit: 
    result = "uint"
  of cnkFloatLit: 
    result = "float"
  of cnkCharLit: 
    result = "char"
  of cnkBoolLit: 
    result = "bool"
  
  of cnkSym, cnkRSym:
    let typeId = cache.variables.getOrDefault(node.name, -1)
    if typeId < 0:
      reportSemError node.info, "Failed to get symbol type `" & node.name & "`."
      return 
    result = cache.instances[typeId].name
      
  of cnkDotExpr:
    var r = cache.inferTypeOrAdd(node.args[0])
    var current = node.args[1]
    var fields: seq[string] = @[]

    while current.kind == cnkDotExpr:
      # Since fields name are unique and already validated
      # We can normalize them to only the first part of the Nimony's symbol
      let f = current.args[0].name.split(".")[0]
      current = current.args[1]
      fields.add(f)
    
    fields.add(current.name.split(".")[0])
    result = cache.getType(r, fields).name

  of cnkObjConstr:
    result = node.args[0].name

  of cnkArrAt:
    let t = cache.inferTypeOrAdd(node.args[0])
    result = cache.getType(t).returnType

  of cnkInfix:
    if node.args[0].name.isInplaceOperator:
      result = cache.inferTypeOrAdd(node.args[1])
    else:
      if node.args[0].kind == cnkSym:
        resolveCall(cache, node)
      let tid = node.args[0].tid
      if tid >= 0 and tid < cache.instances.len:
        result = cache.instances[tid].returnType

  of cnkPrefix, cnkCall:
    if node.args[0].kind == cnkSym:
      resolveCall(cache, node)
    
    let tid = node.args[0].tid
    if tid >= 0 and tid < cache.instances.len:
      result = cache.instances[tid].returnType

  of cnkConv:
    result = node.args[0].name

  of cnkFma, cnkRsqrt:
    var operand = node.args[0]
    result = cache.inferTypeOrAdd(operand)
    
  else:
    reportSemError node.info, "Failed to infer type of expression ```" & renderIR(node) & "```."
    return

  result = cache.equivalences.getOrDefault(result, result)

# A version of inferType that doesn't modify it's argument
# Made to be used post-sem, reduce copies
proc inferType*(cache: var TypeCache, node: CIRNode): string =
  result = "auto"
  case node.kind
  of cnkIntLit: 
    result = "int"
  of cnkUintLit: 
    result = "uint"
  of cnkFloatLit: 
    result = "float"
  of cnkCharLit: 
    result = "char"
  of cnkBoolLit: 
    result = "bool"
  
  of cnkSym:
    let typeId = cache.variables.getOrDefault(node.name, -1)
    result = cache.instances[typeId].name
  of cnkRSym:
    result = cache.instances[node.tid].name
  of cnkDotExpr:
    var r = cache.inferType(node.args[0])
    var current = node.args[1]
    var fields: seq[string] = @[]

    while current.kind == cnkDotExpr:
      let f = current.args[0].name.split(".")[0]
      current = current.args[1]
      fields.add(f)
    
    fields.add(current.name.split(".")[0])
    result = cache.getType(r, fields).name

  of cnkObjConstr:
    result = node.args[0].name

  of cnkArrAt:
    let t = cache.inferType(node.args[0])
    result = cache.getType(t).returnType

  of cnkInfix:
    if node.args[0].name.isInplaceOperator:
      result = cache.inferType(node.args[1])
    else:
      let tid = node.args[0].tid
      if tid >= 0 and tid < cache.instances.len:
        result = cache.instances[tid].returnType

  of cnkPrefix, cnkCall:
    let tid = node.args[0].tid
    if tid >= 0 and tid < cache.instances.len:
      result = cache.instances[tid].returnType

  of cnkConv:
    result = node.args[0].name

  of cnkFma, cnkRsqrt:
    var operand = node.args[0]
    result = cache.inferType(operand)
    
  else:
    return

  result = cache.equivalences.getOrDefault(result, result)

proc resolveProc*(c: TypeCache, n: CIRNode, argTypes: seq[string]): int =
  let fullName = n.args[0].name
  let shortName = fullName.split(".")[0]
  let name = if shortName in c.functions: shortName else: fullName

  if name notin c.functions:
    reportSemError n.info, "Unknown function `" & name & "`. Maybe the function is not native to GPU or not declared in the current module."
    return -1
  
  let overload = c.functions.getOrDefault(name)
  if overload.nodes.len == 0:
    return -1

  var currentNodeId = 0
  result = overload.nodes[0].tid
  var pos = 0
  
  for argTy in argTypes:
    var nextId = overload.nodes[currentNodeId].children.getOrDefault(argTy, -1)
    if nextId < 0 and isWildCardType(argTy):
      let ty = overload.nodes[currentNodeId].findSimilar(argTy, n.args[pos].info, pos)
      nextId = overload.nodes[currentNodeId].children.getOrDefault(ty, -1)
    
    if nextId >= 0:
      currentNodeId = nextId
      result = overload.nodes[currentNodeId].tid
    else:
      if overload.nodes[0].tid >= 0:
        return overload.nodes[0].tid

      var argStr = argTypes.join(", ")
      reportSemError n.info, "Unknown overload for function `" & name & "`. Maybe arguments of types " & argStr & " are unsupported."
      return -1

    inc pos

proc resolveCall(cache: var TypeCache, n: var CIRNode) =
  let fullName = n.args[0].name
  let shortName = fullName.split(".")[0]
  let funcName = if shortName in cache.functions: shortName else: fullName
  var argTypes: seq[string] = @[]

  for i in 1 ..< n.args.len:
    cache.resolveNode(n.args[i], inFunc=true)
    argTypes.add(cache.inferTypeOrAdd(n.args[i]))

  let procId = cache.resolveProc(n, argTypes)
  n.args[0] = newCIRRSym(n.args[0].info, funcName, procId)

proc resolveNode(cache: var TypeCache, n: var CIRNode, inFunc = false) =
  case n.kind
  of cnkSym:
    cache.resolveSymbol(n)
  of cnkShaderName:
    cache.programName = n.args[0].name
  of cnkRSym, cnkIntLit, cnkUintLit, cnkCharLit, cnkFloatLit, cnkBoolLit,
     cnkDiscardStmt, cnkEmpty, cnkContinueStmt, cnkBreakStmt, cnkWritOnly,
     cnkReadOnly:
    discard
  of cnkSymDef:
    cache.registerDefinition(n)
  of cnkUniform:
    cache.registerUniform(n)
  of cnkSSBO:
    cache.registerSSBO(n)
  of cnkTexture:
    cache.registerTexture(n)
  of cnkGlobalIndex:
    cache.registerGlobalIndex(n)
  of cnkFragmentOutput:
    cache.registerFragment(n)
  of cnkVertexOutput:
    cache.registerVertex(n)
  of cnkVertexVarying:
    cache.registerVertexVarying(n)
  of cnkVertexInput:
    cache.registerVertexInput(n)
  of cnkFragmentInput:
    cache.registerFragmentInput(n)
  of cnkTriggerGLSLTranspilation:
    cache.transpilation.incl(tmGLSL)
  of cnkTriggerOpenCLTranspilation:
    cache.transpilation.incl(tmOpenCL)
  of cnkAsgn:
    cache.resolveNode(n.args[0], inFunc=inFunc)
    cache.resolveNode(n.args[1], inFunc=inFunc)

    let ty = cache.inferTypeOrAdd(n.args[0])
    if cache.getType(ty).kind == ContainerType:
      reportSemError n.info, "Can't assign a container to a variable. This would cause aliasing on GPU."
  of cnkInfix:
    if n.args.len == 3 and n.args[0].name.isInplaceOperator:
      cache.resolveNode(n.args[1], inFunc = inFunc)
      cache.resolveNode(n.args[2], inFunc = inFunc)
      let lhsType = cache.inferTypeOrAdd(n.args[1])
      let rhsType = cache.inferTypeOrAdd(n.args[2])
      if not isInplaceTypeCompatible(cache, lhsType, rhsType):
        reportSemError n.info, "In-place operator `" & n.args[0].name &
          "` requires matching scalar types or a compatible vector/scalar pair; got `" &
          lhsType & "` and `" & rhsType & "`."
    else:
      if not inFunc:
        reportSemError n.info, "Top level statements are unsupported on GPU."
      cache.resolveCall(n)
  of cnkCall, cnkPrefix:
    if not inFunc:
      reportSemError n.info, "Top level statements are unsupported on GPU."
    cache.resolveCall(n)
  of cnkDotExpr:
    cache.resolveNode(n.args[0], inFunc = inFunc)
  of cnkFuncDef:
    cache.resolveNode(n.args[1], inFunc = true)
    cache.resolveNode(n.args[3], inFunc = true)
  of cnkForStmt:
    cache.resolveNode(n.args[0], inFunc = inFunc)
    if n.args[1].args.len >= 3:
      cache.resolveNode(n.args[1].args[1], inFunc = inFunc)
      cache.resolveNode(n.args[1].args[2], inFunc = inFunc)
    cache.resolveNode(n.args[2], inFunc = inFunc)
  of cnkTypeEqv:
    cache.equivalences[n.args[0].name] = n.args[1].name
  of cnkObjConstr:
    if not inFunc:
      reportSemError n.info, "Top level statements are unsupported on GPU."
    for i in 1..<n.args.len:
      cache.resolveNode(n.args[i].args[1], inFunc = inFunc)
      n.args[i].args[0].n = n.args[i].args[0].name.split(".")[0]
  else:
    if not inFunc and n.kind notin {cnkStmtList, cnkSection}:
      reportSemError n.info, "Top level statements are unsupported on GPU."
    for arg in n.args.mitems:
      cache.resolveNode(arg, inFunc = inFunc)

proc semPass*(cache: var TypeCache, root: var CIRNode) =
  cache.resolveNode(root, inFunc=false)
