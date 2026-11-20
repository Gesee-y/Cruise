# ################################################################################################################################################################## #
# ###################################################################### GLSL33 BACKEND ############################################################################ #
# ################################################################################################################################################################## #

import std/tables
import ../../../externalModule/opengl/src/opengl
import object_config
import ../bytecode
import ../deps/vmops

const
  GLSL_MAX_BYTECODE_WORDS* = 512
  GLSL_VM_UNIFORM_WORDS* = 256
  GLSL_VM_MAX_TEXTURES* = 8
  GLSL_VM_MAX_VARIANTS* = 16
  GLSL_VM_INPUT_BLOCK_BYTES* = 128
  GLSL_VM_MAX_INPUT_VERTEX* = 32
  GLSL_INPUT_OP_CODE = vocLoadVertexInput.int
  DEFAULT_VM_FEATURES = {bfCalls, bfSampling, bfTranscendentals, bfMixing, bfMatrices, bfVectorMath, bfReg256}

type
  GlslVmVariant = object
    program: GLuint
    vertexBytecodeLocation, fragmentBytecodeLocation: GLint
    vertexUniformLocation, fragmentUniformLocation: GLint

  GlslVm* = object
    program*: GLuint
    variants*: Table[uint32, GlslVmVariant]
    activeVariant*: uint32
    inputWordCount*: int

  VmShaderStage* = enum
    vssVertex
    vssFragment

  # ###################################################################################################### #
 # ############################################# VM GENERATION ########################################## #
# ###################################################################################################### #

include "glsl_vm_vertex.nimf"
include "glsl_vm_fragment.nimf"

proc assembleVMSource*(stage: VmShaderStage,
                       features: set[BytecodeFeature],
                       inputWordCount: int = GLSL_VM_MAX_INPUT_VERTEX): string =
  ## SCF-generated templates select chunks without parsing GLSL at runtime.
  case stage
  of vssVertex:
    result = generateVertexVmSource(features, inputWordCount)
  of vssFragment:
    result = generateFragmentVmSource(features)

  # ###################################################################################################### #
 # ############################################# SHADER HELPERS ######################################### #
# ###################################################################################################### #

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

  # ###################################################################################################### #
 # ########################################### GLSL VM INTERNALS ######################################## #
# ###################################################################################################### #

proc bytecodeInputLayout*(code: openArray[uint32]): seq[tuple[offset, size: int]] =
  assert code.len >= 2, "Vertex VM bytecode has no entry point"
  var pc = int(code[1])
  while pc >= 0 and pc < code.len:
    let word = code[pc]
    if int((word shr 16) and 255'u32) != GLSL_INPUT_OP_CODE:
      break
    var size = int((word shr 24) and 255'u32)
    if size == 0: size = 1
    let offset = int(word and 255'u32)
    assert offset >= 0 and size >= 1 and offset + size <= GLSL_VM_INPUT_BLOCK_BYTES,
      "Vertex input exceeds the 128-byte VM input block"
    result.add (offset, size)
    inc pc

proc variantKey*(vertexProfile, fragmentProfile: BytecodeProfile): uint32 =
  (featureMask(vertexProfile).uint32 shl 16) or featureMask(fragmentProfile).uint32

proc variantKey*(vertexCode, fragmentCode: openArray[uint32]): uint32 =
  let vp = analyzeBytecode(vertexCode)
  let fp = analyzeBytecode(fragmentCode)
  variantKey(vp, fp)

proc buildVariant(vm: GlslVm, vertexFeatures, fragmentFeatures: set[BytecodeFeature]): GlslVmVariant =
  let vertexSource = assembleVMSource(vssVertex, vertexFeatures, vm.inputWordCount)
  let fragmentSource = assembleVMSource(vssFragment, fragmentFeatures, vm.inputWordCount)
  result.program = linkProgram(vertexSource, fragmentSource)
  glUseProgram(result.program)
  for stageName in ["uVertexBytecode", "uFragmentBytecode"]:
    let location = glGetUniformLocation(result.program, (stageName & "[0]").cstring)
    assert location >= 0, "GLSL VM is missing " & stageName
    if stageName == "uVertexBytecode": result.vertexBytecodeLocation = location
    else: result.fragmentBytecodeLocation = location
  for uniformName in ["uVertexUniforms", "uFragmentUniforms"]:
    let location = glGetUniformLocation(result.program, (uniformName & "[0]").cstring)
    assert location >= 0, "GLSL VM is missing " & uniformName
    if uniformName == "uVertexUniforms": result.vertexUniformLocation = location
    else: result.fragmentUniformLocation = location
  for i in 0 ..< GLSL_VM_MAX_TEXTURES:
    let location = glGetUniformLocation(result.program, ("uSamplers[" & $i & "]").cstring)
    if location >= 0: glUniform1i(location, i.GLint)

  # ###################################################################################################### #
 # ############################################# GLSL VM API ############################################ #
# ###################################################################################################### #

proc initGlslVm*(): GlslVm =
  ## Initialize shared VM state. Variant programs are prepared explicitly or
  ## on first use.
  var maxVertexAttributes: GLint
  glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, addr maxVertexAttributes)
  result.inputWordCount = min(maxVertexAttributes, GLSL_VM_MAX_INPUT_VERTEX)
  assert result.inputWordCount >= 1, "OpenGL device exposes no vertex attributes"
  result.variants = initTable[uint32, GlslVmVariant]()
  result.program = 0
  result.activeVariant = 0

proc prepareVariant*(vm: var GlslVm, vertexCode, fragmentCode: openArray[uint32]): uint32 =
  ## Pre-compile and cache the specialized VM shader program for the given bytecode pair.
  assert vertexCode.len > 0 and vertexCode.len <= GLSL_MAX_BYTECODE_WORDS,
    "Vertex bytecode needs 1..512 words"
  assert fragmentCode.len > 0 and fragmentCode.len <= GLSL_MAX_BYTECODE_WORDS,
    "Fragment bytecode needs 1..512 words"
  let vp = analyzeBytecode(vertexCode)
  let fp = analyzeBytecode(fragmentCode)
  let key = variantKey(vp, fp)
  if key notin vm.variants:
    assert vm.variants.len < GLSL_VM_MAX_VARIANTS, "GLSL VM variant limit exceeded"
    vm.variants[key] = vm.buildVariant(vp.features, fp.features)
  return key

proc prepareVariant*(vm: var GlslVm, config: VmObjectConfig): uint32 {.discardable.} =
  vm.prepareVariant(config.vertexBytecode, config.fragmentBytecode)

proc prepareVariants*(vm: var GlslVm, configs: openArray[VmObjectConfig]) =
  ## Pre-generate unique profiles for multiple configs in one setup pass.
  for config in configs:
    discard vm.prepareVariant(config)

proc use*(vm: var GlslVm, vertexCode, fragmentCode: openArray[uint32]) =
  ## Activate the specialized VM shader and upload its bytecode to uniforms.
  let key = vm.prepareVariant(vertexCode, fragmentCode)
  let variant = vm.variants[key]
  vm.program = variant.program
  vm.activeVariant = key
  glUseProgram(variant.program)
  glUniform1uiv(variant.vertexBytecodeLocation, vertexCode.len.GLsizei,
    unsafeAddr vertexCode[0])
  glUniform1uiv(variant.fragmentBytecodeLocation, fragmentCode.len.GLsizei,
    unsafeAddr fragmentCode[0])

proc use*(vm: var GlslVm, config: VmObjectConfig) =
  vm.use(config.vertexBytecode, config.fragmentBytecode)

proc setShader*(vm: var GlslVm, config: VmObjectConfig) =
  ## Alias for use(config).
  vm.use(config)

proc uploadUniforms*(vm: GlslVm, vertexUniforms, fragmentUniforms: openArray[uint32]) =
  ## Upload per-draw uniforms to the active variant.
  assert vm.program != 0 and vm.activeVariant in vm.variants, "No active VM shader program"
  let variant = vm.variants[vm.activeVariant]
  var vBuf: array[GLSL_VM_UNIFORM_WORDS, uint32]
  var fBuf: array[GLSL_VM_UNIFORM_WORDS, uint32]
  let vLen = min(vertexUniforms.len, GLSL_VM_UNIFORM_WORDS)
  let fLen = min(fragmentUniforms.len, GLSL_VM_UNIFORM_WORDS)
  if vLen > 0: copyMem(addr vBuf[0], unsafeAddr vertexUniforms[0], vLen * sizeof(uint32))
  if fLen > 0: copyMem(addr fBuf[0], unsafeAddr fragmentUniforms[0], fLen * sizeof(uint32))
  glUniform1uiv(variant.vertexUniformLocation, GLSL_VM_UNIFORM_WORDS.GLsizei, addr vBuf[0])
  glUniform1uiv(variant.fragmentUniformLocation, GLSL_VM_UNIFORM_WORDS.GLsizei, addr fBuf[0])

proc uploadUniforms*(vm: GlslVm, config: VmObjectConfig) =
  ## Upload uniforms extracted from VmObjectConfig.
  assert vm.program != 0 and vm.activeVariant in vm.variants, "No active VM shader program"
  let variant = vm.variants[vm.activeVariant]
  var vBuf: array[GLSL_VM_UNIFORM_WORDS, uint32]
  var fBuf: array[GLSL_VM_UNIFORM_WORDS, uint32]
  for i, value in config.uniforms:
    if i < GLSL_VM_UNIFORM_WORDS:
      vBuf[i] = value
      fBuf[i] = value
  for i, value in config.vertexUniforms:
    if i < GLSL_VM_UNIFORM_WORDS: vBuf[i] = value
  for i, value in config.fragmentUniforms:
    if i < GLSL_VM_UNIFORM_WORDS: fBuf[i] = value
  glUniform1uiv(variant.vertexUniformLocation, GLSL_VM_UNIFORM_WORDS.GLsizei, addr vBuf[0])
  glUniform1uiv(variant.fragmentUniformLocation, GLSL_VM_UNIFORM_WORDS.GLsizei, addr fBuf[0])

proc runVm*(vm: var GlslVm, config: VmObjectConfig) =
  ## Activate shader and upload uniforms. The caller binds VAO and textures before drawing.
  let key = variantKey(config.vertexBytecode, config.fragmentBytecode)
  if vm.activeVariant != key or vm.program == 0:
    vm.use(config)
  vm.uploadUniforms(config)

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
  var packed = newSeq[byte](config.glVertexCount * GLSL_VM_INPUT_BLOCK_BYTES)

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
        let dst = vertex * GLSL_VM_INPUT_BLOCK_BYTES + field.offset
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
      GLSL_VM_INPUT_BLOCK_BYTES.GLsizei, cast[pointer](index * sizeof(uint32)))
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

proc destroy*(vm: var GlslVm) =
  ## Release VM-owned GL program objects. Call while the OpenGL context is current.
  for variant in vm.variants.values:
    if variant.program != 0:
      glDeleteProgram(variant.program)
  vm.variants.clear()
  vm.program = 0
  vm.activeVariant = 0
