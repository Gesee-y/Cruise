import std/syncio
import ../src/CVM/bytecode

translateToBytecode()

proc testForLoop =
  var sum = 0
  for i in 0 ..< 10:
    sum = sum + i
  echo sum

proc testForLoopInclusive =
  var prod = 1
  for i in 1 .. 5:
    prod = prod * i
  echo prod

testForLoop()
testForLoopInclusive()
