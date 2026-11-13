{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode

translateToBytecode()
setShaderName("triangle_vert")
type
  Vec3 = object
    x, y, z: float32
  Vec4 = object
    x, y, z, w: float32
setShaderType(Vec3, "vec3f")
setShaderType(Vec4, "vec4f")

proc main(gl_pos {.vertexOutput.}: out Vec4,
          color {.vertexOutput.}: var Vec3,
          aPos {.vertexInput.}: Vec3) =
  gl_pos = Vec4(x: aPos.x, y: aPos.y, z: aPos.z, w: float32(1.0))
  color = Vec3(
    x: aPos.x * float32(0.5) + float32(0.5),
    y: aPos.y * float32(0.5) + float32(0.5),
    z: float32(0.85))
