# SDL3 CRenderer

A **fully batched, render-graph-driven 2D renderer** built on top of the
existing `CRenderer[R]` / `CommandBuffer` / `ResourceRegistry` infrastructure,
targeting **SDL3** via `sdl3_nim`.

---

## Architecture overview

```
User Code
    │
    ▼
CRenderer[SDLData]         ← generic renderer wrapper (render.nim)
    ├─ CommandBuffer        ← typed, sorted command queue (commandBuf.nim)
    ├─ ResourceRegistry     ← typed slot-map for textures/screens (resource.nim)
    └─ SDLData              ← backend state (sdl3/backend.nim)
            ├─ TexturePool          ← allocate / recycle / release SDL_Texture*
            ├─ GeometryBatcher      ← CPU-side vertex/index accumulator
            └─ PostProcessPipeline  ← CPU-side pixel effects + GPU-assisted blits

SDLRenderGraph              ← thin wrapper around RenderGraph (core.nim)
    ├─ RenderPassNode(s)    ← user-defined passes (read/write resources)
    ├─ onAllocate/Release   ← create/recycle SDL render-target textures
    ├─ onAlias              ← reuse larger textures (memory aliasing)
    └─ onTransition         ← flush batcher on ColorWrite→ShaderRead boundary
```

### Frame flow

```
beginFrame()
    │  reset stats, clear SDL, clear CommandBuffer passes
    ▼
SDLRenderGraph.executeFrame()
    │  for each parallel level:
    │    allocate transient textures (onAllocate)
    │    execute pass.execute() → records commands into CommandBuffer
    │    executeAll() → dispatches executeCommand overloads
    │       → feeds GeometryBatcher (points/lines/rects/circles/polygons)
    │       → emits BlitTextureCmd / PostProcessCmd directly
    │    apply transitions (flush batcher on write→read boundary)
    │    release transient textures (onRelease)
    ▼
endFrame()
    │  flush remaining geometry (flushBatcher)
    │  run CPU post-process pipeline (pp.run)
    │  SDL_RenderPresent
```

---

## Files

| File | Purpose |
|---|---|
| `sdl3/types.nim` | All backend types (SDLRGBA, FRect, SamplerDesc, PostProcessEffect, …) |
| `sdl3/texture_pool.nim` | SDL_Texture lifecycle: allocate, recycle, release |
| `sdl3/geometry_batcher.nim` | CPU vertex/index accumulation + batch sorting |
| `sdl3/postprocess.nim` | Software pixel effects (blur, bloom, FXAA, vignette, chroma, grade) |
| `sdl3/backend.nim` | SDLData + all `executeCommand` overloads + render-graph callbacks |
| `sdl3_renderer.nim` | Top-level API: init, draw helpers, texture API, event polling |
| `example.nim` | Full demo: render graph, SSAA, particles, UI, post-process |

---

## Supported primitives

| Command | Description |
|---|---|
| `DrawPoint2D` | Anti-aliased point (quad with configurable size) |
| `DrawLine2D` | Thick anti-aliased line segment |
| `DrawRect2D` | Filled or outlined axis-aligned rectangle |
| `DrawCircle2D` | Filled or outlined circle (standard API) |
| `DrawCircleAdv` | Circle with custom segment count + thickness |
| `DrawRoundRect` | Filled or outlined rounded rectangle |
| `DrawPolygon` | Convex polygon (fan-triangulated or outline) |
| `DrawTexture2D` | Textured quad (standard API) |
| `DrawTexturedQuad` | Full control: UV crop, angle, pivot, flip, blend, tint |
| `DrawGeometry` | Raw vertex/index buffer — arbitrary meshes |
| `BlitTexture` | GPU-accelerated render-target blit with scale/blend |
| `ClearTarget` | Clear a render target with a color |
| `PushRenderTarget` | Push a render target onto the stack |
| `PopRenderTarget` | Restore the previous render target |
| `AddPostProcess` | Schedule CPU effects on a render target |

---

## Post-process effects (CPU-side, no shaders required)

| Effect | Description |
|---|---|
| `ppBlur` | Separable Gaussian blur (configurable radius, sigma, passes) |
| `ppBloom` | Threshold → blur → additive composite |
| `ppSharpen` | Unsharp mask |
| `ppVignette` | Radial darkening |
| `ppChromaticAberr` | RGB channel pixel-shift |
| `ppColorGrade` | Brightness / contrast / saturation / tint |
| `ppFXAA` | Luminance-edge-guided anti-aliasing (3 quality levels) |
| `ppDownscale` | Box-filter or nearest downscale |
| `ppUpscale` | Bilinear upscale (via SDL blit) |
| `ppSSAA` | Render at N×, resolve via SDL_RenderTexture |

Effects are applied in order on each texture's CPU pixel buffer, then
re-uploaded. For production use, consider replacing CPU effects with
SDL3 GPU pipeline when available.

---

## Batching strategy

1. Every draw call is recorded as a command in the `CommandBuffer` — no SDL
   call happens during recording.
2. `executeCommand` overloads feed data into `GeometryBatcher`.
3. `GeometryBatcher` accumulates vertices until the **texture**, **blend mode**,
   or **render target** changes — then it starts a new `Batch`.
4. At flush time (`flushBatcher`), batches are sorted by `(target, texture, blend)`
   and submitted as single `SDL_RenderGeometry` calls.
5. This minimises SDL state changes and driver round-trips.

---

## Render graph integration

The `SDLRenderGraph` wraps the generic `RenderGraph` from `core.nim`:

```nim
var srg = initSDLRenderGraph(ren)

let rtId = srg.addRenderResource(RenderResource(
  name: "MyTarget",
  desc: TextureDesc(width: 1920, height: 1080, format: fmtRGBA8, mips: 1),
  transient: true
))

let passId = srg.addRenderPass(
  RenderPassNode(id: 0, enabled: true,
    execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
      addCommand[DrawRect2DCmd, SDLData](cb, ...)
  ),
  reads  = @[],
  writes = @[rtId]
)

srg.executeFrame()  # topological sort → allocate → execute → release
```

Transient textures are automatically allocated as SDL render targets on first
use and returned to the recycle bin when their lifetime ends. Memory aliasing
(two transients sharing the same SDL texture) is handled via `onAlias`.

---

## SSAA workflow

```nim
ren.PushRenderTarget(hiResKey)
# ... draw scene at 2× resolution ...
ren.PopRenderTarget()

# Downscale into lo-res target
ren.BlitTexture(hiResKey, loResKey,
  srcRect = frect(0,0,1,1),
  dstRect = frect(0,0,W,H),
  blend   = blendNone
)

# Composite lo-res to screen
ren.BlitTexture(loResKey)
```

Or use the helper:

```nim
let (hiRes, loRes) = ren.createSSAATarget(1280, 720, scale = 2)
```

---

## Quick start

```nim
import sdl3_renderer

var ren = initSDLRenderer("My Game", 1280, 720)

while running:
  for ev in ren.pollEvents():
    if ev.kind == evQuit: running = false

  ren.beginFrame()

  ren.DrawRect2D(frect(100, 100, 200, 150), rgba(255, 80, 80, 255), filled = true)
  ren.DrawCircleAdv(fpoint(400, 300), 80, rgba(50, 200, 255, 200), filled = true)
  ren.DrawPolygon(@[fpoint(600,100), fpoint(700,300), fpoint(500,300)],
                   rgba(255, 220, 50, 255))

  ren.endFrame()

ren.teardown()
```
