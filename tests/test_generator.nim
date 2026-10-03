import std/syncio
import ../src/CVM/bytecode

translateToBytecode()

proc testSimple =
  var a = 10
  var b = 20
  var c = a + b
  var d = c * 2
  echo d

proc testSimpleIf =
  var a = 10
  var b = 20
  var c = a + b
  var d = c * 2
  
  if d > 0: 
    echo d
  else:
    echo d - 3

testSimple()
