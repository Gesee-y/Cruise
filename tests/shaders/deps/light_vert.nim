{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode
import ../../../src/CVM/default_type

translateToBytecode()
setShaderName("light_vert")
setShaderType(Mat4, "mat4f")
setShaderType(Vec2, "vec2f")
setShaderType(Vec3, "vec3f")
setShaderType(Vec4, "vec4f")

var mvp {.uniform.}: Mat4 = Mat4()

proc main(gl_pos {.vertexOutput.}: out Vec4,
          aPos {.vertexInput.}: Vec3) =
  gl_pos = mvp * newVec4f(aPos, 1.0f)
