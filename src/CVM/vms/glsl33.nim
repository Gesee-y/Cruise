## OpenGL 3.3 wrapper for the GLSL bytecode VMs.
##
## The caller must create and make current an OpenGL 3.3 context, then call
## `loadExtensions()` from the OpenGL binding before constructing this object.
## Uniform offsets are word offsets, matching the shader generator's ABI.

import ../../../externalModule/opengl/src/opengl
import object_config
import ../bytecode

const
  GlslVmMaxBytecodeWords* = 512
  GlslVmUniformWords* = 256
  GlslVmMaxTextures* = 8
  GlslVmMaxVariants* = 16
  GlslVmInputBlockBytes* = 128
  GlslVmInputBlockWords* = GlslVmInputBlockBytes div sizeof(uint32)
  GlslVmMaxVertexInputs* = 32
  GlslVmInputOpcode = 63

type
  GlslVmVariantKey = object
    vertexFeatures, fragmentFeatures: uint16
    vertexRegisters, fragmentRegisters: uint8

  GlslVmVariant = object
    key: GlslVmVariantKey
    program: GLuint
    vertexBytecodeLocation, fragmentBytecodeLocation: GLint
    vertexUniformLocation, fragmentUniformLocation: GLint

  GlslVm* = object
    program*: GLuint
    variants: seq[GlslVmVariant]
    activeVariant: int
    textures: array[GlslVmMaxTextures, GLuint]
    textureActive: array[GlslVmMaxTextures, bool]
    inputWordCount: int
  VmShaderStage* = enum
    vssVertex
    vssFragment

include "glsl_vm_vertex.nimf"
include "glsl_vm_fragment.nimf"

proc assembleVMSource*(stage: VmShaderStage,
                       features: set[BytecodeFeature],
                       inputWordCount: int = GlslVmMaxVertexInputs): string =
  ## SCF-generated templates select chunks without parsing GLSL at runtime.
  case stage
  of vssVertex:
    result = generateVertexVmSource(features, inputWordCount)
  of vssFragment:
    result = generateFragmentVmSource(features)

proc destroy*(vm: var GlslVm)

proc shaderLog(shader: GLuint): string =
  var length: GLint
  glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr length)
  if length <= 1: return ""
  result = newString(length.int)
  glGetShaderInfoLog(shader, length, nil, cast[cstring](addr result[0]))

proc programLog(program: GLuint): string =
  var length: GLint
  glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr length)
  if length <= 1: return ""
  result = newString(length.int)
  glGetProgramInfoLog(program, length, nil, cast[cstring](addr result[0]))

proc compileShader(shaderType: GLenum, source, label: string): GLuint =
  result = glCreateShader(shaderType)
  assert result != 0, "glCreateShader failed for " & label
  var sourcePtr = source.cstring
  var sources = [sourcePtr]
  glShaderSource(result, 1, cast[cstringArray](addr sources[0]), nil)
  glCompileShader(result)
  var compiled: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, addr compiled)
  assert compiled != 0, label & " GLSL compilation failed:\n" & shaderLog(result)

proc linkProgram(vertexSource, fragmentSource: string): GLuint =
  let vertexShader = compileShader(GL_VERTEX_SHADER, vertexSource, "Vertex VM")
  let fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentSource, "Fragment VM")
  result = glCreateProgram()
  glAttachShader(result, vertexShader)
  glAttachShader(result, fragmentShader)
  glLinkProgram(result)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)
  var linked: GLint
  glGetProgramiv(result, GL_LINK_STATUS, addr linked)
  assert linked != 0, "GLSL VM program link failed:\n" & programLog(result)

proc bytecodeInputLayout(code: openArray[uint32]): seq[tuple[offset, size: int]] =
  assert code.len >= 2, "Vertex VM bytecode has no entry point"
  var pc = int(code[1])
  while pc >= 0 and pc < code.len:
    let word = code[pc]
    if int((word shr 16) and 255'u32) != GlslVmInputOpcode:
      break
    var size = int((word shr 24) and 255'u32)
    if size == 0: size = 1
    let offset = int(word and 255'u32)
    assert offset >= 0 and size >= 1 and offset + size <= GlslVmInputBlockBytes,
      "Vertex input exceeds the 128-byte VM input block"
    result.add (offset, size)
    inc pc

proc initGlslVm*(): GlslVm =
  ## Initialize shared VM state. Variant programs are prepared explicitly from
  ## the application's shader configs before rendering begins.
  var maxVertexAttributes: GLint
  glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, addr maxVertexAttributes)
  result.inputWordCount = min(maxVertexAttributes, GlslVmMaxVertexInputs)
  assert result.inputWordCount >= 1, "OpenGL device exposes no vertex attributes"
  result.activeVariant = -1
  for i in 0 ..< GlslVmMaxTextures:
    result.textures[i] = 0

proc variantKey(vertex, fragment: BytecodeProfile): GlslVmVariantKey =
  result.vertexFeatures = featureMask(vertex)
  result.fragmentFeatures = featureMask(fragment)
  result.vertexRegisters = getRegisterWord(vertex.features).uint8
  result.fragmentRegisters = getRegisterWord(fragment.features).uint8

proc buildVariant(vm: GlslVm, key: GlslVmVariantKey,
                  vertexProfile, fragmentProfile: BytecodeProfile): GlslVmVariant =
  let vertexSource = assembleVMSource(vssVertex, vertexProfile.features,
    vm.inputWordCount)
  let fragmentSource = assembleVMSource(vssFragment, fragmentProfile.features,
    vm.inputWordCount)
  result.key = key
  result.program = linkProgram(vertexSource, fragmentSource)
  glUseProgram(result.program)
  for stageName in ["uVertexBytecode", "uFragmentBytecode"]:
    let location = glGetUniformLocation(result.program, (stageName & "[0]").cstring)
    assert location >= 0, "GLSL VM is missing " & stageName
    if stageName == "uVertexBytecode": result.vertexBytecodeLocation = location
    else: result.fragmentBytecodeLocation = location
  for uniformName in ["uVertexUniforms", "uFragmentUniforms"]:
    let location = glGetUniformLocation(result.program, (uniformName & "[0]").cstring)
    assert location >= 0,
      "GLSL VM is missing " & uniformName
    if uniformName == "uVertexUniforms": result.vertexUniformLocation = location
    else: result.fragmentUniformLocation = location
  for i in 0 ..< GlslVmMaxTextures:
    let location = glGetUniformLocation(result.program, ("uSamplers[" & $i & "]").cstring)
    if location >= 0: glUniform1i(location, i.GLint)

proc findVariant(vm: GlslVm, key: GlslVmVariantKey): int =
  for i, variant in vm.variants:
    if variant.key == key:
      return i
  -1

proc prepareVariant(vm: var GlslVm, config: VmObjectConfig) =
  ## Internal step used only by the batch pre-generation API below.
  assert config.vertexBytecode.len > 0 and
    config.vertexBytecode.len <= GlslVmMaxBytecodeWords,
    "Object config needs 1..512 vertex bytecode words"
  assert config.fragmentBytecode.len > 0 and
    config.fragmentBytecode.len <= GlslVmMaxBytecodeWords,
    "Object config needs 1..512 fragment bytecode words"
  let vertexProfile = analyzeBytecode(config.vertexBytecode)
  let fragmentProfile = analyzeBytecode(config.fragmentBytecode)
  let key = variantKey(vertexProfile, fragmentProfile)
  if vm.findVariant(key) >= 0:
    return
  assert vm.variants.len < GlslVmMaxVariants,
    "GLSL VM variant limit exceeded; at most 16 profiles can be prepared"
  vm.variants.add(buildVariant(vm, key, vertexProfile, fragmentProfile))

proc prepareVariants*(vm: var GlslVm, configs: openArray[VmObjectConfig]) =
  ## Pre-generate the unique profiles in one setup pass, before rendering.
  ## The fixed 32-word vertex input is shared by every generated variant.
  for config in configs:
    vm.prepareVariant(config)

proc setShader*(vm: var GlslVm, config: VmObjectConfig) =
  ## Select a previously prepared shader profile and upload its bytecode.
  assert config.vertexBytecode.len > 0 and
    config.vertexBytecode.len <= GlslVmMaxBytecodeWords,
    "Object config needs 1..512 vertex bytecode words"
  assert config.fragmentBytecode.len > 0 and
    config.fragmentBytecode.len <= GlslVmMaxBytecodeWords,
    "Object config needs 1..512 fragment bytecode words"
  let vertexProfile = analyzeBytecode(config.vertexBytecode)
  let fragmentProfile = analyzeBytecode(config.fragmentBytecode)
  let key = variantKey(vertexProfile, fragmentProfile)
  let selected = vm.findVariant(key)
  assert selected >= 0,
    "Shader profile was not prepared; include its config in prepareVariants during setup"
  vm.activeVariant = selected
  let variant = vm.variants[selected]
  vm.program = variant.program
  glUseProgram(variant.program)
  glUniform1uiv(variant.vertexBytecodeLocation, config.vertexBytecode.len.GLsizei,
    unsafeAddr config.vertexBytecode[0])
  glUniform1uiv(variant.fragmentBytecodeLocation, config.fragmentBytecode.len.GLsizei,
    unsafeAddr config.fragmentBytecode[0])

proc configure*(vm: var GlslVm, config: VmObjectConfig) =
  ## Select bytecode and upload the object's textures. Vertex input buffers
  ## are created separately and stored on the config, not owned by the VM.
  vm.setShader(config)
  for i in 0 ..< GlslVmMaxTextures:
    vm.textureActive[i] = false
  for texture in config.textures:
    assert texture.slot >= 0 and texture.slot < GlslVmMaxTextures,
      "Texture slot must be in the VM's texture range"
    assert texture.data.len == texture.width * texture.height * 4,
      "VM textures must contain tightly packed RGBA8 pixels"
    let slot = texture.slot
    if vm.textures[slot] == 0:
      glGenTextures(1, addr vm.textures[slot])
    vm.textureActive[slot] = true
    glActiveTexture((GL_TEXTURE0.int + slot).GLenum)
    glBindTexture(GL_TEXTURE_2D, vm.textures[slot])
    let wrapMode = if texture.repeat: GL_REPEAT else: GL_CLAMP_TO_EDGE
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrapMode.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrapMode.GLint)
    let minFilter = if texture.mipmaps: GL_LINEAR_MIPMAP_LINEAR else: GL_LINEAR
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    let internalFormat = if texture.srgb: GLint(GL_SRGB8_ALPHA8) else: GLint(GL_RGBA8)
    glTexImage2D(GL_TEXTURE_2D, 0, internalFormat, texture.width.GLsizei,
      texture.height.GLsizei, 0, GL_RGBA, GL_UNSIGNED_BYTE,
      unsafeAddr texture.data[0])
    if texture.mipmaps: glGenerateMipmap(GL_TEXTURE_2D)
  for slot in 0 ..< GlslVmMaxTextures:
    glActiveTexture((GL_TEXTURE0.int + slot).GLenum)
    let textureId = if vm.textureActive[slot]: vm.textures[slot] else: 0'u32
    glBindTexture(GL_TEXTURE_2D, textureId)

proc bindTextures*(vm: GlslVm) =
  ## Rebind the currently configured texture set after another renderer has
  ## changed OpenGL's texture-unit state.
  for slot in 0 ..< GlslVmMaxTextures:
    glActiveTexture((GL_TEXTURE0.int + slot).GLenum)
    let textureId = if vm.textureActive[slot]: vm.textures[slot] else: 0'u32
    glBindTexture(GL_TEXTURE_2D, textureId)
  glActiveTexture(GL_TEXTURE0)

proc prepareGlslVmObject*(vm: GlslVm, config: var VmObjectConfig) =
  ## Pack this object's attribute arrays into the GLSL VM's 128-byte input
  ## blocks once, then retain the resulting VBO and VAO in its config.
  assert config.glVao == 0 and config.glInputVbo == 0,
    "GLSL mesh resources are already prepared for this config"
  let layout = bytecodeInputLayout(config.vertexBytecode)
  for field in layout:
    let neededWords = (field.offset + field.size + sizeof(uint32) - 1) div sizeof(uint32)
    assert neededWords <= vm.inputWordCount,
      "Object vertex inputs exceed the VM's GL attribute capacity"
  assert layout.len == config.attributes.len, "Vertex bytecode expects " &
    $layout.len & " attributes, got " & $config.attributes.len
  assert layout.len > 0, "A GLSL VM mesh needs vertex input fields"

  let first = config.attributes[0]
  var firstBuffer: VmBufferConfig
  var firstBufferFound = false
  for buffer in config.buffers:
    if buffer.id == first.bufferId:
      firstBuffer = buffer
      firstBufferFound = true
      break
  assert firstBufferFound, "First vertex attribute references a missing buffer"
  let firstStride = if first.strideBytes == 0: first.elementBytes else: first.strideBytes
  assert first.byteOffset <= firstBuffer.bytes.len and
    firstBuffer.bytes.len - first.byteOffset >= first.elementBytes,
    "First vertex attribute exceeds its source buffer"
  config.glVertexCount = 1 +
    (firstBuffer.bytes.len - first.byteOffset - first.elementBytes) div firstStride
  var packed = newSeq[byte](config.glVertexCount * GlslVmInputBlockBytes)

  for attributeIndex, source in config.attributes:
    let field = layout[attributeIndex]
    var bufferFound = false
    for buffer in config.buffers:
      if buffer.id != source.bufferId: continue
      bufferFound = true
      let stride = if source.strideBytes == 0: source.elementBytes else: source.strideBytes
      assert source.byteOffset <= buffer.bytes.len and stride >= source.elementBytes and
        buffer.bytes.len - source.byteOffset >= source.elementBytes,
        "Object attribute layout exceeds its source buffer"
      let count = 1 + (buffer.bytes.len - source.byteOffset - source.elementBytes) div stride
      assert count == config.glVertexCount,
        "All vertex attribute arrays must have equal lengths"
      assert source.elementBytes == field.size,
        "Attribute size does not match its bytecode input"
      for vertex in 0 ..< count:
        let src = source.byteOffset + vertex * stride
        let dst = vertex * GlslVmInputBlockBytes + field.offset
        for byteIndex in 0 ..< field.size:
          packed[dst + byteIndex] = buffer.bytes[src + byteIndex]
      break
    assert bufferFound, "Object attribute references a missing buffer"

  glGenVertexArrays(1, addr config.glVao)
  glBindVertexArray(config.glVao)
  glGenBuffers(1, addr config.glInputVbo)
  glBindBuffer(GL_ARRAY_BUFFER, config.glInputVbo)
  glBufferData(GL_ARRAY_BUFFER, packed.len.GLsizeiptr, addr packed[0], GL_STATIC_DRAW)
  for index in 0 ..< vm.inputWordCount:
    glEnableVertexAttribArray(index.GLuint)
    glVertexAttribIPointer(index.GLuint, 1, GL_UNSIGNED_INT,
      GlslVmInputBlockBytes.GLsizei, cast[pointer](index * sizeof(uint32)))
  glBindVertexArray(0)

proc bindGlslVmObject*(config: VmObjectConfig) =
  glBindVertexArray(config.glVao)

proc destroyGlslVmObject*(config: var VmObjectConfig) =
  if config.glInputVbo != 0:
    glDeleteBuffers(1, addr config.glInputVbo)
    config.glInputVbo = 0
  if config.glVao != 0:
    glDeleteVertexArrays(1, addr config.glVao)
    config.glVao = 0
  config.glVertexCount = 0

proc runVm*(vm: var GlslVm, config: VmObjectConfig) =
  ## Upload per-draw uniforms and leave the VM program ready. The caller binds
  ## the object's config VAO and index buffer before issuing a draw command.
  var vertexUniforms: array[GlslVmUniformWords, uint32]
  var fragmentUniforms: array[GlslVmUniformWords, uint32]
  for i, value in config.uniforms:
    vertexUniforms[i] = value
    fragmentUniforms[i] = value
  for i, value in config.vertexUniforms: vertexUniforms[i] = value
  for i, value in config.fragmentUniforms: fragmentUniforms[i] = value

  assert vm.activeVariant >= 0
  let variant = vm.variants[vm.activeVariant]
  glUseProgram(variant.program)
  glUniform1uiv(variant.vertexUniformLocation, GlslVmUniformWords.GLsizei, addr vertexUniforms[0])
  glUniform1uiv(variant.fragmentUniformLocation, GlslVmUniformWords.GLsizei, addr fragmentUniforms[0])
  # The caller binds the object's mesh and index buffer before issuing a draw.

proc destroy*(vm: var GlslVm) =
  ## Release VM-owned GL objects. Call while the OpenGL context is current.
  for i in 0 ..< vm.variants.len:
    if vm.variants[i].program != 0:
      glDeleteProgram(vm.variants[i].program)
  vm.variants.setLen(0)
  vm.program = 0
  vm.activeVariant = -1
  glDeleteTextures(GlslVmMaxTextures.GLsizei, addr vm.textures[0])
  vm.textures = default(typeof(vm.textures))

