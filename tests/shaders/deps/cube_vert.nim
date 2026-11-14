{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode
import default_type

translateToBytecode()
setShaderName("cube_vert")
setShaderType(Mat4, "mat4f")
setShaderType(Vec2, "vec2f")
setShaderType(Vec3, "vec3f")
setShaderType(Vec4, "vec4f")

var transform {.uniform.}: Mat4

proc main(gl_pos {.vertexOutput.}: out Vec4,
          uv {.vertexVarying.}: var Vec2,
          aPos {.vertexInput.}: Vec3,
          aTexCoord {.vertexInput.}: Vec2) =
  gl_pos = transform * aPos
  uv = Vec2(
    x: aTexCoord.x,
    y: aTexCoord.y)
