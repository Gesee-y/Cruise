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
var lightPos {.uniform.}: Vec3 = Vec3()
var viewPos {.uniform.}: Vec3 = Vec3()
var tex {.texture.}: Sampler2D = Sampler2D()

proc main(uv {.fragmentInput.}: Vec2,
          normal {.fragmentInput.}: Vec3,
          fragPos {.fragmentInput.}: Vec3,
          fragColor {.fragmentOutput.}: var Vec4) =
  # Ambient
  let ambientStrength = 0.15f
  let ambient = lightColor * ambientStrength

  # Diffuse
  let norm = normalize(normal)
  let lightDir = normalize(lightPos - fragPos)
  let diff = max(dot(norm, lightDir), 0.0f)
  let diffuse = lightColor * diff

  # Specular
  let specularStrength = 0.5f
  let viewDir = normalize(viewPos - fragPos)
  let reflectDir = reflect(-lightDir, norm)
  let spec = pow(max(dot(viewDir, reflectDir), 0.0f), 32.0f)
  let specular = lightColor * (specularStrength * spec)

  let lighting = ambient + diffuse + specular
  let col = lighting * objectColor
  fragColor = newVec4f(col, 1.0f)
