{.feature: "assumeSync".}

import std/[syncio]
import ../../../src/CVM/bytecode

translateToBytecode()
setShaderName("triangle_frag")

type
  Vec4 = object
    x, y, z, w: float32
setShaderType(Vec4, "vec4f")

proc main(color {.fragmentInput.}: float32,
          fragColor {.fragmentOutput.}: var Vec4) =
  fragColor = Vec4(
    x: color * float32(0.5) + float32(0.5),
    y: float32(0.3),
    z: float32(0.85),
    w: float32(1.0))
