{.feature: "assumeSync".}

import std/[syncio, math]
import ../../../src/CVM/bytecode
import default_type

translateToBytecode()
setShaderName("light_cube_frag")
setShaderType(Vec2, "vec2f")
setShaderType(Vec4, "vec4f")
setShaderType(Vec3, "vec3f")
setShaderType(Sampler2D, "sampler2D")

var objectColor {.uniform.}: Vec3 = Vec3()
var lightColor {.uniform.}: Vec3 = Vec3()
var tex {.texture.}: Sampler2D = Sampler2D()

proc main(uv {.fragmentInput.}: Vec2,
          fragColor {.fragmentOutput.}: var Vec4) =
  let col = objectColor * lightColor
  fragColor = Vec4(x: col.x, y: col.y, z: col.z, w: 1.0f)
