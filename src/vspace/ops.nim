############################################################################################################################
#################################################### CRUISE SPACES OPERATION ###############################################
############################################################################################################################

# --------------------------------------------------------------------------------------------------------------------------
# CCartesianCoord operations
# --------------------------------------------------------------------------------------------------------------------------

func `+`*[N: static int, T: CReal](a, b: CCartesianCoord[N, T]): CCartesianCoord[N, T] =
  ## Component-wise addition of two cartesian coordinates.
  for i in 0 ..< N:
    result.components[i] = a.components[i] + b.components[i]

func `-`*[N: static int, T: CReal](a, b: CCartesianCoord[N, T]): CCartesianCoord[N, T] =
  ## Component-wise subtraction of two cartesian coordinates.
  for i in 0 ..< N:
    result.components[i] = a.components[i] - b.components[i]

func `*`*[N: static int, T: CReal](c: CCartesianCoord[N, T], scalar: T): CCartesianCoord[N, T] =
  ## Scale a cartesian coordinate by a scalar.
  for i in 0 ..< N:
    result.components[i] = c.components[i] * scalar

func `*`*[N: static int, T: CReal](scalar: T, c: CCartesianCoord[N, T]): CCartesianCoord[N, T] =
  ## Scale a cartesian coordinate by a scalar (commutative form).
  c * scalar

func dot*[N: static int, T: CReal](a, b: CCartesianCoord[N, T]): T =
  ## Dot product of two cartesian coordinates.
  for i in 0 ..< N:
    result += a.components[i] * b.components[i]

func cross*[T: CReal](a, b: CCartesianCoord[3, T]): CCartesianCoord[3, T] =
  ## Cross product of two 3D cartesian coordinates.
  result.components[0] = a.components[1] * b.components[2] - a.components[2] * b.components[1]
  result.components[1] = a.components[2] * b.components[0] - a.components[0] * b.components[2]
  result.components[2] = a.components[0] * b.components[1] - a.components[1] * b.components[0]

func norm*[N: static int, T: CReal](c: CCartesianCoord[N, T]): float64 =
  ## Euclidean norm (length) of a cartesian coordinate.
  var sum: float64 = 0
  for i in 0 ..< N:
    sum += float64(c.components[i]) * float64(c.components[i])
  sqrt(sum)

func distanceTo*[N: static int, T: CReal](a, b: CCartesianCoord[N, T]): float64 =
  ## Euclidean distance between two cartesian coordinates.
  (a - b).norm()

func lerp*[N: static int, T: CReal](a, b: CCartesianCoord[N, T], t: float64): CCartesianCoord[N, T] =
  ## Linear interpolation between two cartesian coordinates.
  ## t = 0 returns a, t = 1 returns b.
  for i in 0 ..< N:
    result.components[i] = T(float64(a.components[i]) * (1.0 - t) + float64(b.components[i]) * t)

func clamp*[N: static int, T: CReal](c: CCartesianCoord[N, T], lo, hi: T): CCartesianCoord[N, T] =
  ## Clamp every component of a cartesian coordinate to [lo, hi].
  for i in 0 ..< N:
    result.components[i] = clamp(c.components[i], lo, hi)

func mapComponents*[N: static int, T: CReal](c: CCartesianCoord[N, T], f: proc(x: T): T): CCartesianCoord[N, T] =
  ## Apply a function to every component of a cartesian coordinate.
  ##
  ## Example:
  ##   let abs_coord = coord.mapComponents(proc(x: float64): float64 = abs(x))
  for i in 0 ..< N:
    result.components[i] = f(c.components[i])

# --------------------------------------------------------------------------------------------------------------------------
# CRGBA operations
# --------------------------------------------------------------------------------------------------------------------------

func clamp*(c: CRGBA): CRGBA =
  ## Clamp all RGBA components to [0, 1].
  CRGBA(
    r: clamp(c.r, 0f, 1f),
    g: clamp(c.g, 0f, 1f),
    b: clamp(c.b, 0f, 1f),
    a: clamp(c.a, 0f, 1f)
  )

func lerp*(a, b: CRGBA, t: float32): CRGBA =
  ## Linear interpolation between two RGBA colors.
  ## t = 0 returns a, t = 1 returns b. Alpha is interpolated as well.
  CRGBA(
    r: a.r + (b.r - a.r) * t,
    g: a.g + (b.g - a.g) * t,
    b: a.b + (b.b - a.b) * t,
    a: a.a + (b.a - a.a) * t
  )

func mix*(a, b: CRGBA, t: float32): CRGBA =
  ## Alias for `lerp`. Blend two RGBA colors by factor t.
  lerp(a, b, t)

func luminance*(c: CRGBA): float32 =
  ## Perceived luminance of an RGBA color using the BT.709 coefficients.
  ## Alpha is ignored.
  0.2126f * c.r + 0.7152f * c.g + 0.0722f * c.b

func grayscale*(c: CRGBA): CRGBA =
  ## Convert an RGBA color to grayscale, preserving alpha.
  let l = luminance(c)
  CRGBA(r: l, g: l, b: l, a: c.a)

func invert*(c: CRGBA): CRGBA =
  ## Invert the RGB components of an RGBA color. Alpha is preserved.
  CRGBA(r: 1f - c.r, g: 1f - c.g, b: 1f - c.b, a: c.a)

func applyToRGB*(c: CRGBA, f: proc(x: float32): float32): CRGBA =
  ## Apply a function to every RGB component of an RGBA color. Alpha is preserved.
  ##
  ## Example — apply a gamma curve:
  ##   let corrected = color.applyToRGB(proc(x: float32): float32 = pow(x, 1f / 2.2f))
  CRGBA(r: f(c.r), g: f(c.g), b: f(c.b), a: c.a)

func applyToRGBA*(c: CRGBA, f: proc(x: float32): float32): CRGBA =
  ## Apply a function to every component of an RGBA color, including alpha.
  CRGBA(r: f(c.r), g: f(c.g), b: f(c.b), a: f(c.a))

func gamma*(c: CRGBA, g: float32): CRGBA =
  ## Apply gamma correction to the RGB components of an RGBA color.
  ## Values are assumed to be in [0, 1]. Alpha is preserved.
  c.applyToRGB(proc(x: float32): float32 = pow(x, g))
