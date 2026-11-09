{.feature: "assumeSync".}

import std/[syncio, math]
import ../../src/CVM/bytecode

translateToBytecode()
setShaderName("test_builtin")

proc main(gid {.globalIndex.}: int, a {.ssbo.}: seq[float32],
          b {.ssbo.}: seq[float32], c {.ssbo.}: var seq[float32],
          ia {.ssbo.}: seq[int], ib {.ssbo.}: seq[int],
          ic {.ssbo.}: var seq[int]) =
  var x = a[gid]
  var y = b[gid]
  c[gid] = abs(x) + min(x, y) + max(x, y) + sqrt(abs(y)) +
           (float32(1) / sqrt(abs(x)))
  var ix = ia[gid]
  var iy = ib[gid]
  ic[gid] = abs(ix) + min(ix, iy) + max(ix, iy)
