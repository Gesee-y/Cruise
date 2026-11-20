{.feature: "assumeSync".}

# ################################################################################################################### #
# ############################################## BYTECODE TRANSLATOR ################################################ #
# ################################################################################################################### #

import plugins
import std/[syncio, tables, strutils]

type
  TranspilationMode = enum
    tmGLSL33
    tmOpenCL

include "errors.nim"
include "types.nim"
include "allocator.nim"
include "vmops.nim"
include "ir.nim"
include "sem.nim"
include "rewriter.nim"
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

  var re = newRewriterEngine()
  re.rewritePass(irCode, cache)

  var ctx = CodeGenCtx(
    cache: cache,
    code: CBytecode(
      allocator: newVramAllocator(),
      procTable: initTable[string, int](),
      callToPatch: initTable[string, seq[CallPatch]](),
      frameSizes: initTable[string, int](),
      data: @[]
    )
  )

  ctx.predeclareFunctions(irCode)
  ctx.emitInst(vocJmp, 0, 0)
  ctx.emitWord(cast[uint32](-1i32))
  ctx.genStmt(irCode)
  if ctx.entryPoint > 0: 
    ctx.code.data[1] = uint32(ctx.entryPoint) 
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

var inp = loadPluginInput()
var c = inp
saveTree generateBytecode(c)
