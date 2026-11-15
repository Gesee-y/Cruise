{.feature: "assumeSync".}

import std/syncio
import ../../src/CVM/bytecode

type Vec2 = object
  x, y: float32

proc `*`(a, b: Vec2): Vec2 = a
proc `+`(a, b: Vec2): Vec2 = a

translateToBytecode()
setShaderName("test_fma_opt_probe")
setShaderType(Vec2, "vec2f")

var length {.uniform.}: int = 0

proc main(gid {.globalIndex.}: int, a {.ssbo.}: seq[float32],
          b {.ssbo.}: seq[float32], c {.ssbo.}: var seq[float32],
          va {.ssbo.}: seq[Vec2], vb {.ssbo.}: seq[Vec2],
          vc {.ssbo.}: var seq[Vec2]) =
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
    vc[gid] = va[gid] * vb[gid] + va[gid]

proc integerFmaProbe =
  var a = 2
  var b = 3
  var c = 4
  var result = a * b + c
