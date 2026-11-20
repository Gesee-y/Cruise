{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode
import ../../../src/CVM/default_type

translateToBytecode()
translateToGLSL33()
setShaderName("cube_frag")
setShaderType(Vec2, "vec2f")
setShaderType(Vec4, "vec4f")
setShaderType(Vec3, "vec3f")
setShaderType(Sampler2D, "sampler2D")

var timer {.uniform.}: float32 = float32(0.0)
var tex {.texture.}: Sampler2D = Sampler2D()

proc main(uv {.fragmentInput.}: Vec2,
          fragColor {.fragmentOutput.}: var Vec4) =
  fragColor = sample(tex, uv)
