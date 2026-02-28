#############################################################################################################################
################################################### BOX SHAPE ###############################################################
#############################################################################################################################
##
## Axis-Aligned Bounding Boxes for 2D and 3D game development.
##
## Two concepts are used as the structural interface:
##
##   Box2D — any type with x1,y1,x2,y2 : MFloat
##            Compatible with SDL_FRect and similar structs that store
##            two corner points directly.
##
##   Box3D — any type with origin : Vec3  (min corner)
##                         size   : Vec3  (extent, always positive for valid box)
##
## Concrete types BoxF2 and BoxF3 are provided ready to use.
## Any external struct matching the field layout works automatically.
##

import math

# ── assumed available from LA.nim / matrix.nim ────────────────────────────────
# MFloat, Vec2/Vec3 concepts and their concrete types, dot, length, etc.
# If this file is compiled standalone, define minimal stubs here.

type
  Box2D* = concept b
    ## Any type with two corner points stored as x1,y1 (min) and x2,y2 (max).
    ## Deliberately compatible with SDL_FRect-style structs.
    compiles(b.x1)
    compiles(b.y1)
    compiles(b.x2)
    compiles(b.y2)

  Box2Df* = concept b
    ## Any type with two corner points stored as x1,y1 (min) and x2,y2 (max).
    ## Deliberately compatible with SDL_FRect-style structs.
    b.x1 is MFloat
    b.y1 is MFloat
    b.x2 is MFloat
    b.y2 is MFloat

  Box3D* = concept b
    ## Any type with an origin (min corner) and size (extent) stored as Vec3-likes.
    ## origin + size = max corner.
    b.origin.x is MFloat
    b.origin.y is MFloat
    b.origin.z is MFloat
    b.size.x   is MFloat
    b.size.y   is MFloat
    b.size.z   is MFloat

#############################################################################################################################
################################################## MIN / MAX / SIZE ACCESS ##################################################
#############################################################################################################################

# ─────────────────────────────────────────────────────────────────── Box2D ───

func minX*[B: Box2D](b: B): MFloat {.inline.} = b.x1
  ## Left edge (inclusive min X).
func minY*[B: Box2D](b: B): MFloat {.inline.} = b.y1
  ## Bottom edge (inclusive min Y).
func maxX*[B: Box2D](b: B): MFloat {.inline.} = b.x2
  ## Right edge (inclusive max X).
func maxY*[B: Box2D](b: B): MFloat {.inline.} = b.y2
  ## Top edge (inclusive max Y).

func width*[B: Box2D](b: B): MFloat {.inline.} =
  ## Width of the box (x2 - x1).
  b.x2 - b.x1

func height*[B: Box2D](b: B): MFloat {.inline.} =
  ## Height of the box (y2 - y1).
  b.y2 - b.y1

func centerX*[B: Box2D](b: B): MFloat {.inline.} =
  ## X coordinate of the center.
  (b.x1 + b.x2) * 0.5f

func centerY*[B: Box2D](b: B): MFloat {.inline.} =
  ## Y coordinate of the center.
  (b.y1 + b.y2) * 0.5f

func area*[B: Box2D](b: B): MFloat {.inline.} =
  ## Surface area of the 2D box.
  b.width * b.height

func perimeter*[B: Box2D](b: B): MFloat {.inline.} =
  ## Perimeter of the 2D box.
  2f * (b.width + b.height)

func isEmpty*[B: Box2D](b: B): bool {.inline.} =
  ## True when the box has zero or negative area.
  b.x2 <= b.x1 or b.y2 <= b.y1

# ─────────────────────────────────────────────────────────────────── Box3D ───

func minCorner*[B: Box3D](b: B): auto {.inline.} =
  ## Min corner (= origin).
  b.origin

func maxCorner*[B: Box3D](b: B): auto {.inline.} =
  ## Max corner (= origin + size). Returns the same concrete type as origin.
  type V = typeof(b.origin)
  V(x: b.origin.x + b.size.x,
    y: b.origin.y + b.size.y,
    z: b.origin.z + b.size.z)

func center*[B: Box3D](b: B): auto {.inline.} =
  ## Center point of the 3D box.
  type V = typeof(b.origin)
  V(x: b.origin.x + b.size.x*0.5f,
    y: b.origin.y + b.size.y*0.5f,
    z: b.origin.z + b.size.z*0.5f)

func volume*[B: Box3D](b: B): MFloat {.inline.} =
  ## Volume of the 3D box (w * h * d).
  b.size.x * b.size.y * b.size.z

func surfaceArea*[B: Box3D](b: B): MFloat {.inline.} =
  ## Surface area = 2(wh + wd + hd).
  2f * (b.size.x*b.size.y + b.size.x*b.size.z + b.size.y*b.size.z)

func isEmpty*[B: Box3D](b: B): bool {.inline.} =
  ## True when any dimension has zero or negative size.
  b.size.x <= 0f or b.size.y <= 0f or b.size.z <= 0f


#############################################################################################################################
################################################## EQUALITY #################################################################
#############################################################################################################################

func `==`*[B: Box2D](a, b: B): bool {.inline.} =
  a.x1 == b.x1 and a.y1 == b.y1 and a.x2 == b.x2 and a.y2 == b.y2

func `==`*[B: Box3D](a, b: B): bool {.inline.} =
  a.origin.x == b.origin.x and a.origin.y == b.origin.y and a.origin.z == b.origin.z and
  a.size.x   == b.size.x   and a.size.y   == b.size.y   and a.size.z   == b.size.z

func approxEq*[B: Box2D](a, b: B, eps: MFloat = 1e-6f): bool {.inline.} =
  abs(a.x1-b.x1)<=eps and abs(a.y1-b.y1)<=eps and
  abs(a.x2-b.x2)<=eps and abs(a.y2-b.y2)<=eps

func approxEq*[B: Box3D](a, b: B, eps: MFloat = 1e-6f): bool {.inline.} =
  abs(a.origin.x-b.origin.x)<=eps and abs(a.origin.y-b.origin.y)<=eps and
  abs(a.origin.z-b.origin.z)<=eps and abs(a.size.x-b.size.x)<=eps and
  abs(a.size.y-b.size.y)<=eps and abs(a.size.z-b.size.z)<=eps


#############################################################################################################################
################################################## CONTAINMENT / OVERLAP ####################################################
#############################################################################################################################

# ─────────────────────────────────────────────────────────────────── Box2D ───

func contains*[B: Box2D](b: B, px, py: MFloat): bool {.inline.} =
  ## True when point (px,py) is strictly inside the box (not touching edges).
  px > b.x1 and px < b.x2 and py > b.y1 and py < b.y2

func isTouching*[B: Box2D](b: B, px, py: MFloat): bool {.inline.} =
  ## True when point (px,py) is inside or on the boundary.
  px >= b.x1 and px <= b.x2 and py >= b.y1 and py <= b.y2

func containsBox*[B: Box2D](outer, inner: B): bool {.inline.} =
  ## True when `inner` is fully inside `outer` (boundaries may touch).
  inner.x1 >= outer.x1 and inner.y1 >= outer.y1 and
  inner.x2 <= outer.x2 and inner.y2 <= outer.y2

func overlaps*[B: Box2D](a, b: B): bool {.inline.} =
  ## True when the two boxes share any area (touching edges count).
  a.x1 <= b.x2 and a.x2 >= b.x1 and a.y1 <= b.y2 and a.y2 >= b.y1

func overlapsExclusive*[B: Box2D](a, b: B): bool {.inline.} =
  ## True when the two boxes share area, but NOT if they merely touch at edges.
  a.x1 < b.x2 and a.x2 > b.x1 and a.y1 < b.y2 and a.y2 > b.y1

# ─────────────────────────────────────────────────────────────────── Box3D ───

func contains*[B: Box3D](b: B, px, py, pz: MFloat): bool {.inline.} =
  ## True when point (px,py,pz) is strictly inside the box.
  px > b.origin.x and px < b.origin.x+b.size.x and
  py > b.origin.y and py < b.origin.y+b.size.y and
  pz > b.origin.z and pz < b.origin.z+b.size.z

func isTouching*[B: Box3D](b: B, px, py, pz: MFloat): bool {.inline.} =
  ## True when point (px,py,pz) is inside or on the boundary.
  px >= b.origin.x and px <= b.origin.x+b.size.x and
  py >= b.origin.y and py <= b.origin.y+b.size.y and
  pz >= b.origin.z and pz <= b.origin.z+b.size.z

func containsPoint*[B: Box3D, V](b: B, p: V): bool {.inline.} =
  ## True when Vec3-like point p is strictly inside the box.
  isTouching(b, p.x, p.y, p.z)

func containsBox*[B: Box3D](outer, inner: B): bool {.inline.} =
  ## True when `inner` is fully inside `outer`.
  inner.origin.x >= outer.origin.x and
  inner.origin.y >= outer.origin.y and
  inner.origin.z >= outer.origin.z and
  inner.origin.x+inner.size.x <= outer.origin.x+outer.size.x and
  inner.origin.y+inner.size.y <= outer.origin.y+outer.size.y and
  inner.origin.z+inner.size.z <= outer.origin.z+outer.size.z

func overlaps*[B: Box3D](a, b: B): bool {.inline.} =
  ## True when the two 3D boxes share any volume (touching faces count).
  a.origin.x <= b.origin.x+b.size.x and a.origin.x+a.size.x >= b.origin.x and
  a.origin.y <= b.origin.y+b.size.y and a.origin.y+a.size.y >= b.origin.y and
  a.origin.z <= b.origin.z+b.size.z and a.origin.z+a.size.z >= b.origin.z

func overlapsExclusive*[B: Box3D](a, b: B): bool {.inline.} =
  ## True when the two 3D boxes share volume, NOT when merely touching.
  a.origin.x < b.origin.x+b.size.x and a.origin.x+a.size.x > b.origin.x and
  a.origin.y < b.origin.y+b.size.y and a.origin.y+a.size.y > b.origin.y and
  a.origin.z < b.origin.z+b.size.z and a.origin.z+a.size.z > b.origin.z


#############################################################################################################################
################################################## CLOSEST POINT / DISTANCE #################################################
#############################################################################################################################

func closestPoint*[B: Box2D](b: B, px, py: MFloat): (MFloat, MFloat) {.inline.} =
  ## Closest point on or inside the box to (px,py).
  (clamp(px, b.x1, b.x2), clamp(py, b.y1, b.y2))

func distanceSq*[B: Box2D](b: B, px, py: MFloat): MFloat {.inline.} =
  ## Squared distance from point (px,py) to the box surface (0 if inside).
  let dx = max(0f, max(b.x1-px, px-b.x2))
  let dy = max(0f, max(b.y1-py, py-b.y2))
  dx*dx + dy*dy

func distance*[B: Box2D](b: B, px, py: MFloat): MFloat {.inline.} =
  ## Distance from point (px,py) to the box surface (0 if inside).
  sqrt(distanceSq(b, px, py))

func closestPoint*[B: Box3D, V](b: B, p: V): V {.inline.} =
  ## Closest point on or inside the 3D box to Vec3-like point p.
  let mx = b.origin.x+b.size.x
  let my = b.origin.y+b.size.y
  let mz = b.origin.z+b.size.z
  V(x: clamp(p.x, b.origin.x, mx),
    y: clamp(p.y, b.origin.y, my),
    z: clamp(p.z, b.origin.z, mz))

func distanceSq*[B: Box3D, V](b: B, p: V): MFloat {.inline.} =
  ## Squared distance from Vec3-like point p to the 3D box surface.
  let mx = b.origin.x+b.size.x
  let my = b.origin.y+b.size.y
  let mz = b.origin.z+b.size.z
  let dx = max(0f, max(b.origin.x-p.x, p.x-mx))
  let dy = max(0f, max(b.origin.y-p.y, p.y-my))
  let dz = max(0f, max(b.origin.z-p.z, p.z-mz))
  dx*dx + dy*dy + dz*dz

func distance*[B: Box3D, V](b: B, p: V): MFloat {.inline.} =
  ## Distance from Vec3-like point p to the 3D box surface (0 if inside).
  sqrt(distanceSq(b, p))


#############################################################################################################################
################################################## SET OPERATIONS ###########################################################
#############################################################################################################################

# ─────────────────────────────────────────────────────────────────── Box2D ───

func intersect*[B: Box2D](a, b: B): B {.inline.} =
  ## Intersection of two Box2D values.
  ## Result may be empty (x2<=x1 or y2<=y1) — check with isEmpty().
  B(x1: max(a.x1, b.x1), y1: max(a.y1, b.y1),
    x2: min(a.x2, b.x2), y2: min(a.y2, b.y2))

func merge*[B: Box2D](a, b: B): B {.inline.} =
  ## Smallest box containing both a and b (union / bounding box).
  B(x1: min(a.x1, b.x1), y1: min(a.y1, b.y1),
    x2: max(a.x2, b.x2), y2: max(a.y2, b.y2))

func expandBy*[B: Box2D](b: B, amount: MFloat): B {.inline.} =
  ## Grow the box by `amount` on all sides.
  B(x1: b.x1-amount, y1: b.y1-amount,
    x2: b.x2+amount, y2: b.y2+amount)

func shrinkBy*[B: Box2D](b: B, amount: MFloat): B {.inline.} =
  ## Shrink the box by `amount` on all sides (may produce empty box).
  B(x1: b.x1+amount, y1: b.y1+amount,
    x2: b.x2-amount, y2: b.y2-amount)

func translate*[B: Box2D](b: B, dx, dy: MFloat): B {.inline.} =
  ## Translate the box by (dx, dy).
  B(x1: b.x1+dx, y1: b.y1+dy, x2: b.x2+dx, y2: b.y2+dy)

func scale*[B: Box2D](b: B, sx, sy: MFloat): B {.inline.} =
  ## Scale the box around the origin by (sx, sy).
  B(x1: b.x1*sx, y1: b.y1*sy, x2: b.x2*sx, y2: b.y2*sy)

func enclosingPoint*[B: Box2D](b: B, px, py: MFloat): B {.inline.} =
  ## Expand b just enough to include point (px, py).
  B(x1: min(b.x1,px), y1: min(b.y1,py),
    x2: max(b.x2,px), y2: max(b.y2,py))

# ─────────────────────────────────────────────────────────────────── Box3D ───

func intersect*[B: Box3D](a, b: B): B =
  ## Intersection of two Box3D values.
  ## Result may be empty — check with isEmpty().
  let
    ax2 = a.origin.x+a.size.x
    ay2 = a.origin.y+a.size.y
    az2 = a.origin.z+a.size.z
    bx2 = b.origin.x+b.size.x
    by2 = b.origin.y+b.size.y
    bz2 = b.origin.z+b.size.z
    rx1 = max(a.origin.x, b.origin.x)
    ry1 = max(a.origin.y, b.origin.y)
    rz1 = max(a.origin.z, b.origin.z)
    rx2 = min(ax2, bx2)
    ry2 = min(ay2, by2)
    rz2 = min(az2, bz2)
  let V = typeof(a.origin)
  B(origin: V(x:rx1, y:ry1, z:rz1),
    size:   V(x:max(0f,rx2-rx1), y:max(0f,ry2-ry1), z:max(0f,rz2-rz1)))

func merge*[B: Box3D](a, b: B): B =
  ## Smallest box containing both a and b.
  let
    ax2 = a.origin.x+a.size.x
    ay2 = a.origin.y+a.size.y
    az2 = a.origin.z+a.size.z
    bx2 = b.origin.x+b.size.x
    by2 = b.origin.y+b.size.y
    bz2 = b.origin.z+b.size.z
    rx1 = min(a.origin.x,b.origin.x)
    ry1 = min(a.origin.y,b.origin.y)
    rz1 = min(a.origin.z,b.origin.z)
    rx2 = max(ax2,bx2)
    ry2 = max(ay2,by2)
    rz2 = max(az2,bz2)
  type V = typeof(a.origin)
  B(origin: V(x:rx1, y:ry1, z:rz1),
    size:   V(x:rx2-rx1, y:ry2-ry1, z:rz2-rz1))

func expandBy*[B: Box3D](b: B, amount: MFloat): B {.inline.} =
  ## Grow the 3D box by `amount` on all sides.
  type V = typeof(b.origin)
  B(origin: V(x:b.origin.x-amount, y:b.origin.y-amount, z:b.origin.z-amount),
    size:   V(x:b.size.x+amount*2f, y:b.size.y+amount*2f, z:b.size.z+amount*2f))

func shrinkBy*[B: Box3D](b: B, amount: MFloat): B {.inline.} =
  ## Shrink the 3D box by `amount` on all sides (may produce empty box).
  type V = typeof(b.origin)
  B(origin: V(x:b.origin.x+amount, y:b.origin.y+amount, z:b.origin.z+amount),
    size:   V(x:max(0f,b.size.x-amount*2f),
               y:max(0f,b.size.y-amount*2f),
               z:max(0f,b.size.z-amount*2f)))

func translate*[B: Box3D, V](b: B, delta: V): B {.inline.} =
  ## Translate the 3D box by Vec3-like delta.
  type Ov = typeof(b.origin)
  B(origin: Ov(x:b.origin.x+delta.x, y:b.origin.y+delta.y, z:b.origin.z+delta.z),
    size:   b.size)

func enclosingPoint*[B: Box3D, V](b: B, p: V): B {.inline.} =
  ## Expand b just enough to include Vec3-like point p.
  let mx = b.origin.x+b.size.x; let my = b.origin.y+b.size.y; let mz = b.origin.z+b.size.z
  let nx = min(b.origin.x,p.x); let ny = min(b.origin.y,p.y); let nz = min(b.origin.z,p.z)
  let xx = max(mx,p.x);         let xy = max(my,p.y);         let xz = max(mz,p.z)
  type Ov = typeof(b.origin)
  B(origin: Ov(x:nx,y:ny,z:nz), size: Ov(x:xx-nx, y:xy-ny, z:xz-nz))


#############################################################################################################################
################################################## RAY INTERSECTION #########################################################
#############################################################################################################################
## Slab method (Williams et al.) — optimal for AABB, handles all ray directions.
## Returns (tMin, tMax, hit) where hit=true means the ray intersects the box.
## tMin is the entry t, tMax is the exit t. Both are in ray-parameter space.

type RayHit2D* = object
  tMin*, tMax*: MFloat
  hit*: bool

type RayHit3D* = object
  tMin*, tMax*: MFloat
  ## Normal at entry point (axis-aligned, unit length).
  normalX*, normalY*, normalZ*: MFloat
  hit*: bool

func rayIntersect*[B: Box2D](
    b: B,
    ox, oy: MFloat,   ## ray origin
    dx, dy: MFloat,   ## ray direction (need not be normalised)
    tMin: MFloat = 0f,
    tMax: MFloat = 1e30f
  ): RayHit2D =
  ## Slab test for a 2D AABB.
  ## Returns entry/exit t values and whether an intersection exists in [tMin,tMax].
  let invDx = 1f / dx
  let invDy = 1f / dy
  var t1x = (b.x1 - ox) * invDx
  var t2x = (b.x2 - ox) * invDx
  var t1y = (b.y1 - oy) * invDy
  var t2y = (b.y2 - oy) * invDy
  if t1x > t2x: swap(t1x, t2x)
  if t1y > t2y: swap(t1y, t2y)
  let tEnter = max(max(t1x, t1y), tMin)
  let tExit  = min(min(t2x, t2y), tMax)
  RayHit2D(tMin: tEnter, tMax: tExit, hit: tEnter <= tExit)

func rayIntersect*[B: Box3D](
    b: B,
    ox, oy, oz: MFloat,   ## ray origin
    dx, dy, dz: MFloat,   ## ray direction (need not be normalised)
    tMin: MFloat = 0f,
    tMax: MFloat = 1e30f
  ): RayHit3D =
  ## Slab test for a 3D AABB with normal computation at the entry face.
  ## Normal points outward on the face the ray enters through.
  let mx = b.origin.x+b.size.x
  let my = b.origin.y+b.size.y
  let mz = b.origin.z+b.size.z
  let invDx = 1f/dx; let invDy = 1f/dy; let invDz = 1f/dz
  var t1x=(b.origin.x-ox)*invDx; var t2x=(mx-ox)*invDx
  var t1y=(b.origin.y-oy)*invDy; var t2y=(my-oy)*invDy
  var t1z=(b.origin.z-oz)*invDz; var t2z=(mz-oz)*invDz
  if t1x>t2x: swap(t1x,t2x)
  if t1y>t2y: swap(t1y,t2y)
  if t1z>t2z: swap(t1z,t2z)
  let tEnter = max(max(t1x,t1y), max(t1z,tMin))
  let tExit  = min(min(t2x,t2y), min(t2z,tMax))
  if tEnter > tExit:
    return RayHit3D(hit: false)
  # Compute entry face normal
  var nx=0f; var ny=0f; var nz=0f
  if t1x >= t1y and t1x >= t1z:
    nx = if dx < 0f: 1f else: -1f
  elif t1y >= t1x and t1y >= t1z:
    ny = if dy < 0f: 1f else: -1f
  else:
    nz = if dz < 0f: 1f else: -1f
  RayHit3D(tMin:tEnter, tMax:tExit, normalX:nx, normalY:ny, normalZ:nz, hit:true)

func rayIntersectVec*[B: Box3D, V](b: B, origin, dir: V, tMin=0f, tMax=1e30f): RayHit3D {.inline.} =
  ## Vec3-friendly overload of rayIntersect for Box3D.
  rayIntersect(b, origin.x,origin.y,origin.z, dir.x,dir.y,dir.z, tMin, tMax)


#############################################################################################################################
################################################## CORNERS ##################################################################
#############################################################################################################################

func corners*[B: Box2D](b: B): array[4, (MFloat,MFloat)] {.inline.} =
  ## The 4 corners of a 2D box in counter-clockwise order starting from min.
  [(b.x1,b.y1), (b.x2,b.y1), (b.x2,b.y2), (b.x1,b.y2)]

func corners*[B: Box3D](b: B): array[8, (MFloat,MFloat,MFloat)] =
  ## All 8 corners of a 3D box.
  ## Order: iterate Z outer, Y middle, X inner (bit mask 0b_ZYX).
  let mx=b.origin.x+b.size.x; let my=b.origin.y+b.size.y; let mz=b.origin.z+b.size.z
  let xs = [b.origin.x, mx]
  let ys = [b.origin.y, my]
  let zs = [b.origin.z, mz]
  [
    (xs[0],ys[0],zs[0]), (xs[1],ys[0],zs[0]),
    (xs[0],ys[1],zs[0]), (xs[1],ys[1],zs[0]),
    (xs[0],ys[0],zs[1]), (xs[1],ys[0],zs[1]),
    (xs[0],ys[1],zs[1]), (xs[1],ys[1],zs[1])
  ]


#############################################################################################################################
################################################## TRANSFORM ################################################################
#############################################################################################################################

func transformedAabb*[B: Box3D](b: B, m00,m01,m02,m10,m11,m12,m20,m21,m22: MFloat): B =
  ## Compute the AABB of a Box3D after applying a 3×3 linear transform (rotation+scale).
  ## Uses the Arvo/Jim Arvo method: transform each axis extent independently.
  ## Pass the upper-left 3×3 of your Mat4 (column-major: m[col][row]).
  ## Much cheaper than transforming all 8 corners.
  type V = typeof(b.origin)
  let cx=b.origin.x; let cy=b.origin.y; let cz=b.origin.z
  let sx=b.size.x;   let sy=b.size.y;   let sz=b.size.z
  # For each output axis, the new extent is sum of |transform row| * original size
  let newSx = abs(m00)*sx + abs(m10)*sy + abs(m20)*sz
  let newSy = abs(m01)*sx + abs(m11)*sy + abs(m21)*sz
  let newSz = abs(m02)*sx + abs(m12)*sy + abs(m22)*sz
  # New origin = transform * old center - new half-size
  let ocx = m00*cx + m10*cy + m20*cz
  let ocy = m01*cx + m11*cy + m21*cz
  let ocz = m02*cx + m12*cy + m22*cz
  B(origin: V(x:ocx-newSx*0.5f, y:ocy-newSy*0.5f, z:ocz-newSz*0.5f),
    size:   V(x:newSx,           y:newSy,           z:newSz))


#############################################################################################################################
################################################## STRING ###################################################################
#############################################################################################################################

func `$`*[B: Box2D](b: B): string =
  "Box2D(min=(" & $b.x1 & "," & $b.y1 & ") max=(" & $b.x2 & "," & $b.y2 &
  ") size=(" & $b.width & "," & $b.height & "))"

func `$`*[B: Box3D](b: B): string =
  "Box3D(origin=(" & $b.origin.x & "," & $b.origin.y & "," & $b.origin.z &
  ") size=(" & $b.size.x & "," & $b.size.y & "," & $b.size.z & "))"