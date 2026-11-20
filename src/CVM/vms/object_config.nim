## Backend-independent data for one VM workload or rendered object.

type
  VmUniformStage* = enum
    vusShared, vusVertex, vusFragment

  VmBufferConfig* = object
    id*: int
    bytes*: seq[byte]

  VmAttributeConfig* = object
    bufferId*: int
    elementBytes*: int
    byteOffset*: int
    strideBytes*: int

  VmTextureConfig* = object
    slot*: int
    data*: seq[byte]

  VmObjectConfig* = object
    ## `bytecode` and `uniforms` are consumed by CPU/OpenCL. The shader fields
    ## and stage tables are consumed by GLSL. Shared tables are stage-neutral.
    bytecode*: seq[uint32]
    vertexBytecode*, fragmentBytecode*: seq[uint32]
    uniforms*, vertexUniforms*, fragmentUniforms*: seq[uint32]
    buffers*: seq[VmBufferConfig]
    attributes*: seq[VmAttributeConfig]
    textures*: seq[VmTextureConfig]
    ## OpenGL backend mesh handles. Other VM backends ignore these fields.
    glVao*, glInputVbo*: uint32
    glVertexCount*: int

proc newConfig(): VmObjectConfig =
  result = VmObjectConfig()

proc initVmObjectConfig*(bytecode: openArray[uint32] = []): VmObjectConfig =
  result = newConfig()
  result.bytecode = @bytecode

proc initVmShaderConfig*(vertexBytecode, fragmentBytecode: openArray[uint32]): VmObjectConfig =
  result = newConfig()
  result.vertexBytecode = @vertexBytecode
  result.fragmentBytecode = @fragmentBytecode

proc storeUniform[T](table: var seq[uint32], offset: int, value: T) =
  let words = (sizeof(T) + sizeof(uint32) - 1) div sizeof(uint32)
  assert offset >= 0 and offset + words <= 256,
    "Uniform word offset must be in 0..255"
  if table.len < offset + words:
    table.setLen(offset + words)
  var copied = value
  copyMem(addr table[offset], addr copied, sizeof(T))

proc copyUniforms(table: var seq[uint32], values: openArray[uint32]) =
  if table.len != values.len:
    table.setLen(values.len)
  if values.len > 0:
    copyMem(addr table[0], unsafeAddr values[0], values.len * sizeof(uint32))

proc setUniform*[T](config: var VmObjectConfig, offset: int, value: T,
                    stage: VmUniformStage = vusShared) =
  ## Store a typed value at a word offset, preserving its raw representation.
  case stage
  of vusShared: config.uniforms.storeUniform(offset, value)
  of vusVertex: config.vertexUniforms.storeUniform(offset, value)
  of vusFragment: config.fragmentUniforms.storeUniform(offset, value)

proc setUniforms*(config: var VmObjectConfig, values: openArray[uint32],
                  stage: VmUniformStage = vusShared) =
  if values.len > 256:
    assert false, "Uniform table exceeds 256 words"
  case stage
  of vusShared: config.uniforms.copyUniforms(values)
  of vusVertex: config.vertexUniforms.copyUniforms(values)
  of vusFragment: config.fragmentUniforms.copyUniforms(values)

proc setBuffer*(config: var VmObjectConfig, bufferId: int,
                data: pointer, byteLength: int) =
  if bufferId < 0 or byteLength < 0 or (byteLength > 0 and data == nil):
    assert false, "Invalid buffer id, pointer, or byte length"
  var index = 0
  while index < config.buffers.len and config.buffers[index].id != bufferId:
    inc index
  if index == config.buffers.len:
    config.buffers.add VmBufferConfig(id: bufferId)
  var bytes = newSeq[byte](byteLength)
  if byteLength > 0:
    copyMem(addr bytes[0], data, byteLength)
  config.buffers[index].bytes = move(bytes)

proc addVertexAttribute*(config: var VmObjectConfig, bufferId, elementBytes: int,
                         byteOffset: int = 0, strideBytes: int = 0) =
  if bufferId < 0 or elementBytes <= 0 or byteOffset < 0 or strideBytes < 0:
    assert false, "Invalid vertex attribute layout"
  config.attributes.add VmAttributeConfig(bufferId: bufferId,
    elementBytes: elementBytes, byteOffset: byteOffset, strideBytes: strideBytes)

proc setTexture*(config: var VmObjectConfig, slot: int, rgbaPixels: openArray[byte]) =
  if slot < 0 or slot >= 8:
    assert false, "Texture slot must be in 0..7"
  var texture = VmTextureConfig(slot: slot)
  texture.data = @rgbaPixels
  var index = 0
  while index < config.textures.len and config.textures[index].slot != slot:
    inc index
  if index == config.textures.len:
    config.textures.add move(texture)
  else:
    config.textures[index] = move(texture)

