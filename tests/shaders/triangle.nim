import std/os
import ../../../../Github/Cruise/src/windows/windows
import ../../../../Github/Cruise/stdplugin/sdlwin/sdlwin
import ../../externalModule/opengl/src/opengl
import ../../src/CVM/vms/glsl33
import ../../src/CVM/vms/object_config
import shader_setup

proc triangle() =
  let app = initSDL3App()
  let appDir = getAppDir()
  let vertexBytecode = readBytecode(appDir / "deps" / "triangle_vert.cbc")
  let fragmentBytecode = readBytecode(appDir / "deps" / "triangle_frag.cbc")
  
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

  var vm = initGlslVm()
  defer: vm.destroy()
  var objectConfig = initVmShaderConfig(vertexBytecode, fragmentBytecode)

  type VertexPosition = array[3, GLfloat]
  let positions: array[3, VertexPosition] = [
    [-0.65'f32, -0.55'f32, 0.0'f32],
    [ 0.65'f32, -0.55'f32, 0.0'f32],
    [ 0.0'f32,   0.65'f32, 0.0'f32]
  ]
  let texCoords = [[0.0f, 0.0f],
    [1.0f, 0.0f],
    [0.5f, 1.0f]]
  objectConfig.setBuffer(0, unsafeAddr positions[0], sizeof(positions))
  objectConfig.setBuffer(1, unsafeAddr texCoords[0], sizeof(texCoords))
  objectConfig.addVertexAttribute(0, sizeof(VertexPosition))
  objectConfig.addVertexAttribute(1, sizeof(texCoords[0]))

  # Load image texture from assets using SDL3
  let assetPath = appDir / ".." / ".." / "assets" / "box21.png"
  var surface = SDL_LoadPNG(assetPath.cstring)
  assert surface != nil, "Failed to load texture image from: " & assetPath & " error: " & sdlError()
  var convertedSurface = SDL_ConvertSurface(surface, SDL_PIXELFORMAT_RGBA32)
  assert convertedSurface != nil, "Failed to convert texture image from: " & assetPath & " error: " & sdlError()
  SDL_DestroySurface(surface)

  let textureWidth = int(convertedSurface.w)
  let textureHeight = int(convertedSurface.h)
  var rgbaPixels = newSeq[byte](textureWidth * textureHeight * 4)
  copyMem(addr rgbaPixels[0], convertedSurface.pixels, rgbaPixels.len)
  SDL_DestroySurface(convertedSurface)

  var textureId: GLuint
  glGenTextures(1, addr textureId)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, textureId)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, textureWidth.GLsizei, textureHeight.GLsizei,
               0, GL_RGBA, GL_UNSIGNED_BYTE, addr rgbaPixels[0])

  objectConfig.setUniforms([cast[uint32](1.0'f32), cast[uint32](0.0'f32)], vusVertex)
  var timer = 0.0'f32
  var fragmentUniforms = [cast[uint32](timer)]
  glViewport(0, 0, 800.GLsizei, 600.GLsizei)
  glClearColor(0.07'f32, 0.08'f32, 0.12'f32, 1.0'f32)
  vm.prepareVariants([objectConfig])
  vm.prepareGlslVmObject(objectConfig)

  while running:
    app.eventLoop(SDLEventRouter)

    # Quit on Escape
    if app.isKeyJustPressed(CKey_Escape):
      running = false

    timer += 0.016'f32
    fragmentUniforms[0] = cast[uint32](timer)
    objectConfig.setUniforms(fragmentUniforms, vusFragment)

    glClear(GL_COLOR_BUFFER_BIT)
    vm.runVm(objectConfig)
    objectConfig.bindGlslVmObject()
    glDrawArrays(GL_TRIANGLES, 0, positions.len.GLsizei)
    discard SDL_GL_SwapWindow(win.handle)

  win.quitWindow()
  glDeleteTextures(1, addr textureId)
  objectConfig.destroyGlslVmObject()
  app.quitSDL3App()
  SDL_Quit_proc()

triangle()

