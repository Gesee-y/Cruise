## OpenGL 3.3 wrapper for the GLSL bytecode VMs.
##
## The caller must create and make current an OpenGL 3.3 context, then call
## `loadExtensions()` from the OpenGL binding before constructing this object.
## Uniform offsets are word offsets, matching the shader generator's ABI.

import std/strutils
import ../../../externalModule/opengl/src/opengl
import object_config

const
  GlslVmMaxBytecodeWords* = 512
  GlslVmUniformWords* = 256
  GlslVmMaxTextures* = 8
  GlslVmInputBlockBytes* = 128
  GlslVmInputBlockWords* = GlslVmInputBlockBytes div sizeof(uint32)
  GlslVmMaxVertexInputs* = 32
  GlslVmInputOpcode = 63
  GlslVertexVmSource = staticRead("glsl_vm_vertex.glsl")
  GlslFragmentVmSource = staticRead("glsl_vm_fragment.glsl")

type
  GlslVm* = object
    program*: GLuint
    textures: array[GlslVmMaxTextures, GLuint]
    textureActive: array[GlslVmMaxTextures, bool]
    vao: GLuint
    inputVbo: GLuint
    inputWordCount: int
    vertexBytecodeLocation: GLint
    fragmentBytecodeLocation: GLint
    vertexUniformLocation: GLint
    fragmentUniformLocation: GLint

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
  ## Create the GLSL VM program from the library-owned shader implementations.
  var maxVertexAttributes: GLint
  glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, addr maxVertexAttributes)
  result.inputWordCount = min(maxVertexAttributes, GlslVmMaxVertexInputs)
  assert result.inputWordCount >= 1, "OpenGL device exposes no vertex attributes"
  let inputDeclaration = "uint inputs[32];"
  let specializedVertexSource = GlslVertexVmSource.replace(inputDeclaration,
    "uint inputs[" & $result.inputWordCount & "];")
  result.program = linkProgram(specializedVertexSource, GlslFragmentVmSource)
  glGenVertexArrays(1, addr result.vao)
  glBindVertexArray(result.vao)
  glGenBuffers(1, addr result.inputVbo)
  for i in 0 ..< GlslVmMaxTextures:
    result.textures[i] = 0

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
  glBindVertexArray(0)

proc setShader*(vm: var GlslVm, config: VmObjectConfig) =
  ## Select bytecode without replacing the configured vertex inputs or texture
  ## bindings. The new shader must be compatible with those configured inputs.
  ## No draw command is issued.
  assert config.vertexBytecode.len > 0 and
    config.vertexBytecode.len <= GlslVmMaxBytecodeWords,
    "Object config needs 1..512 vertex bytecode words"
  assert config.fragmentBytecode.len > 0 and
    config.fragmentBytecode.len <= GlslVmMaxBytecodeWords,
    "Object config needs 1..512 fragment bytecode words"
  glUseProgram(vm.program)
  glBindVertexArray(vm.vao)
  glUniform1uiv(vm.vertexBytecodeLocation, config.vertexBytecode.len.GLsizei,
    unsafeAddr config.vertexBytecode[0])
  glUniform1uiv(vm.fragmentBytecodeLocation, config.fragmentBytecode.len.GLsizei,
    unsafeAddr config.fragmentBytecode[0])

proc configure*(vm: var GlslVm, config: VmObjectConfig) =
  ## Upload immutable bytecode inputs and textures for an object. Call again
  ## only when switching or changing those resources; runVM handles uniforms.
  vm.setShader(config)
  let layout = bytecodeInputLayout(config.vertexBytecode)
  for field in layout:
    let neededWords = (field.offset + field.size + sizeof(uint32) - 1) div sizeof(uint32)
    assert neededWords <= vm.inputWordCount,
      "Object vertex inputs exceed the VM's GL attribute capacity"
  assert layout.len == config.attributes.len, "Vertex bytecode expects " &
    $layout.len & " attributes, got " & $config.attributes.len
  var vertexCountFromAttributes = 0
  var packed = newSeq[byte]()
  if layout.len > 0:
    let first = config.attributes[0]
    var firstBuffer: VmBufferConfig
    var firstBufferFound = false
    for buffer in config.buffers:
      if buffer.id == first.bufferId:
        firstBuffer = buffer
        firstBufferFound = true
        break
    assert firstBufferFound, "Object attribute references a missing buffer"
    let firstStride = if first.strideBytes == 0: first.elementBytes else: first.strideBytes
    assert first.byteOffset <= firstBuffer.bytes.len and
      firstBuffer.bytes.len - first.byteOffset >= first.elementBytes,
      "First vertex attribute exceeds its source buffer"
    vertexCountFromAttributes = 1 +
      (firstBuffer.bytes.len - first.byteOffset - first.elementBytes) div firstStride
    packed = newSeq[byte](vertexCountFromAttributes * GlslVmInputBlockBytes)

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
      assert count == vertexCountFromAttributes,
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

  glBindVertexArray(vm.vao)
  glBindBuffer(GL_ARRAY_BUFFER, vm.inputVbo)
  if packed.len > 0:
    glBufferData(GL_ARRAY_BUFFER, packed.len.GLsizeiptr, addr packed[0], GL_STATIC_DRAW)
  for index in 0 ..< vm.inputWordCount:
    glEnableVertexAttribArray(index.GLuint)
    glVertexAttribIPointer(index.GLuint, 1, GL_UNSIGNED_INT,
      GlslVmInputBlockBytes.GLsizei, cast[pointer](index * sizeof(uint32)))

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

proc runVm*(vm: var GlslVm, config: VmObjectConfig) =
  ## Upload per-draw uniforms and leave the VM shader/VAO ready for a caller
  ## issued draw command. Configure static resources separately.
  var vertexUniforms: array[GlslVmUniformWords, uint32]
  var fragmentUniforms: array[GlslVmUniformWords, uint32]
  for i, value in config.uniforms:
    vertexUniforms[i] = value
    fragmentUniforms[i] = value
  for i, value in config.vertexUniforms: vertexUniforms[i] = value
  for i, value in config.fragmentUniforms: fragmentUniforms[i] = value

  glUseProgram(vm.program)
  glBindVertexArray(vm.vao)
  glUniform1uiv(vm.vertexUniformLocation, GlslVmUniformWords.GLsizei, addr vertexUniforms[0])
  glUniform1uiv(vm.fragmentUniformLocation, GlslVmUniformWords.GLsizei, addr fragmentUniforms[0])
  # Program, VAO, buffers and texture bindings remain active for the caller's draw.

proc destroy*(vm: var GlslVm) =
  ## Release VM-owned GL objects. Call while the OpenGL context is current.
  if vm.program != 0:
    glDeleteProgram(vm.program)
    vm.program = 0
  if vm.inputVbo != 0:
    glDeleteBuffers(1, addr vm.inputVbo)
    vm.inputVbo = 0
  glDeleteTextures(GlslVmMaxTextures.GLsizei, addr vm.textures[0])
  vm.textures = default(typeof(vm.textures))
  if vm.vao != 0:
    glDeleteVertexArrays(1, addr vm.vao)
    vm.vao = 0

