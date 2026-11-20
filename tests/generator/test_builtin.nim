{.feature: "assumeSync".}

import std/[syncio, math]
import ../../src/CVM/bytecode

translateToBytecode()
setShaderName("test_builtin")

proc main(gid {.globalIndex.}: int, a {.ssbo.}: seq[float32],
          b {.ssbo.}: seq[float32], c {.ssbo.}: var seq[float32],
          ia {.ssbo.}: seq[int32], ib {.ssbo.}: seq[int32],
          ic {.ssbo.}: var seq[int32]) =
  var x = a[gid]
  var y = b[gid]
  var addf = x + float32(2)
  var subf = y - float32(1)
  var mulf = x * float32(2)
  var oneLeft = float32(1) * y
  var oneRight = x * float32(1)
  c[gid] = abs(x) + min(x, y) + max(x, y) + sqrt(abs(y)) +
           (float32(1) / sqrt(abs(x))) + (x / sqrt(abs(y))) +
           addf + subf + mulf + oneLeft + oneRight + sin(x) + cos(y)
  var ix = ia[gid]
  var iy = ib[gid]
  var addi = ix + 3
  var subi = iy - 2
  var muli = ix * 2
  var oneLeftInt = 1 * iy
  var oneRightInt = ix * 1
  ic[gid] = abs(ix) + min(ix, iy) + max(ix, iy) + addi + subi + muli + oneLeftInt + oneRightInt
