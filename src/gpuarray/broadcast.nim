##########################################################################################################################################################
################################################################ OPERATORS BROADCASTING ##################################################################
##########################################################################################################################################################
##
## Generic (backend-agnostic) interface for GPUSeq / GPUArray operations.
##
## Every template below is a no-op stub (`discard`) whose sole purpose is to
## document the contract that every backend (CPU, OpenCL, …) must satisfy.
## Concrete implementations live in the backend files.
##
## Conventions
## -----------
##   T         – a GPUSeq or GPUArray concrete type
##   SomeNumber – SomeInteger | SomeFloat (Nim standard type class)
##   "into"    – non-allocating variant; writes result into a caller-supplied
##               destination buffer instead of allocating a fresh one

# ── already present ──────────────────────────────────────────────────────────

template `+`*[T: GPUSeq | GPUArray](g1, g2: T) = discard
template `-`*[T: GPUSeq | GPUArray](g1, g2: T) = discard
template `*`*[T: GPUSeq | GPUArray](g1, g2: T) = discard
template `/`*[T: GPUSeq | GPUArray](g1, g2: T) = discard

template `+`*[T: GPUSeq | GPUArray](g: T, n: SomeInteger) = discard
template `-`*[T: GPUSeq | GPUArray](g: T, n: SomeInteger) = discard
template `*`*[T: GPUSeq | GPUArray](g: T, n: SomeInteger) = discard
template `/`*[T: GPUSeq | GPUArray](g: T, n: SomeInteger) = discard

template `+`*[T: GPUSeq | GPUArray](g: T, n: SomeFloat) = discard
template `-`*[T: GPUSeq | GPUArray](g: T, n: SomeFloat) = discard
template `*`*[T: GPUSeq | GPUArray](g: T, n: SomeFloat) = discard
template `/`*[T: GPUSeq | GPUArray](g: T, n: SomeFloat) = discard

template sin*[T: GPUSeq | GPUArray](g: T) = discard
template cos*[T: GPUSeq | GPUArray](g: T) = discard
template tan*[T: GPUSeq | GPUArray](g: T) = discard
template exp*[T: GPUSeq | GPUArray](g: T) = discard
template arccos*[T: GPUSeq | GPUArray](g: T) = discard
template arcsin*[T: GPUSeq | GPUArray](g: T) = discard
template arctan*[T: GPUSeq | GPUArray](g: T) = discard
template sqrt*[T: GPUSeq | GPUArray](g: T) = discard
template ln*[T: GPUSeq | GPUArray](g: T) = discard
template abs*[T: GPUSeq | GPUArray](g: T) = discard

# ── commutative scalar forms (scalar OP seq) ─────────────────────────────────

template `+`*[T: GPUSeq | GPUArray](n: SomeInteger, g: T) = discard
  ## Commutative addition:  n + g  ≡  g + n
template `*`*[T: GPUSeq | GPUArray](n: SomeInteger, g: T) = discard
  ## Commutative multiplication:  n * g  ≡  g * n

template `+`*[T: GPUSeq | GPUArray](n: SomeFloat, g: T) = discard
  ## Commutative addition:  n + g  ≡  g + n
template `*`*[T: GPUSeq | GPUArray](n: SomeFloat, g: T) = discard
  ## Commutative multiplication:  n * g  ≡  g * n

# ── asymmetric scalar forms (scalar - seq, scalar / seq) ─────────────────────
##
## These are NOT equivalent to their reversed forms and require explicit
## backend implementations (e.g. result[i] = n - g[i]).

template `-`*[T: GPUSeq | GPUArray](n: SomeNumber, g: T) = discard
  ## Scalar minus every element:  result[i] = n - g[i]
template `/`*[T: GPUSeq | GPUArray](n: SomeNumber, g: T) = discard
  ## Scalar divided by every element:  result[i] = n / g[i]

# ── fill — constant initialisation ───────────────────────────────────────────

template fill*[T: GPUSeq | GPUArray](g: T, val: auto) = discard
  ## Set every element of `g` to `val`.
  ##
  ## Mutates `g` in place; no allocation.
  ##
  ## Example:
  ##   var s = newCPUSeq[float32](4)
  ##   s.fill(0.0'f32)   # → [0, 0, 0, 0]

# ── scalar reductions ─────────────────────────────────────────────────────────

template sum*[T: GPUSeq](g: T): auto = discard
  ## Sum of all logical elements.  Returns 0 for an empty sequence.

template min*[T: GPUSeq](g: T): auto = discard
  ## Minimum element.  Raises `ValueError` on an empty sequence.

template max*[T: GPUSeq](g: T): auto = discard
  ## Maximum element.  Raises `ValueError` on an empty sequence.

template dot*[T: GPUSeq](g1, g2: T): auto = discard
  ## Dot product: sum of g1[i] * g2[i].
  ## Both sequences must have the same logical length.

# ── toOpenArray — zero-copy logical slice ─────────────────────────────────────

template toOpenArray*[T: GPUSeq](g: T, start, stop: int): T = discard
  ## Return a logical view of `g` covering indices [start, stop).
  ##
  ## No data is copied.  The view and the original share the same backing
  ## buffer; writes through either handle are immediately visible to the other.
  ##
  ## Parameters:
  ##   start – first logical index to include (inclusive)
  ##   stop  – first logical index to exclude (exclusive)

# ── non-allocating "into" variants — binary ───────────────────────────────────
##
## Write element-wise results into a caller-supplied buffer `dst`, reusing its
## existing allocation when capacity is sufficient.  `dst.length` is always
## updated to match the source length.
##
## Typical usage (allocation-free hot loop):
##   var buf = newCPUSeq[float32](n)    # allocate once
##   for step in 0..<iters:
##     add(a, b, buf)                   # reuse buf — zero allocation

template add*[T: GPUSeq](g1, g2: T, dst: var T) = discard
  ## Element-wise addition into `dst`:         dst[i] = g1[i] + g2[i]
template sub*[T: GPUSeq](g1, g2: T, dst: var T) = discard
  ## Element-wise subtraction into `dst`:      dst[i] = g1[i] - g2[i]
template mul*[T: GPUSeq](g1, g2: T, dst: var T) = discard
  ## Element-wise multiplication into `dst`:   dst[i] = g1[i] * g2[i]
template divInto*[T: GPUSeq](g1, g2: T, dst: var T) = discard
  ## Element-wise division into `dst`:         dst[i] = g1[i] / g2[i]
  ## Named `divInto` to avoid shadowing Nim's built-in integer `div`.

# ── non-allocating "into" variants — scalar broadcast ────────────────────────

template addScalar*[T: GPUSeq](g: T, scalar: auto, dst: var T) = discard
  ## Scalar addition into `dst`:     dst[i] = g[i] + scalar
template subScalar*[T: GPUSeq](g: T, scalar: auto, dst: var T) = discard
  ## Scalar subtraction into `dst`:  dst[i] = g[i] - scalar
template mulScalar*[T: GPUSeq](g: T, scalar: auto, dst: var T) = discard
  ## Scalar multiplication into `dst`: dst[i] = g[i] * scalar
template divScalar*[T: GPUSeq](g: T, scalar: auto, dst: var T) = discard
  ## Scalar division into `dst`:     dst[i] = g[i] / scalar

# ── non-allocating "into" variants — unary / trigonometric ───────────────────
##
## Constrained to floating-point element types (SomeFloat) except `absInto`
## which accepts any numeric type, matching the allocating `abs` proc.

template sinInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise sine into `dst`.
template cosInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise cosine into `dst`.
template tanInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise tangent into `dst`.
template arcsinInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise arc sine into `dst`.
template arccosInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise arc cosine into `dst`.
template arctanInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise arc tangent into `dst`.
template sqrtInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise square root into `dst`.
template expInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise e^x into `dst`.
template lnInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise natural logarithm into `dst`.
template absInto*[T: GPUSeq](g: T, dst: var T) = discard
  ## Element-wise absolute value into `dst`.  Works on integers and floats.

# ── compound-assignment operators — seq / seq ─────────────────────────────────
##
## Mutate the left-hand side in place without allocating a new buffer.
## Both operands must have the same logical length.

template `+=`*[T: GPUSeq](g1: var T, g2: T) = discard
  ## In-place element-wise addition:       g1[i] += g2[i]
template `-=`*[T: GPUSeq](g1: var T, g2: T) = discard
  ## In-place element-wise subtraction:    g1[i] -= g2[i]
template `*=`*[T: GPUSeq](g1: var T, g2: T) = discard
  ## In-place element-wise multiplication: g1[i] *= g2[i]
template `/=`*[T: GPUSeq](g1: var T, g2: T) = discard
  ## In-place element-wise division:       g1[i] /= g2[i]

# ── compound-assignment operators — seq / scalar ──────────────────────────────

template `+=`*[T: GPUSeq](g: var T, scalar: auto) = discard
  ## In-place scalar addition:       g[i] += scalar
template `-=`*[T: GPUSeq](g: var T, scalar: auto) = discard
  ## In-place scalar subtraction:    g[i] -= scalar
template `*=`*[T: GPUSeq](g: var T, scalar: auto) = discard
  ## In-place scalar multiplication: g[i] *= scalar
template `/=`*[T: GPUSeq](g: var T, scalar: auto) = discard
  ## In-place scalar division:       g[i] /= scalar

template addMany[T: GPUSeq](operands: varargs[T]): T = discard
  ## Element-wise sum of N operands in a single pass / kernel.
  ## All operands must have the same logical length.

template subMany[T: GPUSeq](operands: varargs[T]): T = discard
  ## Element-wise left-fold subtraction of N operands.

template mulMany[T: GPUSeq](operands: varargs[T]): T = discard
  ## Element-wise product of N operands in a single pass / kernel.

template divMany[T: GPUSeq](operands: varargs[T]): T = discard
  ## Element-wise left-fold division of N operands.

template addManyInto[T: GPUSeq](operands: openArray[T], dst: var T) = discard
  ## addMany into a caller-supplied buffer — no allocation.

template subManyInto[T: GPUSeq](operands: openArray[T], dst: var T) = discard
  ## subMany into a caller-supplied buffer — no allocation.

template mulManyInto[T: GPUSeq](operands: openArray[T], dst: var T) = discard
  ## mulMany into a caller-supplied buffer — no allocation.

template divManyInto[T: GPUSeq](operands: openArray[T], dst: var T) = discard
  ## divMany into a caller-supplied buffer — no allocation.
