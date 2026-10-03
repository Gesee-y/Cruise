import std/syncio
import ../src/CVM/bytecode

translateToBytecode()

proc testSimple =
  var a = 10
  var b = 20
  var c = a + b
  var d = c * 2
  echo d

proc testSimpleArg(x: int) =
  var a = x + 10
  var b = x + 20
  var c = a + b
  var d = c * 2
  echo d

testSimple()
