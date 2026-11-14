{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode

translateToBytecode()
setShaderName("triangle_frag")

type
  Vec3 = object
    x, y, z: float32
  Vec4 = object
    x, y, z, w: float32
setShaderType(Vec4, "vec4f")
setShaderType(Vec3, "vec3f")

var timer {.uniform.}: float32 = float32(0.0)

proc main(color {.fragmentInput.}: Vec3,
          fragColor {.fragmentOutput.}: var Vec4) =
  fragColor = Vec4(
    x: color.x,
    y: color.y,
    z: color.z,
    w: float32(1.0))
