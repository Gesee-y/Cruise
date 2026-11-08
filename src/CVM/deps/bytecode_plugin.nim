{.feature: "assumeSync".}

# ################################################################################################################### #
# ############################################## BYTECODE TRANSLATOR ################################################ #
# ################################################################################################################### #

import plugins
import std/[syncio, tables, strutils]

include "errors.nim"
include "types.nim"
include "../allocator.nim"
include "vmops.nim"
include "ir.nim"
include "sem.nim"
include "generator.nim"

proc getShaderName(n: NifCursor): string =
  result = "generated"

proc generateBytecode(n: var NifCursor): NifBuilder =
  var cache = newTypeCache()
  result = createTree()
  var source = n
  
  cache.collectTypeDecls(source)
  cache.propagateRefs()
  cache.computeLayouts()

  var irCode = toIR(source)
  var success = irGenErrors.len == 0
  if not success:
    result.withTree StmtsS, n.info:
      flushIRErrors(result)
    return

  cache.semPass(irCode)
  success = semErrors.len == 0
  if not success:
    result.withTree StmtsS, n.info:
      flushSemErrors(result)
    return

  var ctx = CodeGenCtx(
    cache: cache,
    code: CBytecode(
      allocator: newVramAllocator(),
      procTable: initTable[string, int](),
      callToPatch: initTable[string, seq[int]](),
      data: @[]
    )
  )

  ctx.predeclareFunctions(irCode)
  ctx.genStmt(irCode)
  # The plugin API currently returns a NIF tree. Keep the source unchanged
  # while the generated program is consumed by the forthcoming backend API.
  result.takeTree n
  
  if success:
    var f = open(cache.programName & ".cbc", fmWrite)
    if ctx.code.data.len > 0:
      discard writeBuffer(f, addr ctx.code.data[0], ctx.code.data.len * sizeof(uint32))
    close(f)

proc noTransform(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)
  echo renderTree(result)

var inp = loadPluginInput()
var c = inp
saveTree generateBytecode(c)
