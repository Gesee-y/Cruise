{.feature: "assumeSync".}

import std/syncio
import ../../src/CVM/bytecode

translateToBytecode()
setShaderName("test_user_functions")

proc doubleAndIncrement(value: int32): int32 =
  return addOne(value * 2)

proc addOne(value: int32): int32 =
  return value + 1

proc main(resultBuf {.ssbo.}: var seq[int32]) =
  resultBuf[0] = doubleAndIncrement(20)
