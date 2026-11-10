{.feature: "assumeSync".}

import std/syncio
import ../../src/CVM/bytecode

translateToBytecode()
setShaderName("test_fma_opt_probe")

var length {.uniform.}: int = 0

proc main(gid {.globalIndex.}: int, a {.ssbo.}: seq[float32],
          b {.ssbo.}: seq[float32], c {.ssbo.}: var seq[float32]) =
  if gid < length:
    var lhs = a[gid]
    var rhs = b[gid]
    var fma = lhs * rhs + lhs
    var commutedFma = lhs + rhs * lhs
    var addNeg = lhs + (-rhs)
    var subNeg = lhs - (-rhs)
    var leftNeg = (-lhs) + rhs
    var doubleNeg = -(-lhs)
    c[gid] = fma + commutedFma + addNeg + subNeg + leftNeg + doubleNeg

proc integerFmaProbe =
  var a = 2
  var b = 3
  var c = 4
  var result = a * b + c
