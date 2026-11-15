import std/[os, strutils]
import ../../externalModule/opengl/src/opengl

const
  ShaderBlockBytes* = 128
  ShaderBlockWords* = ShaderBlockBytes div sizeof(uint32)
  UniformTableWords* = 256

type
  VertexAttribute* = object
    data: seq[byte]
    elementSize: int

proc readBytecode*(path: string, maxBytecodeWord=512): seq[uint32] =
  if not fileExists(path):
    raise newException(IOError, "Bytecode file not found: " & path)
  var file = open(path, fmRead)
  defer: file.close()
  var word: uint32
  while file.readBuffer(addr word, sizeof(word)) == sizeof(word):
    result.add word
  if result.len == 0 or result.len > maxBytecodeWord:
    raise newException(IOError, "Invalid bytecode size in " & path)

proc vertexAttribute*[T](values: openArray[T]): VertexAttribute =
  result.elementSize = sizeof(T)
  result.data = newSeq[byte](values.len * result.elementSize)
  if result.data.len > 0:
    copyMem(addr result.data[0], unsafeAddr values[0], result.data.len)

proc vertexInputLayout*(code: openArray[uint32]): seq[tuple[offset, size: int]] =
  if code.len < 2:
    raise newException(IOError, "Vertex bytecode has no entry point")
  var pc = int(code[1])
  while pc >= 0 and pc < code.len:
    let instruction = code[pc]
    let opcode = int((instruction shr 16) and 255'u32)
    if opcode != 63:
      break
    var size = int((instruction shr 24) and 255'u32)
    if size == 0: size = 1
    let offset = int(instruction and 255'u32)
    if offset + size > ShaderBlockBytes:
      raise newException(IOError, "Vertex input field exceeds the 128-byte block")
    result.add (offset, size)
    inc pc

proc vertexInputWordCount*(code: openArray[uint32]): int =
  for field in vertexInputLayout(code):
    result = max(result, (field.offset + field.size + sizeof(uint32) - 1) div
      sizeof(uint32))

proc packVertexInputBlock*(code: openArray[uint32],
                          attributes: openArray[VertexAttribute]): seq[uint32] =
  let layout = vertexInputLayout(code)
  if layout.len != attributes.len:
    raise newException(IOError, "Expected " & $layout.len &
      " vertex attribute arrays, got " & $attributes.len)
  if attributes.len == 0:
    raise newException(IOError, "At least one vertex input array is required")

  let first = attributes[0]
  if first.elementSize <= 0 or first.data.len mod first.elementSize != 0:
    raise newException(IOError, "Invalid first vertex attribute array")
  let vertexCount = first.data.len div first.elementSize
  var packedBytes = newSeq[byte](vertexCount * ShaderBlockBytes)

  for attributeIndex, attribute in attributes:
    let field = layout[attributeIndex]
    if attribute.elementSize != field.size:
      raise newException(IOError, "Vertex attribute " & $attributeIndex &
        " has " & $attribute.elementSize & " bytes per element; bytecode expects " &
        $field.size)
    if attribute.data.len mod attribute.elementSize != 0 or
       attribute.data.len div attribute.elementSize != vertexCount:
      raise newException(IOError, "Vertex attribute arrays must have equal vertex counts")
    for vertex in 0..<vertexCount:
      let srcOffset = vertex * attribute.elementSize
      let dstOffset = vertex * ShaderBlockBytes + field.offset
      for byteIndex in 0..<field.size:
        packedBytes[dstOffset + byteIndex] = attribute.data[srcOffset + byteIndex]

  result = newSeq[uint32](packedBytes.len div sizeof(uint32))
  if packedBytes.len > 0:
    copyMem(addr result[0], addr packedBytes[0], packedBytes.len)

proc shaderLog*(shader: GLuint): string =
  var length: GLint
  glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr length)
  if length <= 1: return ""
  result = newString(length.int)
  glGetShaderInfoLog(shader, length, nil, cast[cstring](addr result[0]))

proc programLog*(program: GLuint): string =
  var length: GLint
  glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr length)
  if length <= 1: return ""
  result = newString(length.int)
  glGetProgramInfoLog(program, length, nil, cast[cstring](addr result[0]))

proc compileShader*(shaderType: GLenum, source: string, label: string): GLuint =
  result = glCreateShader(shaderType)
  if result == 0:
    raise newException(IOError, "glCreateShader failed for " & label)
  var sourcePtr = source.cstring
  var sources = [sourcePtr]
  glShaderSource(result, 1, cast[cstringArray](addr sources[0]), nil)
  glCompileShader(result)
  var compiled: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, addr compiled)
  if compiled == 0:
    let details = shaderLog(result)
    glDeleteShader(result)
    raise newException(IOError, label & " GLSL compilation failed:\n" & details)

proc createVmProgram*(vertexSource, fragmentSource: string): GLuint =
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
  if linked == 0:
    let details = programLog(result)
    glDeleteProgram(result)
    raise newException(IOError, "GLSL VM program link failed:\n" & details)

proc uploadBytecode*(program: GLuint, uniformName, lengthName: string,
                    code: openArray[uint32]) =
  let baseName = uniformName & "[0]"
  let bytecodeLocation = glGetUniformLocation(program, baseName.cstring)
  let lengthLocation = glGetUniformLocation(program, lengthName.cstring)
  if bytecodeLocation < 0 or lengthLocation < 0:
    raise newException(IOError, "GLSL VM bytecode uniforms are missing")
  glUniform1uiv(bytecodeLocation, code.len.GLsizei, addr code[0])
  glUniform1i(lengthLocation, code.len.GLint)

proc uploadUniformBlock*(program: GLuint, uniformName: string,
                        values: openArray[uint32]) =
  let baseName = uniformName & "[0]"
  let location = glGetUniformLocation(program, baseName.cstring)
  if location < 0:
    raise newException(IOError, "GLSL VM uniform table is missing: " & uniformName)
  if values.len > UniformTableWords:
    raise newException(IOError, "Uniform table exceeds " & $UniformTableWords & " uint32 words")
  var table: array[UniformTableWords, uint32]
  for index, value in values:
    table[index] = value
  glUniform1uiv(location, UniformTableWords.GLsizei, addr table[0])

proc bindSamplers*(program: GLuint, samplerArrayName: string = "uSamplers", count: int = 8) =
  for i in 0 ..< count:
    let name = samplerArrayName & "[" & $i & "]"
    let loc = glGetUniformLocation(program, name.cstring)
    if loc >= 0:
      glUniform1i(loc, GLint(i))
