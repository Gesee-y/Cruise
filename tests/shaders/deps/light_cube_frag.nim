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
var accentColor {.uniform.}: Vec3 = Vec3()
var time {.uniform.}: float32 = 0.0f
var tex {.texture.}: Sampler2D = Sampler2D()

proc main(uv {.fragmentInput.}: Vec2,
          normal {.fragmentInput.}: Vec3,
          fragPos {.fragmentInput.}: Vec3,
          fragColor {.fragmentOutput.}: var Vec4) =
  let n = normalize(normal)
  let lightDir = normalize(lightPos - fragPos)
  let viewDir = normalize(viewPos - fragPos)
  let halfDir = normalize(lightDir + viewDir)

  # A soft toon ramp layered over diffuse lighting.
  let diffuse = max(dot(n, lightDir), 0.0f)
  let toon = smoothstep(0.12f, 0.76f, diffuse)
  let base = lerp(objectColor * 0.12f, objectColor, toon)

  # Metallic highlight and a camera-facing rim, animated with a traveling pulse.
  let specular = pow(max(dot(n, halfDir), 0.0f), 36.0f)
  let rim = 1.0f - max(dot(n, viewDir), 0.0f)
  let rimMask = smoothstep(0.18f, 0.82f, rim)
  let pulse = 0.5f + 0.5f * sin(time * 2.4f + dot(fragPos, fragPos) * 2.0f)

  # Procedural etched bands: floor/fract/step make a small moving grid pattern.
  let gridX = abs(fract(fragPos.x * 5.0f + time * 0.18f) - 0.5f)
  let gridY = abs(fract(fragPos.y * 5.0f) - 0.5f)
  let grid = 1.0f - smoothstep(0.025f, 0.085f, min(gridX, gridY))
  let bandIndex = floor((fragPos.z + time * 0.25f) * 3.0f)
  let stripe = step(0.25f, fract(bandIndex * 0.5f))
  let etched = grid * (0.25f + 0.75f * stripe)

  let material = mix(base, accentColor, clamp(rimMask * 0.8f, 0.0f, 1.0f))
  let lit = material * (0.25f + 0.75f * toon)
  let glint = lightColor * (specular * 0.65f)
  let rimGlow = accentColor * (rimMask * (0.25f + pulse * 0.65f))
  let patternGlow = accentColor * (etched * rimMask * 0.22f)
  let col = clamp(lit + glint + rimGlow + patternGlow, 0.0f, 1.0f)
  fragColor = newVec4f(col, 1.0f)
