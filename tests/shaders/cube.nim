import std/[os, math, random, times]
import ../../../../Github/Cruise/src/windows/windows
import ../../../../Github/Cruise/stdplugin/sdlwin/sdlwin
import ../../../../Github/Cruise/src/la/LA
import ../../externalModule/opengl/src/opengl
import ../../src/CVM/vms/glsl33
import ../../src/CVM/vms/object_config
import shader_setup

type
  Vec3 = object
    x, y, z: float32

proc triangle() =
  let app = initSDL3App()
  let appDir = getAppDir()
  let vertexBytecode = readBytecode(appDir / "deps" / "cube_vert.cbc")
  let fragmentBytecode = readBytecode(appDir / "deps" / "cube_frag.cbc")

  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3)
  discard SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE)
  discard SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
  discard SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24)

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 1 — Simple Window", width=800, height=600, gl=true)

  var ctx = SDL_GL_CreateContext(win.handle)
  defer: SDL_GL_DestroyContext(ctx)
  loadExtensions()
  var vm = initGlslVm()
  defer: vm.destroy()
  var objectConfig = initVmShaderConfig(vertexBytecode, fragmentBytecode)
    
  # Connection to the close notifier: when the close button is clicked
  var running = true
  NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
    if ev.kind == WINDOW_CLOSE:
      running = false

  var fov = 55.0'f32
  var pitch = 0.0'f32
  var yaw = 0.0'f32

  NOTIF_MOUSE_WHEEL.connect do(win: CWindow, ev: MouseWheelEvent):
    fov -= float32(ev.ywheel) * 2.5'f32
    if fov < 10.0'f32: fov = 10.0'f32
    if fov > 100.0'f32: fov = 100.0'f32

  NOTIF_MOUSE_MOTION.connect do(win: CWindow, ev: MouseMotionEvent):
    let dx = clamp(float32(ev.xrel), -80.0'f32, 80.0'f32)
    let dy = clamp(float32(ev.yrel), -80.0'f32, 80.0'f32)
    yaw += dx * 0.003'f32
    pitch -= dy * 0.003'f32
    const maxPitch = 1.5'f32
    if pitch > maxPitch: pitch = maxPitch
    if pitch < -maxPitch: pitch = -maxPitch

  type VertexPosition = array[3, GLfloat]
  let positions: array[24, VertexPosition] = [
    # Front face
    [-0.5f, -0.5f,  0.5f],
    [ 0.5f, -0.5f,  0.5f],
    [ 0.5f,  0.5f,  0.5f],
    [-0.5f,  0.5f,  0.5f],
    # Back face
    [-0.5f, -0.5f, -0.5f],
    [-0.5f,  0.5f, -0.5f],
    [ 0.5f,  0.5f, -0.5f],
    [ 0.5f, -0.5f, -0.5f],
    # Top face
    [-0.5f,  0.5f, -0.5f],
    [-0.5f,  0.5f,  0.5f],
    [ 0.5f,  0.5f,  0.5f],
    [ 0.5f,  0.5f, -0.5f],
    # Bottom face
    [-0.5f, -0.5f, -0.5f],
    [ 0.5f, -0.5f, -0.5f],
    [ 0.5f, -0.5f,  0.5f],
    [-0.5f, -0.5f,  0.5f],
    # Right face
    [ 0.5f, -0.5f, -0.5f],
    [ 0.5f,  0.5f, -0.5f],
    [ 0.5f,  0.5f,  0.5f],
    [ 0.5f, -0.5f,  0.5f],
    # Left face
    [-0.5f, -0.5f, -0.5f],
    [-0.5f, -0.5f,  0.5f],
    [-0.5f,  0.5f,  0.5f],
    [-0.5f,  0.5f, -0.5f]
  ]
  let texCoords: array[24, array[2, GLfloat]] = [
    # Front
    [0.0f, 0.0f], [1.0f, 0.0f], [1.0f, 1.0f], [0.0f, 1.0f],
    # Back
    [1.0f, 0.0f], [1.0f, 1.0f], [0.0f, 1.0f], [0.0f, 0.0f],
    # Top
    [0.0f, 1.0f], [0.0f, 0.0f], [1.0f, 0.0f], [1.0f, 1.0f],
    # Bottom
    [1.0f, 1.0f], [0.0f, 1.0f], [0.0f, 0.0f], [1.0f, 0.0f],
    # Right
    [1.0f, 0.0f], [1.0f, 1.0f], [0.0f, 1.0f], [0.0f, 0.0f],
    # Left
    [0.0f, 0.0f], [1.0f, 0.0f], [1.0f, 1.0f], [0.0f, 1.0f]
  ]

  let indices: array[36, uint32] = [
     0u32,  1,  2,  0,  2,  3, # Front
     4u32,  5,  6,  4,  6,  7, # Back
     8u32,  9, 10,  8, 10, 11, # Top
    12u32, 13, 14, 12, 14, 15, # Bottom
    16u32, 17, 18, 16, 18, 19, # Right
    20u32, 21, 22, 20, 22, 23  # Left
  ]
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
  objectConfig.setTexture(0, rgbaPixels, textureWidth, textureHeight)
  SDL_DestroySurface(convertedSurface)

  var vertexUniforms: array[16, uint32]
  var timer = 0.0'f32
  var fragmentUniforms = [cast[uint32](timer)]
  vm.configure(objectConfig)
  var indexBuffer: GLuint
  glGenBuffers(1, addr indexBuffer)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer)
  glBufferData(GL_ELEMENT_ARRAY_BUFFER,
    (indices.len * sizeof(uint32)).GLsizeiptr, unsafeAddr indices[0], GL_STATIC_DRAW)

  # Randomized 3D distribution for 36 cubes
  type
    CubeConfig = object
      basePos: Vec3
      speedX, speedY, speedZ: float32
      phase: float32
      scale: float32
      orbitRadius: float32
      orbitSpeed: float32

  var cubes: array[36, CubeConfig]
  var rng = initRand(20261114)
  const pi32 = float32(PI)
  for i in 0 ..< 36:
    let theta = rng.rand(0.0'f32 .. 2.0'f32 * pi32)
    let phi = rng.rand(-pi32 * 0.4'f32 .. pi32 * 0.4'f32)
    let rad = rng.rand(2.5'f32 .. 8.0'f32)
    let bx = rad * cos(phi) * cos(theta)
    let by = rad * sin(phi)
    let bz = rad * cos(phi) * sin(theta) * 0.8'f32

    cubes[i] = CubeConfig(
      basePos: Vec3(x: bx, y: by, z: bz),
      speedX: rng.rand(0.4'f32 .. 2.2'f32),
      speedY: rng.rand(0.5'f32 .. 2.5'f32),
      speedZ: rng.rand(0.2'f32 .. 1.5'f32),
      phase: rng.rand(0.0'f32 .. 2.0'f32 * pi32),
      scale: rng.rand(0.35'f32 .. 0.85'f32),
      orbitRadius: rng.rand(0.2'f32 .. 0.9'f32),
      orbitSpeed: rng.rand(0.5'f32 .. 2.2'f32)
    )

  var camPos = Vec3(x: 0.0'f32, y: 0.0'f32, z: 12.0'f32)
  var frameCount = 0
  var lastFpsTime = epochTime()

  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LESS)

  glViewport(0, 0, 800.GLsizei, 600.GLsizei)
  glClearColor(0.07'f32, 0.08'f32, 0.12'f32, 1.0'f32)

  while running:
    app.eventLoop(SDLEventRouter)

    # FPS counter update (every 0.5s)
    inc frameCount
    let now = epochTime()
    let elapsed = now - lastFpsTime
    if elapsed >= 0.5:
      let currentFps = float64(frameCount) / elapsed
      let frameMs = 1000.0 / currentFps
      win.setWindowTitle("CVM 3D Cubes - FPS: " & $int(currentFps) & " (" & $(round(frameMs, 1)) & " ms)")
      frameCount = 0
      lastFpsTime = now

    # Quit on Escape
    if app.isKeyJustPressed(CKey_Escape):
      running = false

    # Camera movement: WASD oriented with camera yaw, QE for vertical (Y)
    let moveSpeed = 0.15'f32
    let sinY = sin(yaw)
    let cosY = cos(yaw)
    let fwdX = sinY
    let fwdZ = -cosY
    let rgtX = cosY
    let rgtZ = sinY

    if app.isKeyPressed(CKey_W):
      camPos.x += fwdX * moveSpeed
      camPos.z += fwdZ * moveSpeed
    if app.isKeyPressed(CKey_S):
      camPos.x -= fwdX * moveSpeed
      camPos.z -= fwdZ * moveSpeed
    if app.isKeyPressed(CKey_D):
      camPos.x += rgtX * moveSpeed
      camPos.z += rgtZ * moveSpeed
    if app.isKeyPressed(CKey_A):
      camPos.x -= rgtX * moveSpeed
      camPos.z -= rgtZ * moveSpeed
    if app.isKeyPressed(CKey_E):
      camPos.y += moveSpeed
    if app.isKeyPressed(CKey_Q):
      camPos.y -= moveSpeed

    timer += 0.016'f32
    fragmentUniforms[0] = cast[uint32](timer)
    objectConfig.setUniforms(fragmentUniforms, vusFragment)

    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    let aspect = 800.0'f32 / 600.0'f32
    let proj = mat4Perspective(degToRad(fov), aspect, 0.1'f32, 100.0'f32)
    let front = Vec3(
      x: cos(pitch) * sin(yaw),
      y: sin(pitch),
      z: -cos(pitch) * cos(yaw)
    )
    let center = Vec3(
      x: camPos.x + front.x,
      y: camPos.y + front.y,
      z: camPos.z + front.z
    )
    let up = Vec3(x: 0.0'f32, y: 1.0'f32, z: 0.0'f32)
    let view = mat4LookAt(camPos, center, up)

    for i in 0 ..< 36:
      let c = cubes[i]
      let rotX = timer * c.speedX + c.phase
      let rotY = timer * c.speedY + c.phase
      let rotZ = timer * c.speedZ

      let dynX = c.basePos.x + cos(timer * c.orbitSpeed + c.phase) * c.orbitRadius
      let dynY = c.basePos.y + sin(timer * (c.orbitSpeed * 1.3'f32) + c.phase) * c.orbitRadius
      let dynZ = c.basePos.z + sin(timer * c.orbitSpeed + c.phase) * (c.orbitRadius * 0.6'f32)

      let model = mat4Translate(Vec3(x: dynX, y: dynY, z: dynZ)) *
                  mat4RotateZ(rotZ) * mat4RotateY(rotY) * mat4RotateX(rotX) *
                  mat4Scale(c.scale)
      let mvp = proj * view * model

      for j in 0 ..< 16:
        vertexUniforms[j] = cast[uint32](mvp.m[j])

      objectConfig.setUniforms(vertexUniforms, vusVertex)
      vm.runVm(objectConfig)
      glDrawElements(GL_TRIANGLES, indices.len.GLsizei, GL_UNSIGNED_INT, nil)

    discard SDL_GL_SwapWindow(win.handle)

  glDeleteBuffers(1, addr indexBuffer)
  win.quitWindow()
  app.quitSDL3App()
  SDL_Quit_proc()

triangle()

