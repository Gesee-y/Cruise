{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode
import ../../../src/CVM/default_type

translateToBytecode()
setShaderName("triangle_vert")
setShaderType(Vec2, "vec2f")
setShaderType(Vec3, "vec3f")
setShaderType(Vec4, "vec4f")

var scale {.uniform.}: float32 = float32(0.0)
var translateX {.uniform.}: float32 = float32(0.0)

proc main(gl_pos {.vertexOutput.}: out Vec4,
          uv {.vertexVarying.}: var Vec2,
          aPos {.vertexInput.}: Vec3,
          aTexCoord {.vertexInput.}: Vec2) =
  gl_pos = Vec4(x: aPos.x * scale + translateX,
                y: aPos.y * scale,
                z: aPos.z,
                w: float32(1.0))
  uv = Vec2(
    x: aTexCoord.x,
    y: aTexCoord.y)
