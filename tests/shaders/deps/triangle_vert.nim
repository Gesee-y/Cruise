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

proc main(gl_pos {.vertexOutput.}: out Vec4, aPos: Vec3 {.VertexInput.}) =