{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode
import ../../../src/CVM/default_type

translateToBytecode()
translateToGLSL33()
setShaderName("cube_vert")
setShaderType(Mat4, "mat4f")
setShaderType(Vec2, "vec2f")
setShaderType(Vec3, "vec3f")
setShaderType(Vec4, "vec4f")

var transform {.uniform.}: Mat4 = Mat4()

proc main(gl_pos {.vertexOutput.}: out Vec4,
          uv {.vertexVarying.}: var Vec2,
          aPos {.vertexInput.}: Vec3,
          aTexCoord {.vertexInput.}: Vec2) =
  gl_pos = transform * Vec4(x: aPos.x, y: aPos.y, z: aPos.z, w: float32(1.0))
  uv = Vec2(
    x: aTexCoord.x,
    y: aTexCoord.y)
