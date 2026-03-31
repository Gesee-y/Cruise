## sdl3/backend.nim
##
## SDL3 concrete backend.
##
## Implements:
##   SDLData          — the backend state blob stored inside CRenderer[SDLData]
##   executeCommand   — overloads for every command type
##   passOrder        — render → postprocess → composite
##   screenTarget     — the default render target
##
## Render Graph integration:
##   SDLRenderGraph   — thin wrapper that binds the SDL3 backend callbacks
##                      (onAllocate, onRelease, onTransition, onAlias) to
##                      the generic RenderGraph from core.nim.
##
## Frame flow (two-phase):
##   1. Record phase  — user pushes commands via CRenderer helpers.
##                      Commands are queued, no SDL calls happen.
##   2. Execute phase — executeFrame drains the render graph level by level,
##                      calls executeAll which dispatches to executeCommand.
##                      executeCommand feeds geometry into GeometryBatcher.
##                      At flush points, flushBatcher submits SDL_RenderGeometry.

import ../../externalLibs/sdl3_nim/src/sdl3_nim
import ../../src/render/render
import std/[algorithm, sets, tables, math, times]
import ./types
import ./texture_pool
import ./geometry_batcher
import ./postprocess

# ---------------------------------------------------------------------------
# TextureRegistry entry — what the render graph resource maps to
# ---------------------------------------------------------------------------

type
  SDLTextureEntry* = object
    key*:    TextureKey      ## index into TexturePool
    desc*:   SDLTextureDesc  ## cached descriptor

# ---------------------------------------------------------------------------
# SDLData — backend state
# ---------------------------------------------------------------------------

type
  SDLData* = ref object
    ## All SDL3 backend state. Stored as `CRenderer[SDLData].data`.

    # SDL3 handles
    window*:   ptr SDL_Window
    renderer*: ptr SDL_Renderer

    # Resource management
    pool*:     TexturePool
    pp*:       PostProcessPipeline

    # Geometry batching
    batcher*:  GeometryBatcher

    # Render target stack (for nested begin/end render-target pairs)
    targetStack*: seq[TextureKey]

    # Screen (backbuffer) key — special; not in pool, use nil raw ptr
    screenKey*: TextureKey

    # Registered resource types (for the CRenderer registry)
    scrTypeId*: TypeId

    # Render graph resource map: RenderResource name → SDLTextureEntry
    rgTextures*: Table[string, SDLTextureEntry]
    ## Names bound with `bindRenderGraphTexture` — pool not freed by graph `onRelease`.
    externalGraphTextures*: HashSet[string]

    # Viewport
    viewport*: Viewport

    # Stats
    stats*: FrameStats
    frameStart*: float64

    # Configuration
    clearColor*: SDLRGBA
    defaultSampler*: SamplerDesc

# ---------------------------------------------------------------------------
# SDLData constructor
# ---------------------------------------------------------------------------

proc initSDLData*(window: ptr SDL_Window,
                  renderer: ptr SDL_Renderer,
                  width, height: int): SDLData =
  ## Create the backend data. Call after SDL_CreateRenderer.

  proc allocTex(desc: SDLTextureDesc): pointer =
    let access = case desc.access
      of accessStatic:    SDL_TEXTUREACCESS_STATIC
      of accessStreaming:  SDL_TEXTUREACCESS_STREAMING
      of accessTarget:    SDL_TEXTUREACCESS_TARGET
    let fmt = SDL_PIXELFORMAT_RGBA8888  # always RGBA8 for now
    result = cast[pointer](SDL_CreateTexture(renderer, fmt, access,
                                              cint(desc.width), cint(desc.height)))
    if result == nil:
      raise newException(IOError, "SDL_CreateTexture failed: " & $SDL_GetError())
    # Apply scale mode
    let tex = cast[ptr SDL_Texture](result)
    case desc.sampler.scaleMode
    of scaleNearest: discard SDL_SetTextureScaleMode(tex, SDL_SCALEMODE_NEAREST_enumval)
    of scaleLinear:  discard SDL_SetTextureScaleMode(tex, SDL_SCALEMODE_LINEAR_enumval)
    of scaleBest:    discard SDL_SetTextureScaleMode(tex, SDL_SCALEMODE_PIXELART)
    # Apply blend mode
    let blm = case desc.sampler.blendMode
      of blendNone:     SDL_BLENDMODE_NONE
      of blendAlpha:    SDL_BLENDMODE_BLEND
      of blendAdditive: SDL_BLENDMODE_ADD
      of blendModulate: SDL_BLENDMODE_MOD
      of blendMul:      SDL_BLENDMODE_MUL
    discard SDL_SetTextureBlendMode(tex, blm)

  proc freeTex(raw: pointer) =
    SDL_DestroyTexture(cast[ptr SDL_Texture](raw))

  # Post-process lock/unlock callbacks
  proc lockTex(raw: pointer, pb: var PixelBuffer) =
    let tex   = cast[ptr SDL_Texture](raw)
    var w, h: cfloat
    discard SDL_GetTextureSize(tex, addr w, addr h)
    pb = initPixelBuffer(int(w), int(h))
    var pixels: pointer
    var pitch:  cint
    discard SDL_LockTexture(tex, nil, addr pixels, addr pitch)
    pb.pitch = int(pitch)
    # Copy pixel data into pb.pixels (row by row in case pitch != w*4)
    let rowBytes = int(w) * 4
    for row in 0 ..< int(h):
      let src = cast[ptr UncheckedArray[uint8]](cast[int](pixels) + row * int(pitch))
      let dst = cast[ptr UncheckedArray[uint8]](addr pb.pixels[row * int(w)])
      copyMem(dst, src, rowBytes)
    SDL_UnlockTexture(tex)

  proc unlockTex(raw: pointer, pb: PixelBuffer) =
    let tex = cast[ptr SDL_Texture](raw)
    # Re-upload: lock again in streaming mode, copy pb → pixels
    var pixels: pointer
    var pitch:  cint
    discard SDL_LockTexture(tex, nil, addr pixels, addr pitch)
    let rowBytes = pb.width * 4
    for row in 0 ..< pb.height:
      let src = cast[ptr UncheckedArray[uint8]](unsafeAddr pb.pixels[row * pb.width])
      let dst = cast[ptr UncheckedArray[uint8]](cast[int](pixels) + row * int(pitch))
      copyMem(dst, src, rowBytes)
    SDL_UnlockTexture(tex)

  result = SDLData(
    window:        window,
    renderer:      renderer,
    pool:          initTexturePool(allocTex, freeTex),
    pp:            initPostProcessPipeline(lockTex, unlockTex),
    batcher:       initGeometryBatcher(),
    targetStack:   @[],
    rgTextures:    initTable[string, SDLTextureEntry](),
    externalGraphTextures: initHashSet[string](),
    viewport:      viewport(0, 0, float32(width), float32(height)),
    stats:         FrameStats(),
    clearColor:    rgba(0, 0, 0, 255),
    defaultSampler: defaultSampler(),
  )

# ---------------------------------------------------------------------------
# Target management helpers
# ---------------------------------------------------------------------------

proc pushTarget*(data: var SDLData, key: TextureKey) =
  ## Set `key` as the current SDL render target and push it onto the stack.
  data.targetStack.add(key)
  if key == data.screenKey:
    discard SDL_SetRenderTarget(data.renderer, nil)
  else:
    discard SDL_SetRenderTarget(data.renderer,
      cast[ptr SDL_Texture](data.pool.rawPtr(key)))
  inc data.stats.renderTargetSwitches

proc popTarget*(data: var SDLData) =
  ## Restore the previous render target.
  if data.targetStack.len > 0:
    discard data.targetStack.pop()
  let prev = if data.targetStack.len > 0: data.targetStack[^1]
             else: data.screenKey
  if prev == data.screenKey:
    discard SDL_SetRenderTarget(data.renderer, nil)
  else:
    discard SDL_SetRenderTarget(data.renderer,
      cast[ptr SDL_Texture](data.pool.rawPtr(prev)))
  inc data.stats.renderTargetSwitches

proc currentTarget*(data: SDLData): TextureKey =
  if data.targetStack.len > 0: data.targetStack[^1]
  else: data.screenKey

# ---------------------------------------------------------------------------
# Apply sampler state to a texture before drawing
# ---------------------------------------------------------------------------

proc applySampler*(renderer: ptr SDL_Renderer,
                   tex:      ptr SDL_Texture,
                   sampler:  SamplerDesc) =
  let sm = case sampler.scaleMode
    of scaleNearest: SDL_SCALEMODE_NEAREST_enumval
    of scaleLinear:  SDL_SCALEMODE_LINEAR_enumval
    of scaleBest:    SDL_SCALEMODE_LINEAR_enumval
  discard SDL_SetTextureScaleMode(tex, sm)
  let blm = case sampler.blendMode
    of blendNone:     SDL_BLENDMODE_NONE
    of blendAlpha:    SDL_BLENDMODE_BLEND
    of blendAdditive: SDL_BLENDMODE_ADD
    of blendModulate: SDL_BLENDMODE_MOD
    of blendMul:      SDL_BLENDMODE_MUL
  discard SDL_SetTextureBlendMode(tex, blm)

# ---------------------------------------------------------------------------
# Geometry flush — submit batcher content to SDL_RenderGeometry
# ---------------------------------------------------------------------------

proc flushBatcher*(data: var SDLData) =
  ## Sort batches, then submit each to SDL_RenderGeometry.
  ## Called at end of each pass or when changing render target.
  if data.batcher.batches.len == 0: return
  data.batcher.sort()

  var lastTarget = InvalidTextureKey

  for batch in data.batcher.batches:
    if batch.vertices.len == 0: continue

    # Switch render target if needed
    if batch.targetKey != lastTarget:
      if batch.targetKey == data.screenKey:
        discard SDL_SetRenderTarget(data.renderer, nil)
      else:
        discard SDL_SetRenderTarget(data.renderer,
          cast[ptr SDL_Texture](data.pool.rawPtr(batch.targetKey)))
      lastTarget = batch.targetKey
      inc data.stats.renderTargetSwitches

    # Set blend mode on renderer
    let sdlBlend = case batch.blendMode
      of blendNone:     SDL_BLENDMODE_NONE
      of blendAlpha:    SDL_BLENDMODE_BLEND
      of blendAdditive: SDL_BLENDMODE_ADD
      of blendModulate: SDL_BLENDMODE_MOD
      of blendMul:      SDL_BLENDMODE_MUL
    discard SDL_SetRenderDrawBlendMode(data.renderer, sdlBlend)

    # Build SDL_Vertex array from our Vertex
    var sdlVerts = newSeq[SDL_Vertex](batch.vertices.len)
    for i, v in batch.vertices:
      sdlVerts[i].position.x = v.pos.x
      sdlVerts[i].position.y = v.pos.y
      sdlVerts[i].color.r    = float32(v.color.r) / 255.0
      sdlVerts[i].color.g    = float32(v.color.g) / 255.0
      sdlVerts[i].color.b    = float32(v.color.b) / 255.0
      sdlVerts[i].color.a    = float32(v.color.a) / 255.0
      sdlVerts[i].tex_coord.x = v.uv.x
      sdlVerts[i].tex_coord.y = v.uv.y

    # Indices
    var sdlIdx = newSeq[cint](batch.indices.len)
    for i, idx in batch.indices:
      sdlIdx[i] = cint(idx)

    let texPtr = if batch.textureKey == InvalidTextureKey: nil
                 else: cast[ptr SDL_Texture](data.pool.rawPtr(batch.textureKey))

    inc data.stats.textureBinds
    if texPtr != nil:
      applySampler(data.renderer, texPtr, data.pool.entry(batch.textureKey).desc.sampler)

    let ok = SDL_RenderGeometry(
      data.renderer, texPtr,
      cast[ptr SDL_Vertex](addr sdlVerts[0]), cint(sdlVerts.len),
      cast[ptr cint](addr sdlIdx[0]), cint(sdlIdx.len)
    )
    if not ok:
      echo "SDL_RenderGeometry error: ", SDL_GetError()

    inc data.stats.drawCalls
    data.stats.batchedPrimitives += batch.indices.len div 3
    data.stats.triangleCount     += batch.indices.len div 3

  data.batcher.clear()

# ---------------------------------------------------------------------------
# executeCommand overloads — called by executeAll from CommandBuffer
#
# Note: the renderer pointer in BatchHandle is CRenderer[SDLData]*,
# but since we define executeCommand for SDLData directly we cast accordingly.
# ---------------------------------------------------------------------------

# We need the CRenderer wrapper in scope
# (imported by sdl3_renderer.nim that includes this file)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawPoint2DCmd]) =
  for cmd in batch.commands:
    let color = rgba(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
    data.batcher.emitPoint(fpoint(cmd.pos.x, cmd.pos.y), color,
                            data.currentTarget(), blendAlpha)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawLine2DCmd]) =
  for cmd in batch.commands:
    let color = rgba(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
    data.batcher.emitLine(fpoint(cmd.start.x, cmd.start.y),
                           fpoint(cmd.stop.x,  cmd.stop.y),
                           color, data.currentTarget(), blendAlpha)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawRect2DCmd]) =
  for cmd in batch.commands:
    let color = rgba(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
    data.batcher.emitRect(
      frect(cmd.rect.x1, cmd.rect.y1, cmd.rect.x2 - cmd.rect.x1,
                                       cmd.rect.y2 - cmd.rect.y1),
      color, data.currentTarget(), blendAlpha, cmd.filled)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawCircle2DCmd]) =
  for cmd in batch.commands:
    let color = rgba(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
    data.batcher.emitCircle(fpoint(cmd.center.x, cmd.center.y),
                             cmd.radius, color, data.currentTarget(),
                             blendAlpha, cmd.filled)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawTexture2DCmd]) =
  ## Recover the source texture key from the batch caller compressed handle.
  let texIdx = decompressIndex(batch.caller)
  let texKey  = TextureKey(texIdx + 1)   # pool uses key = slot+1
  for cmd in batch.commands:
    let w = cmd.rect.x2 - cmd.rect.x1
    let h = cmd.rect.x4 - cmd.rect.x3
    let dst = frect(cmd.rect.x1, cmd.rect.x3, w, h)
    let px = if w > 1e-6f: (cmd.center.x - cmd.rect.x1) / w else: 0.5f
    let py = if h > 1e-6f: (cmd.center.y - cmd.rect.x3) / h else: 0.5f
    let pivot = fpoint(px, py)
    let src = frect(0, 0, 1, 1)
    data.batcher.emitTexturedQuad(dst, src, texKey, data.currentTarget(),
                                   blendAlpha,
                                   tint = SDLRGBA.white,
                                   angle = cmd.angle,
                                   pivot = pivot,
                                   flipH = cmd.flipH,
                                   flipV = cmd.flipV)

# ---------------------------------------------------------------------------
# SDL3 extended commands (defined further below)
# ---------------------------------------------------------------------------

type
  ## Draw a circle with advanced params (radius, filled, segments, thickness)
  DrawCircleAdvCmd* = object
    center*:    FPoint
    radius*:    float32
    color*:     SDLRGBA
    filled*:    bool
    segments*:  int
    thickness*: float32
commandAction DrawCircleAdvCmd

type
  ## Draw a rounded rectangle
  DrawRoundRectCmd* = object
    rect*:        FRect
    radius*:      float32
    color*:       SDLRGBA
    filled*:      bool
    cornerSegs*:  int
commandAction DrawRoundRectCmd

type
  ## Draw an arbitrary convex polygon
  DrawPolygonCmd* = object
    points*:    seq[FPoint]
    color*:     SDLRGBA
    filled*:    bool
    thickness*: float32
commandAction DrawPolygonCmd

type
  ## Draw a textured quad with full control (sampler, tint, UV, angle, flip)
  DrawTexturedQuadCmd* = object
    dst*:        FRect
    src*:        FRect    ## UV rect [0,1]
    tint*:       SDLRGBA
    angle*:      float32
    pivot*:      FPoint
    flipH*:      bool
    flipV*:      bool
    blendMode*:  types.SDLBlendMode
    samplerKey*: uint32   ## index into sampler table (0 = default)
commandAction DrawTexturedQuadCmd

type
  ## A raw geometry triangle batch (per-vertex color + UV)
  DrawGeometryCmd* = object
    vertices*: seq[Vertex]
    indices*:  seq[uint32]
    texKey*:   TextureKey
    blend*:    types.SDLBlendMode
commandAction DrawGeometryCmd

type
  ## Post-process request: apply effects to a texture before composite
  PostProcessCmd* = object
    targetKey*: TextureKey
    effects*:   seq[PostProcessEffect]
commandAction PostProcessCmd

type
  ## GPU-assisted blit: copy texture A → texture B with optional scale/blend
  BlitTextureCmd* = object
    srcKey*:    TextureKey
    dstKey*:    TextureKey   ## InvalidTextureKey = screen
    srcRect*:   FRect        ## normalized [0,1] source region
    dstRect*:   FRect        ## pixel destination rect
    blend*:     types.SDLBlendMode
    tint*:      SDLRGBA
    alpha*:     float32
commandAction BlitTextureCmd

type
  ## Clear a render target with a color
  ClearTargetCmd* = object
    targetKey*: TextureKey
    color*:     SDLRGBA
commandAction ClearTargetCmd

type
  ## Push/pop the render target stack (for nested passes)
  PushTargetCmd* = object
    targetKey*: TextureKey
commandAction PushTargetCmd

type
  PopTargetCmd* = object
    dummy*: uint8
commandAction PopTargetCmd

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawCircleAdvCmd]) =
  for cmd in batch.commands:
    data.batcher.emitCircle(cmd.center, cmd.radius, cmd.color,
                             data.currentTarget(), blendAlpha,
                             cmd.filled, cmd.thickness, cmd.segments)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawRoundRectCmd]) =
  for cmd in batch.commands:
    data.batcher.emitRoundedRect(cmd.rect, cmd.radius, cmd.color,
                                  data.currentTarget(), blendAlpha,
                                  cmd.filled, cmd.cornerSegs)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawPolygonCmd]) =
  for cmd in batch.commands:
    data.batcher.emitPolygon(cmd.points, cmd.color, data.currentTarget(),
                              blendAlpha, cmd.filled, cmd.thickness)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawTexturedQuadCmd]) =
  for cmd in batch.commands:
    let texIdx = decompressIndex(batch.caller)
    let texKey  = TextureKey(texIdx + 1)
    data.batcher.emitTexturedQuad(cmd.dst, cmd.src, texKey,
                                   data.currentTarget(), cmd.blendMode,
                                   cmd.tint, cmd.angle, cmd.pivot,
                                   cmd.flipH, cmd.flipV)

proc executeCommand*(data: var SDLData, batch: RenderBatch[DrawGeometryCmd]) =
  ## Direct geometry injection — bypass the batcher and submit immediately.
  for cmd in batch.commands:
    # Flush existing batcher first to preserve order
    data.flushBatcher()

    var sdlVerts = newSeq[SDL_Vertex](cmd.vertices.len)
    for i, v in cmd.vertices:
      sdlVerts[i].position.x  = v.pos.x
      sdlVerts[i].position.y  = v.pos.y
      sdlVerts[i].color.r     = float32(v.color.r) / 255.0
      sdlVerts[i].color.g     = float32(v.color.g) / 255.0
      sdlVerts[i].color.b     = float32(v.color.b) / 255.0
      sdlVerts[i].color.a     = float32(v.color.a) / 255.0
      sdlVerts[i].tex_coord.x = v.uv.x
      sdlVerts[i].tex_coord.y = v.uv.y

    var sdlIdx = newSeq[cint](cmd.indices.len)
    for i, idx in cmd.indices:
      sdlIdx[i] = cint(idx)

    let texPtr = if cmd.texKey == InvalidTextureKey: nil
                 else: cast[ptr SDL_Texture](data.pool.rawPtr(cmd.texKey))

    let sdlBlend = case cmd.blend
      of blendNone:     SDL_BLENDMODE_NONE
      of blendAlpha:    SDL_BLENDMODE_BLEND
      of blendAdditive: SDL_BLENDMODE_ADD
      of blendModulate: SDL_BLENDMODE_MOD
      of blendMul:      SDL_BLENDMODE_MUL
    discard SDL_SetRenderDrawBlendMode(data.renderer, sdlBlend)

    discard SDL_RenderGeometry(data.renderer, texPtr,
      cast[ptr SDL_Vertex](addr sdlVerts[0]), cint(sdlVerts.len),
      cast[ptr cint](addr sdlIdx[0]), cint(sdlIdx.len))
    inc data.stats.drawCalls

proc executeCommand*(data: var SDLData, batch: RenderBatch[PostProcessCmd]) =
  data.flushBatcher()  # flush geometry before pixel manipulation
  for cmd in batch.commands:
    if cmd.targetKey == InvalidTextureKey: continue
    let raw = data.pool.rawPtr(cmd.targetKey)
    for fx in cmd.effects:
      data.pp.addEffect(raw, fx)
  inc data.stats.postProcessPasses

proc cmpBlitCmd(a, b: BlitTextureCmd): int =
  result = cmp(cast[uint32](a.dstKey), cast[uint32](b.dstKey))
  if result != 0: return
  result = cmp(cast[uint32](a.srcKey), cast[uint32](b.srcKey))
  if result != 0: return
  result = cmp(ord(a.blend), ord(b.blend))

proc executeCommand*(data: var SDLData, batch: RenderBatch[BlitTextureCmd]) =
  data.flushBatcher()
  var cmds = batch.commands
  if cmds.len > 1:
    cmds.sort(cmpBlitCmd)
  for cmd in cmds:
    let srcRaw = if cmd.srcKey == InvalidTextureKey: nil
                 else: cast[ptr SDL_Texture](data.pool.rawPtr(cmd.srcKey))
    if srcRaw == nil: continue

    # Set destination target
    if cmd.dstKey == data.screenKey or cmd.dstKey == InvalidTextureKey:
      discard SDL_SetRenderTarget(data.renderer, nil)
    else:
      discard SDL_SetRenderTarget(data.renderer,
        cast[ptr SDL_Texture](data.pool.rawPtr(cmd.dstKey)))

    let sdlBlend = case cmd.blend
      of blendNone:     SDL_BLENDMODE_NONE
      of blendAlpha:    SDL_BLENDMODE_BLEND
      of blendAdditive: SDL_BLENDMODE_ADD
      of blendModulate: SDL_BLENDMODE_MOD
      of blendMul:      SDL_BLENDMODE_MUL
    discard SDL_SetTextureBlendMode(srcRaw, sdlBlend)
    discard SDL_SetTextureColorMod(srcRaw, cmd.tint.r, cmd.tint.g, cmd.tint.b)
    discard SDL_SetTextureAlphaMod(srcRaw, uint8(cmd.alpha * 255))

    var srcW, srcH: cfloat
    discard SDL_GetTextureSize(srcRaw, addr srcW, addr srcH)

    let sdlSrc = SDL_FRect(
      x: cmd.srcRect.x * float32(srcW),
      y: cmd.srcRect.y * float32(srcH),
      w: cmd.srcRect.w * float32(srcW),
      h: cmd.srcRect.h * float32(srcH)
    )
    let sdlDst = SDL_FRect(x: cmd.dstRect.x, y: cmd.dstRect.y,
                            w: cmd.dstRect.w, h: cmd.dstRect.h)

    discard SDL_RenderTexture(data.renderer, srcRaw,
      unsafeAddr sdlSrc, unsafeAddr sdlDst)
    inc data.stats.drawCalls

proc executeCommand*(data: var SDLData, batch: RenderBatch[ClearTargetCmd]) =
  data.flushBatcher()
  for cmd in batch.commands:
    if cmd.targetKey == data.screenKey or cmd.targetKey == InvalidTextureKey:
      discard SDL_SetRenderTarget(data.renderer, nil)
    else:
      discard SDL_SetRenderTarget(data.renderer,
        cast[ptr SDL_Texture](data.pool.rawPtr(cmd.targetKey)))
    let c = cmd.color
    discard SDL_SetRenderDrawColor(data.renderer, c.r, c.g, c.b, c.a)
    discard SDL_RenderClear(data.renderer)

proc executeCommand*(data: var SDLData, batch: RenderBatch[PushTargetCmd]) =
  data.flushBatcher()
  for cmd in batch.commands:
    data.pushTarget(cmd.targetKey)

proc executeCommand*(data: var SDLData, batch: RenderBatch[PopTargetCmd]) =
  data.flushBatcher()
  for _ in batch.commands:
    data.popTarget()

# ---------------------------------------------------------------------------
# passOrder — controls CommandBuffer dispatch sequence
# ---------------------------------------------------------------------------

proc passOrder*(data: SDLData): seq[string] =
  @["render", "postprocess", "composite"]

# ---------------------------------------------------------------------------
# beginFrame / endFrame for SDLData
# ---------------------------------------------------------------------------

proc beginFrameSDL*(data: var SDLData) =
  data.frameStart = epochTime() * 1000.0
  data.stats       = FrameStats()
  data.pp.clear()
  discard SDL_SetRenderTarget(data.renderer, nil)
  let c = data.clearColor
  discard SDL_SetRenderDrawColor(data.renderer, c.r, c.g, c.b, c.a)
  discard SDL_RenderClear(data.renderer)

proc endFrameSDL*(data: var SDLData) =
  ## 1. Flush any remaining geometry
  data.flushBatcher()
  ## 2. Run CPU post-process effects
  data.pp.run()
  ## 3. Present
  discard SDL_RenderPresent(data.renderer)
  data.stats.frameTimeMs = epochTime() * 1000.0 - data.frameStart

