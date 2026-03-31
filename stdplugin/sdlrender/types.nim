## sdl3/types.nim
##
## All SDL3 backend-specific types live here.
## No SDL3 import — just Nim types that mirror SDL3 C structs and enums.
## The actual sdl3_nim bindings are imported only in sdl3_backend.nim.

# ---------------------------------------------------------------------------
# TextureKey — a stable, opaque integer handle
# ---------------------------------------------------------------------------

import hashes
type TextureKey* = distinct uint32

const InvalidTextureKey* = TextureKey(0)

proc `==`*(a, b: TextureKey): bool {.borrow.}
proc `$`*(k: TextureKey): string = "Tex#" & $uint32(k)
proc hash*(k: TextureKey): Hash = hash(uint32(k))

# ---------------------------------------------------------------------------
# Pixel formats (mirrors SDL_PixelFormat subset)
# ---------------------------------------------------------------------------

type
  SDLPixelFormat* = enum
    sdlFmtUnknown     = 0
    sdlFmtRGBA8888    = 0x16462004'i32
    sdlFmtBGRA8888    = 0x16262004'i32
    sdlFmtRGB888      = 0x16161804'i32
    sdlFmtARGB8888    = 0x16362004'i32

# ---------------------------------------------------------------------------
# Blend modes (mirrors SDL_BlendMode)
# ---------------------------------------------------------------------------

type
  SDLBlendMode* = enum
    blendNone     = 0x00000000
    blendAlpha    = 0x00000001   ## src*A + dst*(1-A)
    blendAdditive = 0x00000002   ## src*A + dst
    blendModulate = 0x00000004   ## dst*src
    blendMul      = 0x00000008   ## src*dst + dst*(1-srcA)

# ---------------------------------------------------------------------------
# Scale / filter quality
# ---------------------------------------------------------------------------

type
  SDLScaleMode* = enum
    scaleNearest  = 0   ## No filtering — pixel-art
    scaleLinear   = 1   ## Bilinear interpolation
    scaleBest     = 2   ## Anisotropic when available (SDL3 hint)

# ---------------------------------------------------------------------------
# Flip flags
# ---------------------------------------------------------------------------

type
  SDLFlipMode* = enum
    flipNone       = 0
    flipHorizontal = 1
    flipVertical   = 2
    flipBoth       = 3

# ---------------------------------------------------------------------------
# Texture access modes (mirrors SDL_TextureAccess)
# ---------------------------------------------------------------------------

type
  SDLTextureAccess* = enum
    accessStatic    = 0   ## Changes rarely, not lockable
    accessStreaming  = 1   ## Changes frequently, lockable
    accessTarget    = 2   ## Can be used as render target

# ---------------------------------------------------------------------------
# Draw primitive types
# ---------------------------------------------------------------------------

type
  SDLPrimitiveType* = enum
    primPoint
    primLine
    primLineStrip
    primTriangle
    primTriangleStrip
    primPolygon

# ---------------------------------------------------------------------------
# Color (RGBA8)
# ---------------------------------------------------------------------------

type
  SDLRGBA* = object
    r*, g*, b*, a*: uint8

proc rgba*(r, g, b: uint8, a: uint8 = 255): SDLRGBA {.inline.} =
  SDLRGBA(r: r, g: g, b: b, a: a)

proc white*(_: typedesc[SDLRGBA]):   SDLRGBA = rgba(255,255,255)
proc black*(_: typedesc[SDLRGBA]):   SDLRGBA = rgba(0,0,0)
proc red*(_: typedesc[SDLRGBA]):     SDLRGBA = rgba(255,0,0)
proc green*(_: typedesc[SDLRGBA]):   SDLRGBA = rgba(0,255,0)
proc blue*(_: typedesc[SDLRGBA]):    SDLRGBA = rgba(0,0,255)
proc transparent*(_: typedesc[SDLRGBA]): SDLRGBA = rgba(0,0,0,0)

# ---------------------------------------------------------------------------
# 2D rectangle (float)
# ---------------------------------------------------------------------------

type
  FRect* = object
    x*, y*, w*, h*: float32

proc frect*(x, y, w, h: float32): FRect {.inline.} =
  FRect(x: x, y: y, w: w, h: h)

proc contains*(r: FRect, px, py: float32): bool {.inline.} =
  px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h

proc intersects*(a, b: FRect): bool {.inline.} =
  not (a.x + a.w < b.x or b.x + b.w < a.x or
       a.y + a.h < b.y or b.y + b.h < a.y)

# ---------------------------------------------------------------------------
# 2D point (float)
# ---------------------------------------------------------------------------

type
  FPoint* = object
    x*, y*: float32

proc fpoint*(x, y: float32): FPoint {.inline.} = FPoint(x: x, y: y)

# ---------------------------------------------------------------------------
# Vertex — used for geometry batching
# ---------------------------------------------------------------------------

type
  Vertex* = object
    pos*:   FPoint   ## world-space position
    uv*:    FPoint   ## texture UV (0..1)
    color*: SDLRGBA  ## per-vertex tint

proc vertex*(x, y: float32,
             u, v: float32 = 0,
             r, g, b, a: uint8 = 255): Vertex =
  Vertex(pos: fpoint(x, y), uv: fpoint(u, v), color: rgba(r, g, b, a))

# ---------------------------------------------------------------------------
# Viewport
# ---------------------------------------------------------------------------

type
  Viewport* = object
    x*, y*:      float32
    width*:      float32
    height*:     float32
    minDepth*:   float32  ## always 0 for 2D
    maxDepth*:   float32  ## always 1 for 2D

proc viewport*(x, y, w, h: float32): Viewport =
  Viewport(x: x, y: y, width: w, height: h, minDepth: 0, maxDepth: 1)

# ---------------------------------------------------------------------------
# Sampler / filter descriptor
# ---------------------------------------------------------------------------

type
  SamplerDesc* = object
    scaleMode*:   SDLScaleMode
    blendMode*:   SDLBlendMode
    wrapU*:       bool      ## true = repeat, false = clamp
    wrapV*:       bool
    anisotropy*:  uint8     ## 0 = off, 1..16 = aniso level (hint)

proc defaultSampler*(): SamplerDesc =
  SamplerDesc(scaleMode: scaleLinear, blendMode: blendAlpha,
              wrapU: false, wrapV: false, anisotropy: 0)

proc pixelArtSampler*(): SamplerDesc =
  SamplerDesc(scaleMode: scaleNearest, blendMode: blendAlpha,
              wrapU: false, wrapV: false, anisotropy: 0)

proc additiveSampler*(): SamplerDesc =
  SamplerDesc(scaleMode: scaleLinear, blendMode: blendAdditive,
              wrapU: false, wrapV: false, anisotropy: 0)

# ---------------------------------------------------------------------------
# Texture descriptor (what the backend allocates)
# ---------------------------------------------------------------------------

type
  SDLTextureDesc* = object
    width*, height*: int
    format*:         SDLPixelFormat
    access*:         SDLTextureAccess
    sampler*:        SamplerDesc

proc renderTargetDesc*(w, h: int,
                        sampler = defaultSampler()): SDLTextureDesc =
  SDLTextureDesc(width: w, height: h, format: sdlFmtRGBA8888,
                 access: accessTarget, sampler: sampler)

proc staticTextureDesc*(w, h: int,
                         sampler = defaultSampler()): SDLTextureDesc =
  SDLTextureDesc(width: w, height: h, format: sdlFmtRGBA8888,
                 access: accessStatic, sampler: sampler)

# ---------------------------------------------------------------------------
# Postprocess effect descriptor
# ---------------------------------------------------------------------------

type
  PostProcessKind* = enum
    ppNone
    ppBlur             ## Gaussian blur
    ppBloom            ## Threshold → blur → composite
    ppSharpen          ## Unsharp mask
    ppVignette         ## Radial darkening
    ppChromaticAberr   ## RGB channel split
    ppColorGrade       ## Curve / LUT tint
    ppFXAA             ## Fast approximate anti-aliasing (software)
    ppUpscale          ## Nearest/bilinear upscale to output size
    ppDownscale        ## Box/Lanczos downscale
    ppSSAA             ## Resolve SSAA (render at 2×, blit down)
    ppCustom           ## User-supplied shader-equivalent proc

  BlurParams* = object
    radius*: int       ## kernel half-width in pixels
    sigma*:  float32   ## gaussian sigma; 0 = auto (radius/3)
    passes*: int       ## multi-pass (horizontal + vertical each pass)

  BloomParams* = object
    threshold*:  float32   ## luminance cutoff
    intensity*:  float32   ## bloom strength multiplier
    blur*:       BlurParams

  ColorGradeParams* = object
    brightness*: float32   ## 1 = identity
    contrast*:   float32   ## 1 = identity
    saturation*: float32   ## 1 = identity
    tintR*:      float32
    tintG*:      float32
    tintB*:      float32

  VignetteParams* = object
    strength*:   float32   ## 0..1
    radius*:     float32   ## 0..1 normalized screen radius
    softness*:   float32   ## feather

  ChromaParams* = object
    offsetR*: FPoint
    offsetB*: FPoint

  ScaleParams* = object
    targetW*, targetH*: int
    filter*: SDLScaleMode

  PostProcessEffect* = object
    case kind*: PostProcessKind
    of ppBlur:           blur*:        BlurParams
    of ppBloom:          bloom*:       BloomParams
    of ppSharpen:        sharpenAmt*:  float32
    of ppVignette:       vignette*:    VignetteParams
    of ppChromaticAberr: chroma*:      ChromaParams
    of ppColorGrade:     colorGrade*:  ColorGradeParams
    of ppFXAA:           fxaaQuality*: int   ## 0=low 1=med 2=high
    of ppUpscale:        upscale*:     ScaleParams
    of ppDownscale:      downscale*:   ScaleParams
    of ppSSAA:           ssaaScale*:   int   ## 2 = 2×SSAA
    of ppCustom:         customTag*:   string
    of ppNone:           discard

# ---------------------------------------------------------------------------
# Statistics / debug counters
# ---------------------------------------------------------------------------

type
  FrameStats* = object
    drawCalls*:       int
    batchedPrimitives*: int
    textureBinds*:    int
    renderTargetSwitches*: int
    postProcessPasses*: int
    triangleCount*:   int
    frameTimeMs*:     float64
