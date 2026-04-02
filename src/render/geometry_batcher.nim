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

import std/[math, algorithm]
import ../la/LA

# ---------------------------------------------------------------------------
# Batch
# ---------------------------------------------------------------------------

const
  MaxBatchVerts*   = 65536   ## 64 K vertices per batch — fits in uint16 indices
  MaxBatchIndices* = 98304   ## 1.5× verts (triangulated quads worst case)

type

  Point = object
    x, y: float32

  Rect = object
    x1, x2, y1, y2: float32

  RGBA = object
    r, g, b, a: uint8

  Batch* = object
    ## One contiguous draw call — same texture + blend mode + render target.
    vertices*:    seq[Vertex]
    indices*:     seq[uint32]
    textureKey*:  TextureKey   ## InvalidTextureKey = no texture / solid color
    blendMode*:   SDLBlendMode
    targetKey*:   TextureKey   ## destination render target

template point(x, y) = Point(x: x.float32, y: y.float32) 
template point[V: Vec2](v: V) = point(v.x.float32, v.y.float32)
template rect(x1, x2, y1, y2) = Rect(x1: x1.float32, x2: x2.float32, y1: y1.float32, y2: y2.float32) 
template rect[B: Box2D](b: B) = rect(b.x1, b.x2, b.y1, b.y2)

proc initBatch*(textureKey, targetKey: TextureKey,
                blend: SDLBlendMode): Batch =
  Batch(vertices: newSeqOfCap[Vertex](256),
        indices:  newSeqOfCap[uint32](384),
        textureKey: textureKey,
        blendMode:  blend,
        targetKey:  targetKey)

proc canAppend*(b: Batch, textureKey, targetKey: TextureKey,
                blend: SDLBlendMode): bool {.inline.} =
  b.textureKey == textureKey and
  b.targetKey  == targetKey  and
  b.blendMode  == blend      and
  b.vertices.len < MaxBatchVerts - 64

proc addVertex*(b: var Batch | ptr Batch, v: Vertex): uint32 {.inline.} =
  result = uint32(b.vertices.len)
  b.vertices.add(v)

proc addTriangle*(b: var Batch | ptr Batch, i0, i1, i2: uint32) {.inline.} =
  b.indices.add(i0); b.indices.add(i1); b.indices.add(i2)

proc clear*(b: var Batch | ptr Batch) =
  b.vertices.setLen(0)
  b.indices.setLen(0)

# ---------------------------------------------------------------------------
# GeometryBatcher
# ---------------------------------------------------------------------------

type
  GeometryBatcher* = object
    batches*:     seq[Batch]
    ## Sorted by (targetKey, blendMode) for minimal state changes at flush.

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
  if gb.batches.len > 0 and gb.batches[^1].canAppend(textureKey, targetKey, blend):
    return addr gb.batches[^1]
  gb.batches.add(initBatch(textureKey, targetKey, blend))
  addr gb.batches[^1]

# ---------------------------------------------------------------------------
# Primitive emitters
# ---------------------------------------------------------------------------

proc emitPoint*(gb:         var GeometryBatcher,
                pos:        Point,
                color:      RGBA,
                targetKey:  TextureKey,
                blend:      SDLBlendMode,
                pointSize:  float32 = 1.0) =
  ## Emit a screen-aligned quad for a single point (SDL has no GL_POINTS).
  let b = gb.currentBatch(InvalidTextureKey, targetKey, blend)
  let hs = pointSize * 0.5
  # Quad: TL, TR, BR, BL
  let i0 = b.addVertex(Vertex(pos: point(pos.x - hs, pos.y - hs), uv: point(0,0), color: color))
  let i1 = b.addVertex(Vertex(pos: point(pos.x + hs, pos.y - hs), uv: point(1,0), color: color))
  let i2 = b.addVertex(Vertex(pos: point(pos.x + hs, pos.y + hs), uv: point(1,1), color: color))
  let i3 = b.addVertex(Vertex(pos: point(pos.x - hs, pos.y + hs), uv: point(0,1), color: color))
  b.addTriangle(i0, i1, i2)
  b.addTriangle(i0, i2, i3)

proc emitLine*(gb:        var GeometryBatcher,
               a, b_pt:   Point,
               color:     RGBA,
               targetKey: TextureKey,
               blend:     SDLBlendMode,
               thickness: float32 = 1.0) =
  ## Emit a thick anti-aliased line as a quad strip.
  let dx   = b_pt.x - a.x
  let dy   = b_pt.y - a.y
  let len  = sqrt(dx*dx + dy*dy)
  if len < 1e-6: return

  let nx   = -dy / len * (thickness * 0.5)
  let ny   =  dx / len * (thickness * 0.5)

  let bat = gb.currentBatch(InvalidTextureKey, targetKey, blend)
  let i0  = bat.addVertex(Vertex(pos: point(a.x   + nx, a.y   + ny), color: color))
  let i1  = bat.addVertex(Vertex(pos: point(a.x   - nx, a.y   - ny), color: color))
  let i2  = bat.addVertex(Vertex(pos: point(b_pt.x - nx, b_pt.y - ny), color: color))
  let i3  = bat.addVertex(Vertex(pos: point(b_pt.x + nx, b_pt.y + ny), color: color))
  bat.addTriangle(i0, i1, i2)
  bat.addTriangle(i0, i2, i3)

proc emitRect*(gb:        var GeometryBatcher,
               rect:      Rect,
               color:     RGBA,
               targetKey: TextureKey,
               blend:     SDLBlendMode,
               filled:    bool = true,
               thickness: float32 = 1.0) =
  if filled:
    let b = gb.currentBatch(InvalidTextureKey, targetKey, blend)
    let i0 = b.addVertex(Vertex(pos: point(rect.x,          rect.y),          uv: point(0,0), color: color))
    let i1 = b.addVertex(Vertex(pos: point(rect.x + rect.w, rect.y),          uv: point(1,0), color: color))
    let i2 = b.addVertex(Vertex(pos: point(rect.x + rect.w, rect.y + rect.h), uv: point(1,1), color: color))
    let i3 = b.addVertex(Vertex(pos: point(rect.x,          rect.y + rect.h), uv: point(0,1), color: color))
    b.addTriangle(i0, i1, i2)
    b.addTriangle(i0, i2, i3)
  else:
    # Four thick edge lines
    let x0 = rect.x;          let y0 = rect.y
    let x1 = rect.x + rect.w; let y1 = rect.y + rect.h
    gb.emitLine(point(x0,y0), point(x1,y0), color, targetKey, blend, thickness)  # top
    gb.emitLine(point(x1,y0), point(x1,y1), color, targetKey, blend, thickness)  # right
    gb.emitLine(point(x1,y1), point(x0,y1), color, targetKey, blend, thickness)  # bottom
    gb.emitLine(point(x0,y1), point(x0,y0), color, targetKey, blend, thickness)  # left

proc emitCircle*(gb:        var GeometryBatcher,
                 center:    Point,
                 radius:    float32,
                 color:     RGBA,
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
    segments

  let step  = 2.0 * Pi / float32(segs)

  if filled:
    let b    = gb.currentBatch(InvalidTextureKey, targetKey, blend)
    let iCtr = b.addVertex(Vertex(pos: center, color: color))
    var iPrev = b.addVertex(Vertex(pos: point(center.x + radius, center.y), color: color))

    for i in 1..segs:
      let angle = float32(i) * step
      let iCur  = b.addVertex(Vertex(
        pos: point(center.x + cos(angle) * radius,
                    center.y + sin(angle) * radius),
        color: color
      ))
      b.addTriangle(iCtr, iPrev, iCur)
      iPrev = iCur

    # Anti-alias fringe: thin alpha=0 ring outside
    let alphaZero = RGBA(r: color.r, g: color.g, b: color.b, a: 0)
    let fringeR   = radius + 1.0
    var iOutPrev  = b.addVertex(Vertex(pos: point(center.x + fringeR, center.y), color: alphaZero))
    let iInnFirst = uint32(b.vertices.len) - uint32(segs + 1) - 1  # first inner ring vertex

    for i in 1..segs:
      let angle   = float32(i) * step
      let iOutCur = b.addVertex(Vertex(
        pos: point(center.x + cos(angle) * fringeR,
                    center.y + sin(angle) * fringeR),
        color: alphaZero
      ))
      # fringe triangle between outer[i-1], outer[i], inner[i]
      b.addTriangle(iOutPrev, iOutCur, iInnFirst + uint32(i))
      b.addTriangle(iOutPrev, iInnFirst + uint32(i), iInnFirst + uint32(i - 1))
      iOutPrev = iOutCur

  else:
    # Outline as ring of thick quads
    for i in 0 ..< segs:
      let a0 = float32(i)     * step
      let a1 = float32(i + 1) * step
      let p0 = point(center.x + cos(a0) * radius, center.y + sin(a0) * radius)
      let p1 = point(center.x + cos(a1) * radius, center.y + sin(a1) * radius)
      gb.emitLine(p0, p1, color, targetKey, blend, thickness)

proc emitPolygon*(gb:        var GeometryBatcher,
                  points:    openArray[Point],
                  color:     RGBA,
                  targetKey: TextureKey,
                  blend:     SDLBlendMode,
                  filled:    bool    = true,
                  thickness: float32 = 1.0) =
  ## Fan-triangulate a convex polygon.
  if points.len < 3: return
  if filled:
    let b  = gb.currentBatch(InvalidTextureKey, targetKey, blend)
    let i0 = b.addVertex(Vertex(pos: points[0], color: color))
    for k in 1 .. points.len - 2:
      let ik  = b.addVertex(Vertex(pos: points[k],     color: color))
      let ik1 = b.addVertex(Vertex(pos: points[k + 1], color: color))
      b.addTriangle(i0, ik, ik1)
  else:
    for k in 0 ..< points.len:
      gb.emitLine(points[k], points[(k + 1) mod points.len],
                  color, targetKey, blend, thickness)

proc emitTexturedQuad*(gb:         var GeometryBatcher,
                       dst:        Rect,
                       src:        Rect,   ## UV rectangle in [0,1] space
                       textureKey: TextureKey,
                       targetKey:  TextureKey,
                       blend:      SDLBlendMode,
                       tint:       RGBA   = RGBA.white,
                       angle:      float32   = 0.0,
                       pivot:      Point    = point(0.5, 0.5),
                       flipH:      bool      = false,
                       flipV:      bool      = false) =
  ## Emit a (possibly rotated) textured quad.
  ## `src` is in normalised UV space [0,1]×[0,1].
  ## `pivot` is a normalised pivot inside dst (0.5,0.5 = centre).
  let b = gb.currentBatch(textureKey, targetKey, blend)

  # Local corners before rotation
  let pw   = dst.w * pivot.x
  let ph   = dst.h * pivot.y
  var lc: array[4, Point]
  lc[0] = point(-pw,         -ph)
  lc[1] = point(dst.w - pw,  -ph)
  lc[2] = point(dst.w - pw,  dst.h - ph)
  lc[3] = point(-pw,         dst.h - ph)

  # Rotate if needed
  let cx  = dst.x + pw
  let cy  = dst.y + ph
  let cos_a = cos(angle)
  let sin_a = sin(angle)

  var uvs: array[4, Point]
  uvs[0] = point(if flipH: src.x + src.w else: src.x,        if flipV: src.y + src.h else: src.y)
  uvs[1] = point(if flipH: src.x         else: src.x + src.w, if flipV: src.y + src.h else: src.y)
  uvs[2] = point(if flipH: src.x         else: src.x + src.w, if flipV: src.y         else: src.y + src.h)
  uvs[3] = point(if flipH: src.x + src.w else: src.x,        if flipV: src.y         else: src.y + src.h)

  var indices: array[4, uint32]
  for k in 0..3:
    let rx = lc[k].x * cos_a - lc[k].y * sin_a + cx
    let ry = lc[k].x * sin_a + lc[k].y * cos_a + cy
    indices[k] = b.addVertex(Vertex(pos: point(rx, ry), uv: uvs[k], color: tint))

  b.addTriangle(indices[0], indices[1], indices[2])
  b.addTriangle(indices[0], indices[2], indices[3])

proc emitTriangle*(gb:         var GeometryBatcher,
                   p0, p1, p2: Point,
                   c0, c1, c2: RGBA,
                   textureKey: TextureKey,
                   targetKey:  TextureKey,
                   blend:      SDLBlendMode,
                   uv0, uv1, uv2: Point = point(0,0)) =
  ## Emit a single triangle with per-vertex colors and UVs.
  let b  = gb.currentBatch(textureKey, targetKey, blend)
  let i0 = b.addVertex(Vertex(pos: p0, uv: uv0, color: c0))
  let i1 = b.addVertex(Vertex(pos: p1, uv: uv1, color: c1))
  let i2 = b.addVertex(Vertex(pos: p2, uv: uv2, color: c2))
  b.addTriangle(i0, i1, i2)

proc emitRoundedRect*(gb:        var GeometryBatcher,
                      rect:      Rect,
                      radius:    float32,
                      color:     RGBA,
                      targetKey: TextureKey,
                      blend:     SDLBlendMode,
                      filled:    bool = true,
                      cornerSegs: int = 8) =
  ## Emit a filled rounded rectangle.
  ## Decomposed into: 1 center rect + 4 edge rects + 4 corner fans.
  let r  = min(radius, min(rect.w, rect.h) * 0.5)
  let cx0 = rect.x + r;      let cx1 = rect.x + rect.w - r
  let cy0 = rect.y + r;      let cy1 = rect.y + rect.h - r

  if filled:
    # Center body
    gb.emitRect(rect(rect.x + r, rect.y,          rect.w - 2*r, rect.h),          color, targetKey, blend, true)
    gb.emitRect(rect(rect.x,     rect.y + r,      r,            rect.h - 2*r),      color, targetKey, blend, true)
    gb.emitRect(rect(rect.x + rect.w - r, rect.y + r, r, rect.h - 2*r),            color, targetKey, blend, true)

    # Four corners as pie sectors
    let step = 0.5 * Pi / float32(cornerSegs)
    for k in 0 ..< cornerSegs:
      let a0 = float32(k) * step
      let a1 = float32(k+1) * step
      # Bottom-right corner (0 .. π/2)
      gb.emitTriangle(
        point(cx1, cy1),
        point(cx1 + cos(a0)*r, cy1 + sin(a0)*r),
        point(cx1 + cos(a1)*r, cy1 + sin(a1)*r),
        color, color, color, InvalidTextureKey, targetKey, blend)
      # Bottom-left corner (π/2 .. π)
      gb.emitTriangle(
        point(cx0, cy1),
        point(cx0 + cos(Pi*0.5 + a0)*r, cy1 + sin(Pi*0.5 + a0)*r),
        point(cx0 + cos(Pi*0.5 + a1)*r, cy1 + sin(Pi*0.5 + a1)*r),
        color, color, color, InvalidTextureKey, targetKey, blend)
      # Top-left corner (π .. 3π/2)
      gb.emitTriangle(
        point(cx0, cy0),
        point(cx0 + cos(Pi + a0)*r, cy0 + sin(Pi + a0)*r),
        point(cx0 + cos(Pi + a1)*r, cy0 + sin(Pi + a1)*r),
        color, color, color, InvalidTextureKey, targetKey, blend)
      # Top-right corner (3π/2 .. 2π)
      gb.emitTriangle(
        point(cx1, cy0),
        point(cx1 + cos(Pi*1.5 + a0)*r, cy0 + sin(Pi*1.5 + a0)*r),
        point(cx1 + cos(Pi*1.5 + a1)*r, cy0 + sin(Pi*1.5 + a1)*r),
        color, color, color, InvalidTextureKey, targetKey, blend)
  else:
    # Outline — arcs at corners + straight edges
    let step = 0.5 * Pi / float32(cornerSegs)
    for k in 0 ..< cornerSegs:
      for (ox, oy, baseAngle) in [(cx1, cy1, 0.0f), (cx0, cy1, Pi*0.5f),
                                   (cx0, cy0, Pi.float32), (cx1, cy0, Pi*1.5f)]:
        let a0 = baseAngle + float32(k)   * step
        let a1 = baseAngle + float32(k+1) * step
        gb.emitLine(
          point(ox + cos(a0)*r, oy + sin(a0)*r),
          point(ox + cos(a1)*r, oy + sin(a1)*r),
          color, targetKey, blend)
    gb.emitLine(point(cx0, rect.y),        point(cx1, rect.y),        color, targetKey, blend)
    gb.emitLine(point(cx1, rect.y + rect.h), point(cx0, rect.y + rect.h), color, targetKey, blend)
    gb.emitLine(point(rect.x, cy0),        point(rect.x, cy1),        color, targetKey, blend)
    gb.emitLine(point(rect.x + rect.w, cy0), point(rect.x + rect.w, cy1), color, targetKey, blend)

# ---------------------------------------------------------------------------
# Sorting for minimal state changes
# ---------------------------------------------------------------------------

proc sort*(gb: var GeometryBatcher) =
  ## Sort batches to group same target + same texture together.
  ## Stable sort preserves relative order within a group.
  gb.batches.sort(proc(a, b: Batch): int =
    if uint32(a.targetKey) != uint32(b.targetKey):
      return cmp(uint32(a.targetKey), uint32(b.targetKey))
    if uint32(a.textureKey) != uint32(b.textureKey):
      return cmp(uint32(a.textureKey), uint32(b.textureKey))
    return cmp(int(a.blendMode), int(b.blendMode))
  )
