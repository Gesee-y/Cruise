{.feature: "assumeSync".}

import std/syncio
import ../../src/CVM/bytecode

translateToBytecode()
setShaderName("test_vector_add")

var length {.uniform.} : int = 0

proc main(gid {.globalIndex.} : int, a {.ssbo.} : seq[float32], b {.ssbo.} : seq[float32], c {.ssbo.} : var seq[float32]) =
  if gid < length:
    c[gid] = a[gid] + b[gid]
