{.feature: "assumeSync".}

import std/syncio
import ../../src/CVM/bytecode

translateToBytecode()
setShaderName("test_vector_add")

var length {.uniform.} : int = 0

proc main(gid {.globalIndex.} : int, a {.ssbo.} : seq[int], b {.ssbo.} : seq[int], c {.ssbo.} : var seq[int]) =
  if gid < length:
    c[gid] = a[gid] + b[gid]
