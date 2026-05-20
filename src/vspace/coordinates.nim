############################################################################################################################
###################################################### CRUISE COORDINATES ##################################################
############################################################################################################################

type
  CPolarCoord* = object
    ## 2D polar coordinate.
    ## `r`   — radial distance from the origin, r ≥ 0.
    ## `phi` — azimuthal angle in radians, φ ∈ [0, 2π).
    r*  : float64
    phi*: float64

func cpolar*(r: float64, phi: float64): CPolarCoord =
  ## Construct a CPolarCoord. Angle is wrapped to [0, 2π) automatically.
  CPolarCoord(r: abs(r), phi: phi.mod(2 * PI))

func cpolarFromCartesian*(x, y: float64): CPolarCoord =
  ## Construct a CPolarCoord from Cartesian components.
  cpolar(sqrt(x*x + y*y), arctan2(y, x))

func toCartesian*(c: CPolarCoord): CCartesianCoord[2, float64] =
  ## Convert polar to 2D Cartesian.
  CCartesianCoord[2, float64](components: [c.r * cos(c.phi), c.r * sin(c.phi)])

func fromCartesian*(_: typedesc[CPolarCoord], c: CCartesianCoord[2, float64]): CPolarCoord =
  ## Convert 2D Cartesian to polar.
  cpolarFromCartesian(c.components[0], c.components[1])

func rotate*(c: CPolarCoord, angle: float64): CPolarCoord =
  ## Rotate a polar coordinate by `angle` radians.
  cpolar(c.r, c.phi + angle)

func scale*(c: CPolarCoord, factor: float64): CPolarCoord =
  ## Scale the radial distance of a polar coordinate.
  cpolar(c.r * factor, c.phi)

func lerp*(a, b: CPolarCoord, t: float64): CPolarCoord =
  ## Interpolate between two polar coordinates.
  ## Angle is interpolated along the shortest arc.
  let da = ((b.phi - a.phi + PI).mod(2*PI)) - PI
  cpolar(a.r + (b.r - a.r) * t, a.phi + da * t)

# --------------------------------------------------------------------------------------------------------------------------
# CBipolarCoord — 2D bipolar coordinate (σ, τ)
# --------------------------------------------------------------------------------------------------------------------------

const DefaultBipolarFocus* = 1.0
  ## Default half-distance between the two foci of a bipolar coordinate system.

type
  CBipolarCoord* = object
    ## 2D bipolar coordinate with two foci at (−a, 0) and (+a, 0).
    ## `sigma` — log-radial coordinate, σ ∈ ℝ.
    ## `tau`   — angular coordinate,    τ ∈ [0, 2π).
    ## `a`     — half-distance between foci (default: 1.0).
    sigma*: float64
    tau*  : float64
    a*    : float64

func cbipolar*(sigma, tau: float64, a = DefaultBipolarFocus): CBipolarCoord =
  ## Construct a CBipolarCoord.
  CBipolarCoord(sigma: sigma, tau: tau.mod(2*PI), a: a)

func toCartesian*(c: CBipolarCoord): CCartesianCoord[2, float64] =
  ## Convert bipolar to 2D Cartesian.
  let denom = cosh(c.sigma) - cos(c.tau)
  CCartesianCoord[2, float64](components: [
    c.a * sinh(c.sigma) / denom,
    c.a * sin(c.tau)    / denom
  ])

func fromCartesian*(_: typedesc[CBipolarCoord], c: CCartesianCoord[2, float64],
                    a = DefaultBipolarFocus): CBipolarCoord =
  ## Convert 2D Cartesian to bipolar with half-focus distance `a`.
  let x = c.components[0]
  let y = c.components[1]
  let r1 = sqrt((x + a)^2 + y^2)
  let r2 = sqrt((x - a)^2 + y^2)
  let sigma = ln(r1 / r2)
  let tau   = arctan2(2*a*y, x^2 + y^2 - a^2)
  cbipolar(sigma, tau, a)

# --------------------------------------------------------------------------------------------------------------------------
# CCylindricalCoord — 3D cylindrical coordinate (r, φ, z)
# --------------------------------------------------------------------------------------------------------------------------

type
  CCylindricalCoord* = object
    ## 3D cylindrical coordinate.
    ## `r`   — radial distance from the z-axis, r ≥ 0.
    ## `phi` — azimuthal angle in radians, φ ∈ [0, 2π).
    ## `z`   — height along the z-axis.
    r*  : float64
    phi*: float64
    z*  : float64

func ccylindrical*(r, phi, z: float64): CCylindricalCoord =
  ## Construct a CCylindricalCoord. Angle is wrapped to [0, 2π).
  CCylindricalCoord(r: abs(r), phi: phi.mod(2*PI), z: z)

func toCartesian*(c: CCylindricalCoord): CCartesianCoord[3, float64] =
  ## Convert cylindrical to 3D Cartesian.
  CCartesianCoord[3, float64](components: [
    c.r * cos(c.phi),
    c.r * sin(c.phi),
    c.z
  ])

func fromCartesian*(_: typedesc[CCylindricalCoord], c: CCartesianCoord[3, float64]): CCylindricalCoord =
  ## Convert 3D Cartesian to cylindrical.
  let x = c.components[0]
  let y = c.components[1]
  let z = c.components[2]
  ccylindrical(sqrt(x*x + y*y), arctan2(y, x), z)

func liftZ*(c: CCylindricalCoord, dz: float64): CCylindricalCoord =
  ## Translate the coordinate along the z-axis by `dz`.
  ccylindrical(c.r, c.phi, c.z + dz)

func rotate*(c: CCylindricalCoord, angle: float64): CCylindricalCoord =
  ## Rotate the azimuthal angle by `angle` radians.
  ccylindrical(c.r, c.phi + angle, c.z)

func scale*(c: CCylindricalCoord, factor: float64): CCylindricalCoord =
  ## Scale the radial distance and z-height uniformly.
  ccylindrical(c.r * factor, c.phi, c.z * factor)

func lerp*(a, b: CCylindricalCoord, t: float64): CCylindricalCoord =
  ## Interpolate between two cylindrical coordinates.
  ## Angle interpolated along the shortest arc.
  let da = ((b.phi - a.phi + PI).mod(2*PI)) - PI
  ccylindrical(
    a.r + (b.r - a.r) * t,
    a.phi + da * t,
    a.z + (b.z - a.z) * t
  )

# --------------------------------------------------------------------------------------------------------------------------
# CSphericalCoord — 3D spherical coordinate (r, φ, θ)
# --------------------------------------------------------------------------------------------------------------------------

type
  CSphericalCoord* = object
    ## 3D spherical coordinate (physics convention).
    ## `r`     — radial distance from the origin, r ≥ 0.
    ## `phi`   — azimuthal angle in radians,  φ ∈ [0, 2π).
    ## `theta` — polar (inclination) angle,   θ ∈ [0, π].
    r*    : float64
    phi*  : float64
    theta*: float64

func cspherical*(r, phi, theta: float64): CSphericalCoord =
  ## Construct a CSphericalCoord. Angles are clamped/wrapped automatically.
  CSphericalCoord(
    r    : abs(r),
    phi  : phi.mod(2*PI),
    theta: clamp(theta, 0.0, PI)
  )

func toCartesian*(c: CSphericalCoord): CCartesianCoord[3, float64] =
  ## Convert spherical to 3D Cartesian (physics convention).
  CCartesianCoord[3, float64](components: [
    c.r * sin(c.theta) * cos(c.phi),
    c.r * sin(c.theta) * sin(c.phi),
    c.r * cos(c.theta)
  ])

func fromCartesian*(_: typedesc[CSphericalCoord], c: CCartesianCoord[3, float64]): CSphericalCoord =
  ## Convert 3D Cartesian to spherical.
  let x = c.components[0]
  let y = c.components[1]
  let z = c.components[2]
  let r = sqrt(x*x + y*y + z*z)
  cspherical(r, arctan2(y, x), if r == 0.0: 0.0 else: arccos(z / r))

func elevate*(c: CSphericalCoord, dtheta: float64): CSphericalCoord =
  ## Adjust the polar angle by `dtheta` radians (clamped to [0, π]).
  cspherical(c.r, c.phi, c.theta + dtheta)

func rotate*(c: CSphericalCoord, angle: float64): CSphericalCoord =
  ## Rotate the azimuthal angle by `angle` radians.
  cspherical(c.r, c.phi + angle, c.theta)

func scale*(c: CSphericalCoord, factor: float64): CSphericalCoord =
  ## Scale the radial distance.
  cspherical(c.r * factor, c.phi, c.theta)

func lerp*(a, b: CSphericalCoord, t: float64): CSphericalCoord =
  ## Interpolate between two spherical coordinates (SLERP-like).
  ## Angles interpolated along the shortest arc.
  let da = ((b.phi - a.phi + PI).mod(2*PI)) - PI
  cspherical(
    a.r + (b.r - a.r) * t,
    a.phi + da * t,
    a.theta + (b.theta - a.theta) * t
  )

func angularDistanceTo*(a, b: CSphericalCoord): float64 =
  ## Great-circle angular distance between two spherical coordinates in radians.
  ## Ignores the radial component.
  let cart_a = a.toCartesian()
  let cart_b = b.toCartesian()
  let d = dot(cart_a, cart_b) / (a.r * b.r)
  arccos(clamp(d, -1.0, 1.0))