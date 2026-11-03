  # ###################################################################################################################################### #
 # ############################################################ SEMANTIC PASS ########################################################### #
# ###################################################################################################################################### #

proc resolveSymbol(cache: var TypeCache, n: CIRNode) =
  if cache.variables.getOrDefault(n.name, -1) < 0 and cache.functions.getOrDefault(n.name, -1) < 0:
    reportSemError n.info, """Unable to resolve symbol `""" & n.name & """`. 
      May be a symbol unaccessible from the current module or not natively supported by GPU"""

  try: cache.liveness[n.name].dead = n.info
  except: discard

proc registerDefinition(cache: var TypeCache, n: CIRNode) =
  let tyName = n.args[1].name
  let vname = n.args[0].name
  if tyName notin cache.nameToId:
    reportSemError n.info, "Unknown type `" & tyName & "` for variable `" & vname  & "`. Maybe the type is not native to GPU or undeclared in the current module."
    return
  let typeId = cache.nameToId.getOrDefault(tyName, -1)

  if cache.instances[typeId].kind in {ProcType, RefType}:
    reportSemError n.info, "Can't declare variable of type `ref` or `proc` because pointers are unsupported."
    return
  cache.variables[n.args[0].name] = typeId
  cache.liveness[n.args[0].name] = CLiveness(birth: n.args[0].info, dead: n.args[0].info)

proc inferType*(cache: var TypeCache, node: var CIRNode): string =
  result = "auto"
  case node.kind
  of cnkIntLit: "int"
  of cnkUintLit: "uint"
  of cnkFloatLit: "float"
  of cnkCharLit: "char"
  of cnkBoolLit: "bool"
  
  of cnkSym:
    let typeId = cache.variables.getOrDefault(node.name, -1)
    if typeId < 0:
      reportSemError node.info, "Failed to get symbol type `" & node.name & "`."
      return
    cache.instances[typeId].name
      
  of cnkDotExpr:
    result = cache.inferType(node.args[0])
    var current = node.args[1]
    var fields: seq[string] = @[]

    while current.kind == cnkDotExpr:
      let f = current.args[0].name
      current = current.args[1]
      fields.add(f)
    
    fields.add(current.name)
    result = cache.getType(result, fields).name
  of cnkPrefix, cnkInfix, cnkCall:
    if node.args[0].kind == cnkSym:
      resolveCall(cache, node)
    
    let tid = node.args[0].tid
    return cache.instances[tid].returnType  
  of cnkConv:
    return node.args[0].name
    
  else:
    reportSemError node.info, "Failed to infer type of expression ```" & renderIR(node) & "```."

proc resolveProc*(c: TypeCache, n: CIRNode, argTypes: seq[string]): int =
  let name = n.args[0].name
  result = 0
  if name notin c.functions:
   reportSemError n.info, "Unknown function `" & name & "`. Maybe the function is not native to GPU or not declared in the current module."
   return
  
  let overload = c.functions.getOrDefault(name)
  var currentNodeId = 0
  
  for argTy in argTypes:
    try:
      currentNodeId = overload.nodes[currentNodeId].children[argTy]
      result = overload.nodes[currentNodeId].tid
    else:
      reportSemError n.info, "Unknown function `" & name & "`. Maybe the function is not native to GPU or not declared in the current module."
      return 0

proc resolveCall(cache: var TypeCache, n: var CIRNode) =
  let funcName = n.args[0].name
  var argTypes: seq[string] = @[]

  for i in 1 ..< n.args.len:
    cache.resolveNode(n.args[i])
    argTypes.add(cache.inferType(n.args[i]))

  let procId = cache.resolveProc(n, argTypes)
  n.args[0] = newCIRRSym(n.args[0].info, funcName, procId)

proc resolveNode(cache: var TypeCache, n: var CIRNode) =
  case n.kind:
  of cnkSym:
    cache.resolveSymbol(n)
  of cnkIntLit, cnkUintLit, cnkCharLit, cnkFloatLit, cnkDiscardStmt, cnkEmpty, cnkContinueStmt, cnkWritOnly,
    cnkReadOnly: discard
  of cnkSymDef:
    cache.registerDefinition(n)
  of cnkCall, cnkInfix, cnkPrefix:
    cache.resolveCall(n)
  of cnkDotExpr:
    cache.resolveNode(n.args[0])
  else:
    for arg in n.args.mitems:
      cache.resolveNode(arg)

