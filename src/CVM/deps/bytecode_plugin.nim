# ################################################################################################################### #
# ############################################## BYTECODE TRANSLATOR ################################################ #
# ################################################################################################################### #

import plugins
import ../allocator
import vmops

include "types.nim"
include "scopes.nim"
include "generator.nim"

proc generateBytecode(n: var NifCursor): NifBuilder =
  var ctx = CodeGenCtx(
    cache: newTypeCache(),
    scopes: @[ScopeNode(id: 0, parent: -1, variables: newTrie())]
  )
  var source = n
  ctx.cache.collectTypeDecls(source)
  ctx.cache.propagateRefs()
  ctx.cache.computeLayouts()
  ctx.collectVarData(0, source)

  var code = CBytecode(
    allocator: newVramAllocator(),
    procTable: initTable[string, int]()
  )
  code.predeclareFunctions(source)
  var statements = source
  statements.loopInto:
    if statements.stmtKind in {ProcS, FuncS}:
      ctx.genFunc(code, statements)
    elif statements.stmtKind in {StmtsS, BlockS}:
      ctx.genStmt(code, 0, statements)
    statements.skip()
  
  # The plugin API currently returns a NIF tree. Keep the source unchanged
  # while the generated program is consumed by the forthcoming backend API.
  result = createTree()
  result.takeTree(n)

proc noTransform(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)

var inp = loadPluginInput()
var c = inp
saveTree generateBytecode(c)
