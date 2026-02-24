#############################################################################################################################
################################################## QUATERNIONS ##############################################################
#############################################################################################################################
##
## Quat is simply an alias for the Vec4 concept.
## ANY type with x, y, z, w : MFloat fields works as a quaternion.
## No marker field, no wrapper — zero friction with existing Vec4 types.
##
## Naming convention:
##   When a quaternion operation would collide with a Vec4 operation
##   (dot, length, normalize, +, *, …) the quaternion version is either:
##     - The SAME function  (dot, length, normalize are mathematically identical)
##     - Prefixed with `quat` when the semantics differ (quatMul, quatInverse…)
##

## Quat is just Vec4 — any type with x,y,z,w : MFloat is a valid quaternion.
type Quat* = Vec4

func quatApproxEq*[Q: Quat](a, b: Q, eps: MFloat = 1e-6f): bool {.inline.} =
  ## Approximate equality that accounts for the double-cover q ≡ -q.
  ## Two quaternions represent the SAME rotation if they are equal OR negatives.
  ## (Plain approxEq from LA.nim checks only equality, not the negated form.)
  let same = abs(a.x-b.x)<=eps and abs(a.y-b.y)<=eps and
             abs(a.z-b.z)<=eps and abs(a.w-b.w)<=eps
  let neg  = abs(a.x+b.x)<=eps and abs(a.y+b.y)<=eps and
             abs(a.z+b.z)<=eps and abs(a.w+b.w)<=eps
  same or neg

#############################################################################################################################
################################################## HAMILTON PRODUCT #########################################################
#############################################################################################################################

func quatMul*[Q: Quat](a, b: Q): Q {.inline.} =
  ## Hamilton product — compose two rotations.
  ## a * b applies b's rotation FIRST, then a's (right-to-left, like matrices).
  ## 16 multiplies + 12 adds, fully unrolled.
  Q(x:  a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
    y:  a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
    z:  a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w,
    w:  a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z)

func `*=`*[Q: Quat](a: var Q, b: Q) {.inline.} =
  ## In-place Hamilton product.
  a = quatMul(a, b)


#############################################################################################################################
################################################## CORE OPERATIONS ##########################################################
#############################################################################################################################

func quatConjugate*[Q: Quat](q: Q): Q {.inline.} =
  ## Negate the vector part (x,y,z), keep the scalar (w).
  ## For unit quaternions: conjugate == inverse.
  Q(x: -q.x, y: -q.y, z: -q.z, w: q.w)

func quatInverse*[Q: Quat](q: Q): Q {.inline.} =
  ## General inverse: conjugate / |q|².
  ## For unit quaternions use quatConjugate — it's cheaper.
  let invSq = 1f / (q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w)
  Q(x: -q.x*invSq, y: -q.y*invSq, z: -q.z*invSq, w: q.w*invSq)

func isUnit*[Q: Quat](q: Q, eps: MFloat = 1e-5f): bool {.inline.} =
  ## True when q has unit norm within epsilon.
  abs(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w - 1f) <= eps

func quatIdentity*[Q: Quat](t: typedesc[Q]): Q {.inline.} =
  ## Return the identity quaternion for type Q (no rotation).
  Q(x: 0f, y: 0f, z: 0f, w: 1f)


#############################################################################################################################
################################################## ROTATE VECTOR ############################################################
#############################################################################################################################

func quatRotate*[Q: Quat, V](q: Q, v: V): V {.inline.} =
  ## Rotate vector v by unit quaternion q.
  ## Uses the optimised Rodrigues formula
  let
    tx = 2f * (q.y*v.z - q.z*v.y)
    ty = 2f * (q.z*v.x - q.x*v.z)
    tz = 2f * (q.x*v.y - q.y*v.x)
  V(x: v.x + q.w*tx + (q.y*tz - q.z*ty),
    y: v.y + q.w*ty + (q.z*tx - q.x*tz),
    z: v.z + q.w*tz + (q.x*ty - q.y*tx))

func quatRotateInverse*[Q: Quat, V](q: Q, v: V): V {.inline.} =
  ## Rotate v by the INVERSE of q (world → local space).
  ## Equivalent to rotating by the conjugate for unit quaternions.
  quatRotate(quatConjugate(q), v)


#############################################################################################################################
################################################## CONSTRUCTION #############################################################
#############################################################################################################################

func quatFromAxisAngle*[V, Q: Quat](axis: V, angle: MFloat, t: typedesc[Q]): Q =
  ## Build a unit quaternion from an axis-angle representation.
  ## `axis` must be normalised, `angle` in radians.
  ## `axis` accepts any Vec3-compatible type.
  let half = angle * 0.5f
  let s    = sin(half)
  Q(x: axis.x*s, y: axis.y*s, z: axis.z*s, w: cos(half))

func quatFromEuler*[Q: Quat](pitch, yaw, roll: MFloat, t: typedesc[Q]): Q =
  ## Build from Euler angles in radians — order: Roll(Z) → Pitch(X) → Yaw(Y).
  let
    cp = cos(pitch*0.5f)
    sp = sin(pitch*0.5f)
    cy = cos(yaw  *0.5f)
    sy = sin(yaw  *0.5f)
    cr = cos(roll *0.5f)
    sr = sin(roll *0.5f)
  Q(x: sr*cp*cy - cr*sp*sy,
    y: cr*sp*cy + sr*cp*sy,
    z: cr*cp*sy - sr*sp*cy,
    w: cr*cp*cy + sr*sp*sy)

func quatFromEulerVec*[V, Q: Quat](euler: V, t: typedesc[Q]): Q {.inline.} =
  ## Build from a Vec3-like (pitch=x, yaw=y, roll=z) in radians.
  quatFromEuler[Q](euler.x, euler.y, euler.z, Q)

func quatFromTo*[V, Q: Quat](fromDir, toDir: V, t: typedesc[Q]): Q =
  ## Shortest-arc quaternion rotating fromDir onto toDir.
  ## Both must be normalised. Handles the 180° anti-parallel case safely.
  let d = fromDir.x*toDir.x + fromDir.y*toDir.y + fromDir.z*toDir.z
  if d >= 1f - 1e-6f:
    return Q(x:0f, y:0f, z:0f, w:1f)   # already aligned
  if d <= -1f + 1e-6f:
    # 180° — find an arbitrary perpendicular axis
    var ax = 1f - fromDir.x*fromDir.x
    var ay = -fromDir.x*fromDir.y
    var az = -fromDir.x*fromDir.z
    if ax < 0.01f:
      ax = -fromDir.y*fromDir.x
      ay = 1f - fromDir.y*fromDir.y
      az = -fromDir.y*fromDir.z
    let il = 1f / sqrt(ax*ax + ay*ay + az*az)
    return Q(x: ax*il, y: ay*il, z: az*il, w: 0f)
  let
    cx  = fromDir.y*toDir.z - fromDir.z*toDir.y
    cy  = fromDir.z*toDir.x - fromDir.x*toDir.z
    cz  = fromDir.x*toDir.y - fromDir.y*toDir.x
    s   = sqrt((1f+d)*2f)
    ios  = 1f / s
    raw = Q(x: cx*ios, y: cy*ios, z: cz*ios, w: s*0.5f)
  # normalize
  let l = sqrt(raw.x*raw.x+raw.y*raw.y+raw.z*raw.z+raw.w*raw.w)
  Q(x:raw.x/l, y:raw.y/l, z:raw.z/l, w:raw.w/l)

func quatLookAt*[V, Q: Quat](forward, up: V, t: typedesc[Q]): Q =
  ## Look-at quaternion: orients -Z towards `forward`, `up` as world hint.
  ## Both must be normalised. Uses Shepperd's method (numerically stable).
  let
    fx = -forward.x
    fy = -forward.y
    fz = -forward.z
    rx = up.y*fz - up.z*fy
    ry = up.z*fx - up.x*fz
    rz = up.x*fy - up.y*fx
    rl = 1f / sqrt(rx*rx+ry*ry+rz*rz)
    r0 = rx*rl
    r1 = ry*rl
    r2 = rz*rl
    u0 = fy*r2-fz*r1
    u1 = fz*r0-fx*r2
    u2 = fx*r1-fy*r0
    tr = r0+u1+fz
  if tr > 0f:
    let s = 0.5f/sqrt(tr+1f)
    return Q(x:(u2-fy)*s, y:(fx-r2)*s, z:(r1-u0)*s, w:0.25f/s)
  elif r0>u1 and r0>fz:
    let s = 2f*sqrt(1f+r0-u1-fz)
    return Q(x:0.25f*s, y:(r1+u0)/s, z:(fx+r2)/s, w:(u2-fy)/s)
  elif u1>fz:
    let s = 2f*sqrt(1f+u1-r0-fz)
    return Q(x:(r1+u0)/s, y:0.25f*s, z:(u2+fy)/s, w:(fx-r2)/s)
  else:
    let s = 2f*sqrt(1f+fz-r0-u1)
    return Q(x:(fx+r2)/s, y:(u2+fy)/s, z:0.25f*s, w:(r1-u0)/s)

func quatFromMat3Array*[Q: Quat](m: array[9, MFloat], t: typedesc[Q]): Q =
  ## Reconstruct unit quaternion from a column-major 3×3 rotation matrix.
  ## Shepperd's method — numerically stable in all cases.
  let tr = m[0]+m[4]+m[8]
  if tr > 0f:
    let s = 0.5f/sqrt(tr+1f)
    return Q(x:(m[5]-m[7])*s, y:(m[6]-m[2])*s, z:(m[1]-m[3])*s, w:0.25f/s)
  elif m[0]>m[4] and m[0]>m[8]:
    let s = 2f*sqrt(1f+m[0]-m[4]-m[8])
    return Q(x:0.25f*s, y:(m[3]+m[1])/s, z:(m[6]+m[2])/s, w:(m[5]-m[7])/s)
  elif m[4]>m[8]:
    let s = 2f*sqrt(1f+m[4]-m[0]-m[8])
    return Q(x:(m[3]+m[1])/s, y:0.25f*s, z:(m[7]+m[5])/s, w:(m[6]-m[2])/s)
  else:
    let s = 2f*sqrt(1f+m[8]-m[0]-m[4])
    return Q(x:(m[6]+m[2])/s, y:(m[7]+m[5])/s, z:0.25f*s, w:(m[1]-m[3])/s)


#############################################################################################################################
################################################## DECOMPOSITION ############################################################
#############################################################################################################################

func quatToAxisAngle*[Q: Quat](q: Q): tuple[ax,ay,az, angle: MFloat] =
  ## Decompose a unit quaternion into axis (ax,ay,az) + angle (radians).
  ## Returns plain floats so the axis works with any Vec3 type downstream.
  let sinHalf = sqrt(max(0f, 1f - q.w*q.w))
  if sinHalf < 1e-8f:
    return (1f, 0f, 0f, 0f)
  let inv = 1f / sinHalf
  (q.x*inv, q.y*inv, q.z*inv, 2f*arccos(clamp(q.w,-1f,1f)))

func quatToEuler*[Q: Quat](q: Q): tuple[pitch, yaw, roll: MFloat] =
  ## Decompose to Euler angles in radians (XYZ order).
  ## Pitch=X, Yaw=Y, Roll=Z. Gimbal lock at pitch=±90° → yaw forced to 0.
  let
    sinP = 2f*(q.w*q.x + q.y*q.z)
    cosP = 1f - 2f*(q.x*q.x + q.y*q.y)
    sinY = 2f*(q.w*q.y - q.z*q.x)
    sinR = 2f*(q.w*q.z + q.x*q.y)
    cosR = 1f - 2f*(q.y*q.y + q.z*q.z)
  (pitch: arctan2(sinP, cosP),
   yaw:   if abs(sinY)>=1f: copySign(PI*0.5f,sinY) else: arcsin(clamp(sinY,-1f,1f)),
   roll:  arctan2(sinR, cosR))


#############################################################################################################################
################################################## MATRIX CONVERSION ########################################################
#############################################################################################################################

func quatToMat3Array*[Q: Quat](q: Q): array[9, MFloat] {.inline.} =
  ## Convert unit quaternion to column-major 3×3 rotation matrix array.
  ## Use as: Mat3(m: q.quatToMat3Array())
  let
    x2=q.x+q.x
    y2=q.y+q.y
    z2=q.z+q.z
    xx=q.x*x2
    xy=q.x*y2
    xz=q.x*z2
    yy=q.y*y2
    yz=q.y*z2
    zz=q.z*z2
    wx=q.w*x2
    wy=q.w*y2
    wz=q.w*z2
  [1f-(yy+zz), xy+wz,      xz-wy,
   xy-wz,      1f-(xx+zz), yz+wx,
   xz+wy,      yz-wx,      1f-(xx+yy)]

func quatToMat4Array*[Q: Quat](q: Q): array[16, MFloat] {.inline.} =
  ## Convert unit quaternion to column-major 4×4 rotation matrix array.
  ## Use as: Mat4(m: q.quatToMat4Array())
  let
    x2=q.x+q.x
    y2=q.y+q.y
    z2=q.z+q.z
    xx=q.x*x2
    xy=q.x*y2
    xz=q.x*z2
    yy=q.y*y2
    yz=q.y*z2
    zz=q.z*z2
    wx=q.w*x2
    wy=q.w*y2
    wz=q.w*z2
  [1f-(yy+zz), xy+wz,      xz-wy,      0f,
   xy-wz,      1f-(xx+zz), yz+wx,      0f,
   xz+wy,      yz-wx,      1f-(xx+yy), 0f,
   0f,         0f,         0f,         1f]


#############################################################################################################################
################################################## INTERPOLATION ############################################################
#############################################################################################################################

func quatNlerp*[Q: Quat](a, b: Q, t: MFloat): Q {.inline.} =
  ## Normalised linear interpolation — fast, good for small angles.
  ## Handles double-cover (negates b if dot < 0 to take the short arc).
  ## NOT constant angular velocity — use quatSlerp when that matters.
  let d   = a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w
  let sgn = if d < 0f: -1f else: 1f
  let omT = 1f - t
  let rx  = a.x*omT + b.x*sgn*t
  let ry  = a.y*omT + b.y*sgn*t
  let rz  = a.z*omT + b.z*sgn*t
  let rw  = a.w*omT + b.w*sgn*t
  let inv = 1f / sqrt(rx*rx+ry*ry+rz*rz+rw*rw)
  Q(x:rx*inv, y:ry*inv, z:rz*inv, w:rw*inv)

func quatSlerp*[Q: Quat](a, b: Q, t: MFloat): Q =
  ## Spherical linear interpolation — constant angular velocity.
  ## Handles double-cover and falls back to nlerp for nearly-identical quats.
  var d  = a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w
  var bx = b.x; var by = b.y; var bz = b.z; var bw = b.w
  if d < 0f:                     # take the short arc
    bx= -bx; by= -by; bz= -bz; bw= -bw; d = -d
  if d > 0.9995f:                # nearly identical — nlerp fallback
    return quatNlerp(a, Q(x:bx,y:by,z:bz,w:bw), t)
  let
    angle = arccos(clamp(d,-1f,1f))
    sinA  = sin(angle)
    wa    = sin((1f-t)*angle)/sinA
    wb    = sin(t*angle)/sinA
  Q(x:a.x*wa+bx*wb, y:a.y*wa+by*wb, z:a.z*wa+bz*wb, w:a.w*wa+bw*wb)

func quatSquad*[Q: Quat](q0, q1, s1, s2: Q, t: MFloat): Q {.inline.} =
  ## Spherical cubic (SQUAD) interpolation — C¹-continuous rotation spline.
  ## q0→q1 is the segment, s1/s2 are inner control points from quatSquadTangent.
  quatSlerp(quatSlerp(q0,s2,t), quatSlerp(q1,s1,t), 2f*t*(1f-t))

func quatSquadTangent*[Q: Quat](prev, curr, next: Q): Q =
  ## Compute the inner SQUAD control point for `curr` given its neighbours.
  ## Call once per animation keyframe to set up a smooth spline.
  let ic = quatConjugate(curr)
  let qa = quatMul(ic, prev)
  let qb = quatMul(ic, next)
  # log of unit quaternion: log(q) = (arccos(w)/|v|) * v
  func logQ(x,y,z,w: MFloat): (MFloat,MFloat,MFloat) =
    let sinH = sqrt(x*x+y*y+z*z)
    if sinH < 1e-8f: return (0f,0f,0f)
    let sc = arccos(clamp(w,-1f,1f)) / sinH
    (x*sc, y*sc, z*sc)
  # exp of pure quaternion: exp(v) = (cos|v|, sin|v|/|v| * v)
  func expQ(x,y,z: MFloat): Q =
    let n = sqrt(x*x+y*y+z*z)
    if n < 1e-8f: return Q(x:0f,y:0f,z:0f,w:1f)
    let s = sin(n)/n
    Q(x:x*s, y:y*s, z:z*s, w:cos(n))
  let (lax,lay,laz) = logQ(qa.x,qa.y,qa.z,qa.w)
  let (lbx,lby,lbz) = logQ(qb.x,qb.y,qb.z,qb.w)
  let tang = expQ(-0.25f*(lax+lbx), -0.25f*(lay+lby), -0.25f*(laz+lbz))
  quatMul(curr, tang)

func quatMoveTowards*[Q: Quat](current, target: Q, maxDeltaRad: MFloat): Q =
  ## Rotate current towards target by at most maxDeltaRad radians per call.
  ## Will not overshoot. Useful for turret/character smooth turning.
  let (_, _, _, angle) = quatToAxisAngle(quatMul(quatConjugate(current), target))
  if angle <= maxDeltaRad or angle < 1e-8f: target
  else: quatSlerp(current, target, maxDeltaRad / angle)


#############################################################################################################################
################################################## ANGULAR VELOCITY #########################################################
#############################################################################################################################

func quatAngularVelocity*[Q: Quat, V](q: Q, omega: V): Q {.inline.} =
  ## Quaternion derivative dq/dt from angular velocity omega (rad/s).
  ## Integrate: q_new = normalize(q + quatAngularVelocity(q, omega) * dt)
  ## omega accepts any Vec3-compatible type (x, y, z : MFloat).
  let 
    ox=omega.x*0.5f
    oy=omega.y*0.5f
    oz=omega.z*0.5f
  Q(x:  q.w*ox + q.y*oz - q.z*oy,
    y:  q.w*oy - q.x*oz + q.z*ox,
    z:  q.w*oz + q.x*oy - q.y*ox,
    w: -q.x*ox - q.y*oy - q.z*oz)

func quatIntegrate*[Q: Quat, V](q: Q, omega: V, dt: MFloat): Q {.inline.} =
  ## Euler-integrate angular velocity over dt seconds.
  ## Sufficient for short timesteps (physics sub-steps).
  ## Result is automatically normalised.
  let dq = quatAngularVelocity(q, omega)
  let rx = q.x + dq.x*dt; let ry = q.y + dq.y*dt
  let rz = q.z + dq.z*dt; let rw = q.w + dq.w*dt
  let inv = 1f / sqrt(rx*rx+ry*ry+rz*rz+rw*rw)
  Q(x:rx*inv, y:ry*inv, z:rz*inv, w:rw*inv)


#############################################################################################################################
################################################## STRING ###################################################################
#############################################################################################################################

func quatStr*[Q: Quat](q: Q): string =
  ## Pretty-print as "Quat(x, y, z | w)".
  ## Named quatStr to avoid collision with Vec4's `$`.
  "Quat(" & $q.x & ", " & $q.y & ", " & $q.z & " | " & $q.w & ")"