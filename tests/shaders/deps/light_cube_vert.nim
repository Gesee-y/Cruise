{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode
import default_type

translateToBytecode()
setShaderName("light_cube_vert")
setShaderType(Mat4, "mat4f")
setShaderType(Vec2, "vec2f")
setShaderType(Vec3, "vec3f")
setShaderType(Vec4, "vec4f")

var mvp {.uniform.}: Mat4 = Mat4()
var model {.uniform.}: Mat4 = Mat4()

proc main(gl_pos {.vertexOutput.}: out Vec4,
          uv {.vertexVarying.}: var Vec2,
          normal {.vertexVarying.}: var Vec3,
          fragPos {.vertexVarying.}: var Vec3,
          aPos {.vertexInput.}: Vec3,
          aNormal {.vertexInput.}: Vec3,
          aTexCoord {.vertexInput.}: Vec2) =
  let pos = newVec4f(aPos, 1.0f)
  let fPos = model * pos
  uv = aTexCoord
  normal = newVec3f(model * newVec4f(aNormal, 0.0f))
  fragPos = newVec3f(fPos)
  gl_pos = mvp * pos
