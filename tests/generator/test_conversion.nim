{.feature: "assumeSync".}

import std/syncio
import ../../src/CVM/bytecode

translateToBytecode()
setShaderName("test_conversion")

proc main(gid {.globalIndex.}: int,
          input {.ssbo.}: seq[int32],
          output {.ssbo.}: var seq[float32]) =
  output[gid] = float32(input[gid]) + float32(1) / 2
