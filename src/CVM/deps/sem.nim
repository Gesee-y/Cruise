  # ###################################################################################################################################### #
 # ############################################################ SEMANTIC PASS ########################################################### #
# ###################################################################################################################################### #

proc resolveSymbol(cache: TypeCache, n: CIRNode) =
  assert cache.variables.getOrDefault(n.name, -1) >= 0 or cache.functions.getOrDefault(n.name, -1) >= 0, """Unable to resolve symbol `""" & n.name & """`. 
    May be a symbol unaccessible from the current module or not natively supported by GPU"""

proc registerDefinition(cache: var TypeCache, n: CIRNode) =
  let tyName = n.args[1].name
  let vname = n.args[0].name
  assert tyName in cache.nameToId, "Unknown type `" & tyName & "` for variable `" & vname  & "`. Maybe the type is not native to GPU or undeclared in the current module."
  let typeId = cache.nameToId.getOrDefault(tyName, -1)

  assert cache.instances[typeId].kind notin {ProcType, RefType}, "Can't declare variable of type `ref` or `proc` because pointers are unsupported."
  cache.variables[n.args[0].name] = typeId

proc inferType*(cache: var TypeCache, node: var CIRNode): string =
  case node.kind
  of cnkIntLit: "int"
  of cnkUintLit: "uint"
  of cnkFloatLit: "float"
  of cnkCharLit: "char"
  of cnkBoolLit: "bool"
  
  of cnkSym:
    let typeId = cache.variables.getOrDefault(node.name, -1)
    assert typeId >= 0, "Failed to get symbol type `" & node.name & "`."
    cache.instances[typeId].name
      
  of cnkPrefix, cnkInfix, cnkCall:
    if node.args[0].kind == cnkSym:
      resolveCall(cache, node)
    
    let tid = node.args[0].tid
    return cache.instances[tid].returnType  
  of cnkConv:
    return node.args[0].name
    
  else:
    assert false, "Failed to infer type of expression ```" & renderIR(node) & "```."

proc resolveProc*(c: TypeCache, name: string, argTypes: seq[string]): int =
  assert name in c.functions, "Unknown function `" & name & "`. Maybe the function is not native to GPU or not declared in the current module."
  let overload = c.functions.getOrDefault(name)
  var currentNodeId = 0
  result = -1

  for argTy in argTypes:
    try:
      currentNodeId = overload.nodes[currentNodeId].children[argTy]
      result = overload.nodes[currentNodeId].tid
    else:
      assert false, "Unknown function `" & name & "`. Maybe the function is not native to GPU or not declared in the current module."

proc resolveCall(cache: var TypeCache, n: var CIRNode) =
  let funcName = n.args[0].name
  var argTypes: seq[string] = @[]

  for i in 1 ..< n.args.len:
    cache.resolveNode(n.args[i])
    argTypes.add(cache.inferType(n.args[i]))

  let procId = cache.resolveProc(funcName, argTypes)
  assert procId >= 0, "No matching overload found for function `" & funcName & "` with these argument types."
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
  else:
    for arg in n.args.mitems:
      cache.resolveNode(arg)

