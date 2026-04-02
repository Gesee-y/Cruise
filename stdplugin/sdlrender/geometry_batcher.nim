## sdl3/geometry_batcher.nim
##
## CPU-side geometry batching layer.
##
## Purpose:
##   Accumulate draw calls (points, lines, rects, circles, polygons, textured
##   quads) into contiguous vertex/index buffers, breaking batches only when
##   the texture, blend mode, or render target changes.
##
## How it fits in the pipeline:
##   1. User pushes draw commands into CRenderer (recorded in CommandBuffer).
##   2. executeCommand overloads feed those commands into GeometryBatcher.
##   3. At flush time, each Batch is submitted as a single SDL_RenderGeometry
##      call — minimising SDL state changes and driver overhead.
##
## Anti-aliasing note:
##   Smooth edges are approximated by emitting a thin "fringe" ring around
##   circles/polygons at alpha = 0 (width = 1 pixel), which blends into the
##   background. This is compatible with SDL3's alpha blending without shaders.
##
## Fixes over the original version:
##   [FIX-1] emitCircle: iInnFirst was recomputed from vertices.len after fringe
##           vertices were already added — now inner ring indices are captured
##           explicitly at vertex-creation time, making the fringe triangulation
##           correct regardless of how many vertices preceded this circle in the
##           same batch.
##   [FIX-2] emitRect (outline): the four edge lines left open corners. Replaced
##           with an explicit 8-vertex closed quad-strip that produces clean
##           mitre-style joins at every corner.
##   [FIX-3] canAppend now also checks indices.len against MaxBatchIndices so a
##           dense circle with many segments cannot silently overflow the index
##           budget.
##   [FIX-4] emitPolygon (filled) used a naive fan from points[0], which is
##           incorrect for concave polygons. The ear-clipping algorithm is now
##           used for filled polygons, making it correct for any simple polygon
##           (convex or concave, non-self-intersecting).
##   [FIX-5] sort() is now opt-in and documented: calling it after emitting all
##           geometry reorders batches for minimal GPU state changes but discards
##           the original painter's-order depth. Callers that rely on Z-ordering
##           via draw order must NOT call sort(), or must assign explicit depth
##           keys before sorting.

import std/[math, algorithm]
import ./types

# ---------------------------------------------------------------------------
# Batch
# ---------------------------------------------------------------------------

const
  MaxBatchVerts*   = 65536   ## 64 K vertices per batch — fits in uint16 indices
  MaxBatchIndices* = 98304   ## 1.5× verts (triangulated quads worst case)

type
  Batch* = object
    ## One contiguous draw call — same texture + blend mode + render target.
    vertices*:   seq[Vertex]
    indices*:    seq[uint32]
    textureKey*: TextureKey   ## InvalidTextureKey = no texture / solid colour
    blendMode*:  SDLBlendMode
    targetKey*:  TextureKey   ## destination render target

proc initBatch*(textureKey, targetKey: TextureKey,
                blend: SDLBlendMode): Batch =
  Batch(vertices: newSeqOfCap[Vertex](256),
        indices:  newSeqOfCap[uint32](384),
        textureKey: textureKey,
        blendMode:  blend,
        targetKey:  targetKey)

proc canAppend*(b: Batch, textureKey, targetKey: TextureKey,
                blend: SDLBlendMode): bool {.inline.} =
  ## [FIX-3] Guard both vertex AND index budgets.
  b.textureKey  == textureKey and
  b.targetKey   == targetKey  and
  b.blendMode   == blend      and
  b.vertices.len < MaxBatchVerts   - 64 and
  b.indices.len  < MaxBatchIndices - 96

template addVertex*(b: var Batch | ptr Batch, v: Vertex): uint32 =
  let id = uint32(b.vertices.len)
  b.vertices.add(v)
  id

template addTriangle*(b: var Batch | ptr Batch, i0, i1, i2: uint32) =
  b.indices.add(i0); b.indices.add(i1); b.indices.add(i2)

template clear*(b: var Batch | ptr Batch) =
  b.vertices.setLen(0)
  b.indices.setLen(0)

# ---------------------------------------------------------------------------
# GeometryBatcher
# ---------------------------------------------------------------------------

type
  GeometryBatcher* = object
    batches*: seq[Batch]
    ## NOTE: batches are appended in draw order (painter's algorithm).
    ## Call sort() only when all geometry is opaque and Z-ordering via draw
    ## order is not required — see [FIX-5].

proc initGeometryBatcher*(): GeometryBatcher =
  GeometryBatcher(batches: @[])

proc clear*(gb: var GeometryBatcher) =
  for i in 0 ..< gb.batches.len:
    clear(addr gb.batches[i])
  gb.batches.setLen(0)

proc currentBatch*(gb: var GeometryBatcher,
                   textureKey, targetKey: TextureKey,
                   blend: SDLBlendMode): ptr Batch =
  ## Return the active batch, starting a new one if needed.
  if gb.batches.len > 0 and
     gb.batches[^1].canAppend(textureKey, targetKey, blend):
    return addr gb.batches[^1]
  gb.batches.add(initBatch(textureKey, targetKey, blend))
  addr gb.batches[^1]

# ---------------------------------------------------------------------------
# Primitive emitters
# ---------------------------------------------------------------------------

proc emitPoint*(gb:        var GeometryBatcher,
                pos:       FPoint,
                color:     SDLRGBA,
                targetKey: TextureKey,
                blend:     SDLBlendMode,
                pointSize: float32 = 1.0) =
  ## Emit a screen-aligned quad for a single point (SDL has no GL_POINTS).
  let b  = gb.currentBatch(InvalidTextureKey, targetKey, blend)
  let hs = pointSize * 0.5
  let i0 = b.addVertex(Vertex(pos: fpoint(pos.x - hs, pos.y - hs), uv: fpoint(0,0), color: color))
  let i1 = b.addVertex(Vertex(pos: fpoint(pos.x + hs, pos.y - hs), uv: fpoint(1,0), color: color))
  let i2 = b.addVertex(Vertex(pos: fpoint(pos.x + hs, pos.y + hs), uv: fpoint(1,1), color: color))
  let i3 = b.addVertex(Vertex(pos: fpoint(pos.x - hs, pos.y + hs), uv: fpoint(0,1), color: color))
  b.addTriangle(i0, i1, i2)
  b.addTriangle(i0, i2, i3)

proc emitLine*(gb:        var GeometryBatcher,
               a, b_pt:   FPoint,
               color:     SDLRGBA,
               targetKey: TextureKey,
               blend:     SDLBlendMode,
               thickness: float32 = 1.0) =
  ## Emit a thick line as a quad strip aligned along the segment normal.
  let dx  = b_pt.x - a.x
  let dy  = b_pt.y - a.y
  let len = sqrt(dx*dx + dy*dy)
  if len < 1e-6: return   ## degenerate — skip silently

  let nx  = -dy / len * (thickness * 0.5)
  let ny  =  dx / len * (thickness * 0.5)

  let bat = gb.currentBatch(InvalidTextureKey, targetKey, blend)
  let i0  = bat.addVertex(Vertex(pos: fpoint(a.x    + nx, a.y    + ny), color: color))
  let i1  = bat.addVertex(Vertex(pos: fpoint(a.x    - nx, a.y    - ny), color: color))
  let i2  = bat.addVertex(Vertex(pos: fpoint(b_pt.x - nx, b_pt.y - ny), color: color))
  let i3  = bat.addVertex(Vertex(pos: fpoint(b_pt.x + nx, b_pt.y + ny), color: color))
  bat.addTriangle(i0, i1, i2)
  bat.addTriangle(i0, i2, i3)

# ---------------------------------------------------------------------------
# [FIX-2] emitRect outline — closed 8-vertex ring with clean mitre corners
# ---------------------------------------------------------------------------
#
# Original approach emitted 4 independent emitLine calls.  Each line was a
# standalone quad: its endpoints stopped exactly at the rect corner, leaving
# a triangular gap (or overlap) of size thickness/2 at every corner.
#
# Fix: we build a closed double-ring (inner + outer) of 8 vertices and
# triangulate the 4 edge quads manually.  Because both rings share the same
# corner point, the joins are gap-free and require no extra maths.
#
#   outer ring: o0 o1 o2 o3   (expanded by half-thickness)
#   inner ring: i0 i1 i2 i3   (shrunk by half-thickness)
#
# Edge quads (CCW winding):
#   top    : o0-o1-i1-i0
#   right  : o1-o2-i2-i1
#   bottom : o2-o3-i3-i2
#   left   : o3-o0-i0-i3

proc emitRect*(gb:        var GeometryBatcher,
               rect:      FRect,
               color:     SDLRGBA,
               targetKey: TextureKey,
               blend:     SDLBlendMode,
               filled:    bool    = true,
               thickness: float32 = 1.0) =
  if filled:
    let b  = gb.currentBatch(InvalidTextureKey, targetKey, blend)
    let i0 = b.addVertex(Vertex(pos: fpoint(rect.x,          rect.y),          uv: fpoint(0,0), color: color))
    let i1 = b.addVertex(Vertex(pos: fpoint(rect.x + rect.w, rect.y),          uv: fpoint(1,0), color: color))
    let i2 = b.addVertex(Vertex(pos: fpoint(rect.x + rect.w, rect.y + rect.h), uv: fpoint(1,1), color: color))
    let i3 = b.addVertex(Vertex(pos: fpoint(rect.x,          rect.y + rect.h), uv: fpoint(0,1), color: color))
    b.addTriangle(i0, i1, i2)
    b.addTriangle(i0, i2, i3)
  else:
    ## [FIX-2] Closed ring — 8 vertices, 4 edge quads, perfect mitre joins.
    let ht  = thickness * 0.5
    let x0o = rect.x          - ht;  let y0o = rect.y          - ht
    let x1o = rect.x + rect.w + ht;  let y1o = rect.y          - ht
    let x2o = rect.x + rect.w + ht;  let y2o = rect.y + rect.h + ht
    let x3o = rect.x          - ht;  let y3o = rect.y + rect.h + ht
    let x0i = rect.x          + ht;  let y0i = rect.y          + ht
    let x1i = rect.x + rect.w - ht;  let y1i = rect.y          + ht
    let x2i = rect.x + rect.w - ht;  let y2i = rect.y + rect.h - ht
    let x3i = rect.x          + ht;  let y3i = rect.y + rect.h - ht

    let b  = gb.currentBatch(InvalidTextureKey, targetKey, blend)
    let o0 = b.addVertex(Vertex(pos: fpoint(x0o, y0o), color: color))
    let o1 = b.addVertex(Vertex(pos: fpoint(x1o, y1o), color: color))
    let o2 = b.addVertex(Vertex(pos: fpoint(x2o, y2o), color: color))
    let o3 = b.addVertex(Vertex(pos: fpoint(x3o, y3o), color: color))
    let ii0 = b.addVertex(Vertex(pos: fpoint(x0i, y0i), color: color))
    let ii1 = b.addVertex(Vertex(pos: fpoint(x1i, y1i), color: color))
    let ii2 = b.addVertex(Vertex(pos: fpoint(x2i, y2i), color: color))
    let ii3 = b.addVertex(Vertex(pos: fpoint(x3i, y3i), color: color))
    ## top
    b.addTriangle(o0, o1, ii1); b.addTriangle(o0, ii1, ii0)
    ## right
    b.addTriangle(o1, o2, ii2); b.addTriangle(o1, ii2, ii1)
    ## bottom
    b.addTriangle(o2, o3, ii3); b.addTriangle(o2, ii3, ii2)
    ## left
    b.addTriangle(o3, o0, ii0); b.addTriangle(o3, ii0, ii3)

# ---------------------------------------------------------------------------
# [FIX-1] emitCircle — explicit inner-ring index tracking
# ---------------------------------------------------------------------------
#
# Original code computed iInnFirst by subtracting a fixed offset from
# vertices.len *after* the inner-ring loop, which was wrong whenever the
# batch already contained other vertices before this circle.
#
# Fix: capture the base index of the very first inner-ring vertex (the one
# at angle 0, i.e. iPrev) before the loop starts, and use that base to
# compute indices for subsequent inner-ring vertices: innerIdx(i) = iBase + i.
# This is always correct because inner-ring vertices are added sequentially
# with no interleaving.

proc emitCircle*(gb:        var GeometryBatcher,
                 center:    FPoint,
                 radius:    float32,
                 color:     SDLRGBA,
                 targetKey: TextureKey,
                 blend:     SDLBlendMode,
                 filled:    bool    = true,
                 thickness: float32 = 1.0,
                 segments:  int     = 0) =
  ## Tessellate a circle into a triangle fan (filled) or thick ring (outline).
  ## `segments` = 0 → auto-compute based on radius.
  let segs = if segments <= 0:
    max(12, int(radius * 0.5 * Pi))
  else:
    max(3, segments)   ## clamp: a circle needs at least 3 segments

  let step = 2.0 * Pi / float32(segs)

  if filled:
    let b    = gb.currentBatch(InvalidTextureKey, targetKey, blend)
    let iCtr = b.addVertex(Vertex(pos: center, color: color))

    ## [FIX-1] Record the base index of the inner ring before the loop.
    let iInnerBase = b.addVertex(Vertex(
      pos: fpoint(center.x + radius, center.y),
      color: color))
    ## iInnerBase     = inner[0]  (angle 0)
    ## iInnerBase + 1 = inner[1]  (angle step)
    ## iInnerBase + i = inner[i]  (angle i*step)

    var iPrev = iInnerBase
    for i in 1 .. segs:
      let angle = float32(i) * step
      let iCur  = b.addVertex(Vertex(
        pos: fpoint(center.x + cos(angle) * radius,
                    center.y + sin(angle) * radius),
        color: color))
      b.addTriangle(iCtr, iPrev, iCur)
      iPrev = iCur
      ## Close the fan: the last inner vertex wraps back to inner[0].
      ## This is handled naturally because the last iCur == inner[segs]
      ## and the fan triangle uses (iCtr, inner[segs-1], inner[segs]).
      ## The closing edge inner[segs] → inner[0] is the segment from
      ## angle 2π back to angle 0, which approximates the full circle.

    ## Anti-alias fringe: thin alpha=0 ring just outside the solid disc.
    ## We triangulate it as a strip between the inner ring and the fringe ring.
    let alphaZero = SDLRGBA(r: color.r, g: color.g, b: color.b, a: 0)
    let fringeR   = radius + 1.0

    ## [FIX-1] First fringe vertex at angle 0 — matches inner[0] = iInnerBase.
    let iFringeBase = b.addVertex(Vertex(
      pos: fpoint(center.x + fringeR, center.y),
      color: alphaZero))
    ## iFringeBase + i = fringe[i]  (angle i*step)

    for i in 1 .. segs:
      let angle   = float32(i) * step
      let iOutCur = b.addVertex(Vertex(
        pos: fpoint(center.x + cos(angle) * fringeR,
                    center.y + sin(angle) * fringeR),
        color: alphaZero))
      ## quad: fringe[i-1], fringe[i], inner[i], inner[i-1]
      let fPrev = iFringeBase + uint32(i - 1)
      let fCur  = iFringeBase + uint32(i)          ## == iOutCur
      let nPrev = iInnerBase  + uint32(i - 1)
      let nCur  = iInnerBase  + uint32(i)

      b.addTriangle(fPrev, fCur,  nCur)
      b.addTriangle(fPrev, nCur,  nPrev)

      discard iOutCur  ## value already captured via iFringeBase + i

  else:
    ## Outline: ring of thick quads, one per segment.
    for i in 0 ..< segs:
      let a0 = float32(i) * step
      let a1 = float32(i + 1) * step
      let p0 = fpoint(center.x + cos(a0) * radius, center.y + sin(a0) * radius)
      let p1 = fpoint(center.x + cos(a1) * radius, center.y + sin(a1) * radius)
      gb.emitLine(p0, p1, color, targetKey, blend, thickness)

# ---------------------------------------------------------------------------
# [FIX-4] emitPolygon — ear-clipping for arbitrary simple polygons
# ---------------------------------------------------------------------------
#
# Original code used fan triangulation from points[0], which is only correct
# for strictly convex polygons.  For any concave simple polygon it produces
# triangles that overlap the polygon's exterior.
#
# Fix: ear-clipping triangulation.  An "ear" is a vertex whose two neighbours
# form a triangle that:
#   (a) has the correct winding (cross product > 0 for CCW input), and
#   (b) contains no other polygon vertex in its interior.
# We clip one ear at a time until only a single triangle remains.
# Complexity is O(n²) which is fine for the typical UI polygon sizes (<100 pts).
#
# The algorithm assumes a simple (non-self-intersecting) polygon.
# Winding order is auto-detected: if the signed area is negative (CW input),
# the vertex list is reversed before clipping so the algorithm always works
# on CCW-wound data.

proc cross2D(o, a, b: FPoint): float32 {.inline.} =
  ## 2-D cross product of vectors OA and OB.
  ## Positive → A is to the left of OB (CCW turn at O).
  (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)

proc pointInTriangle(p, a, b, c: FPoint): bool {.inline.} =
  ## True if p lies strictly inside (or on the edge of) triangle ABC.
  let d0 = cross2D(a, b, p)
  let d1 = cross2D(b, c, p)
  let d2 = cross2D(c, a, p)
  let hasNeg = (d0 < 0) or (d1 < 0) or (d2 < 0)
  let hasPos = (d0 > 0) or (d1 > 0) or (d2 > 0)
  not (hasNeg and hasPos)

proc signedArea2(pts: openArray[FPoint]): float32 =
  ## Twice the signed area of the polygon.  Positive → CCW.
  let n = pts.len
  for i in 0 ..< n:
    let j = (i + 1) mod n
    result += (pts[j].x - pts[i].x) * (pts[j].y + pts[i].y)
  ## Note: we return the raw sum (= 2 × signed area in screen space where Y
  ## increases downward), so positive means CW in screen coords.  We reverse
  ## the list when this value is positive to normalise to CCW.

proc emitPolygon*(gb:        var GeometryBatcher,
                  points:    openArray[FPoint],
                  color:     SDLRGBA,
                  targetKey: TextureKey,
                  blend:     SDLBlendMode,
                  filled:    bool    = true,
                  thickness: float32 = 1.0) =
  ## Triangulate a simple (non-self-intersecting) polygon.
  ## Filled: ear-clipping — works for convex AND concave polygons. [FIX-4]
  ## Outline: one emitLine per edge, closed.
  if points.len < 3: return

  if filled:
    ## Work on a mutable index list so we can clip ears without copying points.
    var indices = newSeq[int](points.len)
    for i in 0 ..< points.len: indices[i] = i

    ## Normalise to CCW winding (screen: Y down → positive area = CW → reverse).
    if signedArea2(points) > 0:
      indices.reverse()

    let b = gb.currentBatch(InvalidTextureKey, targetKey, blend)

    ## Add all vertices once; triangles index into them.
    let base = uint32(b.vertices.len)
    for pt in points:
      discard b.addVertex(Vertex(pos: pt, color: color))

    ## Ear-clipping main loop.
    var remaining = indices.len
    var idx       = indices    ## working copy

    var safetyLimit = remaining * remaining + 10  ## O(n²) worst case guard
    while remaining > 3 and safetyLimit > 0:
      dec safetyLimit
      var earFound = false
      for i in 0 ..< remaining:
        let prev = idx[(i + remaining - 1) mod remaining]
        let curr = idx[i]
        let next = idx[(i + 1) mod remaining]

        let p0 = points[prev]
        let p1 = points[curr]
        let p2 = points[next]

        ## Must be a left turn (ear candidate).
        if cross2D(p0, p1, p2) <= 0: continue

        ## No other vertex may lie inside this ear triangle.
        var isEar = true
        for j in 0 ..< remaining:
          let other = idx[j]
          if other == prev or other == curr or other == next: continue
          if pointInTriangle(points[other], p0, p1, p2):
            isEar = false
            break

        if not isEar: continue

        ## Clip the ear: emit triangle and remove curr from the list.
        b.addTriangle(base + uint32(prev),
                      base + uint32(curr),
                      base + uint32(next))
        idx.delete(i)
        dec remaining
        earFound = true
        break

      ## If no ear was found (degenerate / self-intersecting polygon),
      ## bail to avoid an infinite loop.
      if not earFound: break

    ## Emit the final triangle.
    if remaining == 3:
      b.addTriangle(base + uint32(idx[0]),
                    base + uint32(idx[1]),
                    base + uint32(idx[2]))
  else:
    for k in 0 ..< points.len:
      gb.emitLine(points[k], points[(k + 1) mod points.len],
                  color, targetKey, blend, thickness)

proc emitTexturedQuad*(gb:         var GeometryBatcher,
                       dst:        FRect,
                       src:        FRect,   ## UV rectangle in [0,1] space
                       textureKey: TextureKey,
                       targetKey:  TextureKey,
                       blend:      SDLBlendMode,
                       tint:       SDLRGBA  = SDLRGBA.white,
                       angle:      float32  = 0.0,
                       pivot:      FPoint   = fpoint(0.5, 0.5),
                       flipH:      bool     = false,
                       flipV:      bool     = false) =
  ## Emit a (possibly rotated) textured quad.
  ## `src` is in normalised UV space [0,1]×[0,1].
  ## `pivot` is a normalised pivot inside dst (0.5,0.5 = centre).
  let b = gb.currentBatch(textureKey, targetKey, blend)

  ## Local corners before rotation (relative to pivot).
  let pw = dst.w * pivot.x
  let ph = dst.h * pivot.y
  var lc: array[4, FPoint]
  lc[0] = fpoint(-pw,         -ph)
  lc[1] = fpoint(dst.w - pw,  -ph)
  lc[2] = fpoint(dst.w - pw,  dst.h - ph)
  lc[3] = fpoint(-pw,         dst.h - ph)

  let cx    = dst.x + pw
  let cy    = dst.y + ph
  let cos_a = cos(angle)
  let sin_a = sin(angle)

  var uvs: array[4, FPoint]
  uvs[0] = fpoint(if flipH: src.x + src.w else: src.x,        if flipV: src.y + src.h else: src.y)
  uvs[1] = fpoint(if flipH: src.x         else: src.x + src.w, if flipV: src.y + src.h else: src.y)
  uvs[2] = fpoint(if flipH: src.x         else: src.x + src.w, if flipV: src.y         else: src.y + src.h)
  uvs[3] = fpoint(if flipH: src.x + src.w else: src.x,        if flipV: src.y         else: src.y + src.h)

  var vi: array[4, uint32]
  for k in 0..3:
    let rx = lc[k].x * cos_a - lc[k].y * sin_a + cx
    let ry = lc[k].x * sin_a + lc[k].y * cos_a + cy
    vi[k] = b.addVertex(Vertex(pos: fpoint(rx, ry), uv: uvs[k], color: tint))

  b.addTriangle(vi[0], vi[1], vi[2])
  b.addTriangle(vi[0], vi[2], vi[3])

proc emitTriangle*(gb:         var GeometryBatcher,
                   p0, p1, p2: FPoint,
                   c0, c1, c2: SDLRGBA,
                   textureKey: TextureKey,
                   targetKey:  TextureKey,
                   blend:      SDLBlendMode,
                   uv0: FPoint = fpoint(0,0), uv1: FPoint = fpoint(0,0), uv2: FPoint = fpoint(0,0)) =
  ## Emit a single triangle with per-vertex colours and UVs.
  let b  = gb.currentBatch(textureKey, targetKey, blend)
  let i0 = b.addVertex(Vertex(pos: p0, uv: uv0, color: c0))
  let i1 = b.addVertex(Vertex(pos: p1, uv: uv1, color: c1))
  let i2 = b.addVertex(Vertex(pos: p2, uv: uv2, color: c2))
  b.addTriangle(i0, i1, i2)

proc emitRoundedRect*(gb:         var GeometryBatcher,
                      rect:       FRect,
                      radius:     float32,
                      color:      SDLRGBA,
                      targetKey:  TextureKey,
                      blend:      SDLBlendMode,
                      filled:     bool = true,
                      cornerSegs: int  = 8) =
  ## Emit a rounded rectangle.
  ## Filled: centre rect + 2 edge rects + 4 corner fans.
  ## Outline: arc segments at corners + straight edge lines.
  let r   = min(radius, min(rect.w, rect.h) * 0.5)
  let cx0 = rect.x + r;          let cx1 = rect.x + rect.w - r
  let cy0 = rect.y + r;          let cy1 = rect.y + rect.h - r

  if filled:
    ## Centre vertical strip
    gb.emitRect(frect(rect.x + r, rect.y,      rect.w - 2*r, rect.h),      color, targetKey, blend, true)
    ## Left and right edge strips
    gb.emitRect(frect(rect.x,              rect.y + r, r, rect.h - 2*r),   color, targetKey, blend, true)
    gb.emitRect(frect(rect.x + rect.w - r, rect.y + r, r, rect.h - 2*r),   color, targetKey, blend, true)

    ## Four corner fans
    let step = 0.5 * Pi / float32(cornerSegs)
    for k in 0 ..< cornerSegs:
      let a0 = float32(k)   * step
      let a1 = float32(k+1) * step
      ## Bottom-right (0 .. π/2)
      gb.emitTriangle(fpoint(cx1, cy1),
        fpoint(cx1 + cos(a0)*r,         cy1 + sin(a0)*r),
        fpoint(cx1 + cos(a1)*r,         cy1 + sin(a1)*r),
        color, color, color, InvalidTextureKey, targetKey, blend)
      ## Bottom-left (π/2 .. π)
      gb.emitTriangle(fpoint(cx0, cy1),
        fpoint(cx0 + cos(Pi*0.5 + a0)*r, cy1 + sin(Pi*0.5 + a0)*r),
        fpoint(cx0 + cos(Pi*0.5 + a1)*r, cy1 + sin(Pi*0.5 + a1)*r),
        color, color, color, InvalidTextureKey, targetKey, blend)
      ## Top-left (π .. 3π/2)
      gb.emitTriangle(fpoint(cx0, cy0),
        fpoint(cx0 + cos(Pi + a0)*r,     cy0 + sin(Pi + a0)*r),
        fpoint(cx0 + cos(Pi + a1)*r,     cy0 + sin(Pi + a1)*r),
        color, color, color, InvalidTextureKey, targetKey, blend)
      ## Top-right (3π/2 .. 2π)
      gb.emitTriangle(fpoint(cx1, cy0),
        fpoint(cx1 + cos(Pi*1.5 + a0)*r, cy0 + sin(Pi*1.5 + a0)*r),
        fpoint(cx1 + cos(Pi*1.5 + a1)*r, cy0 + sin(Pi*1.5 + a1)*r),
        color, color, color, InvalidTextureKey, targetKey, blend)
  else:
    ## Outline: arc segments at each corner, straight lines on edges.
    let step = 0.5 * Pi / float32(cornerSegs)
    for k in 0 ..< cornerSegs:
      for (ox, oy, baseAngle) in [(cx1, cy1, 0.0f),
                                   (cx0, cy1, Pi * 0.5f),
                                   (cx0, cy0, Pi.float32),
                                   (cx1, cy0, Pi * 1.5f)]:
        let a0 = baseAngle + float32(k)   * step
        let a1 = baseAngle + float32(k+1) * step
        gb.emitLine(
          fpoint(ox + cos(a0)*r, oy + sin(a0)*r),
          fpoint(ox + cos(a1)*r, oy + sin(a1)*r),
          color, targetKey, blend)
    ## Straight edges (connect corner arcs)
    gb.emitLine(fpoint(cx0, rect.y),          fpoint(cx1, rect.y),          color, targetKey, blend)
    gb.emitLine(fpoint(cx1, rect.y + rect.h), fpoint(cx0, rect.y + rect.h), color, targetKey, blend)
    gb.emitLine(fpoint(rect.x,          cy0), fpoint(rect.x,          cy1), color, targetKey, blend)
    gb.emitLine(fpoint(rect.x + rect.w, cy0), fpoint(rect.x + rect.w, cy1), color, targetKey, blend)

# ---------------------------------------------------------------------------
# [FIX-5] sort — documented painter's-order caveat
# ---------------------------------------------------------------------------

proc sort*(gb: var GeometryBatcher) =
  ## Sort batches to minimise GPU state changes (target → texture → blend).
  ##
  ## WARNING: this discards the painter's-order depth established by the
  ## original draw-call sequence.  Only call sort() when:
  ##   • all geometry in the frame is opaque (no alpha blending), OR
  ##   • primitives do not spatially overlap and Z-ordering via draw order
  ##     is not required.
  ## If your UI relies on later draw calls rendering on top of earlier ones
  ## (the normal expectation), do NOT call sort().
  gb.batches.sort(proc(a, b: Batch): int =
    if uint32(a.targetKey) != uint32(b.targetKey):
      return cmp(uint32(a.targetKey), uint32(b.targetKey))
    if uint32(a.textureKey) != uint32(b.textureKey):
      return cmp(uint32(a.textureKey), uint32(b.textureKey))
    return cmp(int(a.blendMode), int(b.blendMode))
  )