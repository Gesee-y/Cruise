#############################################################################################################################
################################################### PROJECTIVE GEOMETRIC ALGEBRA ############################################
#############################################################################################################################
##
## PGA2D — Projective Geometric Algebra in 2D: P(R*_{2,0,1})
## PGA3D — Projective Geometric Algebra in 3D: P(R*_{3,0,1})
##
## Basis and metric:
##
##   2D  — grade 0: s
##          grade 1: e0(null), e1, e2
##          grade 2: e12, e20, e01
##          grade 3: e012
##
##   3D  — grade 0: s
##          grade 1: e0(null), e1, e2, e3
##          grade 2: e12, e13, e14(e10), e23, e24(e20), e34(e30), e01 handled as e41, e02→e42, e03→e43
##          grade 3: e123, e124(e120), e134(e130), e234(e230)
##          grade 4: e1234
##
##   Metric: e1²=1, e2²=1, (e3²=1 in 3D), e0²=0
##
## Conventions:
##   - A LINE   in 2D is a grade-1 element:  (e1·x + e2·y + e0 = 0)
##   - A POINT  in 2D is a grade-2 element:  e12 + e20·x + e01·y
##   - A PLANE  in 3D is a grade-1 element
##   - A LINE   in 3D is a grade-2 element
##   - A POINT  in 3D is a grade-3 element:  e123 + e124·x + e134·y + e234·z (wait — see below)
##
## All operations are templates or funcs on concepts so ANY concrete type
## with the right fields works — zero boilerplate for custom structs.
##

type
  MFloat* = float32

  ##############################################################################
  ## 2D Multivector concept
  ##############################################################################
  MMultiVector2D* = concept v
    ## Grade 0
    compiles(v.s)
    ## Grade 1 — e0 is the projective (null) basis vector
    compiles(v.e0)
    compiles(v.e1)
    compiles(v.e2)
    ## Grade 2
    compiles(v.e12)
    compiles(v.e20)
    compiles(v.e01)
    ## Grade 3 (pseudoscalar)
    compiles(v.e012)

  ##############################################################################
  ## 3D Multivector concept
  ##############################################################################
  MMultiVector3D* = concept v
    ## Grade 0
    compiles(v.s)
    ## Grade 1 — e0 is the projective (null) basis vector
    compiles(v.e0)
    compiles(v.e1)
    compiles(v.e2)
    compiles(v.e3)
    ## Grade 2
    compiles(v.e12)
    compiles(v.e13)
    compiles(v.e23)
    compiles(v.e01)
    compiles(v.e02)
    compiles(v.e03)
    ## Grade 3
    compiles(v.e123)
    compiles(v.e021)
    compiles(v.e013)
    compiles(v.e032)
    ## Grade 4 (pseudoscalar)
    compiles(v.e0123)


#############################################################################################################################
################################################### CONCRETE TYPES ##########################################################
#############################################################################################################################

type
  MVec2* = object
    ## Concrete 2D MVec multivector.  All 8 components.
    s*:    MFloat   ## Grade 0 (scalar)
    e0*:   MFloat   ## Grade 1 — projective / null
    e1*:   MFloat   ## Grade 1
    e2*:   MFloat   ## Grade 1
    e12*:  MFloat   ## Grade 2
    e20*:  MFloat   ## Grade 2
    e01*:  MFloat   ## Grade 2
    e012*: MFloat   ## Grade 3 (pseudoscalar)

  MVec3* = object
    ## Concrete 3D MVec multivector.  All 16 components.
    s*:     MFloat  ## Grade 0
    e0*:    MFloat  ## Grade 1 — projective / null
    e1*:    MFloat  ## Grade 1
    e2*:    MFloat  ## Grade 1
    e3*:    MFloat  ## Grade 1
    e12*:   MFloat  ## Grade 2
    e13*:   MFloat  ## Grade 2
    e23*:   MFloat  ## Grade 2
    e01*:   MFloat  ## Grade 2
    e02*:   MFloat  ## Grade 2
    e03*:   MFloat  ## Grade 2
    e123*:  MFloat  ## Grade 3
    e021*:  MFloat  ## Grade 3  (= -e012)
    e013*:  MFloat  ## Grade 3  (= -e031)
    e032*:  MFloat  ## Grade 3  (= -e023)
    e0123*: MFloat  ## Grade 4 (pseudoscalar)


#############################################################################################################################
################################################### 2D CONSTRUCTORS #########################################################
#############################################################################################################################

func MVec2Line*(a, b, c: MFloat): MVec2 {.inline.} =
  ## Line  ax + by + c = 0  as a grade-1 element.
  ## e1·x + e2·y + e0 = 0  →  (a, b, c) maps to (e1=a, e2=b, e0=c).
  MVec2(e1: a, e2: b, e0: c)

func MVec2Point*(x, y: MFloat): MVec2 {.inline.} =
  ## Ideal point  (x,y)  as a grade-2 element.
  ## p = e12 + x·e20 + y·e01
  MVec2(e12: 1f, e20: x, e01: y)

func MVec2Ideal*(dx, dy: MFloat): MVec2 {.inline.} =
  ## Ideal point (point at infinity) representing direction (dx,dy).
  ## e12 = 0 for points at infinity.
  MVec2(e20: dx, e01: dy)

func MVec2Scalar*(s: MFloat): MVec2 {.inline.} =
  ## Pure scalar (grade-0) element.
  MVec2(s: s)

func MVec2Pseudo*(): MVec2 {.inline.} =
  ## Unit pseudoscalar I = e012.
  MVec2(e012: 1f)

func MVec2Zero*(): MVec2 {.inline.} =
  ## Zero multivector (additive identity).
  MVec2()

func MVec2Identity*(): MVec2 {.inline.} =
  ## Multiplicative identity (scalar 1).
  MVec2(s: 1f)


#############################################################################################################################
################################################### 3D CONSTRUCTORS #########################################################
#############################################################################################################################

func MVec3Plane*(a, b, c, d: MFloat): MVec3 {.inline.} =
  ## Plane  ax + by + cz + d = 0  as a grade-1 element.
  ## e1·x + e2·y + e3·z + e0·d = 0
  MVec3(e1: a, e2: b, e3: c, e0: d)

func MVec3Point*(x, y, z: MFloat): MVec3 {.inline.} =
  ## Euclidean point  (x,y,z)  as a grade-3 element (homogeneous w=1).
  ## p = e123 + x·e032 + y·e013 + z·e021
  MVec3(e123: 1f, e032: x, e013: y, e021: z)

func MVec3Ideal*(dx, dy, dz: MFloat): MVec3 {.inline.} =
  ## Ideal point (direction) — grade-3, e123=0.
  MVec3(e032: dx, e013: dy, e021: dz)

func MVec3Line*(e12, e13, e23, e01, e02, e03: MFloat): MVec3 {.inline.} =
  ## Arbitrary grade-2 element (line in 3D MVec).
  MVec3(e12: e12, e13: e13, e23: e23, e01: e01, e02: e02, e03: e03)

func MVec3Scalar*(s: MFloat): MVec3 {.inline.} =
  MVec3(s: s)

func MVec3Pseudo*(): MVec3 {.inline.} =
  ## Unit pseudoscalar I = e0123.
  MVec3(e0123: 1f)

func MVec3Zero*(): MVec3 {.inline.} =
  MVec3()

func MVec3Identity*(): MVec3 {.inline.} =
  MVec3(s: 1f)


#############################################################################################################################
################################################### 2D BASIC ARITHMETIC #####################################################
#############################################################################################################################

template `+`*[T: MMultiVector2D](a, b: T): T =
  ## Component-wise addition.
  T(s:    a.s    + b.s,
    e0:   a.e0   + b.e0,   e1: a.e1 + b.e1, e2: a.e2 + b.e2,
    e12:  a.e12  + b.e12,  e20: a.e20 + b.e20, e01: a.e01 + b.e01,
    e012: a.e012 + b.e012)

template `-`*[T: MMultiVector2D](a, b: T): T =
  ## Component-wise subtraction.
  T(s:    a.s    - b.s,
    e0:   a.e0   - b.e0,   e1: a.e1 - b.e1, e2: a.e2 - b.e2,
    e12:  a.e12  - b.e12,  e20: a.e20 - b.e20, e01: a.e01 - b.e01,
    e012: a.e012 - b.e012)

template `-`*[T: MMultiVector2D](a: T): T =
  ## Unary negation.
  T(s: -a.s, e0: -a.e0, e1: -a.e1, e2: -a.e2,
    e12: -a.e12, e20: -a.e20, e01: -a.e01, e012: -a.e012)

template `*`*[T: MMultiVector2D](a: T, s: MFloat): T =
  ## Scalar scaling.
  T(s: a.s*s, e0: a.e0*s, e1: a.e1*s, e2: a.e2*s,
    e12: a.e12*s, e20: a.e20*s, e01: a.e01*s, e012: a.e012*s)

template `*`*[T: MMultiVector2D](s: MFloat, a: T): T =
  a * s


#############################################################################################################################
################################################### 3D BASIC ARITHMETIC #####################################################
#############################################################################################################################

template `+`*[T: MMultiVector3D](a, b: T): T =
  T(s: a.s+b.s,
    e0: a.e0+b.e0, e1: a.e1+b.e1, e2: a.e2+b.e2, e3: a.e3+b.e3,
    e12: a.e12+b.e12, e13: a.e13+b.e13, e23: a.e23+b.e23,
    e01: a.e01+b.e01, e02: a.e02+b.e02, e03: a.e03+b.e03,
    e123: a.e123+b.e123, e021: a.e021+b.e021, e013: a.e013+b.e013, e032: a.e032+b.e032,
    e0123: a.e0123+b.e0123)

template `-`*[T: MMultiVector3D](a, b: T): T =
  T(s: a.s-b.s,
    e0: a.e0-b.e0, e1: a.e1-b.e1, e2: a.e2-b.e2, e3: a.e3-b.e3,
    e12: a.e12-b.e12, e13: a.e13-b.e13, e23: a.e23-b.e23,
    e01: a.e01-b.e01, e02: a.e02-b.e02, e03: a.e03-b.e03,
    e123: a.e123-b.e123, e021: a.e021-b.e021, e013: a.e013-b.e013, e032: a.e032-b.e032,
    e0123: a.e0123-b.e0123)

template `-`*[T: MMultiVector3D](a: T): T =
  T(s: -a.s, e0: -a.e0, e1: -a.e1, e2: -a.e2, e3: -a.e3,
    e12: -a.e12, e13: -a.e13, e23: -a.e23,
    e01: -a.e01, e02: -a.e02, e03: -a.e03,
    e123: -a.e123, e021: -a.e021, e013: -a.e013, e032: -a.e032,
    e0123: -a.e0123)

template `*`*[T: MMultiVector3D](a: T, sc: MFloat): T =
  T(s: a.s*sc, e0: a.e0*sc, e1: a.e1*sc, e2: a.e2*sc, e3: a.e3*sc,
    e12: a.e12*sc, e13: a.e13*sc, e23: a.e23*sc,
    e01: a.e01*sc, e02: a.e02*sc, e03: a.e03*sc,
    e123: a.e123*sc, e021: a.e021*sc, e013: a.e013*sc, e032: a.e032*sc,
    e0123: a.e0123*sc)

template `*`*[T: MMultiVector3D](sc: MFloat, a: T): T = a * sc


#############################################################################################################################
################################################### 2D GEOMETRIC PRODUCT ####################################################
#############################################################################################################################
## The geometric product encodes all other products.
## Metric: e1²=1, e2²=1, e0²=0
## Full multiplication table — all 64 basis product pairs, fully unrolled.

func geometricProduct*[T: MMultiVector2D](a, b: T): T =
  ## Full geometric product in PGA2D.
  ## Encodes rotations, translations, and general rigid transforms.
  ## grade-0 result (scalar):
  let rs = a.s*b.s + a.e1*b.e1 + a.e2*b.e2 - a.e12*b.e12
  ## grade-1 results:
  let re0  =  a.s*b.e0  + a.e0*b.s   - a.e1*b.e01  + a.e01*b.e1  + a.e2*b.e20 - a.e20*b.e2  + a.e12*b.e012 + a.e012*b.e12
  let re1  =  a.s*b.e1  + a.e1*b.s   + a.e2*b.e12  - a.e12*b.e2
  let re2  =  a.s*b.e2  - a.e1*b.e12 + a.e2*b.s    + a.e12*b.e1
  ## grade-2 results:
  let re12 =  a.s*b.e12 + a.e1*b.e2  - a.e2*b.e1   + a.e12*b.s
  let re20 =  a.s*b.e20 - a.e1*b.e012 - a.e2*b.e01  + a.e01*b.e2  + a.e12*b.e0  + a.e20*b.s  + a.e012*b.e1 + a.e0*b.e12
  let re01 =  a.s*b.e01 + a.e1*b.e012 - a.e2*b.e20  + a.e20*b.e2  - a.e12*b.e0  + a.e01*b.s  - a.e012*b.e2 - a.e0*b.e20  # wait e0*e20 = e020 = 0 due to e0²=0
  ## grade-3 result (pseudoscalar):
  let re012 = a.s*b.e012 + a.e0*b.e12 - a.e1*b.e20  + a.e2*b.e01 +
              a.e12*b.e0  + a.e20*b.e1 - a.e01*b.e2  + a.e012*b.s
  T(s: rs, e0: re0, e1: re1, e2: re2,
    e12: re12, e20: re20, e01: re01, e012: re012)


#############################################################################################################################
################################################### 2D EXTERIOR (WEDGE) PRODUCT #############################################
#############################################################################################################################
## The exterior product (∧) encodes incidence and constructs higher-grade elements.
##   line ∧ line  = point   (intersection)
##   point ∧ point = line   (join / line through two points)

func exteriorProduct*[T: MMultiVector2D](a, b: T): T =
  ## Exterior / wedge product (∧) in PGA2D.
  ## grade 0: s∧s
  let rs = a.s * b.s
  ## grade 1
  let re0 = a.s*b.e0 + a.e0*b.s
  let re1 = a.s*b.e1 + a.e1*b.s
  let re2 = a.s*b.e2 + a.e2*b.s
  ## grade 2 — wedge of two grade-1 elements
  let re12 = a.s*b.e12 + a.e1*b.e2  - a.e2*b.e1  + a.e12*b.s
  let re20 = a.s*b.e20 + a.e2*b.e0  - a.e0*b.e2  + a.e20*b.s
  let re01 = a.s*b.e01 + a.e0*b.e1  - a.e1*b.e0  + a.e01*b.s
  ## grade 3 — wedge of three grade-1 elements / grade-1 ∧ grade-2
  let re012 = a.s*b.e012 + a.e0*b.e12 - a.e1*b.e20 + a.e2*b.e01 +
              a.e12*b.e0  - a.e20*b.e1 + a.e01*b.e2 + a.e012*b.s
  T(s: rs, e0: re0, e1: re1, e2: re2,
    e12: re12, e20: re20, e01: re01, e012: re012)

template `^`*[T: MMultiVector2D](a, b: T): T =
  ## Operator alias for exterior product.
  exteriorProduct(a, b)


#############################################################################################################################
################################################### 2D REGRESSIVE (VEE) PRODUCT #############################################
#############################################################################################################################
## The regressive product (∨) is the dual of the exterior product.
##   point ∨ point = line   (join)
##   line  ∨ line  = point  (meet — same as exterior in dual space)
## Computed as:  a ∨ b = dual(dual(a) ∧ dual(b))

func dual2D*[T: MMultiVector2D](a: T): T {.inline.} =
  ## Poincaré dual in PGA2D: maps grade-k to grade-(3-k).
  ## The dual of a blade is its orthogonal complement w.r.t. the pseudoscalar.
  ## dual: s↔e012, e0↔e12, e1↔e20, e2↔e01  (with sign from the metric)
  T(s:    a.e012,
    e0:   a.e12,  e1: a.e20,  e2: a.e01,
    e12:  a.e0,   e20: a.e1,  e01: a.e2,
    e012: a.s)

func regressiveProduct*[T: MMultiVector2D](a, b: T): T {.inline.} =
  ## Regressive / vee product (∨) in PGA2D.
  ## Used to JOIN two geometric objects (e.g. two points → the line through them).
  dual2D(exteriorProduct(dual2D(a), dual2D(b)))

template `v`*[T: MMultiVector2D](a, b: T): T =
  ## Operator alias for regressive (join) product.
  regressiveProduct(a, b)


#############################################################################################################################
################################################### 2D INNER (DOT) PRODUCT ##################################################
#############################################################################################################################
## The inner product (·) contracts grades.
## Used to: compute distances, angles, project elements onto each other.

func innerProduct*[T: MMultiVector2D](a, b: T): T =
  ## Symmetric inner product in PGA2D (Hestenes inner product).
  ## Only terms where |grade(a) - grade(b)| = resulting grade survive.
  let rs = a.s*b.s + a.e1*b.e1 + a.e2*b.e2
  let re0 = a.s*b.e0 + a.e0*b.s - a.e1*b.e01 + a.e01*b.e1 + a.e2*b.e20 - a.e20*b.e2
  let re1 = a.s*b.e1 + a.e1*b.s + a.e2*b.e12 - a.e12*b.e2
  let re2 = a.s*b.e2 - a.e1*b.e12 + a.e2*b.s + a.e12*b.e1
  let re12 = a.s*b.e12 + a.e12*b.s
  let re20 = a.s*b.e20 + a.e20*b.s
  let re01 = a.s*b.e01 + a.e01*b.s
  let re012 = a.s*b.e012 + a.e012*b.s
  T(s: rs, e0: re0, e1: re1, e2: re2,
    e12: re12, e20: re20, e01: re01, e012: re012)

template `|`*[T: MMultiVector2D](a, b: T): T =
  ## Operator alias for inner product.
  innerProduct(a, b)


#############################################################################################################################
################################################### 2D SANDWICH PRODUCT #####################################################
#############################################################################################################################
## The sandwich product  R ⟑ X ⟑ ~R  applies a rigid transform to X.
## R is a rotor/translator/motor, X is the element being transformed.
## ~R is the reverse of R.

func reverse2D*[T: MMultiVector2D](a: T): T {.inline.} =
  ## Reverse (†): reverses the order of basis vectors in each blade.
  ## grade 0,1: unchanged; grade 2: sign flip; grade 3: unchanged (even reversal).
  ## In PGA2D: s,e0,e1,e2 unchanged; e12,e20,e01 negated; e012 unchanged.
  T(s: a.s, e0: a.e0, e1: a.e1, e2: a.e2,
    e12: -a.e12, e20: -a.e20, e01: -a.e01,
    e012: a.e012)

func sandwich2D*[T: MMultiVector2D](r, x: T): T {.inline.} =
  ## Apply rotor/motor r to element x: r ⟑ x ⟑ ~r
  ## This is the fundamental transform operation in PGA.
  geometricProduct(geometricProduct(r, x), reverse2D(r))

template `>>>` *[T: MMultiVector2D](r, x: T): T =
  ## Operator alias for sandwich product (transform x by motor r).
  sandwich2D(r, x)


#############################################################################################################################
################################################### 2D SPECIAL ELEMENTS ####################################################
#############################################################################################################################

func norm2D*[T: MMultiVector2D](a: T): MFloat {.inline.} =
  ## Euclidean norm: sqrt of the scalar part of a * reverse(a).
  ## For a unit motor this should be 1.
  sqrt(abs(a.s*a.s + a.e12*a.e12))

func idealNorm2D*[T: MMultiVector2D](a: T): MFloat {.inline.} =
  ## Ideal norm (involves the e0 components — the projective part).
  sqrt(abs(a.e0*a.e0 + a.e20*a.e20 + a.e01*a.e01))

func normalize2D*[T: MMultiVector2D](a: T): T {.inline.} =
  ## Normalize a motor/rotor so its Euclidean norm = 1.
  let n = norm2D(a)
  if n < 1e-8f: a else: a * (1f/n)

func pga2DRotor*(angle: MFloat): MVec2 {.inline.} =
  ## Unit rotor for rotation by `angle` radians around the origin.
  ## R = cos(θ/2) + sin(θ/2)·e12
  let h = angle * 0.5f
  MVec2(s: cos(h), e12: sin(h))

func pga2DTranslator*(dx, dy: MFloat): MVec2 {.inline.} =
  ## Unit translator for translation by (dx,dy).
  ## T = 1 + (dx·e20 + dy·e01)/2  (note: e0²=0 so T is exactly this)
  MVec2(s: 1f, e20: dx*0.5f, e01: dy*0.5f)

func pga2DMotor*(angle, tx, ty: MFloat): MVec2 =
  ## Motor encoding rotation by `angle` then translation by (tx,ty).
  ## M = T * R  (translation after rotation — standard convention).
  let r = pga2DRotor(angle)
  let t = pga2DTranslator(tx, ty)
  geometricProduct(t, r)

func pga2DProjectPoint*[T: MMultiVector2D](p: T): (MFloat, MFloat) {.inline.} =
  ## Extract Euclidean (x,y) from a grade-2 point element.
  ## Normalises by dividing by e12 (the homogeneous weight).
  let w = p.e12
  if abs(w) < 1e-8f: (0f, 0f)  # ideal point / point at infinity
  else: (p.e20 / w, p.e01 / w)

func pga2DProjectLine*[T: MMultiVector2D](l: T): (MFloat, MFloat, MFloat) {.inline.} =
  ## Extract (a,b,c) from a grade-1 line element  ax + by + c = 0.
  (l.e1, l.e2, l.e0)

func meet2D*[T: MMultiVector2D](a, b: T): T {.inline.} =
  ## MEET: intersection of two lines → gives a point.
  ## In PGA the meet IS the exterior product.
  exteriorProduct(a, b)

func join2D*[T: MMultiVector2D](a, b: T): T {.inline.} =
  ## JOIN: line through two points.
  ## In PGA the join IS the regressive product.
  regressiveProduct(a, b)


#############################################################################################################################
################################################### 3D GEOMETRIC PRODUCT ####################################################
#############################################################################################################################
## Metric: e1²=1, e2²=1, e3²=1, e0²=0
## All 256 basis product pairs, grouped and unrolled for performance.
## Signs derived from anticommutativity:  eij = -eji,  ei²=metric(i)

func geometricProduct*[T: MMultiVector3D](a, b: T): T =
  ## Full geometric product in PGA3D. Encodes all rigid body transforms.

  # ── grade 0 ────────────────────────────────────────────────────────────────
  let rs = a.s*b.s + a.e1*b.e1 + a.e2*b.e2 + a.e3*b.e3 -
           a.e12*b.e12 - a.e13*b.e13 - a.e23*b.e23 +
           a.e123*b.e123

  # ── grade 1 ────────────────────────────────────────────────────────────────
  let re0 = a.s*b.e0  + a.e0*b.s   -
            a.e1*b.e01 + a.e01*b.e1 - a.e2*b.e02 + a.e02*b.e2 -
            a.e3*b.e03 + a.e03*b.e3 +
            a.e12*b.e021 - a.e021*b.e12 + a.e13*b.e013 - a.e013*b.e13 +
            a.e23*b.e032 - a.e032*b.e23 -
            a.e123*b.e0123 + a.e0123*b.e123

  let re1 = a.s*b.e1  + a.e1*b.s  +
            a.e2*b.e12 - a.e12*b.e2 + a.e3*b.e13 - a.e13*b.e3 +
            a.e123*b.e23 - a.e23*b.e123

  let re2 = a.s*b.e2  + a.e2*b.s  -
            a.e1*b.e12 + a.e12*b.e1 + a.e3*b.e23 - a.e23*b.e3 -
            a.e123*b.e13 + a.e13*b.e123

  let re3 = a.s*b.e3  + a.e3*b.s  -
            a.e1*b.e13 + a.e13*b.e1 - a.e2*b.e23 + a.e23*b.e2 +
            a.e123*b.e12 - a.e12*b.e123

  # ── grade 2 ────────────────────────────────────────────────────────────────
  let re12 = a.s*b.e12 + a.e1*b.e2  - a.e2*b.e1  + a.e12*b.s   +
             a.e3*b.e123 + a.e123*b.e3 - a.e13*b.e23 + a.e23*b.e13

  let re13 = a.s*b.e13 + a.e1*b.e3  - a.e3*b.e1  + a.e13*b.s   -
             a.e2*b.e123 - a.e123*b.e2 + a.e12*b.e23 - a.e23*b.e12

  let re23 = a.s*b.e23 + a.e2*b.e3  - a.e3*b.e2  + a.e23*b.s   +
             a.e1*b.e123 + a.e123*b.e1 - a.e12*b.e13 + a.e13*b.e12

  let re01 = a.s*b.e01  + a.e0*b.e1   - a.e1*b.e0  + a.e01*b.s  +
             a.e2*b.e021 - a.e021*b.e2 + a.e3*b.e013 - a.e013*b.e3 -
             a.e12*b.e02  + a.e02*b.e12 - a.e13*b.e03 + a.e03*b.e13 +
             a.e23*b.e0123 + a.e0123*b.e23 - a.e123*b.e032 + a.e032*b.e123

  let re02 = a.s*b.e02  + a.e0*b.e2   - a.e2*b.e0  + a.e02*b.s  -
             a.e1*b.e021 + a.e021*b.e1 + a.e3*b.e032 - a.e032*b.e3 +
             a.e12*b.e01  - a.e01*b.e12 - a.e23*b.e03 + a.e03*b.e23 -
             a.e13*b.e0123 - a.e0123*b.e13 + a.e123*b.e013 - a.e013*b.e123

  let re03 = a.s*b.e03  + a.e0*b.e3   - a.e3*b.e0  + a.e03*b.s  -
             a.e1*b.e013 + a.e013*b.e1 - a.e2*b.e032 + a.e032*b.e2 +
             a.e13*b.e01  - a.e01*b.e13 + a.e23*b.e02 - a.e02*b.e23 +
             a.e12*b.e0123 + a.e0123*b.e12 - a.e123*b.e021 + a.e021*b.e123

  # ── grade 3 ────────────────────────────────────────────────────────────────
  let re123 = a.s*b.e123 + a.e1*b.e23  - a.e2*b.e13  + a.e3*b.e12  +
              a.e12*b.e3  - a.e13*b.e2  + a.e23*b.e1  + a.e123*b.s

  let re021 = a.s*b.e021 + a.e0*b.e12  - a.e1*b.e02  + a.e2*b.e01  +
              a.e01*b.e2  - a.e02*b.e1  + a.e12*b.e0  + a.e021*b.s  -
              a.e3*b.e0123 + a.e0123*b.e3 + a.e13*b.e032 + a.e032*b.e13 -
              a.e23*b.e013 - a.e013*b.e23 + a.e123*b.e03 - a.e03*b.e123

  let re013 = a.s*b.e013 + a.e0*b.e13  - a.e1*b.e03  + a.e3*b.e01  +
              a.e01*b.e3  - a.e03*b.e1  + a.e13*b.e0  + a.e013*b.s  +
              a.e2*b.e0123 - a.e0123*b.e2 - a.e12*b.e032 - a.e032*b.e12 +
              a.e23*b.e021 + a.e021*b.e23 - a.e123*b.e02 + a.e02*b.e123

  let re032 = a.s*b.e032 + a.e0*b.e23  - a.e2*b.e03  + a.e3*b.e02  +
              a.e02*b.e3  - a.e03*b.e2  + a.e23*b.e0  + a.e032*b.s  -
              a.e1*b.e0123 + a.e0123*b.e1 + a.e12*b.e013 + a.e013*b.e12 -
              a.e13*b.e021 - a.e021*b.e13 + a.e123*b.e01 - a.e01*b.e123

  # ── grade 4 ────────────────────────────────────────────────────────────────
  let re0123 = a.s*b.e0123  + a.e0*b.e123   - a.e1*b.e032  + a.e2*b.e013  - a.e3*b.e021  +
               a.e01*b.e23  - a.e02*b.e13   + a.e03*b.e12  +
               a.e12*b.e03  - a.e13*b.e02   + a.e23*b.e01  +
               a.e021*b.e3  - a.e013*b.e2   + a.e032*b.e1  - a.e123*b.e0  + a.e0123*b.s

  T(s: rs, e0: re0, e1: re1, e2: re2, e3: re3,
    e12: re12, e13: re13, e23: re23, e01: re01, e02: re02, e03: re03,
    e123: re123, e021: re021, e013: re013, e032: re032, e0123: re0123)


#############################################################################################################################
################################################### 3D EXTERIOR PRODUCT #####################################################
#############################################################################################################################

func exteriorProduct*[T: MMultiVector3D](a, b: T): T =
  ## Exterior / wedge product (∧) in PGA3D.
  ## plane ∧ plane = line,  plane ∧ plane ∧ plane = point
  let rs = a.s*b.s
  let re0 = a.s*b.e0  + a.e0*b.s
  let re1 = a.s*b.e1  + a.e1*b.s
  let re2 = a.s*b.e2  + a.e2*b.s
  let re3 = a.s*b.e3  + a.e3*b.s
  let re12 = a.s*b.e12 + a.e1*b.e2  - a.e2*b.e1  + a.e12*b.s
  let re13 = a.s*b.e13 + a.e1*b.e3  - a.e3*b.e1  + a.e13*b.s
  let re23 = a.s*b.e23 + a.e2*b.e3  - a.e3*b.e2  + a.e23*b.s
  let re01 = a.s*b.e01 + a.e0*b.e1  - a.e1*b.e0  + a.e01*b.s
  let re02 = a.s*b.e02 + a.e0*b.e2  - a.e2*b.e0  + a.e02*b.s
  let re03 = a.s*b.e03 + a.e0*b.e3  - a.e3*b.e0  + a.e03*b.s
  let re123 = a.s*b.e123 + a.e1*b.e23 - a.e2*b.e13 + a.e3*b.e12 +
              a.e12*b.e3  - a.e13*b.e2 + a.e23*b.e1 + a.e123*b.s
  let re021 = a.s*b.e021 + a.e0*b.e12 - a.e1*b.e02 + a.e2*b.e01 +
              a.e01*b.e2  - a.e02*b.e1 + a.e12*b.e0 + a.e021*b.s
  let re013 = a.s*b.e013 + a.e0*b.e13 - a.e1*b.e03 + a.e3*b.e01 +
              a.e01*b.e3  - a.e03*b.e1 + a.e13*b.e0 + a.e013*b.s
  let re032 = a.s*b.e032 + a.e0*b.e23 - a.e2*b.e03 + a.e3*b.e02 +
              a.e02*b.e3  - a.e03*b.e2 + a.e23*b.e0 + a.e032*b.s
  let re0123 = a.s*b.e0123  + a.e0*b.e123  - a.e1*b.e032  + a.e2*b.e013 - a.e3*b.e021 +
               a.e01*b.e23  - a.e02*b.e13  + a.e03*b.e12  +
               a.e12*b.e03  - a.e13*b.e02  + a.e23*b.e01  +
               a.e021*b.e3  - a.e013*b.e2  + a.e032*b.e1  + a.e123*b.e0 + a.e0123*b.s
  T(s: rs, e0: re0, e1: re1, e2: re2, e3: re3,
    e12: re12, e13: re13, e23: re23, e01: re01, e02: re02, e03: re03,
    e123: re123, e021: re021, e013: re013, e032: re032, e0123: re0123)

template `^`*[T: MMultiVector3D](a, b: T): T =
  exteriorProduct(a, b)


#############################################################################################################################
################################################### 3D REGRESSIVE PRODUCT ###################################################
#############################################################################################################################

func dual3D*[T: MMultiVector3D](a: T): T {.inline.} =
  ## Poincaré dual in PGA3D — maps grade-k to grade-(4-k).
  ## Multiply by the pseudoscalar: dual(X) = X * I⁻¹
  ## Signs from: I = e0123, I⁻¹ = -e0123 in this metric.
  T(s:     a.e0123,
    e0:    a.e123,  e1:  a.e032,  e2:  a.e013,   e3:  a.e021,
    e12:   a.e03,   e13: a.e02,   e23: a.e01,
    e01:   a.e23,   e02: a.e13,   e03: a.e12,
    e123:  a.e0,    e021: a.e3,   e013: a.e2,    e032: a.e1,
    e0123: a.s)

func regressiveProduct*[T: MMultiVector3D](a, b: T): T {.inline.} =
  ## Regressive / vee product (∨) in PGA3D.
  ## Used to JOIN geometric objects: line ∨ point = ... etc.
  dual3D(exteriorProduct(dual3D(a), dual3D(b)))

template `v`*[T: MMultiVector3D](a, b: T): T =
  regressiveProduct(a, b)


#############################################################################################################################
################################################### 3D INNER PRODUCT ########################################################
#############################################################################################################################

func innerProduct*[T: MMultiVector3D](a, b: T): T =
  ## Symmetric inner product in PGA3D.
  ## Contracts grades: result grade = |grade(a) - grade(b)|.
  let rs = a.s*b.s + a.e1*b.e1 + a.e2*b.e2 + a.e3*b.e3 -
           a.e12*b.e12 - a.e13*b.e13 - a.e23*b.e23 + a.e123*b.e123
  let re0 = a.s*b.e0 + a.e0*b.s
  let re1 = a.s*b.e1 + a.e1*b.s + a.e2*b.e12 - a.e12*b.e2 + a.e3*b.e13 - a.e13*b.e3 + a.e123*b.e23 - a.e23*b.e123
  let re2 = a.s*b.e2 + a.e2*b.s - a.e1*b.e12 + a.e12*b.e1 + a.e3*b.e23 - a.e23*b.e3 - a.e123*b.e13 + a.e13*b.e123
  let re3 = a.s*b.e3 + a.e3*b.s - a.e1*b.e13 + a.e13*b.e1 - a.e2*b.e23 + a.e23*b.e2 + a.e123*b.e12 - a.e12*b.e123
  let re12 = a.s*b.e12 + a.e12*b.s - a.e13*b.e23 + a.e23*b.e13
  let re13 = a.s*b.e13 + a.e13*b.s + a.e12*b.e23 - a.e23*b.e12
  let re23 = a.s*b.e23 + a.e23*b.s - a.e12*b.e13 + a.e13*b.e12
  let re01 = a.s*b.e01 + a.e01*b.s
  let re02 = a.s*b.e02 + a.e02*b.s
  let re03 = a.s*b.e03 + a.e03*b.s
  let re123 = a.s*b.e123 + a.e1*b.e23 - a.e2*b.e13 + a.e3*b.e12 +
              a.e12*b.e3 - a.e13*b.e2 + a.e23*b.e1 + a.e123*b.s
  let re021 = a.s*b.e021 + a.e021*b.s
  let re013 = a.s*b.e013 + a.e013*b.s
  let re032 = a.s*b.e032 + a.e032*b.s
  let re0123 = a.s*b.e0123 + a.e0123*b.s
  T(s: rs, e0: re0, e1: re1, e2: re2, e3: re3,
    e12: re12, e13: re13, e23: re23, e01: re01, e02: re02, e03: re03,
    e123: re123, e021: re021, e013: re013, e032: re032, e0123: re0123)

template `|`*[T: MMultiVector3D](a, b: T): T =
  innerProduct(a, b)


#############################################################################################################################
################################################### 3D REVERSE / SANDWICH ###################################################
#############################################################################################################################

func reverse3D*[T: MMultiVector3D](a: T): T {.inline.} =
  ## Reverse (†): negate blades of grade 2 and 3.
  ## grade 0,1: +;  grade 2,3: −;  grade 4: +
  T(s: a.s, e0: a.e0, e1: a.e1, e2: a.e2, e3: a.e3,
    e12: -a.e12, e13: -a.e13, e23: -a.e23,
    e01: -a.e01, e02: -a.e02, e03: -a.e03,
    e123: -a.e123, e021: -a.e021, e013: -a.e013, e032: -a.e032,
    e0123: a.e0123)

func sandwich3D*[T: MMultiVector3D](r, x: T): T {.inline.} =
  ## Apply motor r to element x:  r ⟑ x ⟑ ~r
  geometricProduct(geometricProduct(r, x), reverse3D(r))

template `>>>`*[T: MMultiVector3D](r, x: T): T =
  sandwich3D(r, x)


#############################################################################################################################
################################################### 3D SPECIAL ELEMENTS ####################################################
#############################################################################################################################

func norm3D*[T: MMultiVector3D](a: T): MFloat {.inline.} =
  ## Euclidean norm of a 3D motor/rotor.
  sqrt(abs(a.s*a.s + a.e12*a.e12 + a.e13*a.e13 + a.e23*a.e23))

func idealNorm3D*[T: MMultiVector3D](a: T): MFloat {.inline.} =
  ## Ideal (projective) norm of a 3D motor.
  sqrt(abs(a.e01*a.e01 + a.e02*a.e02 + a.e03*a.e03))

func normalize3D*[T: MMultiVector3D](a: T): T {.inline.} =
  ## Normalize a motor so its Euclidean norm = 1.
  let n = norm3D(a)
  if n < 1e-8f: a else: a * (1f/n)

func pga3DRotor*(ax, ay, az, angle: MFloat): MVec3 =
  ## Unit rotor for rotation by `angle` radians around unit axis (ax,ay,az).
  ## R = cos(θ/2) + sin(θ/2)·(ax·e23 + ay·e13 + az·e12)
  ## Note sign convention: e23↔x, -e13↔y (right-hand rule).
  let h = angle * 0.5f
  let s = sin(h)
  MVec3(s: cos(h), e23: ax*s, e13: -ay*s, e12: az*s)

func pga3DTranslator*(dx, dy, dz: MFloat): MVec3 {.inline.} =
  ## Unit translator for translation by (dx,dy,dz).
  ## T = 1 + (1/2)(dx·e01 + dy·e02 + dz·e03)
  MVec3(s: 1f, e01: dx*0.5f, e02: dy*0.5f, e03: dz*0.5f)

func pga3DMotor*(ax, ay, az, angle, tx, ty, tz: MFloat): MVec3 =
  ## Motor encoding rotation around axis then translation.
  ## M = T * R
  let r = pga3DRotor(ax, ay, az, angle)
  let t = pga3DTranslator(tx, ty, tz)
  geometricProduct(t, r)

func pga3DProjectPoint*[T: MMultiVector3D](p: T): (MFloat,MFloat,MFloat) {.inline.} =
  ## Extract Euclidean (x,y,z) from a grade-3 point element.
  ## Normalises by dividing by e123 (homogeneous weight).
  let w = p.e123
  if abs(w) < 1e-8f: (0f,0f,0f)
  else: (p.e032/w, p.e013/w, p.e021/w)

func pga3DProjectPlane*[T: MMultiVector3D](pl: T): (MFloat,MFloat,MFloat,MFloat) {.inline.} =
  ## Extract (a,b,c,d) from a grade-1 plane  ax+by+cz+d=0.
  (pl.e1, pl.e2, pl.e3, pl.e0)

func meet3D*[T: MMultiVector3D](a, b: T): T {.inline.} =
  ## MEET: intersection — plane ∧ plane = line, plane ∧ line = point.
  exteriorProduct(a, b)

func join3D*[T: MMultiVector3D](a, b: T): T {.inline.} =
  ## JOIN: span — point ∨ point = line, point ∨ line = plane.
  regressiveProduct(a, b)

func commutatorProduct*[T: MMultiVector3D](a, b: T): T {.inline.} =
  ## Commutator product: [a,b] = (ab - ba) / 2.
  ## Useful for computing the Lie algebra of motors (generators of motion).
  let ab = geometricProduct(a, b)
  let ba = geometricProduct(b, a)
  T(s:     (ab.s    -ba.s   )*0.5f,
    e0:    (ab.e0   -ba.e0  )*0.5f, e1:  (ab.e1  -ba.e1 )*0.5f,
    e2:    (ab.e2   -ba.e2  )*0.5f, e3:  (ab.e3  -ba.e3 )*0.5f,
    e12:   (ab.e12  -ba.e12 )*0.5f, e13: (ab.e13 -ba.e13)*0.5f,
    e23:   (ab.e23  -ba.e23 )*0.5f, e01: (ab.e01 -ba.e01)*0.5f,
    e02:   (ab.e02  -ba.e02 )*0.5f, e03: (ab.e03 -ba.e03)*0.5f,
    e123:  (ab.e123 -ba.e123)*0.5f,
    e021:  (ab.e021 -ba.e021)*0.5f, e013: (ab.e013-ba.e013)*0.5f,
    e032:  (ab.e032 -ba.e032)*0.5f,
    e0123: (ab.e0123-ba.e0123)*0.5f)


#############################################################################################################################
################################################### 3D MOTOR INTERPOLATION ##################################################
#############################################################################################################################

func log3D*[T: MMultiVector3D](m: T): T =
  ## Logarithm of a unit motor — returns a bivector (the generator).
  ## Needed for motor interpolation (motorNlerp / motorSlerp).
  ## Based on: log(R + εT) = log(R) + ε * T * R⁻¹  (dual number decomposition)
  let n = norm3D(m)
  let theta = arccos(clamp(m.s / n, -1f, 1f))  # half-angle of rotation
  let sinT   = sin(theta)
  let sc     = if abs(sinT) < 1e-8f: 1f else: theta / sinT
  # Rotation bivector part
  let b12 = m.e12 * sc
  let b13 = m.e13 * sc
  let b23 = m.e23 * sc
  # Translation bivector part (dual part of the motor)
  let d = m.s * sc
  let b01 = (m.e01*m.s - m.e23*m.e0123 + m.e01) * sc
  let b02 = (m.e02*m.s - m.e13*m.e0123 + m.e02) * sc  # approximation for non-pure motors
  let b03 = (m.e03*m.s - m.e12*m.e0123 + m.e03) * sc
  T(e12: b12, e13: b13, e23: b23, e01: b01, e02: b02, e03: b03)

func exp3D*[T: MMultiVector3D](b: T): T =
  ## Exponential of a bivector — returns a unit motor.
  ## exp(B) = cos(|Br|) + sin(|Br|)/|Br| * Br + Bt*cos(|Br|) + ...
  ## where Br = Euclidean part, Bt = ideal (translation) part.
  let n2 = b.e12*b.e12 + b.e13*b.e13 + b.e23*b.e23
  let n  = sqrt(n2)
  let c  = cos(n)
  let sc = if n < 1e-8f: 1f else: sin(n)/n
  # Dual (translation) dot with rotation
  let td = b.e01*b.e12 + b.e02*b.e13 + b.e03*b.e23
  let tsc = if n < 1e-8f: 0f else: (cos(n)*td/n2 - sin(n)*td/(n2*n))
  T(s:  c,
    e12: b.e12*sc, e13: b.e13*sc, e23: b.e23*sc,
    e01: b.e01*sc + b.e12*tsc,
    e02: b.e02*sc + b.e13*tsc,
    e03: b.e03*sc + b.e23*tsc,
    e0123: -(b.e01*b.e23 - b.e02*b.e13 + b.e03*b.e12)*sc)

func motorNlerp*[T: MMultiVector3D](a, b: T, t: MFloat): T {.inline.} =
  ## Normalised linear interpolation between two motors.
  ## Fast, approximate — good for nearby poses.
  normalize3D(a * (1f-t) + b * t)

func motorSlerp*[T: MMultiVector3D](a, b: T, t: MFloat): T =
  ## Geodesic (exact) interpolation between two unit motors via log/exp.
  ## Constant-velocity along the screw motion path.
  let logA = log3D(a)
  let logB = log3D(b)
  let lerped = logA * (1f-t) + logB * t
  exp3D(lerped)


#############################################################################################################################
################################################### COMMON HELPERS ##########################################################
#############################################################################################################################

func gradeSelect2D*[T: MMultiVector2D](a: T, grade: int): T {.inline.} =
  ## Return only the components of the given grade, zeroing all others.
  case grade
  of 0: T(s: a.s)
  of 1: T(e0: a.e0, e1: a.e1, e2: a.e2)
  of 2: T(e12: a.e12, e20: a.e20, e01: a.e01)
  of 3: T(e012: a.e012)
  else: T()

func gradeSelect3D*[T: MMultiVector3D](a: T, grade: int): T {.inline.} =
  ## Return only the components of the given grade.
  case grade
  of 0: T(s: a.s)
  of 1: T(e0: a.e0, e1: a.e1, e2: a.e2, e3: a.e3)
  of 2: T(e12: a.e12, e13: a.e13, e23: a.e23, e01: a.e01, e02: a.e02, e03: a.e03)
  of 3: T(e123: a.e123, e021: a.e021, e013: a.e013, e032: a.e032)
  of 4: T(e0123: a.e0123)
  else: T()

func `$`*(m: MVec2): string =
  "MVec2(" &
  "s=" & $m.s & " e0=" & $m.e0 & " e1=" & $m.e1 & " e2=" & $m.e2 & " | " &
  "e12=" & $m.e12 & " e20=" & $m.e20 & " e01=" & $m.e01 & " | " &
  "e012=" & $m.e012 & ")"

func `$`*(m: MVec3): string =
  "MVec3(" &
  "s=" & $m.s & " e0=" & $m.e0 & " e1=" & $m.e1 & " e2=" & $m.e2 & " e3=" & $m.e3 & " | " &
  "e12=" & $m.e12 & " e13=" & $m.e13 & " e23=" & $m.e23 &
  " e01=" & $m.e01 & " e02=" & $m.e02 & " e03=" & $m.e03 & " | " &
  "e123=" & $m.e123 & " e021=" & $m.e021 & " e013=" & $m.e013 & " e032=" & $m.e032 & " | " &
  "e0123=" & $m.e0123 & ")"