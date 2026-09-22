# ################################################################################################################### #
# ############################################## BYTECODE TRANSLATOR ################################################ #
# ################################################################################################################### #

import plugins
import std/[syncio, tables]

include "types.nim"
include "../allocator.nim"
include "vmops.nim"
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
    procTable: initTable[string, int](),
    data: @[]
  )
  code.predeclareFunctions(source)
  var statements = source
  statements.loopInto:
    if statements.stmtKind in {ProcS, FuncS}:
      ctx.genFunc(code, statements)
    #elif statements.stmtKind in {StmtsS, BlockS}:
    #  ctx.genStmt(code, 0, statements)
    statements.skip()

  echo "["
  for i in 0..<code.data.len-1:
    echo code.data[i], ", "

  if code.data.len > 0: echo code.data[^1]
  echo "]"
  
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
