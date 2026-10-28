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
include "ir.nim"

proc generateBytecode(n: var NifCursor): NifBuilder =
  var ctx = CodeGenCtx(
    cache: newTypeCache(),
    scopes: @[ScopeNode(id: 0, parent: -1, variables: newTrie())]
  )
  var source = n
  let irCode = toIR(source)
  echo renderIR(irCode)
  ctx.cache.collectTypeDecls(source)
  ctx.cache.propagateRefs()
  ctx.cache.computeLayouts()
  ctx.collectVarData(0, source)

  var code = CBytecode(
    allocator: newVramAllocator(),
    procTable: initTable[string, int](),
    callToPatch: initTable[string, seq[int]](),
    data: @[]
  )
  code.predeclareFunctions(source)
  var statements = source
  statements.loopInto:
    if statements.stmtKind in {ProcS, FuncS}:
      ctx.genFunc(code, statements)
    elif statements.stmtKind in {StmtsS, BlockS, ScopeS}:
      ctx.genStmt(code, 0, statements)
    statements.skip()

  #var byteData = newSeq[byte](code.data.len*sizeof(uint32))
  #copyMem(addr byteData[0], addr code.data[0], code.data.len*sizeof(uint32))

  var f = open("generated.cbc", fmWrite)
  if code.data.len > 0:
    discard writeBuffer(f, addr code.data[0], code.data.len*sizeof(uint32))
  close(f)
  
  # The plugin API currently returns a NIF tree. Keep the source unchanged
  # while the generated program is consumed by the forthcoming backend API.
  result = createTree()
  result.takeTree(n)
  echo renderTree(result)

proc noTransform(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)

var inp = loadPluginInput()
var c = inp
saveTree generateBytecode(c)
