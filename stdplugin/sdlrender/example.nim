## example.nim
##
## Full demonstration of the SDL3 renderer:
##   - Render graph with custom passes
##   - Off-screen render targets
##   - Geometry batching (points, lines, rects, circles, polygons, rounded rects)
##   - Textured quads with rotation, flip, UV cropping
##   - Post-process effects (blur, bloom, vignette, chromatic aberration, FXAA)
##   - SSAA (render at 2×, downscale)
##   - Custom geometry (per-vertex color triangle mesh)
##   - Multi-pass composite

include "sdl3_renderer.nim"
import std/[math, random]

# ===========================================================================
# Custom render passes (render graph nodes)
# ===========================================================================

## Pass IDs (assigned by addRenderResource / addRenderPass)

var
  ren:  CSDLRenderer
  srg:  SDLRenderGraph
  enableBloom    = true
  enableVignette = true
  enableFXAA     = true
  enableChroma   = false

  ## Off-screen render targets registered as RenderGraph resources
  mainRtId:   int   ## main scene
  uiRtId:     int   ## UI overlay
  ssaaRtId:   int   ## 2× SSAA hi-res
  bloomRtId:  int   ## bloom buffer
  backbufId:  int   ## "backbuffer" node

  ## Actual TextureKeys for direct use
  mainRtKey:     TextureKey
  uiRtKey:       TextureKey
  ssaaRtKey:     TextureKey
  bloomRtKey:    TextureKey
  bloomRtCPUKey: TextureKey

const W  = 1280
const H  = 720
const W2 = W * 2   ## SSAA
const H2 = H * 2

# ---------------------------------------------------------------------------
# Particle demo data
# ---------------------------------------------------------------------------

type Particle = object
  x, y:   float32
  vx, vy: float32
  r:      float32
  color:  SDLRGBA
  life:   float32

var particles: seq[Particle]
var rng = initRand(42)

proc spawnParticle(): Particle =
  Particle(
    x:     float32(rng.rand(W)),
    y:     float32(rng.rand(H)),
    vx:    float32(rng.rand(4.0) - 2.0),
    vy:    float32(rng.rand(4.0) - 2.0),
    r:     float32(rng.rand(8.0) + 2.0),
    color: rgba(uint8(rng.rand(255)), uint8(rng.rand(255)),
                uint8(rng.rand(255)), uint8(rng.rand(200) + 55)),
    life:  float32(rng.rand(120.0) + 30.0)
  )

for _ in 0..200: particles.add spawnParticle()

# ===========================================================================
# Build render graph
# ===========================================================================

proc buildRenderGraph() =
  ssaaRtKey  = ren.createRenderTarget(W2, H2, pixelArtSampler())
  mainRtKey  = ren.createRenderTarget(W, H,   defaultSampler())
  bloomRtKey = ren.createRenderTarget(W, H,   defaultSampler())
  bloomRtCPUKey = ren.createStreamingTexture(W, H,   defaultSampler())
  uiRtKey    = ren.createRenderTarget(W, H,   defaultSampler())

  ## ---- Resources -----------------------------------------------------------

  # SSAA hi-res buffer
  ssaaRtId = srg.addRenderResource(RenderResource(
    name: "SSAA_HiRes",
    desc: TextureDesc(width: uint32(W2), height: uint32(H2), format: fmtRGBA8, mips: 1),
    transient: true
  ))

  # Main scene buffer (low-res output of SSAA)
  mainRtId = srg.addRenderResource(RenderResource(
    name: "MainScene",
    desc: TextureDesc(width: uint32(W), height: uint32(H), format: fmtRGBA8, mips: 1),
    transient: true
  ))

  # Bloom buffer
  bloomRtId = srg.addRenderResource(RenderResource(
    name: "BloomBuf",
    desc: TextureDesc(width: uint32(W), height: uint32(H), format: fmtRGBA8, mips: 1, access: accessStreaming.int),
    transient: true
  ))

  # UI overlay buffer
  uiRtId = srg.addRenderResource(RenderResource(
    name: "UI_Overlay",
    desc: TextureDesc(width: uint32(W), height: uint32(H), format: fmtRGBA8, mips: 1, access: accessStreaming.int),
    transient: true
  ))

  # Backbuffer (not transient — owned by SDL swap chain)
  backbufId = srg.addRenderResource(RenderResource(
    name: "Backbuffer",
    desc: TextureDesc(width: uint32(W), height: uint32(H), format: fmtRGBA8, mips: 1),
    transient: false
  ))
  srg.setBackbuffer(backbufId)

  ## ---- Passes --------------------------------------------------------------

  # Pass 0: ScenePass — render everything onto the SSAA hi-res target
  let scenePass = RenderPassNode(id: 0, enabled: true,
    execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
      # Clear SSAA target
      addCommand[ClearTargetCmd, CSDLRenderer](cb, 0, 0, 0,
        ClearTargetCmd(targetKey: ssaaRtKey, color: rgba(20, 20, 30, 255)),
        "render")
      addCommand[PushTargetCmd, CSDLRenderer](cb, 0, 1, 0,
        PushTargetCmd(targetKey: ssaaRtKey), "render")

      # Background gradient (large filled rect + circles)
      addCommand[DrawRoundRectCmd, CSDLRenderer](cb, 0, 10, 0,
        DrawRoundRectCmd(rect: frect(0, 0, float32(W2), float32(H2)),
                          radius: 0, color: rgba(20, 20, 30, 255), filled: true),
        "render")

      # Particle cloud (circles)
      for p in particles:
        let alpha = uint8(clamp(p.life / 120.0, 0, 1) * float32(p.color.a))
        addCommand[DrawCircleAdvCmd, CSDLRenderer](cb, 0, 20, 0,
          DrawCircleAdvCmd(
            center:   fpoint(p.x * 2, p.y * 2),  # scale to SSAA space
            radius:   p.r * 2,
            color:    rgba(p.color.r, p.color.g, p.color.b, alpha),
            filled:   true,
            segments: 0,
            thickness: 1.0
          ), "render")

      # Some geometry
      addCommand[DrawRect2DCmd, CSDLRenderer](cb, 0, 30, 0,
        DrawRect2DCmd(
          color:  (200u8, 80u8, 80u8, 200u8),
          rect:   (100.0f*2, (100.0f + 200.0f)*2, 100.0f*2, (100.0f + 100.0f)*2),
          filled: true
        ), "render")

      # A line grid
      for i in 0..20:
        let x = float32(i * W2 div 20)
        addCommand[DrawLine2DCmd, CSDLRenderer](cb, 0, 5, 0,
          DrawLine2DCmd(
            color: (50u8, 50u8, 80u8, 100u8),
            start: (x, 0.0f),
            stop:  (x, float32(H2))
          ), "render")
      for i in 0..12:
        let y = float32(i * H2 div 12)
        addCommand[DrawLine2DCmd, CSDLRenderer](cb, 0, 5, 0,
          DrawLine2DCmd(
            color: (50u8, 50u8, 80u8, 100u8),
            start: (0.0f, y),
            stop:  (float32(W2), y)
          ), "render")

      # Star polygon
      var starPts: seq[FPoint]
      let cx = float32(W2) * 0.5; let cy = float32(H2) * 0.5
      for k in 0..9:
        let a = float32(k) * Pi / 5.0 - Pi * 0.5
        let r = if k mod 2 == 0: 200.0f else: 80.0f
        starPts.add fpoint(cx + cos(a)*r, cy + sin(a)*r)
      addCommand[DrawPolygonCmd, CSDLRenderer](cb, 0, 25, 0,
        DrawPolygonCmd(
          points:   starPts,
          color:    rgba(255, 220, 50, 220),
          filled:   true,
          thickness: 3.0
        ), "render")

      addCommand[PopTargetCmd, CSDLRenderer](cb, 0, 100, 0,
        PopTargetCmd(dummy: 0u8), "render")
  )

  let scPass = srg.addRenderPass(scenePass,
    reads  = @[],
    writes = @[ssaaRtId])

  # Pass 1: SSAAResolvePass — downscale SSAA → MainScene using SDL blit
  let ssaaPass = RenderPassNode(id: 1, enabled: true,
    execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
      addCommand[BlitTextureCmd, CSDLRenderer](cb, 0, 0, 0,
        BlitTextureCmd(
          srcKey:  ssaaRtKey,
          dstKey:  mainRtKey,
          srcRect: frect(0, 0, 1, 1),
          dstRect: frect(0, 0, float32(W), float32(H)),
          blend:   blendNone,
          tint:    SDLRGBA.white,
          alpha:   1.0
        ), "composite")
  )
  let sPass = srg.addRenderPass(ssaaPass,
    reads  = @[ssaaRtId],
    writes = @[mainRtId])

  # Pass 2: BloomPass — apply bloom post-process to MainScene → BloomBuf
  let bloomPass = RenderPassNode(id: 2, enabled: true,
    execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
      # Blit main → bloom buffer
      addCommand[BlitTextureCmd, CSDLRenderer](cb, 0, 0, 0,
        BlitTextureCmd(srcKey: mainRtKey, dstKey: bloomRtKey,
                       srcRect: frect(0,0,1,1),
                       dstRect: frect(0,0,float32(W),float32(H)),
                       blend: blendNone, tint: SDLRGBA.white, alpha: 1.0),
        "composite")
      # Schedule bloom effect
      if enableBloom: addCommand[PostProcessRTCmd, CSDLRenderer](cb, 0, 10, 0,
        PostProcessRTCmd(srcKey: bloomRtKey, dstKey: bloomRtCPUKey, effects: @[
          PostProcessEffect(kind: ppBloom, bloom: BloomParams(
            threshold: 0.6,
            intensity: 1.5,
            blur: BlurParams(radius: 8, sigma: 3.0, passes: 2)
          ))
        ]), "postprocess")
      # Add vignette to the bloom buffer
      if enableVignette: addCommand[PostProcessRTCmd, CSDLRenderer](cb, 0, 20, 0,
        PostProcessRTCmd(srcKey: bloomRtKey, dstKey: bloomRtCPUKey, effects: @[
          PostProcessEffect(kind: ppVignette, vignette: VignetteParams(
            strength: 0.6, radius: 0.7, softness: 0.3
          ))
        ]), "postprocess")
      # FXAA on the result
      if enableFXAA: addCommand[PostProcessRTCmd, CSDLRenderer](cb, 0, 30, 0,
        PostProcessRTCmd(srcKey: bloomRtKey, dstKey: bloomRtCPUKey, effects: @[
          PostProcessEffect(kind: ppFXAA, fxaaQuality: 1)
        ]), "postprocess")
  )
  let bpass = srg.addRenderPass(bloomPass,
    deps = @[scPass],
    reads  = @[mainRtId],
    writes = @[bloomRtId])

  # Pass 3: UIPass — draw UI elements on a separate overlay
  let uiPass = RenderPassNode(id: 3, enabled: true,
    execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
      addCommand[ClearTargetCmd, CSDLRenderer](cb, 0, 0, 0,
        ClearTargetCmd(targetKey: uiRtKey, color: rgba(0,0,0,0)), "render")
      addCommand[PushTargetCmd, CSDLRenderer](cb, 0, 1, 0,
        PushTargetCmd(targetKey: uiRtKey), "render")

      # HUD panel (rounded rect)
      addCommand[DrawRoundRectCmd, CSDLRenderer](cb, 0, 10, 0,
        DrawRoundRectCmd(
          rect: frect(20, 20, 200, 80), radius: 12,
          color: rgba(0, 0, 0, 160), filled: true
        ), "render")
      addCommand[DrawRoundRectCmd, CSDLRenderer](cb, 0, 11, 0,
        DrawRoundRectCmd(
          rect: frect(20, 20, 200, 80), radius: 12,
          color: rgba(100, 200, 255, 180), filled: false
        ), "render")

      # Health bar
      addCommand[DrawRect2DCmd, CSDLRenderer](cb, 0, 15, 0,
        DrawRect2DCmd(color: (60u8, 60u8, 60u8, 200u8),
                      rect: (30.0f, 150.0f+30.0f, 30.0f+160.0f, 150.0f+30.0f+20.0f),
                      filled: true), "render")
      addCommand[DrawRect2DCmd, CSDLRenderer](cb, 0, 16, 0,
        DrawRect2DCmd(color: (80u8, 220u8, 80u8, 220u8),
                      rect: (30.0f, 150.0f+30.0f, 30.0f+110.0f, 150.0f+30.0f+20.0f),
                      filled: true), "render")

      addCommand[PopTargetCmd, CSDLRenderer](cb, 0, 100, 0,
        PopTargetCmd(dummy: 0u8), "render")
  )
  let uPass = srg.addRenderPass(uiPass,
    reads  = @[],
    writes = @[uiRtId])

  # Pass 4: CompositePass — merge bloom + UI → screen
  let compositePass = RenderPassNode(id: 4, enabled: true,
    execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
      # Bloom layer (base)
      addCommand[BlitTextureCmd, CSDLRenderer](cb, 0, 0, 0,
        BlitTextureCmd(
          srcKey:  bloomRtCpuKey,
          dstKey:  InvalidTextureKey,  # screen
          srcRect: frect(0, 0, 1, 1),
          dstRect: frect(0, 0, float32(W), float32(H)),
          blend:   blendNone,
          tint:    SDLRGBA.white,
          alpha:   1.0
        ), "composite")

      # UI layer on top (alpha blend)
      addCommand[BlitTextureCmd, CSDLRenderer](cb, 0, 1, 0,
        BlitTextureCmd(
          srcKey:  uiRtKey,
          dstKey:  InvalidTextureKey,
          srcRect: frect(0, 0, 1, 1),
          dstRect: frect(0, 0, float32(W), float32(H)),
          blend:   blendAlpha,
          tint:    SDLRGBA.white,
          alpha:   1.0
        ), "composite")
  )
  let cpassId = srg.addRenderPass(compositePass,
    deps = @[uPass, scPass],
    reads  = @[bloomRtId, uiRtId],
    writes = @[backbufId])

# ===========================================================================
# Main loop
# ===========================================================================

when isMainModule:

  randomize()

  ren = initSDLRenderer("SDL3 CRenderer Demo", W, H, vsync = true)
  srg = initSDLRenderGraph(ren)

  # Build textures (graph allocates them on first executeFrame)
  buildRenderGraph()

  # After the first compile, grab the TextureKeys from the pool
  # (the graph allocates them on first frame; we mirror them here)
  # Note: in a real project you'd look these up from the rgTextures table.
  # For the demo we allocate manually so we have keys for command recording.
  #mainRtKey  = ren.createRenderTarget(W, H,   defaultSampler()) 

  #ren.bindRenderGraphTexture("SSAA_HiRes", ssaaRtKey)
  #ren.bindRenderGraphTexture("MainScene",  mainRtKey)
  #ren.bindRenderGraphTexture("BloomBuf",   bloomRtKey)
  #ren.bindRenderGraphTexture("UI_Overlay", uiRtKey)

  var running  = true
  var frame    = 0
  var t        = 0.0f

  echo "SDL3 CRenderer running. Press ESC to quit."
  echo "Keys: B=toggle bloom, V=toggle vignette, F=toggle FXAA, C=chromatic aberration"

  while running:

    ## ---- Events ----
    for ev in ren.pollEvents():
      case ev.kind
      of evQuit:
        running = false
      of evKeyDown:
        case ev.scancode
        of 41: running = false   ## ESC
        of 5:  enableBloom    = not enableBloom     ## B
        of 25: enableVignette = not enableVignette  ## V
        of 9:  enableFXAA     = not enableFXAA      ## F
        of 6:  enableChroma   = not enableChroma    ## C
        else: discard
      else: discard

    ## ---- Update particles ----
    t += 0.016f
    for p in particles.mitems:
      p.x += p.vx;  p.y += p.vy
      p.life -= 1
      if p.life <= 0 or p.x < 0 or p.x > W or p.y < 0 or p.y > H:
        p = spawnParticle()

    ## ---- Render ----
    ren.beginFrame()

    ## Use the render graph for structured multi-pass rendering
    srg.executeFrame()

    ## Direct draw (bypasses graph — goes to screen directly after composite)
    ## Useful for immediate-mode overlays that don't need a separate target.
    ren.DrawCircleAdv(
      center   = fpoint(float32(W) * 0.5 + cos(t) * 150,
                         float32(H) * 0.5 + sin(t) * 150),
      radius   = 30,
      color    = rgba(255, 100, 50, 200),
      filled   = true
    )

    ## Debug stats overlay
    ren.drawDebugStats(W.float32 - 200, 10)

    ren.endFrame()
    inc frame

  ## ---- Cleanup ----
  srg.teardown()
  ren.releaseTexture(ssaaRtKey)
  ren.releaseTexture(mainRtKey)
  ren.releaseTexture(bloomRtKey)
  ren.releaseTexture(uiRtKey)
  ren.teardown()

  echo "Ran ", frame, " frames. Bye!"
#[
when isMainModule:
  randomize()
  ren = initSDLRenderer("SDL3 CRenderer Demo", W, H, vsync = true)

  # Allouer les targets AVANT tout
  ssaaRtKey  = ren.createRenderTarget(W2, H2, pixelArtSampler())
  mainRtKey  = ren.createRenderTarget(W,  H,  defaultSampler())
  #bloomRtKey = ren.createStreamingTexture(W, H, defaultSampler())
  uiRtKey    = ren.createRenderTarget(W, H, defaultSampler())

  var running = true
  var t = 0.0f
  var frame = 0

  while running:
    for ev in ren.pollEvents():
      if ev.kind == evQuit: running = false
      if ev.kind == evKeyDown and ev.scancode == 41: running = false

    t += 0.016f
    for p in particles.mitems:
      p.x += p.vx; p.y += p.vy
      p.life -= 1
      if p.life <= 0 or p.x < 0 or p.x > W or p.y < 0 or p.y > H:
        p = spawnParticle()

    ren.beginFrame()

    # 1. Dessiner la scène sur ssaaRtKey
    ren.ClearTarget(ssaaRtKey, rgba(20, 20, 30, 255))
    ren.PushRenderTarget(ssaaRtKey)

    # Grille
    for i in 0..20:
      let x = float32(i * W2 div 20)
      ren.DrawLine2D(rgba(50,50,80,100).toVec, fpoint(x, 0), fpoint(x, float32(H2)))
    for i in 0..12:
      let y = float32(i * H2 div 12)
      ren.DrawLine2D(rgba(50,50,80,100).toVec, fpoint(0, y), fpoint(float32(W2), y))

    # Particules
    for p in particles:
      let alpha = uint8(clamp(p.life / 120.0, 0.0, 1.0) * float32(p.color.a))
      ren.DrawCircleAdv(fpoint(p.x*2, p.y*2), p.r*2,
                        rgba(p.color.r, p.color.g, p.color.b, alpha), filled=true)

    # Étoile
    var starPts: seq[FPoint]
    let cx = float32(W2)*0.5; let cy = float32(H2)*0.5
    for k in 0..9:
      let a = float32(k) * Pi / 5.0 - Pi*0.5
      let r = if k mod 2 == 0: 200.0f else: 80.0f
      starPts.add fpoint(cx + cos(a)*r, cy + sin(a)*r)
    ren.DrawPolygon(starPts, rgba(255,220,50,220), filled=true)

    ren.PopRenderTarget()

    # 2. Downscale SSAA → mainRtKey
    ren.BlitTexture(ssaaRtKey, mainRtKey,
                    srcRect=frect(0,0,1,1),
                    dstRect=frect(0,0,float32(W),float32(H)),
                    blend=blendNone, pass="composite")

    # 3. Bloom sur mainRtKey → bloomRtKey
    #ren.BlitTexture(mainRtKey, bloomRtKey,
    #                srcRect=frect(0,0,1,1),
    #                dstRect=frect(0,0,float32(W),float32(H)),
    #                blend=blendNone, pass="composite")
    #ren.AddPostProcess(bloomRtKey, PostProcessEffect(kind: ppBloom,
    #  bloom: BloomParams(threshold: 0.6, intensity: 1.5,
    #                     blur: BlurParams(radius: 8, sigma: 3.0, passes: 2))))
    #ren.AddPostProcess(bloomRtKey, PostProcessEffect(kind: ppVignette,
    #  vignette: VignetteParams(strength: 0.6, radius: 0.7, softness: 0.3)))

    # 4. UI sur uiRtKey
    ren.ClearTarget(uiRtKey, rgba(0,0,0,0))
    ren.PushRenderTarget(uiRtKey)
    ren.DrawRoundRect(frect(20,20,200,80), 12.0, rgba(0,0,0,160), filled=true)
    ren.DrawRoundRect(frect(20,20,200,80), 12.0, rgba(100,200,255,180), filled=false)
    # Barre de vie
    ren.DrawRect2D(rgba(60,60,60,200).toVec, frect(30,180,160,20).toRect, filled=true)
    ren.DrawRect2D(rgba(80,220,80,220).toVec, frect(30,180,110,20).toRect, filled=true)
    ren.PopRenderTarget()

    # 5. Composite → écran
    #ren.BlitTexture(bloomRtKey, InvalidTextureKey,
    #                srcRect=frect(0,0,1,1),
    #                dstRect=frect(0,0,float32(W),float32(H)),
    #                blend=blendNone, pass="composite")
    ren.BlitTexture(uiRtKey, InvalidTextureKey,
                    srcRect=frect(0,0,1,1),
                    dstRect=frect(0,0,float32(W),float32(H)),
                    blend=blendAlpha, pass="composite")

    # 6. Disque animé direct (toujours sur écran)
    ren.DrawCircleAdv(
      fpoint(float32(W)*0.5 + cos(t)*150, float32(H)*0.5 + sin(t)*150),
      30, rgba(255,100,50,200), filled=true)

    ren.drawDebugStats(float32(W)-200, 10)
    ren.endFrame()
    inc frame

  ren.releaseTexture(ssaaRtKey)
  ren.releaseTexture(mainRtKey)
  #ren.releaseTexture(bloomRtKey)
  ren.releaseTexture(uiRtKey)
  ren.teardown()
  echo "Ran ", frame, " frames."
]#