############################################################################################################################
######################################################### CRUISE TESTS #####################################################
############################################################################################################################

import unittest
include "../../src/vspace/vspace.nim"

# --------------------------------------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------------------------------------

const EpsF32 = 1e-4f
const EpsF64 = 1e-9

func `~=`(a, b: float32): bool = abs(a - b) < EpsF32
func `~=`(a, b: float64): bool = abs(a - b) < EpsF64
func `~=`(a, b: CRGBA): bool =
  a.r ~= b.r and a.g ~= b.g and a.b ~= b.b and a.a ~= b.a

suite "CCartesianCoord arithmetic":

  test "addition":
    let a = CCartesianCoord[2, float64](components: [1.0, 2.0])
    let b = CCartesianCoord[2, float64](components: [3.0, 4.0])
    let c = a + b
    check c.components[0] ~= 4.0
    check c.components[1] ~= 6.0

  test "subtraction":
    let a = CCartesianCoord[2, float64](components: [5.0, 3.0])
    let b = CCartesianCoord[2, float64](components: [1.0, 2.0])
    let c = a - b
    check c.components[0] ~= 4.0
    check c.components[1] ~= 1.0

  test "scalar multiplication":
    let a = CCartesianCoord[2, float64](components: [2.0, 3.0])
    let c = a * 2.0
    check c.components[0] ~= 4.0
    check c.components[1] ~= 6.0

  test "scalar multiplication commutative":
    let a = CCartesianCoord[2, float64](components: [2.0, 3.0])
    check (a * 3.0).components[0] ~= (3.0 * a).components[0]

  test "dot product":
    let a = CCartesianCoord[2, float64](components: [1.0, 2.0])
    let b = CCartesianCoord[2, float64](components: [3.0, 4.0])
    check dot(a, b) ~= 11.0

  test "dot product of perpendicular vectors is zero":
    let a = CCartesianCoord[2, float64](components: [1.0, 0.0])
    let b = CCartesianCoord[2, float64](components: [0.0, 1.0])
    check dot(a, b) ~= 0.0

  test "cross product":
    let a = CCartesianCoord[3, float64](components: [1.0, 0.0, 0.0])
    let b = CCartesianCoord[3, float64](components: [0.0, 1.0, 0.0])
    let c = cross(a, b)
    check c.components[0] ~= 0.0
    check c.components[1] ~= 0.0
    check c.components[2] ~= 1.0

  test "cross product anti-commutative":
    let a = CCartesianCoord[3, float64](components: [1.0, 2.0, 3.0])
    let b = CCartesianCoord[3, float64](components: [4.0, 5.0, 6.0])
    let ab = cross(a, b)
    let ba = cross(b, a)
    check ab.components[0] ~= -ba.components[0]
    check ab.components[1] ~= -ba.components[1]
    check ab.components[2] ~= -ba.components[2]

  test "norm of unit vector":
    let a = CCartesianCoord[2, float64](components: [1.0, 0.0])
    check norm(a) ~= 1.0

  test "norm general":
    let a = CCartesianCoord[2, float64](components: [3.0, 4.0])
    check norm(a) ~= 5.0

  test "distanceTo":
    let a = CCartesianCoord[2, float64](components: [0.0, 0.0])
    let b = CCartesianCoord[2, float64](components: [3.0, 4.0])
    check distanceTo(a, b) ~= 5.0

  test "lerp at t=0 returns a":
    let a = CCartesianCoord[2, float64](components: [1.0, 2.0])
    let b = CCartesianCoord[2, float64](components: [5.0, 6.0])
    let c = lerp(a, b, 0.0)
    check c.components[0] ~= 1.0
    check c.components[1] ~= 2.0

  test "lerp at t=1 returns b":
    let a = CCartesianCoord[2, float64](components: [1.0, 2.0])
    let b = CCartesianCoord[2, float64](components: [5.0, 6.0])
    let c = lerp(a, b, 1.0)
    check c.components[0] ~= 5.0
    check c.components[1] ~= 6.0

  test "lerp midpoint":
    let a = CCartesianCoord[2, float64](components: [0.0, 0.0])
    let b = CCartesianCoord[2, float64](components: [4.0, 8.0])
    let c = lerp(a, b, 0.5)
    check c.components[0] ~= 2.0
    check c.components[1] ~= 4.0

  test "clamp":
    let a = CCartesianCoord[2, float64](components: [-1.0, 3.0])
    let c = clamp(a, 0.0, 2.0)
    check c.components[0] ~= 0.0
    check c.components[1] ~= 2.0

  test "mapComponents":
    let a = CCartesianCoord[2, float64](components: [-2.0, 3.0])
    let c = mapComponents(a, proc(x: float64): float64 = abs(x))
    check c.components[0] ~= 2.0
    check c.components[1] ~= 3.0

suite "CRGBA operations":

  test "clamp keeps values in [0,1]":
    let c = CRGBA(r: 1.5f, g: -0.2f, b: 0.5f, a: 2.0f)
    let cl = clamp(c)
    check cl.r ~= 1.0f
    check cl.g ~= 0.0f
    check cl.b ~= 0.5f
    check cl.a ~= 1.0f

  test "lerp at t=0":
    let a = CRGBA(r: 0f, g: 0f, b: 0f, a: 1f)
    let b = CRGBA(r: 1f, g: 1f, b: 1f, a: 1f)
    check lerp(a, b, 0f) ~= a

  test "lerp at t=1":
    let a = CRGBA(r: 0f, g: 0f, b: 0f, a: 1f)
    let b = CRGBA(r: 1f, g: 1f, b: 1f, a: 1f)
    check lerp(a, b, 1f) ~= b

  test "lerp midpoint":
    let a = CRGBA(r: 0f, g: 0f, b: 0f, a: 1f)
    let b = CRGBA(r: 1f, g: 1f, b: 1f, a: 1f)
    let m = lerp(a, b, 0.5f)
    check m.r ~= 0.5f

  test "mix is alias for lerp":
    let a = CRGBA(r: 0.2f, g: 0.4f, b: 0.6f, a: 1f)
    let b = CRGBA(r: 0.8f, g: 0.6f, b: 0.4f, a: 1f)
    check mix(a, b, 0.3f) ~= lerp(a, b, 0.3f)

  test "luminance of black is 0":
    let c = CRGBA(r: 0f, g: 0f, b: 0f, a: 1f)
    check luminance(c) ~= 0f

  test "luminance of white is 1":
    let c = CRGBA(r: 1f, g: 1f, b: 1f, a: 1f)
    check luminance(c) ~= 1f

  test "grayscale preserves alpha":
    let c = CRGBA(r: 1f, g: 0f, b: 0f, a: 0.5f)
    let g = grayscale(c)
    check g.a ~= 0.5f
    check g.r ~= g.g
    check g.g ~= g.b

  test "invert double-inverts to original":
    let c = CRGBA(r: 0.3f, g: 0.6f, b: 0.9f, a: 1f)
    check invert(invert(c)) ~= c

  test "invert preserves alpha":
    let c = CRGBA(r: 0.3f, g: 0.6f, b: 0.9f, a: 0.7f)
    check invert(c).a ~= 0.7f

  test "gamma of 1.0 is identity":
    let c = CRGBA(r: 0.4f, g: 0.6f, b: 0.8f, a: 1f)
    check gamma(c, 1.0f) ~= c

suite "CRGBAi":

  test "toRGBA divides by 255":
    let c = crgbai(255, 0, 128, 255)
    let f = c.toRGBA()
    check f.r ~= 1.0f
    check f.g ~= 0.0f
    check f.b ~= float32(128) / 255f

  test "fromRGBA round-trip":
    let original = crgbai(200, 100, 50, 255)
    let roundtrip = fromRGBA(CRGBAi, original.toRGBA())
    check roundtrip.r == original.r
    check roundtrip.g == original.g
    check roundtrip.b == original.b

  test "toHex basic":
    let c = crgbai(255, 0, 0)
    check c.toHexString() == "#FF0000"

  test "toHex with alpha":
    let c = crgbai(255, 0, 0, 128)
    check c.toHexString(includeAlpha = true) == "#FF000080"

  test "fromHex #RRGGBB":
    let c = CRGBAi.fromHex("#FF0000")
    check c.r == 255
    check c.g == 0
    check c.b == 0
    check c.a == 255

  test "fromHex #RGB shorthand":
    let c = CRGBAi.fromHex("#F00")
    check c.r == 255
    check c.g == 0
    check c.b == 0

  test "fromHex #RRGGBBAA":
    let c = CRGBAi.fromHex("#FF000080")
    check c.r == 255
    check c.a == 128

  test "fromHex round-trip":
    let c = crgbai(123, 45, 67, 255)
    check CRGBAi.fromHex(c.toHexString()).r == c.r
    check CRGBAi.fromHex(c.toHexString()).g == c.g
    check CRGBAi.fromHex(c.toHexString()).b == c.b

suite "CRGBf":

  test "toRGBA sets alpha to 1":
    let c = crgbf(0.5f, 0.25f, 0.75f)
    let f = c.toRGBA()
    check f.a ~= 1.0f

  test "fromRGBA discards alpha":
    let rgba = CRGBA(r: 0.5f, g: 0.25f, b: 0.75f, a: 0.5f)
    let rgb  = fromRGBA(CRGBf, rgba)
    check rgb.r ~= 0.5f
    check rgb.g ~= 0.25f
    check rgb.b ~= 0.75f

suite "CHSVColor":

  test "pure red in HSV → RGBA":
    let hsv  = chsv(0f, 1f, 1f)
    let rgba = hsv.toRGBA()
    check rgba.r ~= 1.0f
    check rgba.g ~= 0.0f
    check rgba.b ~= 0.0f

  test "pure green in HSV → RGBA":
    let hsv  = chsv(120f, 1f, 1f)
    let rgba = hsv.toRGBA()
    check rgba.r ~= 0.0f
    check rgba.g ~= 1.0f
    check rgba.b ~= 0.0f

  test "pure blue in HSV → RGBA":
    let hsv  = chsv(240f, 1f, 1f)
    let rgba = hsv.toRGBA()
    check rgba.r ~= 0.0f
    check rgba.g ~= 0.0f
    check rgba.b ~= 1.0f

  test "white in HSV → RGBA":
    let hsv  = chsv(0f, 0f, 1f)
    let rgba = hsv.toRGBA()
    check rgba.r ~= 1.0f
    check rgba.g ~= 1.0f
    check rgba.b ~= 1.0f

  test "fromRGBA round-trip":
    let original = chsv(200f, 0.6f, 0.8f)
    let roundtrip = fromRGBA(CHSVColor, original.toRGBA())
    check roundtrip.h ~= original.h
    check roundtrip.s ~= original.s
    check roundtrip.v ~= original.v

  test "hue wraps at 360":
    let a = chsv(0f,   1f, 1f)
    let b = chsv(360f, 1f, 1f)
    check a.h ~= b.h

  test "rotate adds to hue":
    let c = chsv(100f, 1f, 1f)
    check rotate(c, 20f).h ~= 120f

  test "saturate clamps at 1":
    let c = chsv(0f, 0.9f, 1f)
    check saturate(c, 0.5f).s ~= 1.0f

suite "CXYZColor":

  test "white round-trip RGBA → XYZ → RGBA":
    let white = CRGBA(r: 1f, g: 1f, b: 1f, a: 1f)
    let xyz   = fromRGBA(CXYZColor, white)
    let back  = xyz.toRGBA()
    check back ~= white

  test "black round-trip":
    let black = CRGBA(r: 0f, g: 0f, b: 0f, a: 1f)
    let xyz   = fromRGBA(CXYZColor, black)
    let back  = xyz.toRGBA()
    check back ~= black

suite "CLABColor":

  test "white has L ≈ 100":
    let white = CRGBA(r: 1f, g: 1f, b: 1f, a: 1f)
    let lab   = fromRGBA(CLABColor, white)
    check lab.l ~= 100f

  test "black has L ≈ 0":
    let black = CRGBA(r: 0f, g: 0f, b: 0f, a: 1f)
    let lab   = fromRGBA(CLABColor, black)
    check lab.l ~= 0f

  test "white round-trip RGBA → LAB → RGBA":
    let white = CRGBA(r: 1f, g: 1f, b: 1f, a: 1f)
    let back  = fromRGBA(CLABColor, white).toRGBA()
    check back ~= white

  test "deltaE of identical colors is 0":
    let lab = fromRGBA(CLABColor, CRGBA(r: 0.5f, g: 0.3f, b: 0.7f, a: 1f))
    check deltaE(lab, lab) ~= 0f

  test "deltaE is symmetric":
    let a = fromRGBA(CLABColor, CRGBA(r: 1f, g: 0f, b: 0f, a: 1f))
    let b = fromRGBA(CLABColor, CRGBA(r: 0f, g: 0f, b: 1f, a: 1f))
    check deltaE(a, b) ~= deltaE(b, a)

suite "Alpha premultiplication":

  test "premultiply scales RGB by alpha":
    let c  = CRGBA(r: 1f, g: 0.5f, b: 0.25f, a: 0.5f)
    let pm = premultiply(c)
    check pm.r ~= 0.5f
    check pm.g ~= 0.25f
    check pm.b ~= 0.125f
    check pm.a ~= 0.5f

  test "unpremultiply reverses premultiply":
    let c  = CRGBA(r: 0.8f, g: 0.4f, b: 0.2f, a: 0.5f)
    let rt = unpremultiply(premultiply(c))
    check rt ~= c

  test "unpremultiply of alpha=0 is a no-op":
    let c = CRGBA(r: 0f, g: 0f, b: 0f, a: 0f)
    check unpremultiply(c).r ~= 0f

suite "Blending modes":

  test "multiply with black gives black":
    let src = CRGBA(r: 0.5f, g: 0.5f, b: 0.5f, a: 1f)
    let dst = CRGBA(r: 0f,   g: 0f,   b: 0f,   a: 1f)
    let r   = blendMultiply(src, dst)
    check r.r ~= 0f

  test "screen with white gives white":
    let src = CRGBA(r: 0.5f, g: 0.5f, b: 0.5f, a: 1f)
    let dst = CRGBA(r: 1f,   g: 1f,   b: 1f,   a: 1f)
    let r   = blendScreen(src, dst)
    check r.r ~= 1f

  test "overlay is symmetric for 0.5":
    let mid = CRGBA(r: 0.5f, g: 0.5f, b: 0.5f, a: 1f)
    let r   = blendOverlay(mid, mid)
    check r.r ~= 0.5f

  test "hard light is overlay with swapped args":
    let a = CRGBA(r: 0.3f, g: 0.5f, b: 0.7f, a: 1f)
    let b = CRGBA(r: 0.6f, g: 0.4f, b: 0.2f, a: 1f)
    check blendHardLight(a, b).r ~= blendOverlay(b, a).r

suite "Color temperature":

  test "warm light (2700K) is red-dominant":
    let c = kelvinToRGBA(2700f)
    check c.r > c.b

  test "cool light (6500K) is blue-dominant or neutral":
    let c = kelvinToRGBA(6500f)
    check c.b >= c.r * 0.8f  # blue is close to or exceeds red

  test "kelvin output is clamped to [0,1]":
    for k in [1000f, 3000f, 6500f, 10000f, 40000f]:
      let c = kelvinToRGBA(k)
      check c.r >= 0f and c.r <= 1f
      check c.g >= 0f and c.g <= 1f
      check c.b >= 0f and c.b <= 1f

suite "CPolarCoord":

  test "toCartesian at phi=0":
    let p = cpolar(1.0, 0.0)
    let c = p.toCartesian()
    check c.components[0] ~= 1.0
    check c.components[1] ~= 0.0

  test "toCartesian at phi=PI/2":
    let p = cpolar(1.0, PI / 2)
    let c = p.toCartesian()
    check c.components[0] ~= 0.0
    check c.components[1] ~= 1.0

  test "fromCartesian round-trip":
    let original = cpolar(3.0, PI / 4)
    let cart     = original.toCartesian()
    let back     = fromCartesian(CPolarCoord, cart)
    check back.r   ~= original.r
    check back.phi ~= original.phi

  test "phi wraps at 2π":
    let a = cpolar(1.0, 0.0)
    let b = cpolar(1.0, 2 * PI)
    check a.phi ~= b.phi

  test "rotate adds angle":
    let p = cpolar(1.0, PI / 4)
    let r = rotate(p, PI / 4)
    check r.phi ~= PI / 2

  test "scale multiplies r":
    let p = cpolar(2.0, PI / 4)
    check scale(p, 3.0).r ~= 6.0

  test "lerp at t=0 returns a":
    let a = cpolar(1.0, 0.0)
    let b = cpolar(3.0, PI)
    let m = lerp(a, b, 0.0)
    check m.r ~= 1.0

  test "lerp at t=1 returns b":
    let a = cpolar(1.0, 0.0)
    let b = cpolar(3.0, PI / 2)
    let m = lerp(a, b, 1.0)
    check m.r   ~= 3.0
    check m.phi ~= PI / 2

suite "CCylindricalCoord":

  test "toCartesian preserves z":
    let c = ccylindrical(1.0, 0.0, 5.0)
    let cart = c.toCartesian()
    check cart.components[2] ~= 5.0

  test "fromCartesian round-trip":
    let original = ccylindrical(2.0, PI / 3, 4.0)
    let back     = fromCartesian(CCylindricalCoord, original.toCartesian())
    check back.r   ~= original.r
    check back.phi ~= original.phi
    check back.z   ~= original.z

  test "liftZ adds to z":
    let c = ccylindrical(1.0, 0.0, 2.0)
    check liftZ(c, 3.0).z ~= 5.0

  test "lerp midpoint z":
    let a = ccylindrical(0.0, 0.0, 0.0)
    let b = ccylindrical(2.0, 0.0, 4.0)
    let m = lerp(a, b, 0.5)
    check m.z ~= 2.0

suite "CSphericalCoord":

  test "north pole (theta=0) maps to (0,0,r)":
    let s    = cspherical(5.0, 0.0, 0.0)
    let cart = s.toCartesian()
    check cart.components[2] ~= 5.0

  test "equator (theta=PI/2, phi=0) maps to (r,0,0)":
    let s    = cspherical(1.0, 0.0, PI / 2)
    let cart = s.toCartesian()
    check cart.components[0] ~= 1.0
    check cart.components[2] ~= 0.0

  test "fromCartesian round-trip":
    let original = cspherical(3.0, PI / 4, PI / 3)
    let back     = fromCartesian(CSphericalCoord, original.toCartesian())
    check back.r     ~= original.r
    check back.phi   ~= original.phi
    check back.theta ~= original.theta

  test "theta clamped to [0, PI]":
    let s = cspherical(1.0, 0.0, 4.0)
    check s.theta <= PI

  test "angularDistanceTo of same point is 0":
    let s = cspherical(1.0, PI / 4, PI / 4)
    check angularDistanceTo(s, s) ~= 0.0

  test "angularDistanceTo of antipodal points is PI":
    let a = cspherical(1.0, 0.0, 0.0)
    let b = cspherical(1.0, 0.0, PI)
    check angularDistanceTo(a, b) ~= PI

  test "named color converts to HSV":
    let hsv = fromRGBA(CHSVColor, CNavy.toRGBA())
    check hsv.v > 0f