# ################################################################################################################################################################## #
# #################################################################### BYTECODE TRANSLATOR ######################################################################### #
# ################################################################################################################################################################## #


proc generateBytecode(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)

proc noTransform(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)

var inp = loadPluginInput()
var c = inp
saveBytecode(c)
saveTree noTransform(inp)
