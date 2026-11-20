import std/syncio
import ../../src/CVM/bytecode

translateToBytecode()
setShaderName("test_obj_and_loops")

type
  Vec3 = object
    x: int
    y: int
    z: int

proc testObjConstr =
  var v = Vec3(x: 10, y: 20, z: 30)
  var z = v.z

proc testLoops =
  var a = 0
  while a < 10:
    a = a + 1
    if a == 5:
      continue
    if a == 8:
      break

  var sum = 0
  for i in 0 ..< 10:
    if i == 2:
      continue
    if i == 7:
      break
    sum = sum + i
