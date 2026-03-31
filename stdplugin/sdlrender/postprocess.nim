## sdl3/postprocess.nim
##
## Software post-process effects applied to SDL_Texture render targets.
##
## Architecture:
##   - Each PostProcessEffect has a corresponding `apply` overload that takes
##     a PixelBuffer (CPU-side pixel data) and mutates it in place.
##   - The PostProcessPipeline holds a list of effects and drives
##     lock → apply → unlock for each texture that needs processing.
##   - For effects that need GPU help (upscale, SSAA resolve), the pipeline
##     emits SDL_RenderTexture calls through the batcher instead of touching
##     pixels directly.
##
## Why CPU-side?
##   SDL3 has no programmable shader pipeline in its 2D API.
##   Effects that must be done purely with SDL draw calls (scale, copy) are
##   separated into the "gpu-assisted" path.

import std/[math, algorithm, sequtils]
import ./types

# ---------------------------------------------------------------------------
# PixelBuffer — CPU-side RGBA8 pixel array (matches SDL_LockTexture output)
# ---------------------------------------------------------------------------

type
  PixelBuffer* = object
    pixels*: seq[uint32]   ## packed RGBA8 (same byte order as SDL surface)
    width*:  int
    height*: int
    pitch*:  int           ## bytes per row (may have padding)

proc initPixelBuffer*(w, h: int): PixelBuffer =
  PixelBuffer(pixels: newSeq[uint32](w * h), width: w, height: h, pitch: w * 4)

proc getPixel*(pb: PixelBuffer, x, y: int): SDLRGBA {.inline.} =
  let p = pb.pixels[y * pb.width + x]
  SDLRGBA(r: uint8(p shr 24), g: uint8((p shr 16) and 0xFF),
          b: uint8((p shr 8) and 0xFF), a: uint8(p and 0xFF))

proc setPixel*(pb: var PixelBuffer, x, y: int, c: SDLRGBA) {.inline.} =
  pb.pixels[y * pb.width + x] =
    (uint32(c.r) shl 24) or (uint32(c.g) shl 16) or (uint32(c.b) shl 8) or uint32(c.a)

proc smoothstep(edge0, edge1, x: float32): float32 {.inline.} =
  let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
  t * t * (3.0 - 2.0 * t)

proc sampleLinear*(pb: PixelBuffer, u, v: float32): SDLRGBA =
  ## Bilinear sample at normalised coords [0,1]×[0,1].
  let fx  = u * float32(pb.width  - 1)
  let fy  = v * float32(pb.height - 1)
  let x0  = clamp(int(fx),       0, pb.width  - 1)
  let x1  = clamp(int(fx) + 1,   0, pb.width  - 1)
  let y0  = clamp(int(fy),       0, pb.height - 1)
  let y1  = clamp(int(fy) + 1,   0, pb.height - 1)
  let tx  = fx - float32(int(fx))
  let ty  = fy - float32(int(fy))
  let c00 = pb.getPixel(x0, y0)
  let c10 = pb.getPixel(x1, y0)
  let c01 = pb.getPixel(x0, y1)
  let c11 = pb.getPixel(x1, y1)
  proc lerp8(a, b: uint8, t: float32): uint8 = uint8(float32(a) * (1-t) + float32(b) * t)
  let r = lerp8(lerp8(c00.r, c10.r, tx), lerp8(c01.r, c11.r, tx), ty)
  let g = lerp8(lerp8(c00.g, c10.g, tx), lerp8(c01.g, c11.g, tx), ty)
  let b = lerp8(lerp8(c00.b, c10.b, tx), lerp8(c01.b, c11.b, tx), ty)
  let a = lerp8(lerp8(c00.a, c10.a, tx), lerp8(c01.a, c11.a, tx), ty)
  SDLRGBA(r: r, g: g, b: b, a: a)

# ---------------------------------------------------------------------------
# Helper: build Gaussian kernel
# ---------------------------------------------------------------------------

proc gaussianKernel(radius: int, sigma: float32): seq[float32] =
  let s   = if sigma <= 0: float32(radius) / 3.0 else: sigma
  let n   = 2 * radius + 1
  result  = newSeq[float32](n)
  var sum = 0.0f
  for i in 0 ..< n:
    let x   = float32(i - radius)
    result[i] = exp(-0.5 * (x/s)*(x/s))
    sum += result[i]
  for i in 0 ..< n: result[i] /= sum

# ---------------------------------------------------------------------------
# Effect: Gaussian blur (separable horizontal + vertical passes)
# ---------------------------------------------------------------------------

proc applyBlur*(pb: var PixelBuffer, params: BlurParams) =
  let radius  = max(1, params.radius)
  let sigma   = if params.sigma <= 0: float32(radius) / 3.0 else: params.sigma
  let passes  = max(1, params.passes)
  let kernel  = gaussianKernel(radius, sigma)
  let w       = pb.width
  let h       = pb.height

  var tmp = initPixelBuffer(w, h)

  for _ in 0 ..< passes:
    # Horizontal pass: pb → tmp
    for y in 0 ..< h:
      for x in 0 ..< w:
        var rSum, gSum, bSum, aSum = 0.0f
        for k in -radius .. radius:
          let sx = clamp(x + k, 0, w - 1)
          let c  = pb.getPixel(sx, y)
          let wt = kernel[k + radius]
          rSum += float32(c.r) * wt
          gSum += float32(c.g) * wt
          bSum += float32(c.b) * wt
          aSum += float32(c.a) * wt
        tmp.setPixel(x, y, SDLRGBA(r: uint8(rSum), g: uint8(gSum),
                                    b: uint8(bSum),  a: uint8(aSum)))
    # Vertical pass: tmp → pb
    for y in 0 ..< h:
      for x in 0 ..< w:
        var rSum, gSum, bSum, aSum = 0.0f
        for k in -radius .. radius:
          let sy = clamp(y + k, 0, h - 1)
          let c  = tmp.getPixel(x, sy)
          let wt = kernel[k + radius]
          rSum += float32(c.r) * wt
          gSum += float32(c.g) * wt
          bSum += float32(c.b) * wt
          aSum += float32(c.a) * wt
        pb.setPixel(x, y, SDLRGBA(r: uint8(rSum), g: uint8(gSum),
                                   b: uint8(bSum),  a: uint8(aSum)))

# ---------------------------------------------------------------------------
# Effect: Bloom
# ---------------------------------------------------------------------------

proc applyBloom*(pb: var PixelBuffer, params: BloomParams) =
  ## 1. Extract bright regions (luminance > threshold)
  ## 2. Blur the bright layer
  ## 3. Additive composite onto original
  let w = pb.width; let h = pb.height

  var bright = initPixelBuffer(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      let c    = pb.getPixel(x, y)
      let lum  = (float32(c.r) * 0.2126 + float32(c.g) * 0.7152 +
                  float32(c.b) * 0.0722) / 255.0
      if lum >= params.threshold:
        bright.setPixel(x, y, c)
      else:
        bright.setPixel(x, y, SDLRGBA(r: 0, g: 0, b: 0, a: 0))

  applyBlur(bright, params.blur)

  # Additive composite
  let intensity = params.intensity
  for y in 0 ..< h:
    for x in 0 ..< w:
      let base = pb.getPixel(x, y)
      let bl   = bright.getPixel(x, y)
      pb.setPixel(x, y, SDLRGBA(
        r: uint8(min(255, int(base.r) + int(float32(bl.r) * intensity))),
        g: uint8(min(255, int(base.g) + int(float32(bl.g) * intensity))),
        b: uint8(min(255, int(base.b) + int(float32(bl.b) * intensity))),
        a: base.a
      ))

# ---------------------------------------------------------------------------
# Effect: Sharpen (unsharp mask)
# ---------------------------------------------------------------------------

proc applySharpen*(pb: var PixelBuffer, amount: float32) =
  ## Unsharp mask: out = original + amount * (original - blurred)
  var blurred = initPixelBuffer(pb.width, pb.height)
  for i in 0 ..< pb.pixels.len:
    blurred.pixels[i] = pb.pixels[i]
  applyBlur(blurred, BlurParams(radius: 1, sigma: 1.0, passes: 1))
  let w = pb.width; let h = pb.height
  for y in 0 ..< h:
    for x in 0 ..< w:
      let orig  = pb.getPixel(x, y)
      let bl    = blurred.getPixel(x, y)
      pb.setPixel(x, y, SDLRGBA(
        r: uint8(clamp(int(orig.r) + int(amount * float32(int(orig.r) - int(bl.r))), 0, 255)),
        g: uint8(clamp(int(orig.g) + int(amount * float32(int(orig.g) - int(bl.g))), 0, 255)),
        b: uint8(clamp(int(orig.b) + int(amount * float32(int(orig.b) - int(bl.b))), 0, 255)),
        a: orig.a
      ))

# ---------------------------------------------------------------------------
# Effect: Vignette
# ---------------------------------------------------------------------------

proc applyVignette*(pb: var PixelBuffer, params: VignetteParams) =
  let w  = pb.width; let h = pb.height
  let cx = float32(w) * 0.5; let cy = float32(h) * 0.5
  let rScale = float32(min(w, h)) * 0.5
  for y in 0 ..< h:
    for x in 0 ..< w:
      let dx   = (float32(x) - cx) / rScale
      let dy   = (float32(y) - cy) / rScale
      let dist = sqrt(dx*dx + dy*dy)
      let t    = smoothstep(params.radius - params.softness,
                            params.radius + params.softness, dist)
      let factor = 1.0 - params.strength * t
      let c    = pb.getPixel(x, y)
      pb.setPixel(x, y, SDLRGBA(
        r: uint8(float32(c.r) * factor),
        g: uint8(float32(c.g) * factor),
        b: uint8(float32(c.b) * factor),
        a: c.a
      ))

# ---------------------------------------------------------------------------
# Effect: Chromatic Aberration
# ---------------------------------------------------------------------------

proc applyChromatic*(pb: var PixelBuffer, params: ChromaParams) =
  ## Shift R and B channels independently; G stays.
  let w = pb.width; let h = pb.height
  var output = initPixelBuffer(w, h)
  for y in 0 ..< h:
    for x in 0 ..< w:
      let orig = pb.getPixel(x, y)
      # Red channel with offset
      let rx  = clamp(x + int(params.offsetR.x), 0, w - 1)
      let ry  = clamp(y + int(params.offsetR.y), 0, h - 1)
      let rC  = pb.getPixel(rx, ry)
      # Blue channel with offset
      let bx  = clamp(x + int(params.offsetB.x), 0, w - 1)
      let by  = clamp(y + int(params.offsetB.y), 0, h - 1)
      let bC  = pb.getPixel(bx, by)
      output.setPixel(x, y, SDLRGBA(r: rC.r, g: orig.g, b: bC.b, a: orig.a))
  pb = output

# ---------------------------------------------------------------------------
# Effect: Color Grading
# ---------------------------------------------------------------------------

proc applyColorGrade*(pb: var PixelBuffer, params: ColorGradeParams) =
  let w = pb.width; let h = pb.height
  for y in 0 ..< h:
    for x in 0 ..< w:
      let c = pb.getPixel(x, y)
      # Convert to [0,1]
      var r = float32(c.r) / 255.0
      var g = float32(c.g) / 255.0
      var b = float32(c.b) / 255.0
      # Brightness
      r *= params.brightness; g *= params.brightness; b *= params.brightness
      # Contrast (pivot at 0.5)
      r = (r - 0.5) * params.contrast + 0.5
      g = (g - 0.5) * params.contrast + 0.5
      b = (b - 0.5) * params.contrast + 0.5
      # Saturation
      let lum = r * 0.2126 + g * 0.7152 + b * 0.0722
      r = lum + params.saturation * (r - lum)
      g = lum + params.saturation * (g - lum)
      b = lum + params.saturation * (b - lum)
      # Tint
      r *= params.tintR; g *= params.tintG; b *= params.tintB
      pb.setPixel(x, y, SDLRGBA(
        r: uint8(clamp(r, 0.0, 1.0) * 255),
        g: uint8(clamp(g, 0.0, 1.0) * 255),
        b: uint8(clamp(b, 0.0, 1.0) * 255),
        a: c.a
      ))

# ---------------------------------------------------------------------------
# Effect: FXAA (Fast Approximate Anti-Aliasing)
# ---------------------------------------------------------------------------

proc applyFXAA*(pb: var PixelBuffer, quality: int = 1) =
  ## Software FXAA — detect edges by luminance gradient, blur along them.
  ## quality: 0=fast, 1=medium, 2=high (more sub-pixel steps)
  let w  = pb.width; let h = pb.height
  let subSteps = case quality
    of 0: 4
    of 1: 8
    else: 12

  proc luma(c: SDLRGBA): float32 {.inline.} =
    (float32(c.r) * 0.2126 + float32(c.g) * 0.7152 + float32(c.b) * 0.0722) / 255.0

  var output = initPixelBuffer(w, h)
  for y in 1 ..< h - 1:
    for x in 1 ..< w - 1:
      let cN  = pb.getPixel(x,   y-1); let cS = pb.getPixel(x,   y+1)
      let cE  = pb.getPixel(x+1, y);   let cW = pb.getPixel(x-1, y)
      let cM  = pb.getPixel(x,   y)
      let lN  = luma(cN); let lS = luma(cS)
      let lE  = luma(cE); let lW = luma(cW); let lM = luma(cM)
      let rangeH = max(lN, max(lS, max(lE, lW)))
      let rangeL = min(lN, min(lS, min(lE, lW)))
      let range  = rangeH - rangeL
      # Threshold: skip non-edge pixels
      if range < max(0.0312, rangeH * 0.125):
        output.setPixel(x, y, cM)
        continue
      # Blend direction along steepest gradient
      let edgeH = abs(lN - lS)
      let edgeV = abs(lE - lW)
      let blendH = edgeV >= edgeH   # blend horizontally?
      let stepLen = float32(subSteps)
      var rSum = float32(cM.r); var gSum = float32(cM.g)
      var bSum = float32(cM.b); var aSum = float32(cM.a)
      var cnt = 1.0f
      for s in 1 .. subSteps:
        let t   = float32(s) / stepLen
        let sx  = if blendH: clamp(x + int(t * float32(if lW > lE: -1 else: 1)), 0, w-1) else: x
        let sy  = if blendH: y else: clamp(y + int(t * float32(if lN > lS: -1 else: 1)), 0, h-1)
        let sc  = pb.getPixel(sx, sy)
        rSum += float32(sc.r); gSum += float32(sc.g)
        bSum += float32(sc.b); aSum += float32(sc.a)
        cnt  += 1.0
      output.setPixel(x, y, SDLRGBA(r: uint8(rSum/cnt), g: uint8(gSum/cnt),
                                   b: uint8(bSum/cnt), a: uint8(aSum/cnt)))
  pb = output

# ---------------------------------------------------------------------------
# CPU upscale (bilinear)
# ---------------------------------------------------------------------------

proc applyUpscale*(pb: var PixelBuffer, targetW, targetH: int,
                   filter: SDLScaleMode = scaleLinear) =
  if targetW <= 0 or targetH <= 0: return
  if targetW == pb.width and targetH == pb.height: return
  var output = initPixelBuffer(targetW, targetH)
  if filter == scaleNearest:
    let sx = float32(pb.width) / float32(targetW)
    let sy = float32(pb.height) / float32(targetH)
    for y in 0 ..< targetH:
      for x in 0 ..< targetW:
        let px = int(float32(x) * sx)
        let py = int(float32(y) * sy)
        output.setPixel(x, y, pb.getPixel(
          clamp(px, 0, pb.width - 1), clamp(py, 0, pb.height - 1)))
  else:
    for y in 0 ..< targetH:
      for x in 0 ..< targetW:
        let u = (float32(x) + 0.5f) / float32(targetW)
        let v = (float32(y) + 0.5f) / float32(targetH)
        output.setPixel(x, y, sampleLinear(pb, u, v))
  pb.pixels = move(output.pixels)
  pb.width = targetW
  pb.height = targetH
  pb.pitch = targetW * 4

# ---------------------------------------------------------------------------
# CPU downscale (box filter / Lanczos approximation)
# ---------------------------------------------------------------------------

proc applyDownscale*(pb: var PixelBuffer, targetW, targetH: int,
                     filter: SDLScaleMode = scaleLinear) =
  if filter == scaleNearest:
    var output = initPixelBuffer(targetW, targetH)
    let sx = float32(pb.width)  / float32(targetW)
    let sy = float32(pb.height) / float32(targetH)
    for y in 0 ..< targetH:
      for x in 0 ..< targetW:
        output.setPixel(x, y, pb.getPixel(int(float32(x)*sx), int(float32(y)*sy)))
    pb = output
  else:
    # Box filter: average all source pixels that map to each dest pixel
    var output = initPixelBuffer(targetW, targetH)
    let sx = float32(pb.width)  / float32(targetW)
    let sy = float32(pb.height) / float32(targetH)
    for y in 0 ..< targetH:
      for x in 0 ..< targetW:
        let x0 = int(float32(x)   * sx)
        let x1 = max(x0, int(float32(x+1) * sx) - 1)
        let y0 = int(float32(y)   * sy)
        let y1 = max(y0, int(float32(y+1) * sy) - 1)
        var rS, gS, bS, caS:float32
        var cnt = 0.0f
        for py in y0..y1:
          for px in x0..x1:
            let c = pb.getPixel(clamp(px, 0, pb.width-1), clamp(py, 0, pb.height-1))
            rS += float32(c.r)
            gS += float32(c.g)
            bS += float32(c.b)
            caS += float32(c.a)
            cnt += 1.0
        if cnt > 0:
          output.setPixel(x, y, SDLRGBA(r: uint8(rS/cnt), g: uint8(gS/cnt),
                                      b: uint8(bS/cnt), a: uint8(caS/cnt)))
    pb = output

# ---------------------------------------------------------------------------
# PostProcessPipeline
# ---------------------------------------------------------------------------

type
  ## A callback that locks a texture and fills a PixelBuffer, then
  ## unlocks and re-uploads after effects. The backend supplies this.
  LockTextureFn*   = proc(rawPtr: pointer, pb: var PixelBuffer) {.closure.}
  UnlockTextureFn* = proc(rawPtr: pointer, pb: PixelBuffer)    {.closure.}

  TextureEffectEntry* = object
    rawPtr*:  pointer             ## SDL_Texture* to process
    effects*: seq[PostProcessEffect]

  PostProcessPipeline* = object
    entries*:    seq[TextureEffectEntry]
    lockFn*:     LockTextureFn
    unlockFn*:   UnlockTextureFn

proc initPostProcessPipeline*(lockFn:   LockTextureFn,
                               unlockFn: UnlockTextureFn): PostProcessPipeline =
  PostProcessPipeline(entries: @[], lockFn: lockFn, unlockFn: unlockFn)

proc addEffect*(pp: var PostProcessPipeline,
                rawPtr:  pointer,
                effect:  PostProcessEffect) =
  for e in pp.entries.mitems:
    if e.rawPtr == rawPtr:
      e.effects.add(effect)
      return
  pp.entries.add(TextureEffectEntry(rawPtr: rawPtr, effects: @[effect]))

proc clear*(pp: var PostProcessPipeline) =
  pp.entries.setLen(0)

proc run*(pp: var PostProcessPipeline) =
  ## Apply all registered effects. Called once per frame after the render pass
  ## but before the final blit.
  for entry in pp.entries.mitems:
    if entry.effects.len == 0: continue
    var pb: PixelBuffer
    pp.lockFn(entry.rawPtr, pb)
    for fx in entry.effects:
      case fx.kind
      of ppBlur:           applyBlur(pb, fx.blur)
      of ppBloom:          applyBloom(pb, fx.bloom)
      of ppSharpen:        applySharpen(pb, fx.sharpenAmt)
      of ppVignette:       applyVignette(pb, fx.vignette)
      of ppChromaticAberr: applyChromatic(pb, fx.chroma)
      of ppColorGrade:     applyColorGrade(pb, fx.colorGrade)
      of ppFXAA:           applyFXAA(pb, fx.fxaaQuality)
      of ppDownscale:      applyDownscale(pb, fx.downscale.targetW,
                                          fx.downscale.targetH, fx.downscale.filter)
      of ppUpscale:        applyUpscale(pb, fx.upscale.targetW, fx.upscale.targetH,
                                        fx.upscale.filter)
      of ppSSAA:
        let s = max(1, fx.ssaaScale)
        let tw = pb.width div s
        let th = pb.height div s
        if tw > 0 and th > 0:
          applyDownscale(pb, tw, th, scaleLinear)
      of ppCustom, ppNone:
        discard
    pp.unlockFn(entry.rawPtr, pb)
