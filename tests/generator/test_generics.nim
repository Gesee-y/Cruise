import std/[syncio, math/common]
import ../../src/CVM/bytecode

translateToBytecode()

type
  Obj[T: SomeInteger] = object
    x: T

proc testGenArg[T: SomeInteger and Arithmetic](o: Obj[T]) =
  var x = o.x
  var a = x + 10
  var b = x + 20
  var c = a + b
  var d = c * 2

proc main() =
  testGenArg(Obj[int](x: 0))
  