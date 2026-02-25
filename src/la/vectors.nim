#############################################################################################################################
#################################################### VECTORS ################################################################
#############################################################################################################################

##
## Pure generic vector math for game development.
## All operations use Nim generics [T: Vec2], [T: Vec3], [T: Vec4]
## so that ANY struct satisfying the concept interface works automatically —
## no concrete return types, no wrapper boilerplate.
##
## Example:
##   type MyVec3 = object
##     x*, y*, z*: float32
##   let a = MyVec3(x:1, y:2, z:3)
##   let b = MyVec3(x:4, y:5, z:6)
##   echo dot(a, b)        # 32.0
##   echo cross(a, b)      # MyVec3(x:-3, y:6, z:-3)
##   echo normalize(a)     # MyVec3 with unit length
##

import math

type
  MFloat* = float32
  SomeInteger* = int8 | int16 | int32 | int64

  Vec2* = concept v
    ## Any type with x, y : MFloat fields satisfies this concept.
    compiles(v.x)
    compiles(v.y)
    not compiles(v.z)

  Vec3* = concept v
    ## Any type with x, y, z : MFloat fields satisfies this concept.
    compiles(v.x)
    compiles(v.y)
    compiles(v.z)
    not compiles(v.w)

  Vec4* = concept v
    ## Any type with x, y, z, w : MFloat fields satisfies this concept.
    compiles(v.x)
    compiles(v.y)
    compiles(v.z)
    compiles(v.w)

  Vec2f* = concept v
    ## Any type with x, y : MFloat fields satisfies this concept.
    v.x is MFloat
    v.y is MFloat
    not compiles(v.z)

  Vec3f* = concept v
    ## Any type with x, y, z : MFloat fields satisfies this concept.
    v.x is MFloat
    v.y is MFloat
    v.z is MFloat
    not compiles(v.w)

  Vec4f* = concept v
    ## Any type with x, y, z, w : MFloat fields satisfies this concept.
    v.x is MFloat
    v.y is MFloat
    v.z is MFloat
    v.w is MFloat

  Vec2i* = concept v
    ## Any type with x, y : MFloat fields satisfies this concept.
    v.x is SomeInteger
    v.y is SomeInteger
    not compiles(v.z)

  Vec3i* = concept v
    ## Any type with x, y, z : SomeInteger fields satisfies this concept.
    v.x is SomeInteger
    v.y is SomeInteger
    v.z is SomeInteger
    not compiles(v.w)

  Vec4i* = concept v
    ## Any type with x, y, z, w : SomeInteger fields satisfies this concept.
    v.x is SomeInteger
    v.y is SomeInteger
    v.z is SomeInteger
    v.w is SomeInteger


#############################################################################################################################
################################################## ARITHMETIC OPERATORS #####################################################
#############################################################################################################################
# Each operator is generic on the concept and returns the caller's own
# concrete type T, so the result type is never lost across the API.

# ─────────────────────────────────────────────────────────────────── Vec2 ───

template `+`*[T: Vec2](a, b: T): T =
  ## Component-wise addition.
  T(x: a.x + b.x, y: a.y + b.y)

template `-`*[T: Vec2](a, b: T): T =
  ## Component-wise subtraction.
  T(x: a.x - b.x, y: a.y - b.y)

template `-`*[T: Vec2](v: T): T =
  ## Unary negation — reverses the vector direction.
  T(x: -v.x, y: -v.y)

template `*`*[T: Vec2](a, b: T): T =
  ## Component-wise (Hadamard) product. Useful for non-uniform scaling.
  T(x: a.x * b.x, y: a.y * b.y)

template `*`*[T: Vec2](v: T, s: MFloat): T =
  ## Scale a Vec2 by a scalar.
  T(x: v.x * s, y: v.y * s)

template `*`*[T: Vec2](s: MFloat, v: T): T =
  ## Scalar-on-left scaling (commutative convenience).
  T(x: v.x * s, y: v.y * s)

template `/`*[T: Vec2](v: T, s: MFloat): T =
  ## Divide a Vec2 by a scalar (single reciprocal multiply internally).
  let inv = 1.MFloat / s
  T(x: v.x * inv, y: v.y * inv)

template `/`*[T: Vec2](a, b: T): T =
  ## Component-wise division.
  T(x: a.x / b.x, y: a.y / b.y)

template `+=`*[T: Vec2](a: var T, b: T) =
  ## In-place component-wise addition.
  a.x += b.x; a.y += b.y

template `-=`*[T: Vec2](a: var T, b: T) =
  ## In-place component-wise subtraction.
  a.x -= b.x; a.y -= b.y

template `*=`*[T: Vec2](v: var T, s: MFloat) =
  ## In-place scalar scaling.
  v.x *= s; v.y *= s

template `/=`*[T: Vec2](v: var T, s: MFloat) =
  ## In-place scalar division.
  let inv = 1.MFloat / s
  v.x *= inv; v.y *= inv

template `==`*[T, N: Vec2](a:T , b: N): bool =
  ## Exact component-wise equality. Prefer `approxEq` for float comparisons.
  a.x == b.x and a.y == b.y

# ─────────────────────────────────────────────────────────────────── Vec3 ───

template `+`*[T: Vec3](a, b: T): T =
  ## Component-wise addition.
  T(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)

template `-`*[T: Vec3](a, b: T): T =
  ## Component-wise subtraction.
  T(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)

template `-`*[T: Vec3](v: T): T =
  ## Unary negation.
  T(x: -v.x, y: -v.y, z: -v.z)

template `*`*[T: Vec3](a, b: T): T =
  ## Component-wise (Hadamard) product.
  T(x: a.x * b.x, y: a.y * b.y, z: a.z * b.z)

template `*`*[T: Vec3](v: T, s: MFloat): T =
  ## Scale a Vec3 by a scalar.
  T(x: v.x * s, y: v.y * s, z: v.z * s)

template `*`*[T: Vec3](s: MFloat, v: T): T =
  ## Scalar-on-left scaling.
  T(x: v.x * s, y: v.y * s, z: v.z * s)

template `/`*[T: Vec3](v: T, s: MFloat): T =
  ## Divide a Vec3 by a scalar.
  let inv = 1.MFloat / s
  T(x: v.x * inv, y: v.y * inv, z: v.z * inv)

template `/`*[T: Vec3](a, b: T): T =
  ## Component-wise division.
  T(x: a.x / b.x, y: a.y / b.y, z: a.z / b.z)

template `+=`*[T: Vec3](a: var T, b: T) =
  a.x += b.x; a.y += b.y; a.z += b.z

template `-=`*[T: Vec3](a: var T, b: T) =
  a.x -= b.x; a.y -= b.y; a.z -= b.z

template `*=`*[T: Vec3](v: var T, s: MFloat) =
  v.x *= s; v.y *= s; v.z *= s

template `/=`*[T: Vec3](v: var T, s: MFloat) =
  let inv = 1.MFloat / s
  v.x *= inv; v.y *= inv; v.z *= inv

template `==`*[T, N: Vec3](a: T, b: N): bool =
  a.x == b.x and a.y == b.y and a.z == b.z

# ─────────────────────────────────────────────────────────────────── Vec4 ───

template `+`*[T: Vec4](a, b: T): T =
  T(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, w: a.w + b.w)

template `-`*[T: Vec4](a, b: T): T =
  T(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z, w: a.w - b.w)

template `-`*[T: Vec4](v: T): T =
  T(x: -v.x, y: -v.y, z: -v.z, w: -v.w)

template `*`*[T: Vec4](a, b: T): T =
  T(x: a.x * b.x, y: a.y * b.y, z: a.z * b.z, w: a.w * b.w)

template `*`*[T: Vec4](v: T, s: MFloat): T =
  T(x: v.x * s, y: v.y * s, z: v.z * s, w: v.w * s)

template `*`*[T: Vec4](s: MFloat, v: T): T =
  T(x: v.x * s, y: v.y * s, z: v.z * s, w: v.w * s)

template `/`*[T: Vec4](v: T, s: MFloat): T =
  let inv = 1.MFloat / s
  T(x: v.x * inv, y: v.y * inv, z: v.z * inv, w: v.w * inv)

template `+=`*[T: Vec4](a: var T, b: T) =
  a.x += b.x; a.y += b.y; a.z += b.z; a.w += b.w

template `-=`*[T: Vec4](a: var T, b: T) =
  a.x -= b.x; a.y -= b.y; a.z -= b.z; a.w -= b.w

template `*=`*[T: Vec4](v: var T, s: MFloat) =
  v.x *= s; v.y *= s; v.z *= s; v.w *= s

template `/=`*[T: Vec4](v: var T, s: MFloat) =
  let inv = 1.MFloat / s
  v.x *= inv; v.y *= inv; v.z *= inv; v.w *= inv

template `==`*[T, N: Vec4](a: T, b: N): bool =
  a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w


#############################################################################################################################
################################################## DOT PRODUCT ##############################################################
#############################################################################################################################

template dot*[T, N: Vec2](a: N, b: T): MFloat =
  ## Dot product: |a|·|b|·cos(θ).
  ## Positive when vectors point the same way, 0 when perpendicular,
  ## negative when opposing. Core to lighting, projection and culling.
  a.x * b.x + a.y * b.y

template dot*[N, T: Vec3](a: N, b: T): MFloat =
  ## Dot product for Vec3.
  a.x * b.x + a.y * b.y + a.z * b.z

template dot*[N, T: Vec4](a: N, b: T): MFloat =
  ## Dot product for Vec4.
  a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w


#############################################################################################################################
################################################## CROSS PRODUCT ############################################################
#############################################################################################################################

template cross*[T: Vec3](a, b: T): T =
  ## Cross product of two Vec3 vectors (right-hand rule).
  ## Returns a vector perpendicular to both inputs.
  ## Magnitude = |a|·|b|·sin(θ) = area of parallelogram spanned by a and b.
  ## Used for: surface normals, torque, "up" vector in look-at matrices.
  T(x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x)

template cross*[N, T: Vec2](a: N, b: T): MFloat =
  ## 2D "cross product" (perp-dot product).
  ## Returns the Z component of the 3D cross product when z = 0.
  ## Positive → b is CCW from a; negative → CW.
  ## Used for: winding order tests, signed triangle area, 2D collisions.
  a.x * b.y - a.y * b.x


#############################################################################################################################
################################################## LENGTH / MAGNITUDE #######################################################
#############################################################################################################################

template lengthSq*[T: Vec2](v: T): MFloat =
  ## Squared Euclidean length. No sqrt — cheaper for comparisons.
  v.x * v.x + v.y * v.y

template length*[T: Vec2](v: T): MFloat =
  ## Euclidean length (magnitude) of a Vec2.
  sqrt(v.lengthSq)

template lengthSq*[T: Vec3](v: T): MFloat =
  ## Squared Euclidean length of a Vec3.
  v.x * v.x + v.y * v.y + v.z * v.z

template length*[T: Vec3](v: T): MFloat =
  ## Euclidean length of a Vec3.
  sqrt(v.lengthSq)

template lengthSq*[T: Vec4](v: T): MFloat =
  ## Squared Euclidean length of a Vec4.
  v.x * v.x + v.y * v.y + v.z * v.z + v.w * v.w

template length*[T: Vec4](v: T): MFloat =
  ## Euclidean length of a Vec4.
  sqrt(v.lengthSq)


#############################################################################################################################
################################################## NORMALIZATION ############################################################
#############################################################################################################################

template normalize*[T: Vec2](v: T): T =
  ## Return a unit-length (length = 1) copy of v.
  ## Result is NaN/Inf when v is the zero vector — use safeNormalize if unsure.
  v / v.length

template normalize*[T: Vec3](v: T): T =
  ## Return a unit-length copy of v.
  v / v.length

template normalize*[T: Vec4](v: T): T =
  ## Return a unit-length copy of v.
  v / v.length

template safeNormalize*[T: Vec2](v: T, fallback: T): T =
  ## Normalize v, returning fallback when v is nearly zero.
  ## Prevents NaN in degenerate cases (zero-velocity objects, null axes…).
  let l = v.length
  if l < 1e-8f: fallback else: v / l

template safeNormalize*[T: Vec3](v: T, fallback: T): T =
  ## Normalize v, returning fallback when v is nearly zero.
  let l = v.length
  if l < 1e-8f: fallback else: v / l


#############################################################################################################################
################################################## DISTANCE #################################################################
#############################################################################################################################

template distanceSq*[N, T: Vec2](a: N, b: T): MFloat =
  ## Squared Euclidean distance between two 2D points.
  ## Cheaper than distance() — ideal for radius/proximity checks.
  let dx = a.x - b.x; let dy = a.y - b.y
  dx * dx + dy * dy

template distance*[N, T: Vec2](a: N, b: T): MFloat =
  ## Euclidean distance between two 2D points.
  sqrt(distanceSq(a, b))

template distanceSq*[N, T: Vec3](a: N, b: T): MFloat =
  ## Squared Euclidean distance between two 3D points.
  let dx = a.x - b.x; let dy = a.y - b.y; let dz = a.z - b.z
  dx*dx + dy*dy + dz*dz

template distance*[N, T: Vec3](a: N, b: T): MFloat =
  ## Euclidean distance between two 3D points.
  sqrt(distanceSq(a, b))


#############################################################################################################################
################################################## INTERPOLATION ############################################################
#############################################################################################################################

template lerp*[T: Vec2](a, b: T, t: MFloat): T =
  ## Linear interpolation: t=0 → a, t=1 → b.
  ## t is NOT clamped — values outside [0,1] extrapolate beyond the segment.
  T(x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t)

template lerp*[T: Vec3](a, b: T, t: MFloat): T =
  ## Linear interpolation between two Vec3 values.
  T(x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
    z: a.z + (b.z - a.z) * t)

template lerp*[T: Vec4](a, b: T, t: MFloat): T =
  ## Linear interpolation between two Vec4 values.
  T(x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
    z: a.z + (b.z - a.z) * t,
    w: a.w + (b.w - a.w) * t)

template lerpClamped*[T: Vec2](a, b: T, t: MFloat): T =
  ## Lerp with t clamped to [0, 1]. Safe version that never extrapolates.
  lerp(a, b, clamp(t, 0.MFloat, 1.MFloat))

template lerpClamped*[T: Vec3](a, b: T, t: MFloat): T =
  lerp(a, b, clamp(t, 0.MFloat, 1.MFloat))

template lerpClamped*[T: Vec4](a, b: T, t: MFloat): T =
  lerp(a, b, clamp(t, 0.MFloat, 1.MFloat))

template slerp*[T: Vec3](a, b: T, t: MFloat): T =
  ## Spherical linear interpolation between two unit Vec3 vectors.
  ## Produces constant angular velocity — ideal for camera / orientation blending.
  ## Both a and b must be normalized. t in [0, 1].
  let cosA = clamp(dot(a, b), -1.MFloat, 1.MFloat)
  let angle = arccos(cosA)
  if angle < 1e-6f:
    return lerp(a, b, t)    # nearly identical — fall back to lerp
  let sinA = sin(angle)
  let wa   = sin((1.MFloat - t) * angle) / sinA
  let wb   = sin(t * angle) / sinA
  T(x: a.x * wa + b.x * wb,
    y: a.y * wa + b.y * wb,
    z: a.z * wa + b.z * wb)

template moveTowards*[T: Vec2](current, target: T, maxDelta: MFloat): T =
  ## Move current towards target by at most maxDelta units per call.
  ## Will not overshoot. Common in AI movement and UI easing.
  let dx   = target.x - current.x
  let dy   = target.y - current.y
  let dist = sqrt(dx*dx + dy*dy)
  if dist <= maxDelta or dist < 1e-8f:
    target
  else:
    let inv = maxDelta / dist
    T(x: current.x + dx * inv, y: current.y + dy * inv)

template moveTowards*[T: Vec3](current, target: T, maxDelta: MFloat): T =
  ## Move current towards target by at most maxDelta units per call (3D).
  let dx   = target.x - current.x
  let dy   = target.y - current.y
  let dz   = target.z - current.z
  let dist = sqrt(dx*dx + dy*dy + dz*dz)
  if dist <= maxDelta or dist < 1e-8f:
    target
  else:
    let inv = maxDelta / dist
    T(x: current.x + dx * inv,
      y: current.y + dy * inv,
      z: current.z + dz * inv)

template smoothStep*[T: Vec2](edge0, edge1, v: T): T =
  ## Per-component smoothstep — smooth Hermite interpolation in [edge0, edge1].
  ## Derivative is zero at the endpoints; useful for smooth procedural shaping.
  template s(a, b, x: MFloat): MFloat =
    let t = clamp((x - a) / (b - a), 0.MFloat, 1.MFloat)
    t * t * (3.MFloat - 2.MFloat * t)
  T(x: s(edge0.x, edge1.x, v.x),
    y: s(edge0.y, edge1.y, v.y))

template smoothStep*[T: Vec3](edge0, edge1, v: T): T =
  ## Per-component smoothstep for Vec3.
  func s(a, b, x: MFloat): MFloat =
    let t = clamp((x - a) / (b - a), 0.MFloat, 1.MFloat)
    t * t * (3.MFloat - 2.MFloat * t)
  T(x: s(edge0.x, edge1.x, v.x),
    y: s(edge0.y, edge1.y, v.y),
    z: s(edge0.z, edge1.z, v.z))


#############################################################################################################################
################################################## COMPONENT-WISE MATH ######################################################
#############################################################################################################################

template abs*[T: Vec2](v: T): T =
  ## Component-wise absolute value.
  T(x: abs(v.x), y: abs(v.y))

template abs*[T: Vec3](v: T): T =
  T(x: abs(v.x), y: abs(v.y), z: abs(v.z))

template abs*[T: Vec4](v: T): T =
  T(x: abs(v.x), y: abs(v.y), z: abs(v.z), w: abs(v.w))

template floor*[T: Vec2](v: T): T =
  ## Component-wise floor (round towards −∞).
  T(x: floor(v.x), y: floor(v.y))

template floor*[T: Vec3](v: T): T =
  T(x: floor(v.x), y: floor(v.y), z: floor(v.z))

template ceil*[T: Vec2](v: T): T =
  ## Component-wise ceiling (round towards +∞).
  T(x: ceil(v.x), y: ceil(v.y))

template ceil*[T: Vec3](v: T): T =
  T(x: ceil(v.x), y: ceil(v.y), z: ceil(v.z))

template round*[T: Vec2](v: T): T =
  ## Component-wise round to nearest integer.
  T(x: round(v.x), y: round(v.y))

template round*[T: Vec3](v: T): T =
  T(x: round(v.x), y: round(v.y), z: round(v.z))

template fract*[T: Vec2](v: T): T =
  ## Component-wise fractional part: v − floor(v). Each result in [0, 1).
  T(x: v.x - floor(v.x), y: v.y - floor(v.y))

template fract*[T: Vec3](v: T): T =
  T(x: v.x - floor(v.x), y: v.y - floor(v.y), z: v.z - floor(v.z))

template min*[T: Vec2](a, b: T): T =
  ## Component-wise minimum.
  T(x: min(a.x, b.x), y: min(a.y, b.y))

template min*[T: Vec3](a, b: T): T =
  T(x: min(a.x, b.x), y: min(a.y, b.y), z: min(a.z, b.z))

template max*[T: Vec2](a, b: T): T =
  ## Component-wise maximum.
  T(x: max(a.x, b.x), y: max(a.y, b.y))

template max*[T: Vec3](a, b: T): T =
  T(x: max(a.x, b.x), y: max(a.y, b.y), z: max(a.z, b.z))

template clamp*[T: Vec2](v, lo, hi: T): T =
  ## Component-wise clamp between lo and hi vectors.
  T(x: clamp(v.x, lo.x, hi.x), y: clamp(v.y, lo.y, hi.y))

template clamp*[T: Vec3](v, lo, hi: T): T =
  T(x: clamp(v.x, lo.x, hi.x),
    y: clamp(v.y, lo.y, hi.y),
    z: clamp(v.z, lo.z, hi.z))

template clamp*[T: Vec4](v, lo, hi: T): T =
  T(x: clamp(v.x, lo.x, hi.x), y: clamp(v.y, lo.y, hi.y),
    z: clamp(v.z, lo.z, hi.z), w: clamp(v.w, lo.w, hi.w))

template clamp*[T: Vec2](v: T, lo, hi: MFloat): T =
  ## Clamp all Vec2 components between scalar lo and hi.
  T(x: clamp(v.x, lo, hi), y: clamp(v.y, lo, hi))

template clamp*[T: Vec3](v: T, lo, hi: MFloat): T =
  T(x: clamp(v.x, lo, hi), y: clamp(v.y, lo, hi), z: clamp(v.z, lo, hi))

template clamp*[T: Vec4](v: T, lo, hi: MFloat): T =
  T(x: clamp(v.x, lo, hi), y: clamp(v.y, lo, hi),
    z: clamp(v.z, lo, hi), w: clamp(v.w, lo, hi))

template saturate*[T: Vec2](v: T): T =
  ## Clamp all components to [0, 1]. Essential for colour math and UV coords.
  T(x: clamp(v.x, 0f, 1f), y: clamp(v.y, 0f, 1f))

template saturate*[T: Vec3](v: T): T =
  T(x: clamp(v.x, 0f, 1f), y: clamp(v.y, 0f, 1f), z: clamp(v.z, 0f, 1f))

template saturate*[T: Vec4](v: T): T =
  T(x: clamp(v.x, 0f, 1f), y: clamp(v.y, 0f, 1f),
    z: clamp(v.z, 0f, 1f), w: clamp(v.w, 0f, 1f))

template sign*[T: Vec2](v: T): T =
  ## Component-wise sign: returns −1, 0, or +1 per component.
  T(x: MFloat(v.x.sgn), y: MFloat(v.y.sgn))

template sign*[T: Vec3](v: T): T =
  T(x: MFloat(v.x.sgn), y: MFloat(v.y.sgn), z: MFloat(v.z.sgn))

template sum*[T: Vec2](v: T): MFloat =
  ## Sum of all components. Useful for computing averages.
  v.x + v.y

template sum*[T: Vec3](v: T): MFloat =
  v.x + v.y + v.z

template sum*[T: Vec4](v: T): MFloat =
  v.x + v.y + v.z + v.w

template minComponent*[T: Vec2](v: T): MFloat =
  ## Smallest component value of v.
  min(v.x, v.y)

template minComponent*[T: Vec3](v: T): MFloat =
  min(v.x, min(v.y, v.z))

template maxComponent*[T: Vec2](v: T): MFloat =
  ## Largest component value of v.
  max(v.x, v.y)

template maxComponent*[T: Vec3](v: T): MFloat =
  max(v.x, max(v.y, v.z))


#############################################################################################################################
################################################## GEOMETRY / PHYSICS #######################################################
#############################################################################################################################

template reflect*[T: Vec2](incident, normal: T): T =
  ## Reflect the incident vector about a unit surface normal (2D).
  ## Formula: incident − 2·dot(incident, normal)·normal.
  let d = 2.MFloat * dot(incident, normal)
  T(x: incident.x - d * normal.x,
    y: incident.y - d * normal.y)

template reflect*[T: Vec3](incident, normal: T): T =
  ## Reflect the incident vector about a unit surface normal (3D).
  ## Classic uses: specular lighting, elastic collision response.
  let d = 2.MFloat * dot(incident, normal)
  T(x: incident.x - d * normal.x,
    y: incident.y - d * normal.y,
    z: incident.z - d * normal.z)

template refract*[T: Vec3](incident, normal: T, eta: MFloat): T =
  ## Refracted direction via Snell's law.
  ## eta = n₁/n₂ (e.g. 1.0/1.5 for air→glass).
  ## incident must be normalized and point towards the surface.
  ## Returns the zero vector on total internal reflection.
  let ni = dot(normal, incident)
  let k  = 1.MFloat - eta * eta * (1.MFloat - ni * ni)
  if k < 0:
    T(x: 0, y: 0, z: 0)    # total internal reflection
  else:
    let c = eta * ni + sqrt(k)
    T(x: eta * incident.x - c * normal.x,
      y: eta * incident.y - c * normal.y,
      z: eta * incident.z - c * normal.z)

template project*[T: Vec2](v, onto: T): T =
  ## Project v onto `onto`. onto need not be normalized.
  ## Returns the component of v along the direction of onto.
  onto * (dot(v, onto) / onto.lengthSq)

template project*[T: Vec3](v, onto: T): T =
  ## Project v onto `onto` (3D). onto need not be normalized.
  onto * (dot(v, onto) / onto.lengthSq)

template reject*[T: Vec2](v, onto: T): T =
  ## Rejection of v from `onto` — the component of v perpendicular to onto.
  ## Invariant: project(v, onto) + reject(v, onto) == v.
  v - project(v, onto)

template reject*[T: Vec3](v, onto: T): T =
  v - project(v, onto)

template perpendicular*[T: Vec2](v: T): T =
  ## Return a vector perpendicular to v, rotated 90° counter-clockwise.
  T(x: -v.y, y: v.x)

template faceForward*[T: Vec3](n, incident, nRef: T): T =
  ## Return n oriented so it faces the same hemisphere as nRef relative to
  ## incident. Useful for ensuring surface normals face the camera/viewer.
  if dot(nRef, incident) < 0: n else: T(x: -n.x, y: -n.y, z: -n.z)


#############################################################################################################################
################################################## ANGLE UTILITIES ##########################################################
#############################################################################################################################

template angle*[N, T: Vec2](a: N, b: T): MFloat =
  ## Unsigned angle in radians between two Vec2 vectors (both must be non-zero).
  arccos(clamp(dot(a, b) / (a.length * b.length), -1.MFloat, 1.MFloat))

template angle*[N, T: Vec3](a: N, b: T): MFloat =
  ## Unsigned angle in radians between two Vec3 vectors.
  arccos(clamp(dot(a, b) / (a.length * b.length), -1.MFloat, 1.MFloat))

template signedAngle*[N, T: Vec2](a: N, b: T): MFloat =
  ## Signed angle in radians from a to b.
  ## Positive = counter-clockwise, negative = clockwise.
  arctan2(cross(a, b), dot(a, b))

template toAngle*[T: Vec2](v: T): MFloat =
  ## Angle of v relative to the +X axis in radians (= atan2(y, x)).
  arctan2(v.y, v.x)

template rotate*[T: Vec2](v: T, angle: MFloat): T =
  ## Rotate a Vec2 by `angle` radians counter-clockwise around the origin.
  let c = cos(angle); let s = sin(angle)
  T(x: v.x * c - v.y * s,
    y: v.x * s + v.y * c)

template rotateAround*[T: Vec2](v, pivot: T, angle: MFloat): T =
  ## Rotate v around an arbitrary 2D pivot point by `angle` radians.
  let c  = cos(angle); let s = sin(angle)
  let dx = v.x - pivot.x;  let dy = v.y - pivot.y
  T(x: pivot.x + dx * c - dy * s,
    y: pivot.y + dx * s + dy * c)


#############################################################################################################################
################################################## APPROXIMATE EQUALITY #####################################################
#############################################################################################################################

template approxEq*[N, T: Vec2](a: N, b: T, eps: MFloat = 1e-6f): bool =
  ## Component-wise approximate equality within epsilon.
  ## Prefer over `==` when comparing computed floating-point vectors.
  abs(a.x - b.x) <= eps and abs(a.y - b.y) <= eps

template approxEq*[N, T: Vec3](a: N, b: T, eps: MFloat = 1e-6f): bool =
  abs(a.x - b.x) <= eps and abs(a.y - b.y) <= eps and abs(a.z - b.z) <= eps

template approxEq*[N, T: Vec4](a: N, b: T, eps: MFloat = 1e-6f): bool =
  abs(a.x - b.x) <= eps and abs(a.y - b.y) <= eps and
  abs(a.z - b.z) <= eps and abs(a.w - b.w) <= eps

template isNormalized*[T: Vec2](v: T, eps: MFloat = 1e-5f): bool =
  ## True if v has unit length within epsilon.
  abs(v.lengthSq - 1.MFloat) <= eps

template isNormalized*[T: Vec3](v: T, eps: MFloat = 1e-5f): bool =
  abs(v.lengthSq - 1.MFloat) <= eps

template isZero*[T: Vec2](v: T, eps: MFloat = 1e-8f): bool =
  ## True if v is effectively the zero vector.
  v.lengthSq <= eps * eps

template isZero*[T: Vec3](v: T, eps: MFloat = 1e-8f): bool =
  v.lengthSq <= eps * eps


#############################################################################################################################
################################################## STRING REPRESENTATION ####################################################
#############################################################################################################################

template `$`*[T: Vec2](v: T): string =
  ## Pretty-print any Vec2-compatible value as "(x, y)".
  "(" & $v.x & ", " & $v.y & ")"

template `$`*[T: Vec3](v: T): string =
  ## Pretty-print any Vec3-compatible value as "(x, y, z)".
  "(" & $v.x & ", " & $v.y & ", " & $v.z & ")"

template `$`*[T: Vec4](v: T): string =
  ## Pretty-print any Vec4-compatible value as "(x, y, z, w)".
  "(" & $v.x & ", " & $v.y & ", " & $v.z & ", " & $v.w & ")"
