#############################################################################################################################
################################################## RANDOM DISTRIBUTIONS #####################################################
#############################################################################################################################
##
## Spatial random distributions for game development.
## All functions return any type satisfying Vec2/Vec3/Vec4 concepts —
## pass the desired output type as the last argument.
##
## Every sampler takes pre-drawn uniform values [0,1) as input so you can
## plug in ANY random source: stdlib `random`, a seeded RNG, a quasi-random
## sequence (Halton, Sobol…), or a deterministic replay buffer.
##
## Usage:
##   import random
##   var rng = initRand(42)
##
##   # With stdlib RNG
##   let p = randInSphere[MyVec3](rng)
##
##   # With raw uniforms (bring-your-own RNG)
##   let p = randInSphereRaw[MyVec3](u, v, r)
##
##   # Global RNG shorthand
##   let p = randInSphere[MyVec3]()
##

import math, random

# ── internal shorthand ────────────────────────────────────────────────────────
template u01(rng: var Rand): MFloat = rng.rand(1.0).MFloat
template u01(): MFloat = rand(1.0).MFloat

#############################################################################################################################
################################################## 1-D HELPERS ##############################################################
#############################################################################################################################

template randRange*(rng: var Rand; lo, hi: MFloat): MFloat  =
  ## Uniform float in [lo, hi).
  lo + rng.u01 * (hi - lo)

template randRange*(lo, hi: MFloat): MFloat  =
  ## Uniform float in [lo, hi) using the global RNG.
  lo + u01() * (hi - lo)

template randSign*(rng: var Rand): MFloat  =
  ## Returns -1 or +1 with equal probability.
  if rng.rand(1) == 0: -1f else: 1f

template randSign*(): MFloat  =
  if rand(1) == 0: -1f else: 1f

#############################################################################################################################
################################################## CIRCLE / DISK (2-D) ######################################################
#############################################################################################################################

template randOnCircleRaw*[V: Vec2](u: MFloat): V  =
  ## Uniform point ON the unit circle (perimeter) from 1 uniform value.
  ## u in [0, 1).
  let angle = u * (MFloat(PI) * 2f)
  V(x: cos(angle), y: sin(angle))

template randOnCircle*[V: Vec2](rng: var Rand): V  =
  ## Uniform point ON the unit circle using the given RNG.
  randOnCircleRaw[V](rng.u01, V)

template randOnCircle*[V: Vec2](t: typedesc[V]): V  =
  ## Uniform point ON the unit circle using the global RNG.
  randOnCircleRaw[V](u01(), V)

# ─────────────────────────────────────────────────────────────────────────────

template randInDiskRaw*[V: Vec2](u, v: MFloat): V  =
  ## Uniform point IN the unit disk (area) from 2 uniform values.
  ## Uses sqrt(v) for radius so area is uniformly covered.
  ## Source: https://mathworld.wolfram.com/DiskPointPicking.html
  let
    angle = u * (MFloat(PI) * 2f)
    r     = sqrt(v)           # NOT v — sqrt corrects for polar-area bias
  V(x: r * cos(angle), y: r * sin(angle))

template randInDisk*[V: Vec2](rng: var Rand): V  =
  randInDiskRaw[V](rng.u01, rng.u01, V)

template randInDisk*[V: Vec2](t: typedesc[V]): V  =
  randInDiskRaw[V](u01(), u01(), V)

# ─────────────────────────────────────────────────────────────────────────────

template randInAnnulusRaw*[V: Vec2](u, v, innerR, outerR: MFloat): V  =
  ## Uniform point in an annulus (ring) between innerR and outerR.
  ## 2 uniform values required.
  let
    angle = u * (MFloat(PI) * 2f)
    r     = sqrt(innerR*innerR + v*(outerR*outerR - innerR*innerR))
  V(x: r * cos(angle), y: r * sin(angle))

template randInAnnulus*[V: Vec2](rng: var Rand, innerR, outerR: MFloat): V  =
  randInAnnulusRaw[V](rng.u01, rng.u01, innerR, outerR, V)

template randInAnnulus*[V: Vec2](innerR, outerR: MFloat): V  =
  randInAnnulusRaw[V](u01(), u01(), innerR, outerR, V)

#############################################################################################################################
################################################## SPHERE / BALL (3-D) ######################################################
#############################################################################################################################

template randOnSphereRaw*[V: Vec3](u, v: MFloat): V  =
  ## Uniform point ON the unit sphere (surface) from 2 uniform values.
  ## Uses the Marsaglia / equal-area mapping — no clustering at poles.
  ## Source: https://mathworld.wolfram.com/SpherePointPicking.html
  let
    phi    = arccos(1f - 2f * v)   # elevation: maps v∈[0,1] → φ∈[0,π]
    theta  = u * (MFloat(PI) * 2f) # azimuth
    sinPhi = sin(phi)
  V(x: sinPhi * cos(theta),
    y: sinPhi * sin(theta),
    z: cos(phi))

template randOnSphere*[V: Vec3](rng: var Rand): V  =
  randOnSphereRaw[V](rng.u01, rng.u01, V)

template randOnSphere*[V: Vec3](t: typedesc[V]): V  =
  randOnSphereRaw[V](u01(), u01(), V)

# ─────────────────────────────────────────────────────────────────────────────

template randInSphereRaw*[V: Vec3](u, v, r: MFloat): V  =
  ## Uniform point IN the unit sphere (volume) from 3 uniform values.
  ## cbrt(r) corrects for the volume-element bias in spherical coordinates,
  ## ensuring points are uniformly distributed throughout the ball.
  ## Source: https://karthikkaranth.me/blog/generating-random-points-in-a-sphere/
  let
    theta = u * (MFloat(PI) * 2f)   # azimuth  ∈ [0, 2π)
    phi   = arccos(2f * v - 1f)     # elevation ∈ [0, π]
    rr    = cbrt(r)                  # cbrt corrects volume-element bias
    sp    = sin(phi)
    cp = cos(phi)
    st    = sin(theta)
    ct = cos(theta)
  V(x: rr * sp * ct,
    y: rr * sp * st,
    z: rr * cp)

template randInSphere*[V: Vec3](rng: var Rand): V  =
  ## Uniform point in the unit sphere using the given RNG.
  randInSphereRaw[V](rng.u01, rng.u01, rng.u01, V)

template randInSphere*[V: Vec3](t: typedesc[V]): V  =
  ## Uniform point in the unit sphere using the global RNG.
  randInSphereRaw[V](u01(), u01(), u01(), V)

# ─────────────────────────────────────────────────────────────────────────────

template randInShellRaw*[V: Vec3](u, v, r, innerR, outerR: MFloat): V  =
  ## Uniform point in a spherical shell between innerR and outerR.
  ## 3 uniform values required.
  let dir = randOnSphereRaw[V](u, v, V)
  let rr  = cbrt(innerR*innerR*innerR +
                 r*(outerR*outerR*outerR - innerR*innerR*innerR))
  V(x: dir.x*rr, y: dir.y*rr, z: dir.z*rr)

template randInShell*[V: Vec3](rng: var Rand, innerR, outerR: MFloat): V  =
  randInShellRaw[V](rng.u01, rng.u01, rng.u01, innerR, outerR, V)

template randInShell*[V: Vec3](innerR, outerR: MFloat): V  =
  randInShellRaw[V](u01(), u01(), u01(), innerR, outerR, V)

#############################################################################################################################
################################################## HEMISPHERE ###############################################################
#############################################################################################################################

template randOnHemisphereRaw*[V: Vec3](u, v: MFloat): V  =
  ## Uniform point on the upper unit hemisphere (z >= 0).
  ## Used for diffuse shading, ambient occlusion, cosine-weighted sampling.
  let p = randOnSphereRaw[V](u, v, V)
  V(x: p.x, y: p.y, z: abs(p.z))   # reflect below-equator points up

template randOnHemisphere*[V: Vec3](rng: var Rand): V  =
  randOnHemisphereRaw[V](rng.u01, rng.u01, V)

template randOnHemisphere*[V: Vec3](t: typedesc[V]): V  =
  randOnHemisphereRaw[V](u01(), u01(), V)

# ─────────────────────────────────────────────────────────────────────────────

template randCosineHemisphereRaw*[V: Vec3](u, v: MFloat): V  =
  ## Cosine-weighted sample on the upper hemisphere — biased towards the pole.
  ## Ideal importance-sampling distribution for Lambertian (diffuse) BRDFs.
  ## Source: PBR Book §13.6
  let
    r     = sqrt(v)
    theta = u * (MFloat(PI) * 2f)
  V(x: r * cos(theta),
    y: r * sin(theta),
    z: sqrt(max(0f, 1f - v)))   # z = sqrt(1 - r²), always >= 0

template randCosineHemisphere*[V: Vec3](rng: var Rand): V  =
  randCosineHemisphereRaw[V](rng.u01, rng.u01, V)

template randCosineHemisphere*[V: Vec3](t: typedesc[V]): V  =
  randCosineHemisphereRaw[V](u01(), u01(), V)

#############################################################################################################################
################################################## RECTANGLES / BOXES #######################################################
#############################################################################################################################

template randInRectRaw*[V: Vec2](u, v: MFloat): V  =
  ## Uniform point in the unit square [0,1)².
  V(x: u, y: v)

template randInRect*[V: Vec2](rng: var Rand): V  =
  V(x: rng.u01, y: rng.u01)

template randInRect*[V: Vec2](t: typedesc[V]): V  =
  V(x: u01(), y: u01())

template randInRectRangeRaw*[V: Vec2](u, v: MFloat,
                                   minX, maxX, minY, maxY: MFloat,
                                   t: typedesc[V]): V  =
  ## Uniform point in an axis-aligned rectangle.
  V(x: minX + u*(maxX-minX), y: minY + v*(maxY-minY))

template randInRectRange*[V: Vec2](rng: var Rand,
                                minX, maxX, minY, maxY: MFloat,
                                t: typedesc[V]): V  =
  randInRectRangeRaw[V](rng.u01, rng.u01, minX, maxX, minY, maxY, V)

# ─────────────────────────────────────────────────────────────────────────────

template randInBoxRaw*[V: Vec3](u, v, w: MFloat): V  =
  ## Uniform point in the unit cube [0,1)³.
  V(x: u, y: v, z: w)

template randInBox*[V: Vec3](rng: var Rand): V  =
  V(x: rng.u01, y: rng.u01, z: rng.u01)

template randInBox*[V: Vec3](t: typedesc[V]): V  =
  V(x: u01(), y: u01(), z: u01())

template randInBoxRange*[V: Vec3](rng: var Rand,
                               minP, maxP: V,
                               t: typedesc[V]): V  =
  ## Uniform point in an axis-aligned box defined by minP and maxP.
  V(x: minP.x + rng.u01*(maxP.x-minP.x),
    y: minP.y + rng.u01*(maxP.y-minP.y),
    z: minP.z + rng.u01*(maxP.z-minP.z))

#############################################################################################################################
################################################## TRIANGLE #################################################################
#############################################################################################################################

template randInTriangleRaw*[V: Vec2](u, v: MFloat, a, b, c: V): V  =
  ## Uniform point inside a 2D triangle (a, b, c) using 2 uniform values.
  ## Uses the square-root mapping to avoid the fold-back trick.
  ## Source: Osada et al. 2002
  let
    r1 = sqrt(u)
    s  = 1f - r1
    w0 = 1f - r1        # = s
    w1 = r1 * (1f - v)
    w2 = r1 * v
  V(x: w0*a.x + w1*b.x + w2*c.x,
    y: w0*a.y + w1*b.y + w2*c.y)

template randInTriangle*[V: Vec2](rng: var Rand, a, b, c: V): V  =
  randInTriangleRaw[V](rng.u01, rng.u01, a, b, c, V)

template randInTriangle3DRaw*[V: Vec3](u, v: MFloat, a, b, c: V): V  =
  ## Uniform point inside a 3D triangle (a, b, c).
  let
    r1 = sqrt(u)
    w0 = 1f - r1
    w1 = r1 * (1f - v)
    w2 = r1 * v
  V(x: w0*a.x + w1*b.x + w2*c.x,
    y: w0*a.y + w1*b.y + w2*c.y,
    z: w0*a.z + w1*b.z + w2*c.z)

template randInTriangle3D*[V: Vec3](rng: var Rand, a, b, c: V): V  =
  randInTriangle3DRaw[V](rng.u01, rng.u01, a, b, c, V)

#############################################################################################################################
################################################## DIRECTION / ORIENTATION ##################################################
#############################################################################################################################

template randDirection2DRaw*[V: Vec2](u: MFloat): V  =
  ## Uniform random unit vector in 2D. Alias for randOnCircle.
  randOnCircleRaw[V](u, V)

template randDirection2D*[V: Vec2](rng: var Rand): V  =
  randOnCircle[V](rng, V)

template randDirection3D*[V: Vec3](rng: var Rand): V  =
  ## Uniform random unit vector in 3D. Alias for randOnSphere.
  randOnSphere[V](rng, V)

template randDirection3D*[V: Vec3](t: typedesc[V]): V  =
  randOnSphere[V](V)

template randConeRaw*[V: Vec3](u, v, halfAngle: MFloat,
                             axis: V): V =
  ## Uniform random direction within a cone of `halfAngle` radians around `axis`.
  ## axis must be normalised. Used for spotlight penumbra, fuzzy reflections.
  let
    cosA  = cos(halfAngle)
    z     = cosA + v * (1f - cosA)      # z ∈ [cosA, 1]
    r     = sqrt(max(0f, 1f - z*z))
    phi   = u * (MFloat(PI) * 2f)
    # local direction
    lx    = r * cos(phi)
    ly    = r * sin(phi)
    lz    = z
    # build an orthonormal basis around axis (Frisvad 2012)
    sign  = if axis.z >= 0f: 1f else: -1f
    aa    = -1f / (sign + axis.z)
    bb    = axis.x * axis.y * aa
    tx    = 1f + sign * axis.x * axis.x * aa
    ty    = sign * bb
    tz    = -sign * axis.x
    bx    = bb
    by    = sign + axis.y * axis.y * aa
    bz    = -axis.y
  V(x: lx*tx + ly*bx + lz*axis.x,
    y: lx*ty + ly*by + lz*axis.y,
    z: lx*tz + ly*bz + lz*axis.z)

template randCone*[V: Vec3](rng: var Rand, halfAngle: MFloat,
                         axis: V): V  =
  randConeRaw[V](rng.u01, rng.u01, halfAngle, axis, V)

template randCone*[V: Vec3](halfAngle: MFloat, axis: V): V  =
  randConeRaw[V](u01(), u01(), halfAngle, axis, V)

#############################################################################################################################
################################################## GAUSSIAN #################################################################
#############################################################################################################################

template randGaussian*(rng: var Rand, mean: MFloat = 0f, std: MFloat = 1f): MFloat =
  ## Box-Muller transform — produces one Gaussian sample from 2 uniforms.
  ## More efficient to call randGaussian2 and use both outputs.
  let u = max(rng.u01, 1e-7f)   # guard against log(0)
  let v = rng.u01
  mean + std * sqrt(-2f * ln(u)) * cos(MFloat(PI) * 2f * v)

template randGaussian2*(rng: var Rand,
                    mean: MFloat = 0f,
                    std:  MFloat = 1f): (MFloat, MFloat) =
  ## Box-Muller: produces TWO independent Gaussian samples efficiently.
  let u = max(rng.u01, 1e-7f)
  let v = rng.u01
  let r = std * sqrt(-2f * ln(u))
  let a = MFloat(PI) * 2f * v
  (mean + r*cos(a), mean + r*sin(a))

template randGaussianVec2*[V: Vec2](rng: var Rand, std: MFloat = 1f): V =
  ## 2D isotropic Gaussian — each component independently N(0, std²).
  let (a, b) = randGaussian2(rng, 0f, std)
  V(x: a, y: b)

template randGaussianVec3*[V: Vec3](rng: var Rand, std: MFloat = 1f): V =
  ## 3D isotropic Gaussian — used for particle velocity scatter,
  ## perturbing normals, or generating random walk steps.
  let (a, b) = randGaussian2(rng, 0f, std)
  let c      = randGaussian(rng, 0f, std)
  V(x: a, y: b, z: c)

template randGaussianOnSphere*[V: Vec3](rng: var Rand): V =
  ## Uniform sphere sample via normalised 3D Gaussian.
  ## Alternative to the trig-based method — same distribution, different path.
  let v = randGaussianVec3[V](rng, 1f, V)
  let l = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
  if l < 1e-8f: V(x:0f, y:0f, z:1f)
  else: V(x:v.x/l, y:v.y/l, z:v.z/l)