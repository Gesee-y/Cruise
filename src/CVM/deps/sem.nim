  # ###################################################################################################################################### #
 # ############################################################ SEMANTIC PASS ########################################################### #
# ###################################################################################################################################### #

proc resolveSymbol(cache: var TypeCache, n: CIRNode) =
  let isType = n.name in cache.functions or n.name in cache.nameToId
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
  let tyName = n.args[1].name
  let vname = n.args[0].name
  if tyName notin cache.nameToId:
    reportSemError n.info, "Unknown type `" & tyName & "` for variable/uniform `" & vname  & "`. Maybe the type is not native to GPU or undeclared in the current module."
    return false
  let typeId = cache.nameToId.getOrDefault(tyName, -1)

  if typeId >= 0 and cache.instances[typeId].kind in {ProcType, RefType}:
    reportSemError n.info, "Can't declare variable of type `ref` or `proc` because pointers are unsupported."
    return false

proc registerDefinition(cache: var TypeCache, n: CIRNode) =
  let tyName = n.args[1].name
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.nameToId.getOrDefault(tyName, -1)
    cache.variables[vname] = typeId
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)

proc registerUniform(cache: var TypeCache, n: CIRNode) =
  let tyName = n.args[0].args[1].name
  let vname = n.args[0].args[0].name
  if cache.isValidDefinition(n.args[0]):
    let typeId = cache.nameToId.getOrDefault(tyName, -1)
    cache.variables[vname] = typeId
    cache.addUniform(vname, typeId)

proc registerSSBO(cache: var TypeCache, n: CIRNode) =
  let tyName = n.args[1].name
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.nameToId.getOrDefault(tyName, -1)
    cache.variables[vname] = typeId
    cache.addSSBO(vname, typeId)

proc registerGlobalIndex(cache: var TypeCache, n: CIRNode) =
  let tyName = n.args[1].name
  let vname = n.args[0].name
  if cache.isValidDefinition(n):
    let typeId = cache.nameToId.getOrDefault(tyName, -1)
    cache.variables[vname] = typeId
    cache.liveness[vname] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)
    cache.addGlobalIndex(vname, typeId)

proc isWildCardType(ty: string): bool =
  return ty == "int" or ty == "float" or ty == "uint"

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

proc inferType*(cache: var TypeCache, node: var CIRNode): string =
  result = "auto"
  case node.kind
  of cnkIntLit: return "int"
  of cnkUintLit: return "uint"
  of cnkFloatLit: return "float"
  of cnkCharLit: return "char"
  of cnkBoolLit: return "bool"
  
  of cnkSym, cnkRSym:
    let typeId = cache.variables.getOrDefault(node.name, -1)
    if typeId < 0:
      reportSemError node.info, "Failed to get symbol type `" & node.name & "`."
      return 
    return cache.instances[typeId].name
      
  of cnkDotExpr:
    var r = cache.inferType(node.args[0])
    var current = node.args[1]
    var fields: seq[string] = @[]

    while current.kind == cnkDotExpr:
      let f = current.args[0].name
      current = current.args[1]
      fields.add(f)
    
    fields.add(current.name)
    return cache.getType(r, fields).name

  of cnkObjConstr:
    return node.args[0].name

  of cnkArrAt:
    let t = cache.inferType(node.args[0])
    return cache.getType(t).returnType

  of cnkPrefix, cnkInfix, cnkCall:
    if node.args[0].kind == cnkSym:
      resolveCall(cache, node)
    
    let tid = node.args[0].tid
    if tid >= 0 and tid < cache.instances.len:
      return cache.instances[tid].returnType

  of cnkConv:
    return node.args[0].name
    
  else:
    reportSemError node.info, "Failed to infer type of expression ```" & renderIR(node) & "```."
    return

proc resolveProc*(c: TypeCache, n: CIRNode, argTypes: seq[string]): int =
  let name = n.args[0].name

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
  let funcName = n.args[0].name
  var argTypes: seq[string] = @[]

  for i in 1 ..< n.args.len:
    cache.resolveNode(n.args[i], inFunc=true)
    argTypes.add(cache.inferType(n.args[i]))

  let procId = cache.resolveProc(n, argTypes)
  n.args[0] = newCIRRSym(n.args[0].info, funcName, procId)

proc resolveNode(cache: var TypeCache, n: var CIRNode, inFunc = false) =
  case n.kind
  of cnkSym:
    cache.resolveSymbol(n)
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
  of cnkGlobalIndex:
    cache.registerGlobalIndex(n)
  of cnkCall, cnkInfix, cnkPrefix:
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
  of cnkObjConstr:
    if not inFunc:
      reportSemError n.info, "Top level statements are unsupported on GPU."
    for i in 1..<n.args.len:
      cache.resolveNode(n.args[i].args[1], inFunc = inFunc)
  else:
    if not inFunc and n.kind notin {cnkStmtList, cnkSection}:
      reportSemError n.info, "Top level statements are unsupported on GPU."
    for arg in n.args.mitems:
      cache.resolveNode(arg, inFunc = inFunc)

proc semPass*(cache: var TypeCache, root: var CIRNode) =
  cache.resolveNode(root, inFunc=false)
