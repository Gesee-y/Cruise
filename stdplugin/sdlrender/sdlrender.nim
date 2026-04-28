## sdl3_renderer.nim
##
## Top-level SDL3 2D Renderer — the single import for end-users.
##
## What this provides:
##   CSDLRenderer       — the concrete renderer type (CRenderer[SDLData])
##   SDLRenderGraph    — render-graph wrapper pre-wired to the SDL3 backend
##   initCSDLRenderer   — create window + SDL context + renderer
##   Standard draw API — DrawPoint2D, DrawLine2D, DrawRect2D, etc.
##   Extended draw API — DrawCircleAdv, DrawRoundRect, DrawPolygon,
##                       DrawTexturedQuad, DrawGeometry
##   Texture API       — loadTexture, createRenderTarget, releaseTexture
##   Post-process API  — addPostProcessEffect (per render target)
##   Graph API         — addRenderPass, executeFrame
##   Frame API         — beginFrame, endFrame, teardown

import ../../externalLibs/sdl3_nim/src/sdl3_nim
import std/[options, sets, tables, os, hashes]

## Pull in the entire existing render infrastructure
import ../../src/render/render

## Render graph (must load before `backend.nim` — callbacks reference `RenderResource`)
import ../rendergraph/core
import ../../src/la/La

## SDL3 backend modules
include "types.nim"
include "math3d.nim"
include "texture_pool.nim"
include "geometry_batcher.nim"
include "postprocess.nim"
include "backend.nim"

# ---------------------------------------------------------------------------
# Render graph backend callbacks (`RenderResource` lives in rendergraph/core)
# ---------------------------------------------------------------------------

template sdlOnAllocate*(data: var SDLData): AllocateCallback =
  let onAlloc = proc (res: var RenderResource) =
    if res.name in data.rgTextures:
      let entry = data.rgTextures[res.name]
      res.backingPtr = data.pool.rawPtr(entry.key)
      return

    var desc: SDLTextureDesc


    if res.desc.access == 0:
      desc = staticTextureDesc(int(res.desc.width), int(res.desc.height))
    elif res.desc.access == 1:
      desc = streamingTextureDesc(int(res.desc.width), int(res.desc.height))
    else:
      desc = renderTargetDesc(int(res.desc.width), int(res.desc.height))
    let key  = data.pool.allocTransient(desc, res.name)
    data.rgTextures[res.name] = SDLTextureEntry(key: key, desc: desc)
    res.backingPtr = data.pool.rawPtr(key)
  
  onAlloc

template sdlOnRelease*(data: var SDLData): ReleaseCallback =
  let onRelease = proc (res: var RenderResource) =
    if sets.contains(data.externalGraphTextures, res.name):
      data.rgTextures.del(res.name)
      res.backingPtr = nil
      return
    if res.name in data.rgTextures:
      let entry = data.rgTextures[res.name]
      data.pool.release(entry.key)
      data.rgTextures.del(res.name)
    res.backingPtr = nil

  onRelease

template sdlOnAlias*(data: var SDLData): AliasCallback =
  let onAlias = proc (canonical: var RenderResource, alias: var RenderResource) =
    alias.backingPtr = canonical.backingPtr
    if canonical.name in data.rgTextures:
      let canonEntry = data.rgTextures[canonical.name]
      data.rgTextures[alias.name] = canonEntry
      data.pool.addRef(canonEntry.key)
  
  onAlias

template sdlOnTransition*(data: var SDLData): TransitionCallback =
  let onTransition = proc (res: var RenderResource,
                    fromState, toState: RenderResourceState) =
    if fromState == rsColorWrite and toState == rsShaderRead:
      data.flushBatcher()
  onTransition

proc sdlExecuteAll*(ren: var CSDLRenderer, cb: var CommandBuffer) =
  ## Dispatch all recorded commands in pass order.
  var data = ren.data
  let dataPtr = cast[pointer](ren)
  for pass in data.passOrder():
    #echo pass
    for h in cb.sortedHandles(pass):
      h.process(dataPtr)
  data.flushBatcher()


# ===========================================================================
# SDLRenderGraph — wires SDL callbacks into the generic RenderGraph
# ===========================================================================

type SDLRenderGraph* = object
  rg*:  RenderGraph
  ren*: ptr CSDLRenderer   ## borrowed reference — must outlive the graph

proc initSDLRenderGraph*(ren: var CSDLRenderer): SDLRenderGraph =
  ## Build a render graph pre-wired to the given CSDLRenderer's backend.
  let data = addr ren.data
  result.rg = initRenderGraph(
    onAllocate   = sdlOnAllocate(data[]),
    onRelease    = sdlOnRelease(data[]),
    onTransition = sdlOnTransition(data[]),
    onAlias      = sdlOnAlias(data[])
  )
  result.ren = addr ren

proc addRenderPass*(srg: var SDLRenderGraph,
                    pass:   RenderPassNode,
                    reads:  seq[int] = @[],
                    writes: seq[int] = @[],
                    deps:   seq[int] = @[]): int =
  srg.rg.addRenderPass(pass, reads, writes, deps)

proc addRenderResource*(srg: var SDLRenderGraph,
                         res: RenderResource): int =
  srg.rg.addRenderResource(res)

proc setBackbuffer*(srg: var SDLRenderGraph, id: int) =
  srg.rg.setBackbuffer(id)

proc executeFrame*(srg: var SDLRenderGraph) =
  ## Dispatches graph passes; `executeAll` targets `SDLData` (same as `endFrame` on `ren.data`).
  srg.rg.executeFrame(srg.ren[])

proc teardown*(srg: var SDLRenderGraph) =
  srg.rg.teardown()

# ===========================================================================
# Render graph ↔ texture pool bridge
# ===========================================================================
#
# Call `bindRenderGraphTexture` **before** the first `executeFrame` that allocates
# the named `RenderResource`, so `onAllocate` reuses your `TextureKey` instead of
# creating a second SDL texture. Graph `onRelease` skips destroying the pool slot
# for bound names (you keep ownership via `releaseTexture`).

proc bindRenderGraphTexture*(ren: var CSDLRenderer, resourceName: string, key: TextureKey) =
  let desc = ren.data.pool.desc(key)
  ren.data.rgTextures[resourceName] = SDLTextureEntry(key: key, desc: desc)
  ren.data.externalGraphTextures.incl(resourceName)

proc lookupGraphTexture*(ren: CSDLRenderer, resourceName: string): TextureKey =
  if not tables.contains(ren.data.rgTextures, resourceName):
    raise newException(KeyError, "lookupGraphTexture: unknown resource \"" & resourceName & "\"")
  ren.data.rgTextures[resourceName].key

proc tryLookupGraphTexture*(ren: CSDLRenderer, resourceName: string): Option[TextureKey] =
  if not tables.contains(ren.data.rgTextures, resourceName):
    return none(TextureKey)
  some(ren.data.rgTextures[resourceName].key)

# ===========================================================================
# Renderer lifecycle
# ===========================================================================

proc initSDLRenderer*(window: ptr SDL_Window, vsync: bool = true): CSDLRenderer =
  if window == nil:
    raise newException(ValueError, "La fenêtre fournie est nil")

  let sdlRen = SDL_CreateRenderer(window, nil)
  if sdlRen == nil:
    raise newException(IOError, "SDL_CreateRenderer failed: " & $SDL_GetError())

  discard SDL_SetRenderVSync(sdlRen, if vsync: 1 else: 0)

  var w, h: cint
  discard SDL_GetWindowSize(window, addr w, addr h)

  var data = initSDLData(window, sdlRen, int(w), int(h))
  var ren = initCRenderer[SDLData](data)

  ren.data.scrTypeId = registerType[SDLData, uint32](ren)
  ren.executeAll = sdlExecuteAll
  ren.data.screenKey = TextureKey(0)

  result = ren

proc initSDLRenderer*(title:     string  = "SDL3 Renderer",
                       width:     int     = 1280,
                       height:    int     = 720,
                       vsync:     bool    = true,
                       highDpi:   bool    = false): CSDLRenderer =
  ## Initialize SDL3, create window and renderer, return a fully ready CSDLRenderer.
  if not SDL_Init(SDL_INIT_VIDEO or SDL_INIT_EVENTS):
    raise newException(IOError, "SDL_Init failed: " & $SDL_GetError())

  var flags = SDL_WINDOW_RESIZABLE
  if highDpi: flags = flags or SDL_WINDOW_HIGH_PIXEL_DENSITY

  let window = SDL_CreateWindow(title.cstring, cint(width), cint(height), flags)
  if window == nil:
    raise newException(IOError, "SDL_CreateWindow failed: " & $SDL_GetError())

  return initSDLRenderer(window, vsync)

# ---------------------------------------------------------------------------
# screenTarget accessor (required by the command push helpers)
# ---------------------------------------------------------------------------

proc screenTarget*(ren: CSDLRenderer): CResource[Screen] {.inline.} =
  ## Returns the handle for the screen render target.
  ## Commands pushed with this target go directly to the backbuffer.
  CResource[Screen](uint64(ren.data.scrTypeId) shl TypeIdShift)

# ===========================================================================
# Frame lifecycle
# ===========================================================================

# Dans commandBuf.nim
proc passOrder*(ren: CSDLRenderer): seq[string] =
  @["render", "postprocess", "composite"]

# ===========================================================================
# executeAll for SDLData (overrides the generic fallback)
# ===========================================================================

proc beginFrame*(ren: var CSDLRenderer) =
  ## Start a new frame: clear, reset stats, flush command buffer.
  ren.data.beginFrameSDL()
  ren.commandBuffer.clearPass("render")
  ren.commandBuffer.clearPass("postprocess")
  ren.commandBuffer.clearPass("composite")

proc endFrame*(rg: var SDLRenderGraph) =
  ## Execute all recorded commands, run post-process, present.
  var ren = rg.ren[]
  #ren.executeAll(ren, rg.rg.cb)
  ren.data.endFrameSDL()

proc endFrame*(ren: var CSDLRenderer) =
  ## Execute all recorded commands, run post-process, present.
  ren.executeAll(ren, ren.commandBuffer)
  ren.data.endFrameSDL()

proc teardown*(ren: var CSDLRenderer) =
  ## Release all SDL resources.
  ren.commandBuffer.destroyAllPasses()
  ren.registry.teardown()
  ren.data.pool.teardown()
  SDL_DestroyRenderer(ren.data.renderer)
  SDL_DestroyWindow(ren.data.window)
  SDL_Quit_proc()

proc stats*(ren: CSDLRenderer): FrameStats {.inline.} =
  ren.data.stats

proc setClearColor*(ren: var CSDLRenderer, r, g, b: uint8, a: uint8 = 255) =
  ren.data.clearColor = rgba(r, g, b, a)

proc setViewport*(ren: var CSDLRenderer, x, y, w, h: float32) =
  ren.data.viewport = viewport(x, y, w, h)
  var vp = SDL_Rect(x: cint(x), y: cint(y), w: cint(w), h: cint(h))
  discard SDL_SetRenderViewport(ren.data.renderer, addr vp)

# ===========================================================================
# Texture management
# ===========================================================================

proc loadTexture*(ren:   var CSDLRenderer,
                  path:  string,
                  sampler = defaultSampler()): TextureKey =
  ## Load an image file and register it as a persistent texture.
  ## Requires SDL3_image (sdl3_image_nim) — add it to your nimble deps.
  var raw: ptr SDL_Surface = nil
  when defined(sdl3Image):
    raw = IMG_Load(path.cstring)
    if raw == nil:
      echo "WARN loadTexture IMG_Load failed, fallback BMP: ", SDL_GetError()
  
  raw = SDL_LoadBMP(path.cstring)   # fallback: BMP without SDL_image
  if raw == nil:
    raise newException(IOError, "loadTexture: " & path & " — " & $SDL_GetError())
  let tex = SDL_CreateTextureFromSurface(ren.data.renderer, raw)
  SDL_DestroySurface(raw)
  if tex == nil:
    raise newException(IOError, "SDL_CreateTextureFromSurface failed: " & $SDL_GetError())
  var w, h: cfloat
  discard SDL_GetTextureSize(tex, addr w, addr h)
  let desc = SDLTextureDesc(width: int(w), height: int(h),
                             format: sdlFmtRGBA8888, access: accessStatic,
                             sampler: sampler)
  result = ren.data.pool.registerExternalPersistent(cast[pointer](tex), desc, path)
  applySampler(ren.data.renderer, tex, sampler)

proc createRenderTarget*(ren:     var CSDLRenderer,
                          width, height: int,
                          sampler = defaultSampler()): TextureKey =
  ## Allocate an off-screen render target texture.
  let desc = renderTargetDesc(width, height, sampler)
  ren.data.pool.allocTransient(desc, "rt_" & $width & "x" & $height)

proc createStreamingTexture*(ren:     var CSDLRenderer,
                          width, height: int,
                          sampler = defaultSampler()): TextureKey =
  ## Allocate an off-screen render target texture.
  let desc = streamingTextureDesc(width, height, sampler)
  ren.data.pool.allocTransient(desc, "rt_" & $width & "x" & $height)


proc releaseTexture*(ren: var CSDLRenderer, key: TextureKey) =
  ren.data.pool.release(key)

proc textureSize*(ren: CSDLRenderer, key: TextureKey): tuple[w, h: int] =
  let d = ren.data.pool.desc(key)
  (d.width, d.height)

# ===========================================================================
# Extended drawing commands
# ===========================================================================

proc DrawCircleAdv*[R](
    ren:      var R,
    center:   FPoint,
    radius:   float32,
    color:    SDLRGBA,
    filled:   bool    = true,
    segments: int     = 0,
    thickness: float32 = 1.0,
    priority: uint32  = 0,
    pass:     string   = "render"
) =
  addCommand[DrawCircleAdvCmd, R](ren.commandBuffer,
    0u32, priority, 0u32,
    DrawCircleAdvCmd(center: center, radius: radius, color: color,
                     filled: filled, segments: segments, thickness: thickness),
    pass
  )

proc DrawRoundRect*[R](
    ren:        var R,
    rect:       FRect,
    radius:     float32,
    color:      SDLRGBA,
    filled:     bool  = true,
    cornerSegs: int   = 8,
    priority:   uint32 = 0,
    pass:       string  = "render"
) =
  addCommand[DrawRoundRectCmd, R](ren.commandBuffer,
    0u32, priority, 0u32,
    DrawRoundRectCmd(rect: rect, radius: radius, color: color,
                     filled: filled, cornerSegs: cornerSegs),
    pass
  )

proc DrawPolygon*[R](
    ren:      var R,
    points:   seq[FPoint],
    color:    SDLRGBA,
    filled:   bool    = true,
    thickness: float32 = 1.0,
    priority: uint32  = 0,
    pass:     string   = "render"
) =
  addCommand[DrawPolygonCmd, R](ren.commandBuffer,
    0u32, priority, 0u32,
    DrawPolygonCmd(points: points, color: color, filled: filled, thickness: thickness),
    pass
  )

proc DrawTexturedQuad*[R](
    ren:       var R,
    key:       TextureKey,
    dst:       FRect,
    src:       FRect     = frect(0, 0, 1, 1),
    tint:      SDLRGBA   = SDLRGBA.white,
    angle:     float32   = 0,
    pivot:     FPoint    = fpoint(0.5, 0.5),
    flipH:     bool      = false,
    flipV:     bool      = false,
    blendMode: SDLBlendMode = blendAlpha,
    priority:  uint32    = 0,
    pass:      string     = "render"
) =
  addCommand[DrawTexturedQuadCmd, R](ren.commandBuffer,
    0u32, priority, uint32(key) - 1,
    DrawTexturedQuadCmd(dst: dst, src: src, tint: tint, angle: angle,
                        pivot: pivot, flipH: flipH, flipV: flipV,
                        blendMode: blendMode),
    pass
  )

proc DrawGeometry*[R](
    ren:      var R,
    vertices: seq[Vertex],
    indices:  seq[uint32],
    key:      TextureKey    = InvalidTextureKey,
    blend:    SDLBlendMode  = blendAlpha,
    priority: uint32        = 0,
    pass:     string         = "render"
) =
  addCommand[DrawGeometryCmd, R](ren.commandBuffer,
    0u32, priority, 0u32,
    DrawGeometryCmd(vertices: vertices, indices: indices, texKey: key, blend: blend),
    pass
  )

proc DrawTexturedQuad3D*[R](
    ren:        var R,
    key:        TextureKey,
    mvp:        Mat4,
    world:      array[4, SdlVec3f],
    uv:         array[4, FPoint],
    viewportW:  float32,
    viewportH:  float32,
    tint:       SDLRGBA     = SDLRGBA.white,
    blend:      SDLBlendMode = blendAlpha,
    priority:   uint32      = 0,
    pass:       string      = "render"
) =
  ## Perspective quad in 3D → projected with `mvp`, drawn as a six-index triangle pair.
  let verts = texturedQuadVertices3d(mvp, world, uv, viewportW, viewportH, tint)
  let idx = texturedQuadIndices3d()
  addCommand[DrawGeometryCmd, R](ren.commandBuffer,
    0u32, priority, 0u32,
    DrawGeometryCmd(vertices: verts, indices: idx, texKey: key, blend: blend),
    pass
  )

proc BlitTexture*[R](
    ren:      var R,
    src:      TextureKey,
    dst:      TextureKey       = InvalidTextureKey,
    srcRect:  FRect            = frect(0, 0, 1, 1),
    dstRect:  FRect            = frect(0, 0, 0, 0),   ## 0,0 = full target
    blend:    SDLBlendMode     = blendAlpha,
    tint:     SDLRGBA          = SDLRGBA.white,
    alpha:    float32          = 1.0,
    priority: uint32           = 0,
    pass:     string            = "composite"
) =
  addCommand[BlitTextureCmd, R](ren.commandBuffer,
    0u32, priority, 0u32,
    BlitTextureCmd(srcKey: src, dstKey: dst, srcRect: srcRect, dstRect: dstRect,
                   blend: blend, tint: tint, alpha: alpha),
    pass
  )

proc AddPostProcess*[R](
    ren:      var R,
    target:   TextureKey,
    effect:   PostProcessEffect,
    priority: uint32 = 0,
    pass:     string  = "postprocess"
) =
  addCommand[PostProcessCmd, R](ren.commandBuffer,
    0u32, priority, 0u32,
    PostProcessCmd(targetKey: target, effects: @[effect]),
    pass
  )

proc PostProcessRT*[R](
    ren:      var R,
    src:      TextureKey,            ## render target (accessTarget)
    dst:      TextureKey,            ## streaming texture (accessStreaming)
    effects:  seq[PostProcessEffect],
    priority: uint32 = 0,
    pass:     string  = "postprocess"
) =
  addCommand[PostProcessRTCmd, R](ren.commandBuffer,
    0u32, priority, 0u32,
    PostProcessRTCmd(srcKey: src, dstKey: dst, effects: effects),
    pass)

proc ClearTarget*[R](
    ren:    var R,
    target: TextureKey,
    color:  SDLRGBA  = SDLRGBA.black,
    pass:   string    = "render"
) =
  addCommand[ClearTargetCmd, R](ren.commandBuffer,
    0u32, 0u32, 0u32,
    ClearTargetCmd(targetKey: target, color: color),
    pass
  )

proc PushRenderTarget*[R](
    ren:    var R,
    target: TextureKey,
    pass:   string = "render"
) =
  addCommand[PushTargetCmd, R](ren.commandBuffer,
    0u32, 0u32, 0u32,
    PushTargetCmd(targetKey: target),
    pass
  )

proc PopRenderTarget*[R](ren: var R, pass: string = "render") =
  addCommand[PopTargetCmd, R](ren.commandBuffer,
    0u32, 0u32, 0u32,
    PopTargetCmd(dummy: 0u8),
    pass
  )

# ===========================================================================
# Event polling helpers (thin wrappers — keep SDL3 out of user code)
# ===========================================================================

type
  EventKind* = enum
    evQuit, evKeyDown, evKeyUp, evMouseMove, evMouseDown, evMouseUp,
    evMouseWheel, evWindowResize, evOther

  InputEvent* = object
    case kind*: EventKind
    of evKeyDown, evKeyUp:
      scancode*: int
      sym*:      int
      mods*:     uint16
    of evMouseMove:
      mx*, my*: float32
      dx*, dy*: float32
    of evMouseDown, evMouseUp:
      button*: uint8
      clicks*: uint8
      px*, py*: float32
    of evMouseWheel:
      wx*, wy*: float32
    of evWindowResize:
      newW*, newH*: int
    of evQuit, evOther:
      discard

proc pollEvents*(ren: var CSDLRenderer): seq[InputEvent] =
  ## Poll all pending SDL events and return them as backend-agnostic InputEvents.
  result = @[]
  var e: SDL_Event
  while SDL_PollEvent(addr e):
    case uint32(e.type_field)
    of uint32(SDL_EVENT_QUIT):
      result.add InputEvent(kind: evQuit)
    of uint32(SDL_EVENT_KEY_DOWN):
      result.add InputEvent(kind: evKeyDown,
        scancode: int(e.key.scancode),
        sym:      int(e.key.key),
        mods:     uint16(e.key.mod_field))
    of uint32(SDL_EVENT_KEY_UP):
      result.add InputEvent(kind: evKeyUp,
        scancode: int(e.key.scancode),
        sym:      int(e.key.key),
        mods:     uint16(e.key.mod_field))
    of uint32(SDL_EVENT_MOUSE_MOTION):
      result.add InputEvent(kind: evMouseMove,
        mx: e.motion.x, my: e.motion.y,
        dx: e.motion.xrel, dy: e.motion.yrel)
    of uint32(SDL_EVENT_MOUSE_BUTTON_DOWN):
      result.add InputEvent(kind: evMouseDown,
        button: e.button.button, clicks: e.button.clicks,
        px: e.button.x, py: e.button.y)
    of uint32(SDL_EVENT_MOUSE_BUTTON_UP):
      result.add InputEvent(kind: evMouseUp,
        button: e.button.button, clicks: e.button.clicks,
        px: e.button.x, py: e.button.y)
    of uint32(SDL_EVENT_MOUSE_WHEEL):
      result.add InputEvent(kind: evMouseWheel,
        wx: e.wheel.x, wy: e.wheel.y)
    of uint32(SDL_EVENT_WINDOW_RESIZED):
      result.add InputEvent(kind: evWindowResize,
        newW: int(e.window.data1), newH: int(e.window.data2))
    else:
      result.add InputEvent(kind: evOther)

# ===========================================================================
# SSAA helper — render at 2× size, downscale to output
# ===========================================================================

proc createSSAATarget*(ren: var CSDLRenderer,
                        outputW, outputH: int,
                        scale:  int = 2): tuple[hiRes, loRes: TextureKey] =
  ## Create a 2× (or N×) render target for SSAA, plus the output target.
  ## Workflow:
  ##   1. Render scene onto `hiRes`
  ##   2. AddPostProcess(ren, hiRes, PostProcessEffect(kind: ppSSAA, ssaaScale: scale))
  ##   3. BlitTexture(ren, hiRes, loRes)   — SDL scales down during blit
  ##   4. BlitTexture(ren, loRes, screen)
  let hiRes = ren.createRenderTarget(outputW * scale, outputH * scale,
                                      pixelArtSampler())
  let loRes = ren.createRenderTarget(outputW, outputH, defaultSampler())
  (hiRes, loRes)

# ===========================================================================
# Anisotropic hint
# ===========================================================================

proc setAnisotropy*(ren: var CSDLRenderer, key: TextureKey, level: uint8) =
  ## Apply SDL3 anisotropy hint to a texture.
  ## SDL3 maps this through hints — effectiveness depends on the GPU driver.
  let raw  = ren.data.pool.rawPtr(key)
  if raw == nil: return
  let tex  = cast[ptr SDL_Texture](raw)
  discard SDL_SetTextureScaleMode(tex, SDL_SCALEMODE_LINEAR_enumval)
  discard SDL_SetHint("SDL_HINT_RENDER_SCALE_QUALITY",
                      if level >= 8: "2".cstring else: "1".cstring)

# ===========================================================================
# Debug overlay
# ===========================================================================

proc drawDebugStats*(ren: var CSDLRenderer, x, y: float32) =
  ## Print frame stats as simple text using SDL_RenderDebugText (SDL3.1+).
  let s = ren.data.stats
  let lines = [
    "Frame: "     & $int(s.frameTimeMs)     & " ms",
    "DrawCalls: " & $s.drawCalls,
    "Triangles: " & $s.triangleCount,
    "Batches: "   & $s.batchedPrimitives,
    "RTSwitch: "  & $s.renderTargetSwitches,
    "PostFX: "    & $s.postProcessPasses,
  ]
  var iy = y
  for line in lines:
    discard SDL_RenderDebugText(ren.data.renderer, x, iy, line.cstring)
    iy += 16.0
