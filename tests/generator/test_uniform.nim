import std/syncio
import ../../src/CVM/bytecode

translateToBytecode()

var x {.uniform.} : int = 0

proc main(x {.globalIndex.} : int, y {.ssbo.} : seq[int]) =
  var a = x + y[0]
  var b = x + y[a]
  var c = a + b
  var d = c * 2