# Cruise Shader VM (CVM/CSVM/SVM, whatever, no one's care :p)

Cruise VM is an implementation of a **Virtual Machine** on top of **Nimony** or **Nim 3**, whethever tf you want to call it.
So what it does is use compiler plugins to turn a module into bytecode.

It also has a few restriction:

- Can't use `ref`
- Can only use builtin functions or those defined in the module
- No recursion
- Limited memory and stack size (255 bytes of memory, 64 bytes stack)
- No top level expression
- Needs an entry point

So why should we care about such a restricted VM ?
Because it's made entirely to run on GPU!

## Quick start

In the program to run on the VM, let's name it `mainKernel.nim`:

```nim
import CVM/bytecode

translateToBytecode()
setShaderName("myShader")

var N {.uniform.}: int = 0

proc main(i {.globalIndex.}: int, a {.ssbo.}: seq[int], b {.ssbo.}: seq[int], c {.ssbo.}: var seq[int]):
  if i < N:
    c[i] = a[i] + b[i]
```

This will generate a `myShader.cbc` file, which contains the bytecode of the program.

To also emit source from the same rewritten IR, add `translateToGLSL33()` and/or
`translateToOpenCL()` beside `translateToBytecode()`. The plugin writes
`myShader.glsl` and `myShader.cl`; selecting either backend does not replace the
bytecode output.

Then in the program running it:

```nim
import CVM/vms/cpu

proc main:
  let data = readBytecode("path/to/myShader.cbc")
  let a = @[1, 2, 3]
  let b = @[4, 5, 6]
  var c = newSeq[int](3)
  var obj = initVmObjectConfig(data)
  obj.setBuffer(0, addr a[0])
  obj.setBuffer(1, addr b[0])
  obj.setBuffer(2, addr c[0])
  obj.setUniform(0, 3)
  var vm = initCpuVm()

  vm.configure(obj) # Update static data in the VM
  vm.runVm(obj) # Execute the bytecode
```

## Examples

### 36 Cubes in space

<details>
<summary> See shaders </summary>
Vertex shader:

```nim
{.feature: "assumeSync".}

import std/[syncio, math]
import CVM/[bytecode, default_type]

translateToBytecode()
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
```

Fragment shader:

```nim
{.feature: "assumeSync".}

import std/[syncio, math]
import CVM/[bytecode, default_type]

translateToBytecode()
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
```

</details>
<video src="https://codeberg.org/Gesee/CVM/raw/commit/cad21384191b02602a87338b45c737929b7d78d7/renders/r3.mp4" controls width="100%"></video>

### Cyber cube + lightning and with a cute pichu

<details>
<summary> See shaders </summary>
Vertex shader:

```nim
{.feature: "assumeSync".}

import std/[syncio, math]
import CVM/[bytecode, default_type]

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
```

Light Vertex shader:

```nim
{.feature: "assumeSync".}

import std/[syncio, math]
import CVM/[bytecode, default_type]

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
```

Object Fragment shader:

```nim
{.feature: "assumeSync".}

import std/[syncio, math]
import CVM/[bytecode, default_type]

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
  let viewDir = normalize(viewPos - fragPos)
  let n = normalize(faceforward(normal, -viewDir, normal))
  let lightDir = normalize(lightPos - fragPos)
  let lightAttenuation = 1.0f / (1.0f + distance(lightPos, fragPos) * 0.12f)
  let halfDir = normalize(lightDir + viewDir)

  # A soft toon ramp layered over diffuse lighting.
  let diffuse = max(dot(n, lightDir), 0.0f)
  let toon = smoothstep(0.12f, 0.76f, diffuse)
  let toonBand = clamp(round(toon * 3.0f) / 3.0f, 0.0f, 1.0f)
  let base = lerp(objectColor * 0.12f, objectColor, toon)

  # Metallic highlight and a camera-facing rim, animated with a traveling pulse.
  let specular = pow(max(dot(n, halfDir), 0.0f), 36.0f)
  let rim = 1.0f - max(dot(n, viewDir), 0.0f)
  let rimMask = smoothstep(0.18f, 0.82f, 1.0f - exp(-rim * 4.0f))
  let angle = atan(fragPos.y, fragPos.x)
  let sweep = `mod`(angle + time * 0.4f, 6.283185f)
  let pulse = 0.5f + 0.5f * sin(radians(time * 138.0f) + sweep + dot(fragPos, fragPos) * 2.0f)
  let tangentEnergy = length(cross(n, lightDir))
  let tangentColor = abs(cross(n, lightDir)) * 0.08f
  let refractedDir = refract(-viewDir, n, 0.82f)
  let refractedLight = max(dot(refractedDir, lightDir), 0.0f)

  # Procedural etched bands: floor/fract/step make a small moving grid pattern.
  let gridX = abs(fract(fragPos.x * 5.0f + time * 0.18f) - 0.5f)
  let gridY = abs(fract(fragPos.y * 5.0f) - 0.5f)
  let grid = 1.0f - smoothstep(0.025f, 0.085f, min(gridX, gridY))
  let bandIndex = floor((fragPos.z + time * 0.25f) * 3.0f)
  let stripe = step(0.25f, fract(bandIndex * 0.5f))
  let etched = grid * (0.25f + 0.75f * stripe)

  let material = mix(base, accentColor, clamp(rimMask * 0.8f, 0.0f, 1.0f))
  let texel = sampleLod(tex, uv, 0.0f)
  let texColor = newVec3f(texel)
  let textured = mix(material, texColor, 0.18f)
  let lit = textured * ((0.25f + 0.75f * toonBand) * lightAttenuation)
  let specularGlint = lightColor * (specular * 0.65f)
  let refractedGlint = min(lightColor, accentColor + 0.25f) *
                       (refractedLight * tangentEnergy * 0.12f)
  let glint = max(specularGlint, refractedGlint)
  let rimGlow = accentColor * (rimMask * (0.25f + pulse * 0.65f))
  let patternGlow = accentColor * (etched * rimMask * 0.22f)
  let col = clamp(lit + glint + rimGlow + patternGlow + tangentColor, 0.0f, 1.0f)
  fragColor = newVec4f(col, 1.0f)

```

Light Fragment shader:

```nim
{.feature: "assumeSync".}

import std/[syncio, math]
import CVM/[bytecode, default_type]

translateToBytecode()
setShaderName("light_frag")
setShaderType(Vec2, "vec2f")
setShaderType(Vec4, "vec4f")
setShaderType(Vec3, "vec3f")
setShaderType(Sampler2D, "sampler2D")

var timer {.uniform.}: float32 = float32(0.0)
var tex {.texture.}: Sampler2D = Sampler2D()

proc main(uv {.fragmentInput.}: Vec2,
          fragColor {.fragmentOutput.}: var Vec4) =
  fragColor = newVec4f(1.0f, 1.0f, 1.0f, 1.0f)
```

</details>
<video src="https://codeberg.org/Gesee/CVM/raw/commit/cad21384191b02602a87338b45c737929b7d78d7/renders/r2.mp4" controls width="100%"></video>
(Both the light and the object render use only the VM as shader and the bytecode is passed as uniform)

### [Plastic crate from poly haven with PBR](https://polyhaven.com/a/plastic_crate_02)

<details>
<summary> See shaders </summary>
Vertex shader:

```nim
{.feature: "assumeSync".}

import std/[syncio, math]
import CVM/[bytecode, default_type]

translateToBytecode()
setShaderName("crate_vert")
setShaderType(Mat4, "mat4f")
setShaderType(Vec2, "vec2f")
setShaderType(Vec3, "vec3f")
setShaderType(Vec4, "vec4f")

var mvp {.uniform.}: Mat4 = Mat4()
var model {.uniform.}: Mat4 = Mat4()

proc main(glPosition {.vertexOutput.}: out Vec4,
          uv {.vertexVarying.}: var Vec2,
          worldNormal {.vertexVarying.}: var Vec3,
          worldTangent {.vertexVarying.}: var Vec4,
          worldPosition {.vertexVarying.}: var Vec3,
          position {.vertexInput.}: Vec3,
          normal {.vertexInput.}: Vec3,
          texCoord {.vertexInput.}: Vec2,
          tangent {.vertexInput.}: Vec4) =
  let localPosition = newVec4f(position, 1.0f)
  let transformedPosition = model * localPosition
  let transformedNormal = model * newVec4f(normal, 0.0f)
  let transformedTangent = model * newVec4f(newVec3f(tangent), 0.0f)
  uv = texCoord
  worldNormal = newVec3f(transformedNormal)
  worldTangent = newVec4f(newVec3f(transformedTangent), tangent.w)
  worldPosition = newVec3f(transformedPosition)
  glPosition = mvp * localPosition
```

Fragment shader:

```nim
{.feature: "assumeSync".}

import std/[syncio, math]
import CVM/[bytecode, default_type]

translateToBytecode()
setShaderName("crate_frag")
setShaderType(Vec2, "vec2f")
setShaderType(Vec3, "vec3f")
setShaderType(Vec4, "vec4f")
setShaderType(Sampler2D, "sampler2D")

var baseColorFactor {.uniform.}: Vec3 = Vec3()
var lightPosition {.uniform.}: Vec3 = Vec3()
var viewPosition {.uniform.}: Vec3 = Vec3()
var lightColor {.uniform.}: Vec3 = Vec3()
var ambientStrength {.uniform.}: float32 = 0.0f
var metallicFactor {.uniform.}: float32 = 0.0f
var roughnessFactor {.uniform.}: float32 = 1.0f
var alphaFactor {.uniform.}: float32 = 1.0f
var baseColorTexture {.texture.}: Sampler2D = Sampler2D()
var normalTexture {.texture.}: Sampler2D = Sampler2D()
var armTexture {.texture.}: Sampler2D = Sampler2D()
var opacityTexture {.texture.}: Sampler2D = Sampler2D()

proc main(uv {.fragmentInput.}: Vec2,
          worldNormal {.fragmentInput.}: Vec3,
          worldTangent {.fragmentInput.}: Vec4,
          worldPosition {.fragmentInput.}: Vec3,
          fragmentColor {.fragmentOutput.}: var Vec4) =
  let baseSample = sampleLod(baseColorTexture, uv, 0.0f)
  let normalSample = sampleLod(normalTexture, uv, 0.0f)
  let armSample = sampleLod(armTexture, uv, 0.0f)
  let opacitySample = sampleLod(opacityTexture, uv, 0.0f)

  let base = newVec3f(baseSample) * baseColorFactor
  let n = normalize(worldNormal)
  let tangentValue = newVec3f(worldTangent)
  let t = normalize(tangentValue - n * dot(n, tangentValue))
  let b = cross(n, t) * worldTangent.w
  let tangentNormal = normalize(newVec3f(
    normalSample.x * 2.0f - 1.0f,
    normalSample.y * 2.0f - 1.0f,
    normalSample.z * 2.0f - 1.0f))
  let shadingNormal = normalize(t * tangentNormal.x +
                                b * tangentNormal.y +
                                n * tangentNormal.z)

  let lightVector = lightPosition - worldPosition
  let distanceSquared = dot(lightVector, lightVector)
  let lightDir = normalize(lightVector)
  let viewDir = normalize(viewPosition - worldPosition)
  let halfDir = normalize(lightDir + viewDir)
  let nDotL = max(dot(shadingNormal, lightDir), 0.0f)
  let roughness = clamp(armSample.y * roughnessFactor, 0.08f, 1.0f)
  let metallic = clamp(armSample.z * metallicFactor, 0.0f, 1.0f)
  let ao = clamp(armSample.x, 0.15f, 1.0f)
  let f0 = mix(newVec3f(0.04f, 0.04f, 0.04f), base, metallic)
  let specularPower = mix(64.0f, 8.0f, roughness)
  let specular = f0 * pow(max(dot(shadingNormal, halfDir), 0.0f), specularPower)
  let diffuse = base * ((1.0f - metallic) * nDotL * 0.318309886f)
  let attenuation = 1.0f / (1.0f + distanceSquared * 0.12f)
  let direct = (diffuse + specular) * lightColor * attenuation
  let ambient = base * (ambientStrength * ao)
  let color = clamp(ambient + direct, 0.0f, 1.0f)
  let alpha = baseSample.w * opacitySample.x * alphaFactor
  fragmentColor = newVec4f(color, alpha)
```

</details>
<video src="https://codeberg.org/Gesee/CVM/raw/commit/cad21384191b02602a87338b45c737929b7d78d7/renders/r1.mp4" controls width="100%"></video>

> Note
> This project is **NOT** a renderer. It's a VM you integrate in your existing workflow.
> Not a drop in framework for you to start your dream game.
> This is made to integrate your project as a regular shader

## Why this ?

This project has been made for one big reason, getting rid of shader compilation stutters in game.
This was directly inspired by Dolphin's maintainers work on **ubershader**.

They already thought about a possible shader interpreter, but the cost of implementing it seemed to high for the rewards. Ubershader was like a simplified attempt (but nonetheless extremely complicated) at this.

Instead of a real interpretation, every shader was just combine into one titan shader that was compiled once and could run the game while the real shader were compiled in the background.

To make it possible it took an incredible amount of work and of course, is no solution you can recommend to anyone who doesn't know tf they are doing.
Ubershaders scale poorly, it worked for dolphin because the gamecube had a finite (and reasonable) amount of shaders and pipelines, but that might not always be the case.

They also incurs a huge pressure on GPU register, making them way slow to run (added to being slow to compile)

So **CVM** is just my attempt at making the idea of shader interpreter true.
Really being able to interpret shader on GPU without the gimmick that is the ubershader. 

Shaders are written in Nim, translated to bytecode and executed in the VM, as simple as that.

## Why Nim ?

Writing a VM from scratch is pure hell. So instead of trying to parse shader code I just try to use a preexisting language infrastructure.
However, I needed a langage that easily offer access to it's internal representation and allow to process whole modules (or functions).

Most languages don't allow you to do that in a stable way because they don't really offer any API contract over the compiler's internals.
So came Nim (Nimony/Nim3).

With his compiler plugins (which act as user defined compiler pass), it's way easier to directly generate bytecode from a correct representation.
No more need to check semantic correctness, only have to check whether an operation is allowed on GPU or not.

This way, I got the whole front-end part of the VM done, plus there are tons of transpiler project for Nim -> shaderLang. So it made thing even easier!
Being able to use Nim for everything without writing a single line of shader code!

## Why use this ?

- Execute shader without compilation time (meaning faster load time).
- Easy hot-reload (just reread the bytecode) making dev time faster.
- Can handle your graphic program while the real shader compile in the background
- Has a constant pressure on register (since the VM is the only program)
- Thread divergence only happens if the original code would have diverged because each thread runs the same bytecode
- VM memory efficiently fits in GPU cache

## Cons

- Slower than a native GPU program.
- Still ongoing (handling more GPU construct, run on more shader langs, etc etc)
