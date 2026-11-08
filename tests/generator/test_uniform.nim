{.feature: "assumeSync".}

import std/syncio
import ../../src/CVM/bytecode

translateToBytecode()

var u {.uniform.} : int = 0

proc main(x {.globalIndex.} : int, y {.ssbo.} : var seq[int]) =
  var a = u + y[0]
  var b = x + y[a]
  var c = a + b
  var d = c * 2
  y[0] = d