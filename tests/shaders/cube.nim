import std/[os, strutils]
import ../../../../Github/Cruise/src/windows/windows
import ../../../../Github/Cruise/stdplugin/sdlwin/sdlwin
import ../../externalModule/opengl/src/opengl
import shader_setup

proc triangle() =
  let app = initSDL3App()
  let appDir = getAppDir()
  let vertexBytecode = readBytecode(appDir / "deps" / "cube_vert.cbc")
  let fragmentBytecode = readBytecode(appDir / "deps" / "cube_frag.cbc")
  var vertexSource = readFile(appDir / "glsl_vm_vertex.glsl")
  let fragmentSource = readFile(appDir / "glsl_vm_fragment.glsl")

  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3)
  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE)
  discard SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 1 — Simple Window", width=800, height=600, gl=true)

  var ctx = SDL_GL_CreateContext(win.handle)
  defer: SDL_GL_DestroyContext(ctx)
  loadExtensions()
    
  # Connection to the close notifier: when the close button is clicked
  var running = true
  NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
    if ev.kind == WINDOW_CLOSE:
      running = false

  var maxVertexAttributes: GLint
  glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, addr maxVertexAttributes)
  let inputWords = vertexInputWordCount(vertexBytecode)
  if inputWords <= 0:
    raise newException(IOError, "Vertex bytecode does not declare a packed input")
  if inputWords > maxVertexAttributes:
    raise newException(IOError, "Vertex bytecode reads " & $inputWords &
      " uint input words, but this OpenGL device exposes only " &
      $maxVertexAttributes & " vertex attribute locations")
  # Keep the GLSL VM's 128-byte input-block ABI while avoiding unused attribute
  # locations on devices whose GL_MAX_VERTEX_ATTRIBS is below 32.
  let declaration = "uint inputs[32];"
  if declaration notin vertexSource:
    raise newException(IOError, "GLSL VM shader is missing uint inputs[32]")
  vertexSource = vertexSource.replace(declaration,
    "uint inputs[" & $inputWords & "];")

  let program = createVmProgram(vertexSource, fragmentSource)
  defer: glDeleteProgram(program)

  type VertexPosition = array[3, GLfloat]
  let positions: array[4, VertexPosition] = [
    [0.5f, 0.5f, 0.0f],
    [0.5f, -0.5f, 0.0f],
    [-0.5f, -0.5f, 0.0f],
    [-0.5f, 0.5f, 0.0f]
  ]
  let texCoords = [[1.0f, 1.0f],
    [1.0f, 0.0f],
    [0.0f, 0.0f],
    [0.0f, 1.0f]]

  let indices = [
    0u32, 1, 3,
    1, 2, 3
  ]
  let inputBlock = packVertexInputBlock(vertexBytecode,
    [vertexAttribute(positions), vertexAttribute(texCoords)])
  var vao, vbo, ebo: GLuint
  glGenVertexArrays(1, addr vao)
  glBindVertexArray(vao)

  glGenBuffers(1, addr vbo)
  glBindBuffer(GL_ARRAY_BUFFER, vbo)
  glBufferData(GL_ARRAY_BUFFER,
    GLsizeiptr(inputBlock.len * sizeof(uint32)), unsafeAddr inputBlock[0],
    GL_STATIC_DRAW)

  glGenBuffers(1, addr ebo)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, (sizeof(indices[0])*indices.len).GLsizeiptr, unsafeAddr indices[0], GL_STATIC_DRAW)

  for index in 0..<inputWords:
    glEnableVertexAttribArray(index.GLuint)
    glVertexAttribIPointer(index.GLuint, 1, GL_UNSIGNED_INT, ShaderBlockBytes.GLsizei,
      cast[pointer](index * sizeof(uint32)))

  glUseProgram(program)
  uploadBytecode(program, "uVertexBytecode", "uVertexBytecodeLen", vertexBytecode)
  uploadBytecode(program, "uFragmentBytecode", "uFragmentBytecodeLen", fragmentBytecode)
  bindSamplers(program, "uSamplers", 8)

  # Load image texture from assets using SDL3
  let assetPath = appDir / ".." / ".." / "assets" / "box21.png"
  var surface = SDL_LoadPNG(assetPath.cstring)
  if surface == nil:
    raise newException(IOError, "Failed to load texture image from: " & assetPath & " error: " & sdlError())
  var convertedSurface = SDL_ConvertSurface(surface, SDL_PIXELFORMAT_RGBA32)
  if convertedSurface == nil:
    convertedSurface = surface
  else:
    SDL_DestroySurface(surface)

  var textureId: GLuint
  glGenTextures(1, addr textureId)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, textureId)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexImage2D(GL_TEXTURE_2D, 0.GLint, GL_RGBA.GLint, convertedSurface.w.GLsizei,
               convertedSurface.h.GLsizei, 0.GLint, GL_RGBA, GL_UNSIGNED_BYTE,
               convertedSurface.pixels)
  SDL_DestroySurface(convertedSurface)

  let vertexUniforms = [cast[uint32](1.0'f32), cast[uint32](0.0'f32)]
  var timer = 0.0'f32
  var fragmentUniforms = [cast[uint32](timer)]
  glBindVertexArray(vao)

  glViewport(0, 0, 800.GLsizei, 600.GLsizei)
  glClearColor(0.07'f32, 0.08'f32, 0.12'f32, 1.0'f32)

  while running:
    app.eventLoop(SDLEventRouter)

    # Quit on Escape
    if app.isKeyJustPressed(CKey_Escape):
      running = false

    timer += 0.016'f32
    fragmentUniforms[0] = cast[uint32](timer)
    uploadUniformBlock(program, "uVertexUniforms", vertexUniforms)
    uploadUniformBlock(program, "uFragmentUniforms", fragmentUniforms)

    glClear(GL_COLOR_BUFFER_BIT)
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, nil)
    discard SDL_GL_SwapWindow(win.handle)

  glDeleteTextures(1, addr textureId)
  glDeleteBuffers(1, addr vbo)
  glDeleteVertexArrays(1, addr vao)
  win.quitWindow()
  app.quitSDL3App()
  SDL_Quit_proc()

triangle()

