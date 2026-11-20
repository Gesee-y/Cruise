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
include "backends/common.nim"
include "backends/glsl33.nim"
include "backends/opencl.nim"

proc writeBackendSource(path, source: string) =
  var f = open(path, fmWrite)
  var sourceBuffer = newSeq[char](source.len)
  for i, ch in source:
    sourceBuffer[i] = ch
  if sourceBuffer.len > 0:
    discard writeBuffer(f, addr sourceBuffer[0], sourceBuffer.len)
  close(f)

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

  # Both text backends consume the same semantically checked, rewritten CIR
  # tree as the bytecode generator.
  var glslSource = ""
  var openclSource = ""
  if tmGLSL33 in cache.transpilation:
    glslSource = emitGLSL33(irCode, cache)
  if tmOpenCL in cache.transpilation:
    openclSource = emitOpenCL(irCode, cache)
  if irGenErrors.len > 0:
    result.withTree StmtsS, n.info:
      flushIRErrors(result)
    return
  if tmGLSL33 in cache.transpilation:
    writeBackendSource(cache.programName & ".glsl", glslSource)
  if tmOpenCL in cache.transpilation:
    writeBackendSource(cache.programName & ".cl", openclSource)

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
