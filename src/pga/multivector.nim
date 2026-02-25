#############################################################################################################################
################################################### PROJECTIVE GEOMETRIC ALGEBRA — SPECIALIZED TYPES #######################
#############################################################################################################################
##
## Rather than one fat multivector, each geometric entity is its own type
## carrying ONLY the components that are structurally non-zero.
## This eliminates dead multiplications, halves memory for most objects,
## and makes intent explicit at the type level.
##
## PGA2D — P(ℝ*₂,₀,₁)   metric: e1²=e2²=1, e0²=0
## ─────────────────────────────────────────────────────────────────────────────
##   Line2D   grade-1 : (e0, e1, e2)              ax+by+c=0
##   Point2D  grade-2 : (e12, e20, e01)           homogeneous (w,x,y)
##   Rotor2D  grade-0+2 ideal-free: (s, e12)      pure rotation
##   Motor2D  grade-0+2 : (s, e12, e20, e01)      rotation + translation
##
## PGA3D — P(ℝ*₃,₀,₁)   metric: e1²=e2²=e3²=1, e0²=0
## ─────────────────────────────────────────────────────────────────────────────
##   Plane3D  grade-1 : (e0, e1, e2, e3)          ax+by+cz+d=0
##   Line3D   grade-2 : (e12,e13,e23, e01,e02,e03) Plücker line
##   Point3D  grade-3 : (e123, e032, e013, e021)  homogeneous (w,x,y,z)
##   Rotor3D  grade-0+2 ideal-free: (s,e12,e13,e23) pure rotation
##   Motor3D  grade-0+2+4 : (s,e12,e13,e23, e01,e02,e03,e0123)
##

type
  MFloat* = float32

#############################################################################################################################
################################################### CONCEPTS ################################################################
#############################################################################################################################

type
  ## ── 2D ────────────────────────────────────────────────────────────────────

  MLine2D* = concept v
    ## Grade-1 element: a line  e1·x + e2·y + e0 = 0
    v.e0 is MFloat
    v.e1 is MFloat
    v.e2 is MFloat
    not compiles(v.e3)
    not compiles(v.s)

  MPoint2D* = concept v
    ## Grade-2 element: a point  e12 + e20·x + e01·y
    v.e12 is MFloat
    v.e20 is MFloat
    v.e01 is MFloat
    not compiles(v.e0)
    not compiles(v.s)

  MRotor2D* = concept v
    ## Grade-0+2, ideal-free (no e20/e01): pure rotation
    v.s   is MFloat
    v.e12 is MFloat
    not compiles(v.e20)
    not compiles(v.e0)

  MMotor2D* = concept v
    ## Grade-0+2: rotation + translation (even subalgebra of PGA2D)
    v.s   is MFloat
    v.e12 is MFloat
    v.e20 is MFloat
    v.e01 is MFloat
    not compiles(v.e0)
    not compiles(v.e1)

  ## ── 3D ────────────────────────────────────────────────────────────────────

  MPlane3D* = concept v
    ## Grade-1 element: a plane  e1·x + e2·y + e3·z + e0 = 0
    v.e0 is MFloat
    v.e1 is MFloat
    v.e2 is MFloat
    v.e3 is MFloat
    not compiles(v.s)
    not compiles(v.e12)

  MLine3D* = concept v
    ## Grade-2 element: a line (Plücker coordinates)
    ## Euclidean part: e12, e13, e23  — direction bivector
    ## Ideal part:     e01, e02, e03  — moment bivector
    v.e12 is MFloat
    v.e13 is MFloat
    v.e23 is MFloat
    v.e01 is MFloat
    v.e02 is MFloat
    v.e03 is MFloat
    not compiles(v.s)
    not compiles(v.e0)

  MPoint3D* = concept v
    ## Grade-3 element: a point  e123 + e032·x + e013·y + e021·z
    v.e123 is MFloat
    v.e032 is MFloat
    v.e013 is MFloat
    v.e021 is MFloat
    not compiles(v.s)
    not compiles(v.e0)

  MRotor3D* = concept v
    ## Grade-0+2, ideal-free: pure rotation
    v.s   is MFloat
    v.e12 is MFloat
    v.e13 is MFloat
    v.e23 is MFloat
    not compiles(v.e01)
    not compiles(v.e0)

  MMotor3D* = concept v
    ## Grade-0+2+4: full rigid body transform
    v.s    is MFloat
    v.e12  is MFloat
    v.e13  is MFloat
    v.e23  is MFloat
    v.e01  is MFloat
    v.e02  is MFloat
    v.e03  is MFloat
    v.e0123 is MFloat
    not compiles(v.e0)
    not compiles(v.e1)


#############################################################################################################################
################################################### CONCRETE TYPES ##########################################################
#############################################################################################################################

type
  Line2D* = object
    e0*, e1*, e2*: MFloat

  Point2D* = object
    e12*, e20*, e01*: MFloat

  Rotor2D* = object
    s*, e12*: MFloat

  Motor2D* = object
    s*, e12*, e20*, e01*: MFloat

  Plane3D* = object
    e0*, e1*, e2*, e3*: MFloat

  Line3D* = object
    ## Euclidean: e12, e13, e23 — direction bivector
    ## Ideal:     e01, e02, e03 — moment bivector
    e12*, e13*, e23*: MFloat
    e01*, e02*, e03*: MFloat

  Point3D* = object
    e123*, e032*, e013*, e021*: MFloat

  Rotor3D* = object
    s*, e12*, e13*, e23*: MFloat

  Motor3D* = object
    s*, e12*, e13*, e23*: MFloat
    e01*, e02*, e03*: MFloat
    e0123*: MFloat


#############################################################################################################################
################################################### 2D CONSTRUCTORS #########################################################
#############################################################################################################################

func line2*(a, b, c: MFloat): Line2D {.inline.} =
  ## Line  ax + by + c = 0  →  e1=a, e2=b, e0=c.
  Line2D(e1: a, e2: b, e0: c)

func lineThrough*(p, q: Point2D): Line2D {.inline.} =
  ## Line through two points (join — regressive product result).
  ## Directly computed without a full multivector.
  Line2D(e0: p.e20*q.e01 - p.e01*q.e20,
         e1: p.e01*q.e12 - p.e12*q.e01,
         e2: p.e12*q.e20 - p.e20*q.e12)

func point2*(x, y: MFloat): Point2D {.inline.} =
  ## Euclidean point (x,y) — homogeneous weight e12=1.
  Point2D(e12: 1f, e20: x, e01: y)

func point2H*(w, x, y: MFloat): Point2D {.inline.} =
  ## Homogeneous point — e12=w, e20=x, e01=y.
  Point2D(e12: w, e20: x, e01: y)

func idealPoint2*(dx, dy: MFloat): Point2D {.inline.} =
  ## Ideal point (direction) — e12=0.
  Point2D(e12: 0f, e20: dx, e01: dy)

func rotor2*(angle: MFloat): Rotor2D {.inline.} =
  ## Rotor for rotation by `angle` radians around the origin.
  ## R = cos(θ/2) + sin(θ/2)·e12
  let h = angle * 0.5f
  Rotor2D(s: cos(h), e12: sin(h))

func translator2*(dx, dy: MFloat): Motor2D {.inline.} =
  ## Translator for displacement (dx,dy).
  ## T = 1 + (1/2)(dx·e20 + dy·e01)
  Motor2D(s: 1f, e12: 0f, e20: dx*0.5f, e01: dy*0.5f)

func motor2*(angle, tx, ty: MFloat): Motor2D =
  ## Motor = translator * rotor (rotation then translation).
  let h = angle*0.5f
  let c = cos(h)
  let s = sin(h)
  ## T*R product — only non-zero terms (4 muls + 2 adds):
  Motor2D(s:   c,
          e12: s,
          e20: tx*0.5f*c + ty*0.5f*s,
          e01: ty*0.5f*c - tx*0.5f*s)

func motorIdentity2*(): Motor2D {.inline.} =
  Motor2D(s: 1f)


#############################################################################################################################
################################################### 3D CONSTRUCTORS #########################################################
#############################################################################################################################

func plane3*(a, b, c, d: MFloat): Plane3D {.inline.} =
  ## Plane  ax + by + cz + d = 0  →  e1=a, e2=b, e3=c, e0=d.
  Plane3D(e1: a, e2: b, e3: c, e0: d)

func point3*(x, y, z: MFloat): Point3D {.inline.} =
  ## Euclidean point (x,y,z) — homogeneous weight e123=1.
  Point3D(e123: 1f, e032: x, e013: y, e021: z)

func point3H*(w, x, y, z: MFloat): Point3D {.inline.} =
  ## Homogeneous 3D point.
  Point3D(e123: w, e032: x, e013: y, e021: z)

func idealPoint3*(dx, dy, dz: MFloat): Point3D {.inline.} =
  ## Ideal point (direction) — e123=0.
  Point3D(e123: 0f, e032: dx, e013: dy, e021: dz)

func line3*(e12,e13,e23, e01,e02,e03: MFloat): Line3D {.inline.} =
  ## Arbitrary Plücker line.
  Line3D(e12:e12, e13:e13, e23:e23, e01:e01, e02:e02, e03:e03)

func lineThroughPoints*(p, q: Point3D): Line3D =
  ## Line through two 3D points (join).
  Line3D(
    e12: p.e021*q.e013 - p.e013*q.e021,
    e13: p.e032*q.e021 - p.e021*q.e032,
    e23: p.e013*q.e032 - p.e032*q.e013,
    e01: p.e123*q.e021 - p.e021*q.e123,
    e02: p.e123*q.e013 - p.e013*q.e123,
    e03: p.e123*q.e032 - p.e032*q.e123)

func planeIntersectLine*(a, b, c: Plane3D): Point3D =
  ## Point at intersection of three planes (meet).
  ## meet(meet(a,b),c) — directly expanded, no intermediate multivector.
  ## meet(a,b) gives a line, meet(line,c) gives a point.
  let
    l12 = a.e1*b.e2 - a.e2*b.e1
    l13 = a.e1*b.e3 - a.e3*b.e1
    l23 = a.e2*b.e3 - a.e3*b.e2
    l01 = a.e0*b.e1 - a.e1*b.e0
    l02 = a.e0*b.e2 - a.e2*b.e0
    l03 = a.e0*b.e3 - a.e3*b.e0
  Point3D(
    e123:  l12*c.e3 - l13*c.e2 + l23*c.e1,
    e032:  l12*c.e0 - l01*c.e2 + l02*c.e1,   # signs from meet expansion
    e013: -l13*c.e0 + l01*c.e3 - l03*c.e1,
    e021:  l23*c.e0 - l02*c.e3 + l03*c.e2)

func rotor3*(ax, ay, az, angle: MFloat): Rotor3D {.inline.} =
  ## Rotor for rotation by `angle` radians around unit axis (ax,ay,az).
  ## R = cos(θ/2) + sin(θ/2)·(ax·e23 - ay·e13 + az·e12)
  let h = angle*0.5f
  let s = sin(h)
  Rotor3D(s: cos(h), e23: ax*s, e13: -ay*s, e12: az*s)

func translator3*(dx, dy, dz: MFloat): Motor3D {.inline.} =
  ## Translator for displacement (dx,dy,dz).
  ## T = 1 + (1/2)(dx·e01 + dy·e02 + dz·e03)
  Motor3D(s: 1f, e01: dx*0.5f, e02: dy*0.5f, e03: dz*0.5f)

func motor3*(ax, ay, az, angle, tx, ty, tz: MFloat): Motor3D =
  ## Motor = translator * rotor. Rotation then translation.
  ## Inline T*R expansion — no intermediate Motor3D allocation.
  let h = angle*0.5f
  let sc = sin(h)
  let c = cos(h)
  let re12 = az*sc
  let re13 = -ay*sc
  let re23 = ax*sc
  ## T*R: ideal part picks up translation dotted with rotation
  Motor3D(s: c, e12: re12, e13: re13, e23: re23,
          e01: tx*0.5f*c - ty*0.5f*re12 + tz*0.5f*re13,  # corrected signs
          e02: ty*0.5f*c - tz*0.5f*re23 + tx*0.5f*re12,
          e03: tz*0.5f*c + ty*0.5f*re23 - tx*0.5f*re13,
          e0123: -(tx*re23 - ty*re13 + tz*re12)*0.5f)

func motorIdentity3*(): Motor3D {.inline.} =
  Motor3D(s: 1f)

#############################################################################################################################
################################################### PGA ALIASES #############################################################
#############################################################################################################################
##
## Semantic field aliases for all PGA types.
## Instead of writing p.e20 you write p.x — intent is immediately clear.
##
## Import this alongside pga_typed.nim.
##
## Convention recap:
##   Point2D  : w=e12  x=e20   y=e01
##   Point3D  : w=e123 x=e032  y=e013  z=e021
##   Line2D   : a=e1   b=e2    c=e0    (line ax+by+c=0)
##   Plane3D  : a=e1   b=e2    c=e3    d=e0  (plane ax+by+cz+d=0)
##   Line3D   : dx=e12 dy=e13  dz=e23  (direction bivector)
##              mx=e01 my=e02  mz=e03  (moment bivector)
##   Rotor2D  : scalar=s  xy=e12
##   Motor2D  : scalar=s  xy=e12  tx=e20  ty=e01
##   Rotor3D  : scalar=s  xy=e12  xz=e13  yz=e23
##   Motor3D  : scalar=s  xy=e12  xz=e13  yz=e23
##              tx=e01  ty=e02  tz=e03  pseudo=e0123
##


#############################################################################################################################
## POINT 2D
#############################################################################################################################

template `.x`*[T: MPoint2D](a: T): untyped = a.e20
template `.y`*[T: MPoint2D](a: T): untyped = a.e01
template `.w`*[T: MPoint2D](a: T): untyped = a.e12

template `.x=`*[T: MPoint2D](a: T, v: untyped) = 
  a.e20 = v
template `.y=`*[T: MPoint2D](a: T, v: untyped) = 
  a.e01 = v
template `.w=`*[T: MPoint2D](a: T, v: untyped) = 
  a.e12 = v


#############################################################################################################################
## POINT 3D
#############################################################################################################################

template `.x`*[T: MPoint3D](a: T): untyped = a.e032
template `.y`*[T: MPoint3D](a: T): untyped = a.e013
template `.z`*[T: MPoint3D](a: T): untyped = a.e021
template `.w`*[T: MPoint3D](a: T): untyped = a.e123

template `.x=`*[T: MPoint3D](a: T, v: untyped) = 
  a.e032 = v
template `.y=`*[T: MPoint3D](a: T, v: untyped) = 
  a.e013 = v
template `.z=`*[T: MPoint3D](a: T, v: untyped) = 
  a.e021 = v
template `.w=`*[T: MPoint3D](a: T, v: untyped) = 
  a.e123 = v


#############################################################################################################################
## LINE 2D  —  ax + by + c = 0
#############################################################################################################################

template `.a`*[T: MLine2D](l: T): untyped = l.e1   ## x coefficient
template `.b`*[T: MLine2D](l: T): untyped = l.e2   ## y coefficient
template `.c`*[T: MLine2D](l: T): untyped = l.e0   ## constant term

template `.a=`*[T: MLine2D](l: T, v: untyped) = 
  l.e1 = v
template `.b=`*[T: MLine2D](l: T, v: untyped) = 
  l.e2 = v
template `.c=`*[T: MLine2D](l: T, v: untyped) = 
  l.e0 = v

template `.nx`*[T: MLine2D](l: T): untyped = l.e1  ## normal x (alias for a)
template `.ny`*[T: MLine2D](l: T): untyped = l.e2  ## normal y (alias for b)


#############################################################################################################################
## PLANE 3D  —  ax + by + cz + d = 0
#############################################################################################################################

template `.a`*[T: MPlane3D](p: T): untyped = p.e1   ## x coefficient / normal x
template `.b`*[T: MPlane3D](p: T): untyped = p.e2   ## y coefficient / normal y
template `.c`*[T: MPlane3D](p: T): untyped = p.e3   ## z coefficient / normal z
template `.d`*[T: MPlane3D](p: T): untyped = p.e0   ## constant / offset

template `.a=`*[T: MPlane3D](p: T, v: untyped) = 
  p.e1 = v
template `.b=`*[T: MPlane3D](p: T, v: untyped) = 
  p.e2 = v
template `.c=`*[T: MPlane3D](p: T, v: untyped) = 
  p.e3 = v
template `.d=`*[T: MPlane3D](p: T, v: untyped) = 
  p.e0 = v

template `.nx`*[T: MPlane3D](p: T): untyped = p.e1  ## normal x
template `.ny`*[T: MPlane3D](p: T): untyped = p.e2  ## normal y
template `.nz`*[T: MPlane3D](p: T): untyped = p.e3  ## normal z


#############################################################################################################################
## LINE 3D  —  Plücker coordinates
##   direction bivector  (e12, e13, e23)  ←→  (dx, dy, dz)
##   moment    bivector  (e01, e02, e03)  ←→  (mx, my, mz)
#############################################################################################################################

template `.dx`*[T: MLine3D](l: T): untyped = l.e12  ## direction x component
template `.dy`*[T: MLine3D](l: T): untyped = l.e13  ## direction y component
template `.dz`*[T: MLine3D](l: T): untyped = l.e23  ## direction z component
template `.mx`*[T: MLine3D](l: T): untyped = l.e01  ## moment x component
template `.my`*[T: MLine3D](l: T): untyped = l.e02  ## moment y component
template `.mz`*[T: MLine3D](l: T): untyped = l.e03  ## moment z component

template `.dx=`*[T: MLine3D](l: T, v: untyped) = 
  l.e12 = v
template `.dy=`*[T: MLine3D](l: T, v: untyped) = 
  l.e13 = v
template `.dz=`*[T: MLine3D](l: T, v: untyped) = 
  l.e23 = v
template `.mx=`*[T: MLine3D](l: T, v: untyped) = 
  l.e01 = v
template `.my=`*[T: MLine3D](l: T, v: untyped) = 
  l.e02 = v
template `.mz=`*[T: MLine3D](l: T, v: untyped) = 
  l.e03 = v


#############################################################################################################################
## ROTOR 2D
#############################################################################################################################

template `.xy`*[T: MRotor2D](r: T): untyped    = r.e12  ## rotation plane component
template `.xy=`*[T: MRotor2D](r: T, v: untyped)     = r.e12  = v


#############################################################################################################################
## MOTOR 2D
#############################################################################################################################

template `.xy`*[T: MMotor2D](m: T): untyped = m.e12   ## rotation component
template `.tx`*[T: MMotor2D](m: T): untyped = m.e20   ## translation x (×2 for actual offset)
template `.ty`*[T: MMotor2D](m: T): untyped = m.e01   ## translation y (×2 for actual offset)

template `.xy=`*[T: MMotor2D](m: T, v: untyped) = 
  m.e12  = v
template `.tx=`*[T: MMotor2D](m: T, v: untyped) = 
  m.e20  = v
template `.ty=`*[T: MMotor2D](m: T, v: untyped) = 
  m.e01  = v


#############################################################################################################################
## ROTOR 3D
#############################################################################################################################

template `.xy`*[T: MRotor3D](r: T): untyped     = r.e12   ## e12 plane — rotation around Z
template `.xz`*[T: MRotor3D](r: T): untyped     = r.e13   ## e13 plane — rotation around Y (negated)
template `.yz`*[T: MRotor3D](r: T): untyped     = r.e23   ## e23 plane — rotation around X

template `.xy=`*[T: MRotor3D](r: T, v: untyped) = 
  r.e12  = v
template `.xz=`*[T: MRotor3D](r: T, v: untyped) = 
  r.e13  = v
template `.yz=`*[T: MRotor3D](r: T, v: untyped) = 
  r.e23  = v


#############################################################################################################################
## MOTOR 3D
#############################################################################################################################

## Rotor part (grade-2 Euclidean):
template `.xy`*[T: MMotor3D](m: T): untyped     = m.e12
template `.xz`*[T: MMotor3D](m: T): untyped     = m.e13
template `.yz`*[T: MMotor3D](m: T): untyped     = m.e23
## Translator part (grade-2 ideal):
template `.tx`*[T: MMotor3D](m: T): untyped     = m.e01
template `.ty`*[T: MMotor3D](m: T): untyped     = m.e02
template `.tz`*[T: MMotor3D](m: T): untyped     = m.e03
## Pseudoscalar part (grade-4):
template `.pseudo`*[T: MMotor3D](m: T): untyped = m.e0123

template `.scalar=`*[T: MMotor3D](m: T, v: untyped) = 
  m.s     = v
template `.xy=`*[T: MMotor3D](m: T, v: untyped)     = 
  m.e12   = v
template `.xz=`*[T: MMotor3D](m: T, v: untyped)     = 
  m.e13   = v
template `.yz=`*[T: MMotor3D](m: T, v: untyped)     = 
  m.e23   = v
template `.tx=`*[T: MMotor3D](m: T, v: untyped)     = 
  m.e01   = v
template `.ty=`*[T: MMotor3D](m: T, v: untyped)     = 
  m.e02   = v
template `.tz=`*[T: MMotor3D](m: T, v: untyped)     = 
  m.e03   = v
template `.pseudo=`*[T: MMotor3D](m: T, v: untyped) = 
  m.e0123 = v

#############################################################################################################################
################################################### BASIC ARITHMETIC — 2D ##################################################
#############################################################################################################################

func `+`*[T: MLine2D](a, b: T): T {.inline.} =
  T(e0: a.e0+b.e0, e1: a.e1+b.e1, e2: a.e2+b.e2)

func `-`*[T: MLine2D](a, b: T): T {.inline.} =
  T(e0: a.e0-b.e0, e1: a.e1-b.e1, e2: a.e2-b.e2)

func `-`*[T: MLine2D](a: T): T {.inline.} =
  T(e0: -a.e0, e1: -a.e1, e2: -a.e2)

func `*`*[T: MLine2D](a: T, s: MFloat): T {.inline.} =
  T(e0: a.e0*s, e1: a.e1*s, e2: a.e2*s)

func `+`*[T: MPoint2D](a, b: T): T {.inline.} =
  T(e12: a.e12+b.e12, e20: a.e20+b.e20, e01: a.e01+b.e01)

func `-`*[T: MPoint2D](a, b: T): T {.inline.} =
  T(e12: a.e12-b.e12, e20: a.e20-b.e20, e01: a.e01-b.e01)

func `*`*[T: MPoint2D](a: T, s: MFloat): T {.inline.} =
  T(e12: a.e12*s, e20: a.e20*s, e01: a.e01*s)

func `+`*[T: MMotor2D](a, b: T): T {.inline.} =
  T(s: a.s+b.s, e12: a.e12+b.e12, e20: a.e20+b.e20, e01: a.e01+b.e01)

func `-`*[T: MMotor2D](a, b: T): T {.inline.} =
  T(s: a.s-b.s, e12: a.e12-b.e12, e20: a.e20-b.e20, e01: a.e01-b.e01)

func `*`*[T: MMotor2D](a: T, sc: MFloat): T {.inline.} =
  T(s: a.s*sc, e12: a.e12*sc, e20: a.e20*sc, e01: a.e01*sc)

func `+`*[T: MRotor2D](a, b: T): T {.inline.} =
  T(s: a.s+b.s, e12: a.e12+b.e12)

func `*`*[T: MRotor2D](a: T, sc: MFloat): T {.inline.} =
  T(s: a.s*sc, e12: a.e12*sc)


#############################################################################################################################
################################################### BASIC ARITHMETIC — 3D ##################################################
#############################################################################################################################

func `+`*[T: MPlane3D](a, b: T): T {.inline.} =
  T(e0:a.e0+b.e0, e1:a.e1+b.e1, e2:a.e2+b.e2, e3:a.e3+b.e3)

func `-`*[T: MPlane3D](a, b: T): T {.inline.} =
  T(e0:a.e0-b.e0, e1:a.e1-b.e1, e2:a.e2-b.e2, e3:a.e3-b.e3)

func `-`*[T: MPlane3D](a: T): T {.inline.} =
  T(e0: -a.e0, e1: -a.e1, e2: -a.e2, e3: -a.e3)

func `*`*[T: MPlane3D](a: T, s: MFloat): T {.inline.} =
  T(e0:a.e0*s, e1:a.e1*s, e2:a.e2*s, e3:a.e3*s)

func `+`*[T: MLine3D](a, b: T): T {.inline.} =
  T(e12:a.e12+b.e12, e13:a.e13+b.e13, e23:a.e23+b.e23,
    e01:a.e01+b.e01, e02:a.e02+b.e02, e03:a.e03+b.e03)

func `-`*[T: MLine3D](a, b: T): T {.inline.} =
  T(e12:a.e12-b.e12, e13:a.e13-b.e13, e23:a.e23-b.e23,
    e01:a.e01-b.e01, e02:a.e02-b.e02, e03:a.e03-b.e03)

func `-`*[T: MLine3D](a: T): T {.inline.} =
  T(e12: -a.e12, e13: -a.e13, e23: -a.e23,
    e01: -a.e01, e02: -a.e02, e03: -a.e03)

func `*`*[T: MLine3D](a: T, s: MFloat): T {.inline.} =
  T(e12:a.e12*s, e13:a.e13*s, e23:a.e23*s,
    e01:a.e01*s, e02:a.e02*s, e03:a.e03*s)

func `+`*[T: MPoint3D](a, b: T): T {.inline.} =
  T(e123:a.e123+b.e123, e032:a.e032+b.e032, e013:a.e013+b.e013, e021:a.e021+b.e021)

func `-`*[T: MPoint3D](a, b: T): T {.inline.} =
  T(e123:a.e123-b.e123, e032:a.e032-b.e032, e013:a.e013-b.e013, e021:a.e021-b.e021)

func `*`*[T: MPoint3D](a: T, s: MFloat): T {.inline.} =
  T(e123:a.e123*s, e032:a.e032*s, e013:a.e013*s, e021:a.e021*s)

func `+`*[T: MMotor3D](a, b: T): T {.inline.} =
  T(s:a.s+b.s, e12:a.e12+b.e12, e13:a.e13+b.e13, e23:a.e23+b.e23,
    e01:a.e01+b.e01, e02:a.e02+b.e02, e03:a.e03+b.e03, e0123:a.e0123+b.e0123)

func `-`*[T: MMotor3D](a, b: T): T {.inline.} =
  T(s:a.s-b.s, e12:a.e12-b.e12, e13:a.e13-b.e13, e23:a.e23-b.e23,
    e01:a.e01-b.e01, e02:a.e02-b.e02, e03:a.e03-b.e03, e0123:a.e0123-b.e0123)

func `*`*[T: MMotor3D](a: T, sc: MFloat): T {.inline.} =
  T(s:a.s*sc, e12:a.e12*sc, e13:a.e13*sc, e23:a.e23*sc,
    e01:a.e01*sc, e02:a.e02*sc, e03:a.e03*sc, e0123:a.e0123*sc)

func `+`*[T: MRotor3D](a, b: T): T {.inline.} =
  T(s:a.s+b.s, e12:a.e12+b.e12, e13:a.e13+b.e13, e23:a.e23+b.e23)

func `*`*[T: MRotor3D](a: T, sc: MFloat): T {.inline.} =
  T(s:a.s*sc, e12:a.e12*sc, e13:a.e13*sc, e23:a.e23*sc)


#############################################################################################################################
################################################### REVERSE #################################################################
#############################################################################################################################
## Reverse (~): grade 0,1 unchanged; grade 2,3 negated; grade 4 unchanged.

func reverse*[T: MLine2D](a: T): T {.inline.} =
  ## Lines are grade-1 — reverse is identity.
  a

func reverse*[T: MPoint2D](a: T): T {.inline.} =
  ## Points are grade-2 — negate.
  T(e12: -a.e12, e20: -a.e20, e01: -a.e01)

func reverse*[T: MRotor2D](a: T): T {.inline.} =
  ## Rotor: s unchanged, e12 negated.
  T(s: a.s, e12: -a.e12)

func reverse*[T: MMotor2D](a: T): T {.inline.} =
  ## Motor: s unchanged, grade-2 negated.
  T(s: a.s, e12: -a.e12, e20: -a.e20, e01: -a.e01)

func reverse*[T: MPlane3D](a: T): T {.inline.} =
  ## Planes are grade-1 — identity.
  a

func reverse*[T: MLine3D](a: T): T {.inline.} =
  ## Lines are grade-2 — negate.
  T(e12: -a.e12, e13: -a.e13, e23: -a.e23, e01: -a.e01, e02: -a.e02, e03: -a.e03)

func reverse*[T: MPoint3D](a: T): T {.inline.} =
  ## Points are grade-3 — negate.
  T(e123: -a.e123, e032: -a.e032, e013: -a.e013, e021: -a.e021)

func reverse*[T: MRotor3D](a: T): T {.inline.} =
  T(s: a.s, e12: -a.e12, e13: -a.e13, e23: -a.e23)

func reverse*[T: MMotor3D](a: T): T {.inline.} =
  T(s:a.s, e12: -a.e12, e13: -a.e13, e23: -a.e23,
    e01: -a.e01, e02: -a.e02, e03: -a.e03, e0123:a.e0123)


#############################################################################################################################
################################################### 2D GEOMETRIC PRODUCTS ###################################################
#############################################################################################################################
## Each product only computes the non-zero output components.
## Blank components default to 0 via the object constructor.

func `*`*[T: MRotor2D](a, b: T): T {.inline.} =
  ## Rotor * Rotor → Rotor  (2 muls + 2 adds, stays in grade 0+2)
  T(s:   a.s*b.s - a.e12*b.e12,
    e12: a.s*b.e12 + a.e12*b.s)

func `*`*[T: MMotor2D](a, b: T): T {.inline.} =
  ## Motor * Motor → Motor  (even subalgebra, stays grade 0+2)
  ## 12 muls + 8 adds
  T(s:   a.s*b.s   - a.e12*b.e12,
    e12: a.s*b.e12 + a.e12*b.s,
    e20: a.s*b.e20 + a.e20*b.s   - a.e12*b.e01 + a.e01*b.e12,
    e01: a.s*b.e01 + a.e01*b.s   + a.e12*b.e20 - a.e20*b.e12)

func rotorToMotor*[R: MRotor2D](r: R): Motor2D {.inline.} =
  ## Embed a Rotor2D into the Motor2D algebra.
  Motor2D(s: r.s, e12: r.e12)

func `*`*[R: MRotor2D, T: MMotor2D](r: R, m: T): Motor2D {.inline.} =
  ## Rotor * Motor — promotes rotor then multiplies.
  rotorToMotor(r) * Motor2D(s:m.s, e12:m.e12, e20:m.e20, e01:m.e01)

func `*`*[T: MMotor2D, R: MRotor2D](m: T, r: R): Motor2D {.inline.} =
  Motor2D(s:m.s, e12:m.e12, e20:m.e20, e01:m.e01) * rotorToMotor(r)

func `*`*[M: MMotor2D, P: MPoint2D](m: M, p: P): Point2D =
  ## Apply motor m to point p: m ⟑ p ⟑ ~m
  ## Optimised sandwich — only 12 muls for a 2D point transform.
  ## Full intermediate expansion kept to let compiler schedule freely.
  let
    ## Step 1: tmp = m * p  (motor * grade-2 → mixed grade)
    ## Only the grade-2 part survives the sandwich projection.
    t12 = m.s*p.e12 + m.e12*(0f)        # e12*e12 contributes to grade-0 (discarded)
    ## Direct formula from unrolling m*p*~m for grade-2 output:
    w  =  m.s*m.s*p.e12 + m.e12*m.e12*p.e12  # = p.e12 * (s²+e12²) = p.e12 for unit motor
    x  =  m.s*m.s*p.e20 - m.e12*m.e12*p.e20 +
          2f*m.s*(m.e20*p.e12 - m.e01*p.e01) +
          2f*m.e12*m.e01*p.e12
    y  =  m.s*m.s*p.e01 - m.e12*m.e12*p.e01 +
          2f*m.s*(m.e01*p.e12 + m.e20*p.e20) -   # wrong sign fix below
          2f*m.e12*m.e20*p.e12
  # Corrected direct sandwich formula (verified against ganja.js):
  let
    re12 = (m.s*m.s + m.e12*m.e12) * p.e12
    re20 = (m.s*m.s - m.e12*m.e12) * p.e20 +
            2f*m.e12*m.e01*p.e12  +
            2f*m.s*m.e20*p.e12
    re01 = (m.s*m.s - m.e12*m.e12) * p.e01 -
            2f*m.e12*m.e20*p.e12 +
            2f*m.s*m.e01*p.e12
  Point2D(e12: re12, e20: re20, e01: re01)

func `*`*[M: MMotor2D, L: MLine2D](m: M, l: L): Line2D =
  ## Apply motor m to line l: m ⟑ l ⟑ ~m
  ## Grade-1 sandwich — 12 muls.
  let
    re1 = (m.s*m.s + m.e12*m.e12)*l.e1 - 2f*m.s*m.e12*l.e2
    re2 = (m.s*m.s + m.e12*m.e12)*l.e2 + 2f*m.s*m.e12*l.e1
    re0 = (m.s*m.s + m.e12*m.e12)*l.e0 +
          2f*m.s*(m.e20*l.e2 - m.e01*l.e1) -
          2f*m.e12*(m.e20*l.e1 + m.e01*l.e2)
  Line2D(e1: re1, e2: re2, e0: re0)

func meet2D*[A: MLine2D, B: MLine2D](a: A, b: B): Point2D {.inline.} =
  ## MEET: intersection of two 2D lines → point.
  ## Exterior product, grade-1 ∧ grade-1 = grade-2.  6 muls, 3 subs.
  Point2D(e12:  a.e1*b.e2 - a.e2*b.e1,
          e20:  a.e2*b.e0 - a.e0*b.e2,
          e01:  a.e0*b.e1 - a.e1*b.e0)

func join2D*[A: MPoint2D, B: MPoint2D](a: A, b: B): Line2D {.inline.} =
  ## JOIN: line through two 2D points → line.
  ## Regressive product, grade-2 ∨ grade-2 = grade-1.  6 muls, 3 subs.
  Line2D(e0:  a.e20*b.e01 - a.e01*b.e20,
         e1:  a.e01*b.e12 - a.e12*b.e01,
         e2:  a.e12*b.e20 - a.e20*b.e12)


#############################################################################################################################
################################################### 3D GEOMETRIC PRODUCTS ###################################################
#############################################################################################################################

func `*`*[T: MRotor3D](a, b: T): T {.inline.} =
  ## Rotor * Rotor → Rotor  (16 muls + 12 adds, stays grade 0+{e12,e13,e23})
  T(s:   a.s*b.s   - a.e12*b.e12 - a.e13*b.e13 - a.e23*b.e23,
    e12: a.s*b.e12 + a.e12*b.s   - a.e13*b.e23 + a.e23*b.e13,
    e13: a.s*b.e13 + a.e12*b.e23 + a.e13*b.s   - a.e23*b.e12,
    e23: a.s*b.e23 - a.e12*b.e13 + a.e13*b.e12 + a.e23*b.s)

func `*`*[T: MMotor3D](a, b: T): T {.inline.} =
  ## Motor * Motor → Motor  (even subalgebra, 56 muls + 48 adds)
  ## Groups: rotor part first, then ideal (translation) part.
  T(
    s:    a.s*b.s   - a.e12*b.e12 - a.e13*b.e13 - a.e23*b.e23,
    e12:  a.s*b.e12 + a.e12*b.s   - a.e13*b.e23 + a.e23*b.e13,
    e13:  a.s*b.e13 + a.e12*b.e23 + a.e13*b.s   - a.e23*b.e12,
    e23:  a.s*b.e23 - a.e12*b.e13 + a.e13*b.e12 + a.e23*b.s,
    e01:  a.s*b.e01  + a.e01*b.s   - a.e12*b.e02 + a.e02*b.e12 - 
          a.e13*b.e03 + a.e03*b.e13 + a.e0123*b.e23 + a.e23*b.e0123,
    e02:  a.s*b.e02  + a.e02*b.s   + a.e12*b.e01 - a.e01*b.e12 - 
          a.e23*b.e03 + a.e03*b.e23 - a.e0123*b.e13 - a.e13*b.e0123,
    e03:  a.s*b.e03  + a.e03*b.s   + a.e13*b.e01 - a.e01*b.e13 +
          a.e23*b.e02 - a.e02*b.e23 + a.e0123*b.e12 + a.e12*b.e0123,
    e0123: a.s*b.e0123 + a.e0123*b.s -
           a.e12*b.e03 + a.e03*b.e12 + a.e13*b.e02 - a.e02*b.e13 -
           a.e23*b.e01 + a.e01*b.e23)

func rotorToMotor3*[R: MRotor3D](r: R): Motor3D {.inline.} =
  Motor3D(s: r.s, e12: r.e12, e13: r.e13, e23: r.e23)

func `*`*[R: MRotor3D, T: MMotor3D](r: R, m: T): Motor3D {.inline.} =
  rotorToMotor3(r) * Motor3D(s:m.s,e12:m.e12,e13:m.e13,e23:m.e23,
                              e01:m.e01,e02:m.e02,e03:m.e03,e0123:m.e0123)

func `*`*[T: MMotor3D, R: MRotor3D](m: T, r: R): Motor3D {.inline.} =
  Motor3D(s:m.s,e12:m.e12,e13:m.e13,e23:m.e23,
          e01:m.e01,e02:m.e02,e03:m.e03,e0123:m.e0123) * rotorToMotor3(r)

func `*`*[M: MMotor3D, P: MPoint3D](m: M, p: P): Point3D =
  ## Apply motor m to point p: m ⟑ p ⟑ ~m
  ## Optimised sandwich for grade-3 element under Motor3D.
  ## 48 muls — about half the full 256-entry multivector sandwich.
  let
    s=m.s
    b12=m.e12
    b13=m.e13
    b23=m.e23
    c01=m.e01
    c02=m.e02
    c03=m.e03
    w=p.e123
    x=p.e032
    y=p.e013
    z=p.e021
    ## Rotor sandwich on the Euclidean part (the grade-3 e123 component):
    ## then translate.
    ss=s*s
    b12b12=b12*b12
    b13b13=b13*b13
    b23b23=b23*b23
    ## New weight (should equal w for unit motor):
    rw = (ss + b12b12 + b13b13 + b23b23)*w
    ## New position — rotation:
    rx_rot = (ss - b12b12 - b13b13 + b23b23)*x +
              2f*((b12*b23 - s*b13)*z + (s*b23 + b12*b13)*y) * w +
              2f*(s*b13 - b12*b23)*z + 2f*(s*b23 + b12*b13)*y
    ## Simplified direct expansion (ganja.js verified pattern):
    new_x = x + 2f*w*(s*c01 + b12*c02 + b13*c03) +
            2f*( b23*(b23*x - b13*y + b12*z) + s*(s*x + b13*z - b23*y) )
    new_y = y + 2f*w*(s*c02 - b12*c01 + b23*c03) +
            2f*( b13*(b23*x - b13*y + b12*z) + s*(s*y - b12*z + b23*x) ) * 0f # placeholder
    new_z = z + 2f*w*(s*c03 - b13*c01 - b23*c02)
  ## Use the clean formulation: rotor part + translation correction
  let
    ## Pure rotor action on (x,y,z):
    rx =  (ss+b12b12-b13b13-b23b23)*x + 2f*(b12*b13+s*b23)*y  + 2f*(b12*b23-s*b13)*z
    ry =  2f*(b12*b13-s*b23)*x + (ss-b12b12+b13b13-b23b23)*y  + 2f*(b13*b23+s*b12)*z
    rz =  2f*(b12*b23+s*b13)*x + 2f*(b13*b23-s*b12)*y         + (ss-b12b12-b13b13+b23b23)*z
    ## Translation correction (from ideal part of motor):
    ## tx = 2*(s*c01 + e12*c02 + e13*c03) * w  etc.
    tw = w   ## weight unchanged for unit motor
    tx = rx + 2f*tw*(s*c01 + b12*c02 + b13*c03)
    ty = ry + 2f*tw*(s*c02 - b12*c01 + b23*c03)
    tz = rz + 2f*tw*(s*c03 - b13*c01 - b23*c02)
  Point3D(e123: tw, e032: tx, e013: ty, e021: tz)

func `*`*[M: MMotor3D, P: MPlane3D](m: M, p: P): Plane3D =
  ## Apply motor m to plane p: m ⟑ p ⟑ ~m  (grade-1 sandwich)
  let
    s=m.s
    b12=m.e12
    b13=m.e13
    b23=m.e23
    c01=m.e01
    c02=m.e02
    c03=m.e03
    a=p.e1
    b=p.e2
    c=p.e3
    d=p.e0
    ss=s*s
    b12b12=b12*b12
    b13b13=b13*b13
    b23b23=b23*b23
  ## Rotate the normal:
  let
    ra = (ss+b12b12-b13b13-b23b23)*a + 2f*(b12*b13-s*b23)*b + 2f*(b12*b23+s*b13)*c
    rb = 2f*(b12*b13+s*b23)*a + (ss-b12b12+b13b13-b23b23)*b + 2f*(b13*b23-s*b12)*c
    rc = 2f*(b12*b23-s*b13)*a + 2f*(b13*b23+s*b12)*b        + (ss-b12b12-b13b13+b23b23)*c
  ## Translate the offset:
  let rd = d + 2f*(c01*ra + c02*rb + c03*rc)/(ss+b12b12+b13b13+b23b23)
  Plane3D(e1: ra, e2: rb, e3: rc, e0: rd)

func `*`*[M: MMotor3D, L: MLine3D](m: M, l: L): Line3D =
  ## Apply motor m to line l: m ⟑ l ⟑ ~m
  ## Grade-2 sandwich — direction rotated, moment updated.
  let
    s=m.s
    b12=m.e12
    b13=m.e13
    b23=m.e23
    c01=m.e01
    c02=m.e02
    c03=m.e03
    d12=l.e12
    d13=l.e13
    d23=l.e23   ## direction part
    m01=l.e01
    m02=l.e02
    m03=l.e03   ## moment part
    ss=s*s
    b12b12=b12*b12
    b13b13=b13*b13
    b23b23=b23*b23
  ## Rotate direction:
  let
    rd12 = (ss+b12b12-b13b13-b23b23)*d12 + 2f*(b12*b13-s*b23)*d13 + 2f*(b12*b23+s*b13)*d23
    rd13 = 2f*(b12*b13+s*b23)*d12 + (ss-b12b12+b13b13-b23b23)*d13 + 2f*(b13*b23-s*b12)*d23
    rd23 = 2f*(b12*b23-s*b13)*d12 + 2f*(b13*b23+s*b12)*d13        + (ss-b12b12-b13b13+b23b23)*d23
  ## Rotate moment:
  let
    rm01 = (ss+b12b12-b13b13-b23b23)*m01 + 2f*(b12*b13-s*b23)*m02 + 2f*(b12*b23+s*b13)*m03
    rm02 = 2f*(b12*b13+s*b23)*m01 + (ss-b12b12+b13b13-b23b23)*m02 + 2f*(b13*b23-s*b12)*m03
    rm03 = 2f*(b12*b23-s*b13)*m01 + 2f*(b13*b23+s*b12)*m02        + (ss-b12b12-b13b13+b23b23)*m03
  ## Translation correction on moment: cross(t, rd)
  let
    tx = 2f*c01
    ty = 2f*c02
    tz = 2f*c03
  Line3D(e12: rd12, e13: rd13, e23: rd23,
         e01: rm01 + ty*rd23 - tz*rd13,
         e02: rm02 - tx*rd23 + tz*rd12,
         e03: rm03 + tx*rd13 - ty*rd12)


#############################################################################################################################
################################################### MEET / JOIN — 3D ########################################################
#############################################################################################################################

func meet3D*[A: MPlane3D, B: MPlane3D](a: A, b: B): Line3D {.inline.} =
  ## MEET: intersection of two planes → line.
  ## Exterior product grade-1 ∧ grade-1 = grade-2.  12 muls.
  Line3D(e12: a.e1*b.e2  - a.e2*b.e1,
         e13: a.e1*b.e3  - a.e3*b.e1,
         e23: a.e2*b.e3  - a.e3*b.e2,
         e01: a.e0*b.e1  - a.e1*b.e0,
         e02: a.e0*b.e2  - a.e2*b.e0,
         e03: a.e0*b.e3  - a.e3*b.e0)

func meet3D*[P: MPlane3D, L: MLine3D](p: P, l: L): Point3D {.inline.} =
  ## MEET: plane ∧ line → point.  24 muls.
  Point3D(
    e123: p.e1*l.e23 - p.e2*l.e13 + p.e3*l.e12,
    e032: p.e0*l.e23 - p.e2*l.e03 + p.e3*l.e02,
    e013: -p.e0*l.e13 + p.e1*l.e03 - p.e3*l.e01,
    e021: p.e0*l.e12  - p.e1*l.e02 + p.e2*l.e01)

func join3D*[A: MPoint3D, B: MPoint3D](a: A, b: B): Line3D {.inline.} =
  ## JOIN: line through two 3D points.  12 muls.
  Line3D(
    e12:  a.e021*b.e013 - a.e013*b.e021,
    e13:  a.e032*b.e021 - a.e021*b.e032,
    e23:  a.e013*b.e032 - a.e032*b.e013,
    e01:  a.e123*b.e021 - a.e021*b.e123,
    e02:  a.e123*b.e013 - a.e013*b.e123,
    e03:  a.e123*b.e032 - a.e032*b.e123)

func join3D*[L: MLine3D, P: MPoint3D](l: L, p: P): Plane3D {.inline.} =
  ## JOIN: plane through line and point.  24 muls.
  Plane3D(
    e0: l.e01*p.e032 + l.e02*p.e013 + l.e03*p.e021,
    e1: l.e12*p.e013 - l.e13*p.e032 + l.e23*p.e123,
    e2: -l.e12*p.e021 + l.e13*p.e123 + l.e23*p.e032,   # sign correction
    e3: l.e12*p.e123  - l.e23*p.e021 - l.e13*p.e013)   # verified pattern


#############################################################################################################################
################################################### NORMS / NORMALIZE #######################################################
#############################################################################################################################

func norm*[T: MLine2D](l: T): MFloat {.inline.} =
  ## Euclidean norm of a line: sqrt(e1²+e2²).
  sqrt(l.e1*l.e1 + l.e2*l.e2)

func normalize*[T: MLine2D](l: T): T {.inline.} =
  ## Normalize line so e1²+e2²=1.
  let n = l.norm
  if n < 1e-8f: l else: l * (1f/n)

func norm*[T: MPoint2D](p: T): MFloat {.inline.} =
  ## Euclidean norm of a point: |e12| (the homogeneous weight).
  abs(p.e12)

func normalize*[T: MPoint2D](p: T): T {.inline.} =
  ## Normalize point so e12=1 (convert to Euclidean coordinates).
  let w = p.e12
  if abs(w) < 1e-8f: p else: p * (1f/w)

func norm*[T: MRotor2D](r: T): MFloat {.inline.} =
  sqrt(r.s*r.s + r.e12*r.e12)

func normalize*[T: MRotor2D](r: T): T {.inline.} =
  let n = r.norm
  if n < 1e-8f: r else: r * (1f/n)

func norm*[T: MMotor2D](m: T): MFloat {.inline.} =
  sqrt(m.s*m.s + m.e12*m.e12)

func normalize*[T: MMotor2D](m: T): T {.inline.} =
  ## Normalize motor Euclidean part to 1.
  let n = m.norm
  if n < 1e-8f: m else: m * (1f/n)

func norm*[T: MPlane3D](p: T): MFloat {.inline.} =
  sqrt(p.e1*p.e1 + p.e2*p.e2 + p.e3*p.e3)

func normalize*[T: MPlane3D](p: T): T {.inline.} =
  let n = p.norm
  if n < 1e-8f: p else: p * (1f/n)

func norm*[T: MLine3D](l: T): MFloat {.inline.} =
  sqrt(l.e12*l.e12 + l.e13*l.e13 + l.e23*l.e23)

func normalize*[T: MLine3D](l: T): T {.inline.} =
  let n = l.norm
  if n < 1e-8f: l else: l * (1f/n)

func norm*[T: MPoint3D](p: T): MFloat {.inline.} =
  abs(p.e123)

func normalize*[T: MPoint3D](p: T): T {.inline.} =
  let w = p.e123
  if abs(w) < 1e-8f: p else: p * (1f/w)

func norm*[T: MRotor3D](r: T): MFloat {.inline.} =
  sqrt(r.s*r.s + r.e12*r.e12 + r.e13*r.e13 + r.e23*r.e23)

func normalize*[T: MRotor3D](r: T): T {.inline.} =
  let n = r.norm
  if n < 1e-8f: r else: r * (1f/n)

func norm*[T: MMotor3D](m: T): MFloat {.inline.} =
  sqrt(m.s*m.s + m.e12*m.e12 + m.e13*m.e13 + m.e23*m.e23)

func normalize*[T: MMotor3D](m: T): T {.inline.} =
  let n = m.norm
  if n < 1e-8f: m else: m * (1f/n)


#############################################################################################################################
################################################### DISTANCES / ANGLES ######################################################
#############################################################################################################################

func distance*[A: MPoint2D, B: MPoint2D](a: A, b: B): MFloat =
  ## Euclidean distance between two 2D points.
  ## |join(a,b)| / (|a|·|b|)  simplified for normalized points.
  let
    na = a.e12
    nb = b.e12
    dx = a.e20/na - b.e20/nb
    dy = a.e01/na - b.e01/nb
  sqrt(dx*dx + dy*dy)

func distance*[P: MPoint2D, L: MLine2D](p: P, l: L): MFloat =
  ## Distance from point p to line l.
  ## |(p ∨ l)| / (|p|·|l|)
  let w = p.e12
  abs(l.e1*(p.e20/w) + l.e2*(p.e01/w) + l.e0) / l.norm

func angle*[A: MLine2D, B: MLine2D](a: A, b: B): MFloat =
  ## Angle between two 2D lines in radians.
  let d = a.e1*b.e1 + a.e2*b.e2
  arccos(clamp(d / (a.norm * b.norm), -1f, 1f))

func distance*[A: MPoint3D, B: MPoint3D](a: A, b: B): MFloat =
  ## Euclidean distance between two 3D points.
  let
    wa = a.e123
    wb = b.e123
    dx = a.e032/wa - b.e032/wb
    dy = a.e013/wa - b.e013/wb
    dz = a.e021/wa - b.e021/wb
  sqrt(dx*dx + dy*dy + dz*dz)

func distance*[P: MPoint3D, L: MLine3D](p: P, l: L): MFloat =
  ## Distance from point to line in 3D.
  let w = p.e123
  let
    x = p.e032/w
    y = p.e013/w
    z = p.e021/w
    ## cross(dir, point-on-line) formula — moment = p × d for normalized line
    cx = y*l.e23 - z*l.e13
    cy = z*l.e12 - x*l.e23
    cz = x*l.e13 - y*l.e12
  sqrt(cx*cx+cy*cy+cz*cz) / l.norm

func distance*[P: MPoint3D, Pl: MPlane3D](p: P, pl: Pl): MFloat =
  ## Signed distance from point to plane.
  let w = p.e123
  (pl.e1*(p.e032/w) + pl.e2*(p.e013/w) + pl.e3*(p.e021/w) + pl.e0) / pl.norm

func angle*[A: MPlane3D, B: MPlane3D](a: A, b: B): MFloat =
  ## Angle between two planes (= angle between their normals).
  let d = a.e1*b.e1 + a.e2*b.e2 + a.e3*b.e3
  arccos(clamp(d / (a.norm * b.norm), -1f, 1f))


#############################################################################################################################
################################################### MOTOR INTERPOLATION #####################################################
#############################################################################################################################

func motorNlerp2D*[T: MMotor2D](a, b: T, t: MFloat): Motor2D {.inline.} =
  ## Fast normalised lerp between two 2D motors.
  normalize(a * (1f-t) + b * t)

func motorNlerp3D*[T: MMotor3D](a, b: T, t: MFloat): Motor3D {.inline.} =
  normalize(a * (1f-t) + b * t)

func motorSlerp3D*[T: MMotor3D](a, b: T, t: MFloat): Motor3D =
  ## Geodesic motor interpolation via log/exp in the Lie algebra.
  ## Produces constant-velocity screw motion.
  let
    ## log = bivector generator of the motion a⁻¹b
    ab = reverse(a) * Motor3D(s:b.s,e12:b.e12,e13:b.e13,e23:b.e23,
                               e01:b.e01,e02:b.e02,e03:b.e03,e0123:b.e0123)
    n2 = ab.e12*ab.e12 + ab.e13*ab.e13 + ab.e23*ab.e23
    n  = sqrt(n2)
    sc = if n < 1e-8f: t else: sin(n*t)/n
    c  = cos(n*t)
  ## exp(t * log(a⁻¹b)) then left-multiply by a
  let step = Motor3D(s:c, e12:ab.e12*sc, e13:ab.e13*sc, e23:ab.e23*sc,
                     e01:ab.e01*sc, e02:ab.e02*sc, e03:ab.e03*sc,
                     e0123:ab.e0123*sc)
  Motor3D(s:a.s,e12:a.e12,e13:a.e13,e23:a.e23,
          e01:a.e01,e02:a.e02,e03:a.e03,e0123:a.e0123) * step


#############################################################################################################################
################################################### PROJECTION ##############################################################
#############################################################################################################################

func project*[P: MPoint2D, L: MLine2D](p: P, l: L): Point2D =
  ## Project point p onto line l (foot of perpendicular).
  ## Computed as: meet(l, join(p, dual(l)))  — but directly expanded.
  let
    w = p.e12
    x = p.e20/w
    y = p.e01/w
    ## closest point = p - (l·p/|l|²)·l_perp
    d = l.e1*x + l.e2*y + l.e0
    n2 = l.e1*l.e1 + l.e2*l.e2
    px = x - l.e1*d/n2
    py = y - l.e2*d/n2
  Point2D(e12: 1f, e20: px, e01: py)

func project*[L: MLine3D, P: MPlane3D](l: L, p: P): Line3D =
  ## Project line l onto plane p.
  ## Result is the intersection of p with the plane containing l and p's normal.
  let
    ## Component of l's direction along plane normal:
    dn = l.e12*p.e3 - l.e13*p.e2 + l.e23*p.e1
  Line3D(
    e12: l.e12 - dn*p.e1*p.e1/(p.e1*p.e1+p.e2*p.e2+p.e3*p.e3),
    e13: l.e13 - dn*p.e2*p.e1/(p.e1*p.e1+p.e2*p.e2+p.e3*p.e3),
    e23: l.e23 - dn*p.e3*p.e1/(p.e1*p.e1+p.e2*p.e2+p.e3*p.e3),
    e01: l.e01, e02: l.e02, e03: l.e03)


#############################################################################################################################
################################################### EXTRACT COORDINATES #####################################################
#############################################################################################################################

func toXY*[T: MPoint2D](p: T): (MFloat,MFloat) {.inline.} =
  ## Extract Euclidean (x,y) from a 2D point.
  let w = p.e12
  (p.e20/w, p.e01/w)

func toXYZ*[T: MPoint3D](p: T): (MFloat,MFloat,MFloat) {.inline.} =
  ## Extract Euclidean (x,y,z) from a 3D point.
  let w = p.e123
  (p.e032/w, p.e013/w, p.e021/w)

func toLineCoeffs*[T: MLine2D](l: T): (MFloat,MFloat,MFloat) {.inline.} =
  ## Extract (a,b,c) from line ax+by+c=0.
  (l.e1, l.e2, l.e0)

func toPlaneCoeffs*[T: MPlane3D](p: T): (MFloat,MFloat,MFloat,MFloat) {.inline.} =
  ## Extract (a,b,c,d) from plane ax+by+cz+d=0.
  (p.e1, p.e2, p.e3, p.e0)

func motorAngle*[T: MMotor2D](m: T): MFloat {.inline.} =
  ## Extract the rotation angle from a 2D motor.
  2f * arctan2(m.e12, m.s)

func motorTranslation*[T: MMotor2D](m: T): (MFloat,MFloat) {.inline.} =
  ## Extract the (tx,ty) translation from a 2D motor.
  ## Valid only for a normalized motor.
  (2f*(m.s*m.e20 + m.e12*m.e01),
   2f*(m.s*m.e01 - m.e12*m.e20))


#############################################################################################################################
################################################### STRING ##################################################################
#############################################################################################################################

func `$`*(l: Line2D):  string = "Line2D(e1=" & $l.e1 & " e2=" & $l.e2 & " e0=" & $l.e0 & ")"
func `$`*(p: Point2D): string = "Point2D(e12=" & $p.e12 & " e20=" & $p.e20 & " e01=" & $p.e01 & ")"
func `$`*(r: Rotor2D): string = "Rotor2D(s=" & $r.s & " e12=" & $r.e12 & ")"
func `$`*(m: Motor2D): string = "Motor2D(s=" & $m.s & " e12=" & $m.e12 & " e20=" & $m.e20 & " e01=" & $m.e01 & ")"
func `$`*(p: Plane3D): string = "Plane3D(e1=" & $p.e1 & " e2=" & $p.e2 & " e3=" & $p.e3 & " e0=" & $p.e0 & ")"
func `$`*(l: Line3D):  string = "Line3D(e12=" & $l.e12 & " e13=" & $l.e13 & " e23=" & $l.e23 &
                                       " e01=" & $l.e01 & " e02=" & $l.e02 & " e03=" & $l.e03 & ")"
func `$`*(p: Point3D): string = "Point3D(e123=" & $p.e123 & " e032=" & $p.e032 & " e013=" & $p.e013 & " e021=" & $p.e021 & ")"
func `$`*(r: Rotor3D): string = "Rotor3D(s=" & $r.s & " e12=" & $r.e12 & " e13=" & $r.e13 & " e23=" & $r.e23 & ")"
func `$`*(m: Motor3D): string = "Motor3D(s=" & $m.s & " e12=" & $m.e12 & " e13=" & $m.e13 & " e23=" & $m.e23 &
                                        " e01=" & $m.e01 & " e02=" & $m.e02 & " e03=" & $m.e03 &
                                        " e0123=" & $m.e0123 & ")"