# Cruise Vector Spaces

Cruise Vector Spaces is a Nim library for manipulating colors and coordinates
through a unified, extensible interface. It is built around two families of
vector spaces and a pivot-based conversion system that makes any two types in
the same family interoperable, including types you define yourself.

## Core concepts

The library distinguishes two kinds of space:

- **`CBoundedSpace`**: spaces with a well-defined domain, primarily colors
  (RGB, HSV, LAB, …). The canonical pivot is `CRGBA` (float32, [0, 1]).
- **`CUnboundedSpace`**: spaces that extend without limit, primarily coordinate
  systems (polar, spherical, …). The canonical pivot is `CCartesianCoord[N, T]`.

Every conversion between two types in the same family goes through the pivot.
This means adding a new type automatically gives you `convertTo` for free, you only need to implement two functions.

## Quick start

```nim
import cruise/src/vspace/vspace

let c1 = crgbai(255, 128, 0)          # orange, uint8 per channel
let c2 = Crimson                       # predefined CSS constant
let c3 = convertTo(CHSVColor, c1)     # convert to HSV via CRGBA pivot
let c4 = lerp(c1.toRGBA(), c2.toRGBA(), 0.5f)  # blend two colors

echo c1.toHex()                        # "#FF8000"
echo c3                                # CHSVColor(h: 30.0, s: 1.0, v: 1.0)

let polar = cpolar(1.0, PI / 4)
let cart  = polar.toCartesian()        # CCartesianCoord[2, float64]
let back  = convertTo(CPolarCoord, cart)
```

## Extending the library

Adding a new color space or coordinate system requires exactly two functions `toRGBA` / `fromRGBA` for colors, `toCartesian` / `fromCartesian` for coordinates.
The rest (`convertTo`, `lerp`, blending, …) is inherited automatically.

```nim
# A new color space just implement the two pivot functions
type CMyColor* = object
  x*, y*, z*: float32

func toRGBA*(c: CMyColor): CRGBA = ...
func fromRGBA*(_: typedesc[CMyColor], c: CRGBA): CMyColor = ...

# That's it. convertTo, lerp, blending modes all work immediately:
let a = CMyColor(...)
let b = convertTo[CHSVColor](a)
let m = lerp(a.toRGBA(), b.toRGBA(), 0.5f)
```

```nim
# A new coordinate system use same pattern
type CToroidalCoord* = object
  r*, phi*, theta*: float64           # no domain field → CUnboundedSpace

func toCartesian*(c: CToroidalCoord): CCartesianCoord[3, float64] = ...
func fromCartesian*(_: typedesc[CToroidalCoord],
                    c: CCartesianCoord[3, float64]): CToroidalCoord = ...
```

## Built-in types

**Colors (`CBoundedSpace`)**
|     Type    |        Description        |
|-------------|---------------------------|
| `CRGBA`     | Float RGBA, pivot type    |
| `CRGBAi`    | Integer RGBA [0, 255]     |
| `CRGBf`     | Float RGB, no alpha       |
| `CHSVColor` | Hue / Saturation / Value  |
| `CXYZColor` | CIE XYZ (D65)             |
| `CLABColor` | CIELAB perceptual space   |

**Coordinates (`CUnboundedSpace`)**
| Type | Description |
|---|---|
| `CCartesianCoord[N, T]` | N-dimensional cartesian, pivot type |
| `CPolarCoord` | 2D polar (r, φ) |
| `CBipolarCoord` | 2D bipolar (σ, τ) |
| `CCylindricalCoord` | 3D cylindrical (r, φ, z) |
| `CSphericalCoord` | 3D spherical (r, φ, θ) |

## Features

- **Unified conversion**: `convertTo` works between any two types in the same family
- **140 named colors**: full CSS palette as `CRGBAi` constants (`CCrimson`, `CNavy`, …)
- **Color utilities**: blending modes, alpha premultiplication, color temperature (Kelvin to RGB), hex parsing
- **Coordinate utilities**: lerp, norm, dot/cross product, angular distance
