import ../../../../Github/Cruise/src/windows/windows
import ../../../../Github/Cruise/stdplugin/sdlwin/sdlwin
import ../../externalModule/opengl/src/opengl

proc triangle() =
  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 1 — Simple Window", width=800, height=600)
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1)
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE)

  # Connection to the close notifier: when the close button is clicked
  var running = true
  NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
    if ev.kind == WINDOW_CLOSE:
      running = false

  var buffs: GLuint
  let vertices = [-0.5f, -0.5f, 0.0f,
                  0.5f, -0.5f, 0.0f,
                  0.0f, 0.5f, 0.0f
                ]
  glGenBuffers(1, addr buffs)
  glBindBuffer(GL_ARRAY_BUFFER, buffs)
  glBufferData(GL_ARRAY_BUFFER, sizeof(float32)*vertices.len, vertices, GL_STATIC_DRAW)
  let shader = loadShaderBytecode("deps/triangle_vert.cbc")

  while running:
    app.eventLoop(SDLEventRouter)

    # Quit on Escape
    if app.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()

triangle()