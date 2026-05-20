############################################################################################################################
######################################################## CRUISE COLORS #####################################################
############################################################################################################################

type
  CRGBAi* = object
    ## RGBA color with integer components in [0, 255].
    r*, g*, b*, a*: uint8

func crgbai*(r, g, b: uint8, a: uint8 = 255): CRGBAi =
  ## Construct a CRGBAi color. Alpha defaults to fully opaque (255).
  CRGBAi(r: r, g: g, b: b, a: a)

func toRGBA*(c: CRGBAi): CRGBA =
  ## Convert integer RGBA to float RGBA by dividing each component by 255.
  CRGBA(
    r: float32(c.r) / 255f,
    g: float32(c.g) / 255f,
    b: float32(c.b) / 255f,
    a: float32(c.a) / 255f
  )

func fromRGBA*(_: typedesc[CRGBAi], c: CRGBA): CRGBAi =
  ## Convert float RGBA to integer RGBA by multiplying each component by 255.
  crgbai(
    uint8(clamp(c.r, 0f, 1f) * 255f),
    uint8(clamp(c.g, 0f, 1f) * 255f),
    uint8(clamp(c.b, 0f, 1f) * 255f),
    uint8(clamp(c.a, 0f, 1f) * 255f)
  )

func toHexString*(c: CRGBAi, includeAlpha = false): string =
  ## Format a CRGBAi as a hex color string.
  ## Returns `#RRGGBB` by default, or `#RRGGBBAA` when `includeAlpha` is true.
  if includeAlpha:
    fmt"#{c.r:02X}{c.g:02X}{c.b:02X}{c.a:02X}"
  else:
    fmt"#{c.r:02X}{c.g:02X}{c.b:02X}"

func toHex*(c: CRGBAi): uint32 =
  c.r.uint32 or (c.g.uint32 shl 8) or (c.b.uint32 shl 16) or (c.a.uint32 shl 24) 

func fromHex*(_: typedesc[CRGBAi], hex: uint32): CRGBAi =
  CRGBAi(r: hex and 255, g: (hex shr 8) and 255, b: (hex shr 16) and 255, a: (hex shr 24) and 255)

func fromHex*(_: typedesc[CRGBAi], hex: string): CRGBAi =
  ## Parse a hex color string into a CRGBAi.
  ## Accepts `#RGB`, `#RRGGBB`, or `#RRGGBBAA` formats.
  let s = hex.strip(chars = {'#', ' '})
  case s.len
  of 3:
    let r = parseHexInt($s[0] & $s[0])
    let g = parseHexInt($s[1] & $s[1])
    let b = parseHexInt($s[2] & $s[2])
    crgbai(uint8(r), uint8(g), uint8(b))
  of 6:
    crgbai(
      uint8(parseHexInt(s[0..1])),
      uint8(parseHexInt(s[2..3])),
      uint8(parseHexInt(s[4..5]))
    )
  of 8:
    crgbai(
      uint8(parseHexInt(s[0..1])),
      uint8(parseHexInt(s[2..3])),
      uint8(parseHexInt(s[4..5])),
      uint8(parseHexInt(s[6..7]))
    )
  else:
    raise newException(ValueError, "Invalid hex color: " & hex)

# --------------------------------------------------------------------------------------------------------------------------
# CRGBf — float RGB [0, 1], no alpha
# --------------------------------------------------------------------------------------------------------------------------

type
  CRGBf* = object
    ## RGB color with float components in [0, 1]. No alpha channel.
    r*, g*, b*: float32

func crgbf*(r, g, b: float32): CRGBf =
  ## Construct a CRGBf color.
  CRGBf(r: r, g: g, b: b)

func toRGBA*(c: CRGBf): CRGBA =
  ## Convert float RGB to float RGBA with alpha = 1.
  CRGBA(r: c.r, g: c.g, b: c.b, a: 1f)

func fromRGBA*(_: typedesc[CRGBf], c: CRGBA): CRGBf =
  ## Convert float RGBA to float RGB. Alpha is discarded.
  crgbf(c.r, c.g, c.b)

func toHex*(c: CRGBf): uint32 =
  ## Format a CRGBf as a `#RRGGBB` hex uint.
  fromRGBA(CRGBAi, c.toRGBA()).toHex()

func toHexString*(c: CRGBf, includeAlpha=false): string =
  ## Format a CRGBf as a `#RRGGBB` hex string.
  fromRGBA(CRGBAi, c.toRGBA()).toHexString(includeAlpha)

template fromHex*(_: typedesc[CRGBf], hex: untyped): CRGBf =
  ## Parse a hex color string into a CRGBf. Alpha is discarded.
  fromRGBA(CRGBf, CRGBAi.fromHex(hex).toRGBA())

# --------------------------------------------------------------------------------------------------------------------------
# CHSVColor — Hue / Saturation / Value
# --------------------------------------------------------------------------------------------------------------------------

type
  CHSVColor* = object
    ## HSV color. h ∈ [0, 360), s ∈ [0, 1], v ∈ [0, 1].
    h*, s*, v*: float32

func chsv*(h, s, v: float32): CHSVColor =
  ## Construct a CHSVColor. Hue is wrapped to [0, 360) automatically.
  CHSVColor(h: h.mod(360f), s: clamp(s, 0f, 1f), v: clamp(v, 0f, 1f))

func toRGBA*(c: CHSVColor): CRGBA =
  ## Convert HSV to RGBA using the standard sector algorithm.
  let hi = int(c.h / 60f) mod 6
  let f  = (c.h / 60f) - float32(int(c.h / 60f))
  let p  = c.v * (1f - c.s)
  let q  = c.v * (1f - f * c.s)
  let t  = c.v * (1f - (1f - f) * c.s)
  let (r, g, b) = case hi
    of 0: (c.v, t,   p  )
    of 1: (q,   c.v, p  )
    of 2: (p,   c.v, t  )
    of 3: (p,   q,   c.v)
    of 4: (t,   p,   c.v)
    else: (c.v, p,   q  )
  CRGBA(r: r, g: g, b: b, a: 1f)

func fromRGBA*(_: typedesc[CHSVColor], c: CRGBA): CHSVColor =
  ## Convert RGBA to HSV. Alpha is discarded.
  let mx = max(c.r, max(c.g, c.b))
  let mn = min(c.r, min(c.g, c.b))
  let d  = mx - mn
  let s  = if mx == 0f: 0f else: d / mx
  let h  =
    if d == 0f: 0f
    elif mx == c.r: 60f * (((c.g - c.b) / d).mod(6f))
    elif mx == c.g: 60f * ((c.b - c.r) / d + 2f)
    else:           60f * ((c.r - c.g) / d + 4f)
  chsv(h, s, mx)

func rotate*(c: CHSVColor, degrees: float32): CHSVColor =
  ## Rotate the hue of an HSV color by `degrees`. Wraps at 360.
  chsv(c.h + degrees, c.s, c.v)

func saturate*(c: CHSVColor, amount: float32): CHSVColor =
  ## Increase saturation by `amount` (clamped to [0, 1]).
  chsv(c.h, c.s + amount, c.v)

func brighten*(c: CHSVColor, amount: float32): CHSVColor =
  ## Increase value (brightness) by `amount` (clamped to [0, 1]).
  chsv(c.h, c.s, c.v + amount)

# --------------------------------------------------------------------------------------------------------------------------
# CXYZColor — CIE XYZ tristimulus
# --------------------------------------------------------------------------------------------------------------------------

type
  CXYZColor* = object
    ## CIE XYZ color. X, Y, Z ∈ [0, 1] (normalized D65 white point).
    x*, y*, z*: float32

func cxyz*(x, y, z: float32): CXYZColor =
  CXYZColor(x: x, y: y, z: z)

func linearize(v: float32): float32 =
  ## Apply inverse sRGB gamma (sRGB → linear light).
  if v <= 0.04045f: v / 12.92f
  else: pow((v + 0.055f) / 1.055f, 2.4f)

func delinearize(v: float32): float32 =
  ## Apply sRGB gamma (linear light → sRGB).
  if v <= 0.0031308f: 12.92f * v
  else: 1.055f * pow(v, 1f / 2.4f) - 0.055f

func toRGBA*(c: CXYZColor): CRGBA =
  ## Convert CIE XYZ to sRGB RGBA using the D65 matrix. Alpha = 1.
  let r = delinearize( 3.2406f * c.x - 1.5372f * c.y - 0.4986f * c.z)
  let g = delinearize(-0.9689f * c.x + 1.8758f * c.y + 0.0415f * c.z)
  let b = delinearize( 0.0557f * c.x - 0.2040f * c.y + 1.0570f * c.z)
  CRGBA(r: clamp(r, 0f, 1f), g: clamp(g, 0f, 1f), b: clamp(b, 0f, 1f), a: 1f)

func fromRGBA*(_: typedesc[CXYZColor], c: CRGBA): CXYZColor =
  ## Convert sRGB RGBA to CIE XYZ using the D65 matrix. Alpha is discarded.
  let r = linearize(c.r)
  let g = linearize(c.g)
  let b = linearize(c.b)
  cxyz(
    0.4124f * r + 0.3576f * g + 0.1805f * b,
    0.2126f * r + 0.7152f * g + 0.0722f * b,
    0.0193f * r + 0.1192f * g + 0.9505f * b
  )

# --------------------------------------------------------------------------------------------------------------------------
# CLABColor — CIELAB perceptual color space
# --------------------------------------------------------------------------------------------------------------------------

type
  CLABColor* = object
    ## CIELAB color. L ∈ [0, 100], a ∈ [-128, 127], b ∈ [-128, 127].
    l*, a*, b*: float32

func clab*(l, a, b: float32): CLABColor =
  CLABColor(l: l, a: a, b: b)

# D65 reference white point
const D65 = (x: 0.95047f, y: 1.00000f, z: 1.08883f)

func labF(t: float32): float32 =
  if t > 0.008856f: pow(t, 1f/3f)
  else: (7.787f * t) + (16f / 116f)

func labFInv(t: float32): float32 =
  let t3 = t * t * t
  if t3 > 0.008856f: t3
  else: (t - 16f / 116f) / 7.787f

func toRGBA*(c: CLABColor): CRGBA =
  ## Convert CIELAB to sRGB RGBA via XYZ. Alpha = 1.
  let fy = (c.l + 16f) / 116f
  let fx = c.a / 500f + fy
  let fz = fy - c.b / 200f
  let xyz = cxyz(
    labFInv(fx) * D65.x,
    labFInv(fy) * D65.y,
    labFInv(fz) * D65.z
  )
  xyz.toRGBA()

func fromRGBA*(_: typedesc[CLABColor], c: CRGBA): CLABColor =
  ## Convert sRGB RGBA to CIELAB via XYZ. Alpha is discarded.
  let xyz = fromRGBA(CXYZColor, c)
  let fx = labF(xyz.x / D65.x)
  let fy = labF(xyz.y / D65.y)
  let fz = labF(xyz.z / D65.z)
  clab(
    116f * fy - 16f,
    500f * (fx - fy),
    200f * (fy - fz)
  )

func deltaE*(a, b: CLABColor): float32 =
  ## CIE76 perceptual distance between two LAB colors.
  ## Values < 1 are imperceptible, > 10 are clearly different.
  sqrt((a.l-b.l)^2 + (a.a-b.a)^2 + (a.b-b.b)^2)

# --------------------------------------------------------------------------------------------------------------------------
# Hex utilities for CRGBA
# --------------------------------------------------------------------------------------------------------------------------

func toHexString*(c: CRGBA, includeAlpha = false): string =
  ## Format a CRGBA as a hex string.
  fromRGBA(CRGBAi, c).toHexString(includeAlpha)

func toHex*(c: CRGBA): uint32 =
  ## Format a CRGBA as a hex uint.
  fromRGBA(CRGBAi, c).toHex()

func fromHex*(_: typedesc[CRGBA], hex: string): CRGBA =
  ## Parse a hex color string into a CRGBA.
  CRGBAi.fromHex(hex).toRGBA()

# --------------------------------------------------------------------------------------------------------------------------
# Alpha premultiplication
# --------------------------------------------------------------------------------------------------------------------------

func premultiply*(c: CRGBA): CRGBA =
  ## Premultiply RGB components by alpha. Used for correct alpha compositing.
  CRGBA(r: c.r * c.a, g: c.g * c.a, b: c.b * c.a, a: c.a)

func unpremultiply*(c: CRGBA): CRGBA =
  ## Reverse premultiplication. No-op if alpha is zero.
  if c.a == 0f: c
  else: CRGBA(r: c.r / c.a, g: c.g / c.a, b: c.b / c.a, a: c.a)

# --------------------------------------------------------------------------------------------------------------------------
# Blending modes  (src over dst, Porter-Duff)
# --------------------------------------------------------------------------------------------------------------------------

func blendMultiply*(src, dst: CRGBA): CRGBA =
  ## Multiply blend: darkens by multiplying RGB components.
  CRGBA(r: src.r * dst.r, g: src.g * dst.g, b: src.b * dst.b, a: src.a)

func blendScreen*(src, dst: CRGBA): CRGBA =
  ## Screen blend: lightens by inverting, multiplying, and inverting again.
  CRGBA(
    r: 1f - (1f - src.r) * (1f - dst.r),
    g: 1f - (1f - src.g) * (1f - dst.g),
    b: 1f - (1f - src.b) * (1f - dst.b),
    a: src.a
  )

func blendOverlay*(src, dst: CRGBA): CRGBA =
  ## Overlay blend: multiplies darks and screens lights.
  func f(s, d: float32): float32 =
    if d < 0.5f: 2f * s * d
    else: 1f - 2f * (1f - s) * (1f - d)
  CRGBA(r: f(src.r, dst.r), g: f(src.g, dst.g), b: f(src.b, dst.b), a: src.a)

func blendSoftLight*(src, dst: CRGBA): CRGBA =
  ## Soft light blend: a softer version of overlay.
  func f(s, d: float32): float32 =
    if s < 0.5f: d - (1f - 2f*s) * d * (1f - d)
    else: d + (2f*s - 1f) * (sqrt(d) - d)
  CRGBA(r: f(src.r, dst.r), g: f(src.g, dst.g), b: f(src.b, dst.b), a: src.a)

func blendHardLight*(src, dst: CRGBA): CRGBA =
  ## Hard light blend: overlay with src and dst swapped.
  blendOverlay(dst, src)

# --------------------------------------------------------------------------------------------------------------------------
# Color temperature (Kelvin → RGB)
# --------------------------------------------------------------------------------------------------------------------------

func kelvinToRGBA*(kelvin: float32): CRGBA =
  ## Approximate RGB for a blackbody color temperature in Kelvin.
  ## Valid range: 1000K – 40000K. Based on Tanner Helland's algorithm.
  let t = clamp(kelvin, 1000f, 40000f) / 100f
  let r =
    if t <= 66f: 1f
    else: clamp(329.698727446f * pow(t - 60f, -0.1332047592f) / 255f, 0f, 1f)
  let g =
    if t <= 66f: clamp((99.4708025861f * ln(t) - 161.1195681661f) / 255f, 0f, 1f)
    else: clamp(288.1221695283f * pow(t - 60f, -0.0755148492f) / 255f, 0f, 1f)
  let b =
    if t >= 66f: 1f
    elif t <= 19f: 0f
    else: clamp((138.5177312231f * ln(t - 10f) - 305.0447927307f) / 255f, 0f, 1f)
  CRGBA(r: r, g: g, b: b, a: 1f)