#############################################################################################################################
################################################## SPHERE / CIRCLE ##########################################################
#############################################################################################################################
##
## Sphere2D — circle in 2D: center with (x,y) and radius.
## Sphere3D — sphere in 3D: center with (x,y,z) and radius.
##
## The `not compiles(s.center.z)` guard on Sphere2D ensures that a 3D sphere
## never accidentally matches the 2D concept — same mutual-exclusion trick
## used in LA.nim for Vec2/Vec3.
##
## Any external struct with matching fields works automatically:
##   type MyCircle = object
##     center: MyVec2   # any type with x,y : float32
##     radius: float32
##   # → immediately satisfies Sphere2D, all ops available.
##

type
  Sphere2D* = concept s
    ## Any type whose center has (x,y) : MFloat but NOT z,
    ## and whose radius is MFloat.
    s.center.x is MFloat
    s.center.y is MFloat
    not compiles(s.center.z)  ## Excludes Sphere3D — same guard as Vec2 vs Vec3.
    s.radius   is MFloat

  Sphere3D* = concept s
    ## Any type whose center has (x,y,z) : MFloat and whose radius is MFloat.
    s.center.x is MFloat
    s.center.y is MFloat
    s.center.z is MFloat
    s.radius   is MFloat

#############################################################################################################################
################################################## BASIC PROPERTIES #########################################################
#############################################################################################################################

# ───────────────────────────────────────────────────────────────── Sphere2D ──

func area*[S: Sphere2D](s: S): MFloat {.inline.} =
  ## Area of the circle: π·r².
  PI.MFloat * s.radius * s.radius

func circumference*[S: Sphere2D](s: S): MFloat {.inline.} =
  ## Circumference (perimeter) of the circle: 2π·r.
  2f * PI.MFloat * s.radius

func diameter*[S: Sphere2D](s: S): MFloat {.inline.} =
  ## Diameter of the circle: 2r.
  s.radius * 2f

func radiusSq*[S: Sphere2D](s: S): MFloat {.inline.} =
  ## Squared radius — avoids a sqrt in distance comparisons.
  s.radius * s.radius

# ───────────────────────────────────────────────────────────────── Sphere3D ──

func volume*[S: Sphere3D](s: S): MFloat {.inline.} =
  ## Volume of the sphere: (4/3)·π·r³.
  (4f / 3f) * PI.MFloat * s.radius * s.radius * s.radius

func surfaceArea*[S: Sphere3D](s: S): MFloat {.inline.} =
  ## Surface area of the sphere: 4·π·r².
  4f * PI.MFloat * s.radius * s.radius

func diameter*[S: Sphere3D](s: S): MFloat {.inline.} =
  ## Diameter of the sphere: 2r.
  s.radius * 2f

func radiusSq*[S: Sphere3D](s: S): MFloat {.inline.} =
  ## Squared radius.
  s.radius * s.radius


#############################################################################################################################
################################################## EQUALITY #################################################################
#############################################################################################################################

func `==`*[S: Sphere2D](a, b: S): bool {.inline.} =
  a.center.x == b.center.x and a.center.y == b.center.y and a.radius == b.radius

func `==`*[S: Sphere3D](a, b: S): bool {.inline.} =
  a.center.x == b.center.x and a.center.y == b.center.y and
  a.center.z == b.center.z and a.radius   == b.radius

func approxEq*[S: Sphere2D](a, b: S, eps: MFloat = 1e-6f): bool {.inline.} =
  abs(a.center.x-b.center.x)<=eps and abs(a.center.y-b.center.y)<=eps and
  abs(a.radius-b.radius)<=eps

func approxEq*[S: Sphere3D](a, b: S, eps: MFloat = 1e-6f): bool {.inline.} =
  abs(a.center.x-b.center.x)<=eps and abs(a.center.y-b.center.y)<=eps and
  abs(a.center.z-b.center.z)<=eps and abs(a.radius-b.radius)<=eps


#############################################################################################################################
################################################## CONTAINMENT ##############################################################
#############################################################################################################################

# ───────────────────────────────────────────────────────────────── Sphere2D ──

func contains*[S: Sphere2D](s: S, px, py: MFloat): bool {.inline.} =
  ## True when point (px,py) is strictly inside the circle (not on boundary).
  let dx=px-s.center.x; let dy=py-s.center.y
  dx*dx + dy*dy < s.radiusSq

func isTouching*[S: Sphere2D](s: S, px, py: MFloat): bool {.inline.} =
  ## True when point (px,py) is inside or on the boundary of the circle.
  let dx=px-s.center.x; let dy=py-s.center.y
  dx*dx + dy*dy <= s.radiusSq

func containsPoint*[S: Sphere2D, V](s: S, p: V): bool {.inline.} =
  ## Vec2-friendly overload: true when p is strictly inside the circle.
  contains(s, p.x, p.y)

func isTouchingPoint*[S: Sphere2D, V](s: S, p: V): bool {.inline.} =
  ## Vec2-friendly overload: true when p is inside or on the boundary.
  isTouching(s, p.x, p.y)

func containsSphere*[S: Sphere2D](outer, inner: S): bool {.inline.} =
  ## True when `inner` is fully inside `outer` (boundaries may touch).
  ## A sphere contains another when dist(centers) + inner.r <= outer.r.
  let dx=inner.center.x-outer.center.x; let dy=inner.center.y-outer.center.y
  let dist = sqrt(dx*dx+dy*dy)
  dist + inner.radius <= outer.radius

# ───────────────────────────────────────────────────────────────── Sphere3D ──

func contains*[S: Sphere3D](s: S, px, py, pz: MFloat): bool {.inline.} =
  ## True when point (px,py,pz) is strictly inside the sphere.
  let dx=px-s.center.x; let dy=py-s.center.y; let dz=pz-s.center.z
  dx*dx + dy*dy + dz*dz < s.radiusSq

func isTouching*[S: Sphere3D](s: S, px, py, pz: MFloat): bool {.inline.} =
  ## True when point is inside or on the surface of the sphere.
  let dx=px-s.center.x; let dy=py-s.center.y; let dz=pz-s.center.z
  dx*dx + dy*dy + dz*dz <= s.radiusSq

func containsPoint*[S: Sphere3D, V](s: S, p: V): bool {.inline.} =
  ## Vec3-friendly overload.
  contains(s, p.x, p.y, p.z)

func isTouchingPoint*[S: Sphere3D, V](s: S, p: V): bool {.inline.} =
  isTouching(s, p.x, p.y, p.z)

func containsSphere*[S: Sphere3D](outer, inner: S): bool {.inline.} =
  ## True when `inner` is fully inside `outer`.
  let dx=inner.center.x-outer.center.x
  let dy=inner.center.y-outer.center.y
  let dz=inner.center.z-outer.center.z
  sqrt(dx*dx+dy*dy+dz*dz) + inner.radius <= outer.radius


#############################################################################################################################
################################################## OVERLAP / INTERSECTION ###################################################
#############################################################################################################################

# ───────────────────────────────────────────────────────────────── Sphere2D ──

func overlaps*[S: Sphere2D](a, b: S): bool {.inline.} =
  ## True when two circles share any area (touching boundaries count).
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y
  let sumR = a.radius+b.radius
  dx*dx + dy*dy <= sumR*sumR

func overlapsExclusive*[S: Sphere2D](a, b: S): bool {.inline.} =
  ## True when circles overlap but do NOT merely touch at a single point.
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y
  let sumR = a.radius+b.radius
  dx*dx + dy*dy < sumR*sumR

func overlapDepth*[S: Sphere2D](a, b: S): MFloat {.inline.} =
  ## How deeply two circles overlap (positive = overlap, negative = gap).
  ## Useful for collision resolution / separation vectors.
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y
  (a.radius+b.radius) - sqrt(dx*dx+dy*dy)

# ───────────────────────────────────────────────────────────────── Sphere3D ──

func overlaps*[S: Sphere3D](a, b: S): bool {.inline.} =
  ## True when two spheres share any volume (touching surfaces count).
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y; let dz=a.center.z-b.center.z
  let sumR=a.radius+b.radius
  dx*dx + dy*dy + dz*dz <= sumR*sumR

func overlapsExclusive*[S: Sphere3D](a, b: S): bool {.inline.} =
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y; let dz=a.center.z-b.center.z
  let sumR=a.radius+b.radius
  dx*dx + dy*dy + dz*dz < sumR*sumR

func overlapDepth*[S: Sphere3D](a, b: S): MFloat {.inline.} =
  ## Penetration depth between two spheres (positive = overlap, negative = gap).
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y; let dz=a.center.z-b.center.z
  (a.radius+b.radius) - sqrt(dx*dx+dy*dy+dz*dz)


#############################################################################################################################
################################################## DISTANCE #################################################################
#############################################################################################################################

# ───────────────────────────────────────────────────────────────── Sphere2D ──

func distanceSqToPoint*[S: Sphere2D](s: S, px, py: MFloat): MFloat {.inline.} =
  ## Squared distance from point to circle CENTER (not surface).
  let dx=px-s.center.x; let dy=py-s.center.y
  dx*dx + dy*dy

func distanceToPoint*[S: Sphere2D](s: S, px, py: MFloat): MFloat {.inline.} =
  ## Distance from point to circle CENTER.
  sqrt(distanceSqToPoint(s, px, py))

func distanceToSurface*[S: Sphere2D](s: S, px, py: MFloat): MFloat {.inline.} =
  ## Signed distance from point to circle SURFACE.
  ## Negative when inside, 0 on the boundary, positive when outside.
  distanceToPoint(s, px, py) - s.radius

func distanceSqToPoint*[S: Sphere2D, V](s: S, p: V): MFloat {.inline.} =
  distanceSqToPoint(s, p.x, p.y)

func distanceToPoint*[S: Sphere2D, V](s: S, p: V): MFloat {.inline.} =
  distanceToPoint(s, p.x, p.y)

func distanceToSurface*[S: Sphere2D, V](s: S, p: V): MFloat {.inline.} =
  distanceToSurface(s, p.x, p.y)

func distanceBetween*[S: Sphere2D](a, b: S): MFloat {.inline.} =
  ## Distance between the surfaces of two circles (negative = overlapping).
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y
  sqrt(dx*dx+dy*dy) - a.radius - b.radius

# ───────────────────────────────────────────────────────────────── Sphere3D ──

func distanceSqToPoint*[S: Sphere3D](s: S, px, py, pz: MFloat): MFloat {.inline.} =
  ## Squared distance from point to sphere CENTER.
  let dx=px-s.center.x; let dy=py-s.center.y; let dz=pz-s.center.z
  dx*dx + dy*dy + dz*dz

func distanceToPoint*[S: Sphere3D](s: S, px, py, pz: MFloat): MFloat {.inline.} =
  sqrt(distanceSqToPoint(s, px, py, pz))

func distanceToSurface*[S: Sphere3D](s: S, px, py, pz: MFloat): MFloat {.inline.} =
  ## Signed distance from point to sphere SURFACE.
  distanceToPoint(s, px, py, pz) - s.radius

func distanceSqToPoint*[S: Sphere3D, V](s: S, p: V): MFloat {.inline.} =
  distanceSqToPoint(s, p.x, p.y, p.z)

func distanceToPoint*[S: Sphere3D, V](s: S, p: V): MFloat {.inline.} =
  distanceToPoint(s, p.x, p.y, p.z)

func distanceToSurface*[S: Sphere3D, V](s: S, p: V): MFloat {.inline.} =
  distanceToSurface(s, p.x, p.y, p.z)

func distanceBetween*[S: Sphere3D](a, b: S): MFloat {.inline.} =
  ## Distance between the surfaces of two spheres (negative = overlapping).
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y; let dz=a.center.z-b.center.z
  sqrt(dx*dx+dy*dy+dz*dz) - a.radius - b.radius


#############################################################################################################################
################################################## CLOSEST POINT ############################################################
#############################################################################################################################

func closestPointOnSurface*[S: Sphere2D](s: S, px, py: MFloat): (MFloat,MFloat) =
  ## Closest point ON the circle boundary to (px,py).
  ## Returns the center itself (projected to surface) if the point IS the center.
  let dx=px-s.center.x; let dy=py-s.center.y
  let d=sqrt(dx*dx+dy*dy)
  if d < 1e-8f:
    (s.center.x+s.radius, s.center.y)   # arbitrary direction when coincident
  else:
    let inv=s.radius/d
    (s.center.x+dx*inv, s.center.y+dy*inv)

func closestPointOnSurface*[S: Sphere2D, V](s: S, p: V): (MFloat,MFloat) {.inline.} =
  closestPointOnSurface(s, p.x, p.y)

func closestPointOnSurface*[S: Sphere3D, V](s: S, p: V): V =
  ## Closest point ON the sphere surface to Vec3-like point p.
  let dx=p.x-s.center.x; let dy=p.y-s.center.y; let dz=p.z-s.center.z
  let d=sqrt(dx*dx+dy*dy+dz*dz)
  if d < 1e-8f:
    V(x:s.center.x+s.radius, y:s.center.y, z:s.center.z)
  else:
    let inv=s.radius/d
    V(x:s.center.x+dx*inv, y:s.center.y+dy*inv, z:s.center.z+dz*inv)

func closestPointClamped*[S: Sphere3D, V](s: S, p: V): V {.inline.} =
  ## Closest point to p that is INSIDE or ON the sphere.
  ## Returns p itself when p is inside.
  let dx=p.x-s.center.x; let dy=p.y-s.center.y; let dz=p.z-s.center.z
  let dSq=dx*dx+dy*dy+dz*dz
  if dSq <= s.radiusSq: p
  else:
    let inv=s.radius/sqrt(dSq)
    V(x:s.center.x+dx*inv, y:s.center.y+dy*inv, z:s.center.z+dz*inv)


#############################################################################################################################
################################################## SET OPERATIONS ###########################################################
#############################################################################################################################

# ───────────────────────────────────────────────────────────────── Sphere2D ──

func translate*[S: Sphere2D](s: S, dx, dy: MFloat): S {.inline.} =
  ## Translate the circle center by (dx, dy).
  type V = typeof(s.center)
  S(center: V(x:s.center.x+dx, y:s.center.y+dy), radius: s.radius)

func translateVec*[S: Sphere2D, V](s: S, d: V): S {.inline.} =
  ## Translate by any Vec2-like delta.
  translate(s, d.x, d.y)

func scale*[S: Sphere2D](s: S, factor: MFloat): S {.inline.} =
  ## Scale the circle radius by factor (center unchanged).
  S(center: s.center, radius: s.radius * factor)

func expandBy*[S: Sphere2D](s: S, amount: MFloat): S {.inline.} =
  ## Grow the circle radius by `amount`.
  S(center: s.center, radius: s.radius + amount)

func shrinkBy*[S: Sphere2D](s: S, amount: MFloat): S {.inline.} =
  ## Shrink the circle radius by `amount` (clamped to 0).
  S(center: s.center, radius: max(0f, s.radius - amount))

func merge*[S: Sphere2D](a, b: S): S =
  ## Smallest circle containing both a and b.
  ## Uses the analytic formula: center on the line between centers,
  ## radius = (dist + ra + rb) / 2.
  let dx=b.center.x-a.center.x; let dy=b.center.y-a.center.y
  let dist=sqrt(dx*dx+dy*dy)
  if dist < 1e-8f:
    # Concentric — just take the larger radius
    if a.radius >= b.radius: a else: b
  elif dist + b.radius <= a.radius:
    a   # b is fully inside a
  elif dist + a.radius <= b.radius:
    b   # a is fully inside b
  else:
    let newR = (dist + a.radius + b.radius) * 0.5f
    let t    = (newR - a.radius) / dist
    type V   = typeof(a.center)
    S(center: V(x:a.center.x+dx*t, y:a.center.y+dy*t), radius: newR)

# ───────────────────────────────────────────────────────────────── Sphere3D ──

func translate*[S: Sphere3D, V](s: S, d: V): S {.inline.} =
  ## Translate the sphere center by Vec3-like delta.
  type Cv = typeof(s.center)
  S(center: Cv(x:s.center.x+d.x, y:s.center.y+d.y, z:s.center.z+d.z),
    radius: s.radius)

func scale*[S: Sphere3D](s: S, factor: MFloat): S {.inline.} =
  ## Scale the sphere radius by factor (center unchanged).
  S(center: s.center, radius: s.radius * factor)

func expandBy*[S: Sphere3D](s: S, amount: MFloat): S {.inline.} =
  ## Grow the sphere radius by `amount`.
  S(center: s.center, radius: s.radius + amount)

func shrinkBy*[S: Sphere3D](s: S, amount: MFloat): S {.inline.} =
  ## Shrink the sphere radius by `amount` (clamped to 0).
  S(center: s.center, radius: max(0f, s.radius - amount))

func merge*[S: Sphere3D](a, b: S): S =
  ## Smallest sphere containing both a and b.
  let dx=b.center.x-a.center.x; let dy=b.center.y-a.center.y; let dz=b.center.z-a.center.z
  let dist=sqrt(dx*dx+dy*dy+dz*dz)
  if dist < 1e-8f:
    if a.radius >= b.radius: a else: b
  elif dist + b.radius <= a.radius: a
  elif dist + a.radius <= b.radius: b
  else:
    let newR = (dist + a.radius + b.radius) * 0.5f
    let t    = (newR - a.radius) / dist
    type Cv  = typeof(a.center)
    S(center: Cv(x:a.center.x+dx*t, y:a.center.y+dy*t, z:a.center.z+dz*t),
      radius: newR)


#############################################################################################################################
################################################## RAY INTERSECTION #########################################################
#############################################################################################################################

type
  SphereHit* = object
    ## Result of a ray-sphere intersection test.
    tMin*, tMax*: MFloat   ## Entry and exit t values along the ray.
    hit*: bool             ## True when the ray intersects the sphere.

func rayIntersect*[S: Sphere2D](
    s:  S,
    ox, oy: MFloat,    ## Ray origin.
    dx, dy: MFloat,    ## Ray direction (need not be normalised).
    tMin: MFloat = 0f,
    tMax: MFloat = 1e30f
  ): SphereHit =
  ## Analytic ray-circle intersection.
  ## Solves |O + t·D - C|² = r² as a quadratic in t.
  let ocx=ox-s.center.x; let ocy=oy-s.center.y
  let a=dx*dx+dy*dy
  let b=2f*(ocx*dx+ocy*dy)
  let c=ocx*ocx+ocy*ocy - s.radiusSq
  let disc=b*b - 4f*a*c
  if disc < 0f:
    return SphereHit(hit: false)
  let sqrtD=sqrt(disc)
  let inv2a=1f/(2f*a)
  let t1=(-b-sqrtD)*inv2a
  let t2=(-b+sqrtD)*inv2a
  let tEnter=max(t1, tMin)
  let tExit =min(t2, tMax)
  SphereHit(tMin:tEnter, tMax:tExit, hit: tEnter<=tExit)

func rayIntersect*[S: Sphere3D](
    s:  S,
    ox, oy, oz: MFloat,   ## Ray origin.
    dx, dy, dz: MFloat,   ## Ray direction (need not be normalised).
    tMin: MFloat = 0f,
    tMax: MFloat = 1e30f
  ): SphereHit =
  ## Analytic ray-sphere intersection.
  let ocx=ox-s.center.x; let ocy=oy-s.center.y; let ocz=oz-s.center.z
  let a=dx*dx+dy*dy+dz*dz
  let b=2f*(ocx*dx+ocy*dy+ocz*dz)
  let c=ocx*ocx+ocy*ocy+ocz*ocz - s.radiusSq
  let disc=b*b - 4f*a*c
  if disc < 0f:
    return SphereHit(hit: false)
  let sqrtD=sqrt(disc)
  let inv2a=1f/(2f*a)
  let t1=(-b-sqrtD)*inv2a
  let t2=(-b+sqrtD)*inv2a
  let tEnter=max(t1,tMin)
  let tExit =min(t2,tMax)
  SphereHit(tMin:tEnter, tMax:tExit, hit: tEnter<=tExit)

func rayIntersectVec*[S: Sphere3D, V](
    s: S, origin, dir: V,
    tMin: MFloat = 0f,
    tMax: MFloat = 1e30f
  ): SphereHit {.inline.} =
  ## Vec3-friendly overload of rayIntersect for Sphere3D.
  rayIntersect(s, origin.x,origin.y,origin.z, dir.x,dir.y,dir.z, tMin, tMax)

func normalAt*[S: Sphere3D, V](s: S, point: V): V {.inline.} =
  ## Outward unit normal at a point on the sphere surface.
  ## `point` should be on or very close to the surface.
  let dx=point.x-s.center.x; let dy=point.y-s.center.y; let dz=point.z-s.center.z
  let inv=1f/sqrt(dx*dx+dy*dy+dz*dz)
  V(x:dx*inv, y:dy*inv, z:dz*inv)

func normalAt*[S: Sphere2D](s: S, px, py: MFloat): (MFloat,MFloat) {.inline.} =
  ## Outward unit normal at a point on the circle boundary.
  let dx=px-s.center.x; let dy=py-s.center.y
  let inv=1f/sqrt(dx*dx+dy*dy)
  (dx*inv, dy*inv)


#############################################################################################################################
################################################## CROSS-SHAPE INTERSECTION #################################################
#############################################################################################################################
## Sphere vs Box — useful for physics broadphase and trigger volumes.
## Box concept is inlined structurally to avoid a hard import dependency.

func sphereVsBox2D*[S: Sphere2D](
    s: S,
    bx1, by1, bx2, by2: MFloat
  ): bool {.inline.} =
  ## True when circle and AABB overlap.
  ## Uses the squared-distance-to-closest-point method (no sqrt needed).
  let cx=clamp(s.center.x, bx1, bx2)
  let cy=clamp(s.center.y, by1, by2)
  let dx=s.center.x-cx; let dy=s.center.y-cy
  dx*dx + dy*dy <= s.radiusSq

func sphereVsBox3D*[S: Sphere3D](
    s: S,
    ox, oy, oz: MFloat,   # Box3D origin (min corner).
    sx, sy, sz: MFloat    # Box3D size.
  ): bool {.inline.} =
  ## True when sphere and AABB overlap.
  let cx=clamp(s.center.x, ox, ox+sx)
  let cy=clamp(s.center.y, oy, oy+sy)
  let cz=clamp(s.center.z, oz, oz+sz)
  let dx=s.center.x-cx; let dy=s.center.y-cy; let dz=s.center.z-cz
  dx*dx + dy*dy + dz*dz <= s.radiusSq


#############################################################################################################################
################################################## COLLISION RESPONSE #######################################################
#############################################################################################################################

type
  CollisionInfo2D* = object
    ## Result of a circle-circle collision query.
    hit*:        bool
    depth*:      MFloat          ## Penetration depth (positive = overlapping).
    normalX*:    MFloat          ## Separation normal pointing from b into a.
    normalY*:    MFloat

  CollisionInfo3D* = object
    hit*:        bool
    depth*:      MFloat
    normalX*:    MFloat
    normalY*:    MFloat
    normalZ*:    MFloat

func collide*[S: Sphere2D](a, b: S): CollisionInfo2D =
  ## Full circle-circle collision: depth and separation normal.
  ## Normal points FROM b TOWARDS a (push a away from b).
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y
  let dist=sqrt(dx*dx+dy*dy)
  let sumR=a.radius+b.radius
  if dist >= sumR:
    return CollisionInfo2D(hit: false)
  if dist < 1e-8f:
    # Perfectly overlapping centers — arbitrary separation direction.
    return CollisionInfo2D(hit:true, depth:sumR, normalX:1f, normalY:0f)
  let inv=1f/dist
  CollisionInfo2D(hit:true, depth:sumR-dist, normalX:dx*inv, normalY:dy*inv)

func collide*[S: Sphere3D](a, b: S): CollisionInfo3D =
  ## Full sphere-sphere collision: depth and separation normal.
  let dx=a.center.x-b.center.x; let dy=a.center.y-b.center.y; let dz=a.center.z-b.center.z
  let dist=sqrt(dx*dx+dy*dy+dz*dz)
  let sumR=a.radius+b.radius
  if dist >= sumR:
    return CollisionInfo3D(hit: false)
  if dist < 1e-8f:
    return CollisionInfo3D(hit:true, depth:sumR, normalX:1f, normalY:0f, normalZ:0f)
  let inv=1f/dist
  CollisionInfo3D(hit:true, depth:sumR-dist,
    normalX:dx*inv, normalY:dy*inv, normalZ:dz*inv)


#############################################################################################################################
################################################## BOUNDS (→ Box) ###########################################################
#############################################################################################################################

func bounds2D*[S: Sphere2D](s: S): (MFloat,MFloat,MFloat,MFloat) {.inline.} =
  ## Axis-aligned bounding box of the circle as (x1,y1,x2,y2).
  ## Compatible with Box2D concept structs.
  (s.center.x-s.radius, s.center.y-s.radius,
   s.center.x+s.radius, s.center.y+s.radius)

func bounds3DOrigin*[S: Sphere3D](s: S): (MFloat,MFloat,MFloat) {.inline.} =
  ## Min corner of the sphere's AABB.
  (s.center.x-s.radius, s.center.y-s.radius, s.center.z-s.radius)

func bounds3DSize*[S: Sphere3D](s: S): (MFloat,MFloat,MFloat) {.inline.} =
  ## Size of the sphere's AABB (always a cube with side = diameter).
  let d=s.diameter
  (d, d, d)


#############################################################################################################################
################################################## STRING ###################################################################
#############################################################################################################################

func `$`*[S: Sphere2D](s: S): string =
  "Circle(center=(" & $s.center.x & "," & $s.center.y &
  ") r=" & $s.radius & " area=" & $s.area & ")"

func `$`*[S: Sphere3D](s: S): string =
  "Sphere(center=(" & $s.center.x & "," & $s.center.y & "," & $s.center.z &
  ") r=" & $s.radius & " vol=" & $s.volume & ")"