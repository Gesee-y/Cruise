import std/[os]
import ../../../../Github/Cruise/src/windows/windows
import ../../../../Github/Cruise/stdplugin/sdlwin/sdlwin
import ../../externalModule/opengl/src/opengl

proc readBytecode*(path: string, maxBytecodeWord=256): seq[uint32] =
  result = @[]
  if not fileExists(path):
    return
  var file = open(path, fmRead)
  defer: file.close()
  var word: uint32
  while file.readBuffer(addr word, sizeof(word)) == sizeof(word):
    result.add word

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

proc compileShader(shaderType: GLenum, source: string, label: string): GLuint =
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

proc createVmProgram(vertexSource, fragmentSource: string): GLuint =
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

proc uploadBytecode(program: GLuint, uniformName, lengthName: string,
                    code: openArray[uint32]) =
  let baseName = uniformName & "[0]"
  let bytecodeLocation = glGetUniformLocation(program, baseName.cstring)
  let lengthLocation = glGetUniformLocation(program, lengthName.cstring)
  if bytecodeLocation < 0 or lengthLocation < 0:
    raise newException(IOError, "GLSL VM bytecode uniforms are missing")
  glUniform1uiv(bytecodeLocation, code.len.GLsizei, addr code[0])
  glUniform1i(lengthLocation, code.len.GLint)


proc triangle() =
  let app = initSDL3App()
  let appDir = getAppDir()
  let vertexBytecode = readBytecode(appDir / "deps" / "triangle_vert.cbc")
  let fragmentBytecode = readBytecode(appDir / "deps" / "triangle_frag.cbc")
  let vertexSource = readFile(appDir / "glsl_vm_vertex.glsl")
  let fragmentSource = readFile(appDir / "glsl_vm_fragment.glsl")

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 1 — Simple Window", width=800, height=600, gl=true)
  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1)
  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE)
  discard SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)

  var ctx = SDL_GL_CreateContext(win.handle)
  defer: SDL_GL_DestroyContext(ctx)
  loadExtensions()
    
  # Connection to the close notifier: when the close button is clicked
  var running = true
  NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
    if ev.kind == WINDOW_CLOSE:
      running = false

  let program = createVmProgram(vertexSource, fragmentSource)
  defer: glDeleteProgram(program)

  let vertices: seq[GLfloat] = @[-0.5f, -0.5f, 0.0f,
                  0.5f, -0.5f, 0.0f,
                  0.0f, 0.5f, 0.0f
                ]
  var vao, vbo: GLuint
  glGenVertexArrays(1, addr vao)
  glBindVertexArray(vao)

  glGenBuffers(1, addr vbo)
  glBindBuffer(GL_ARRAY_BUFFER, vbo)
  glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(sizeof(GLfloat)*9),
                 unsafeAddr vertices[0], GL_STATIC_DRAW)
  glEnableVertexAttribArray(0)
  glVertexAttribPointer(0, 3, cGL_FLOAT, GL_FALSE, 0, nil)
  
  glUseProgram(program)
  uploadBytecode(program, "uVertexBytecode", "uVertexBytecodeLen", vertexBytecode)
  uploadBytecode(program, "uFragmentBytecode", "uFragmentBytecodeLen", fragmentBytecode)
  
  glBindVertexArray(vao)

  glViewport(0, 0, 800.GLsizei, 600.GLsizei)
  glClearColor(0.07'f32, 0.08'f32, 0.12'f32, 1.0'f32)

  while running:
    app.eventLoop(SDLEventRouter)

    # Quit on Escape
    if app.isKeyJustPressed(CKey_Escape):
      running = false

    glClear(GL_COLOR_BUFFER_BIT)
    glDrawArrays(GL_TRIANGLES, 0, 3)
    discard SDL_GL_SwapWindow(win.handle)

  glDeleteBuffers(1, addr vbo)
  glDeleteVertexArrays(1, addr vao)
  win.quitWindow()
  app.quitSDL3App()
  SDL_Quit_proc()

triangle()

