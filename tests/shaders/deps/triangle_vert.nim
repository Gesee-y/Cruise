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

var scale {.uniform.}: float32 = float32(0.0)
var translateX {.uniform.}: float32 = float32(0.0)

proc main(gl_pos {.vertexOutput.}: out Vec4,
          color {.vertexVarying.}: var Vec3,
          aPos {.vertexInput.}: Vec3,
          aColor {.vertexInput.}: Vec3) =
  gl_pos = Vec4(x: aPos.x * scale + translateX,
                y: aPos.y * scale,
                z: aPos.z,
                w: float32(1.0))
  color = Vec3(
    x: aColor.x,
    y: aColor.y,
    z: aColor.z)
