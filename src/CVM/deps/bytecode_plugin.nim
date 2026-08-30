# ################################################################################################################### #
# ############################################## BYTECODE TRANSLATOR ################################################ #
# ################################################################################################################### #

import plugins

proc generateBytecode(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)

proc noTransform(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)

var inp = loadPluginInput()
var c = inp
# Bytecode emission is not implemented yet.  Keep the source tree unchanged so
# the plugin remains a valid compilation-time pass until the generator is ready.
discard generateBytecode(c)
saveTree noTransform(inp)
