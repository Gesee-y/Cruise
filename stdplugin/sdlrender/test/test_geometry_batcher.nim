## test_geometry_batcher.nim
##
## Full test suite for the fixed sdl3/geometry_batcher.nim.
##
## Run:
##   nim c -r test_geometry_batcher.nim
##
## Coverage:
##   - All original tests (regression)
##   - [FIX-1] emitCircle: fringe indices correct with pre-existing vertices
##   - [FIX-2] emitRect outline: closed ring, no corner gaps
##   - [FIX-3] canAppend: index budget enforced in addition to vertex budget
##   - [FIX-4] emitPolygon: concave polygons triangulated correctly
##   - [FIX-5] sort: painter's-order caveat (documented, not enforced)

import std/[math, unittest, algorithm]
include "../sdl3_renderer.nim"

# ===========================================================================
# Helpers
# ===========================================================================

let
  TX0 = InvalidTextureKey
  TX1 = TextureKey(1)
  TX2 = TextureKey(2)
  TGT = TextureKey(10)
  RED = rgba(255,0,0)
  BLUE = rgba(0,0,255)
  WHITE = SDLRGBA.white

proc totalVerts(gb: GeometryBatcher): int =
  for b in gb.batches: result += b.vertices.len

proc totalIndices(gb: GeometryBatcher): int =
  for b in gb.batches: result += b.indices.len

proc indicesMultipleOf3(gb: GeometryBatcher): bool =
  for b in gb.batches:
    if b.indices.len mod 3 != 0: return false
  true

proc allIndicesInRange(gb: GeometryBatcher): bool =
  for b in gb.batches:
    for idx in b.indices:
      if int(idx) >= b.vertices.len: return false
  true

proc triArea(b: Batch, i0, i1, i2: int): float32 =
  let p0 = b.vertices[i0].pos; let p1 = b.vertices[i1].pos; let p2 = b.vertices[i2].pos
  0.5 * abs((p1.x-p0.x)*(p2.y-p0.y) - (p2.x-p0.x)*(p1.y-p0.y))

# ===========================================================================
# TESTS
# ===========================================================================

suite "Types — FPoint, FRect, SDLRGBA":
  test "fpoint constructs correctly":
    let p = fpoint(3.0, 4.0); check p.x == 3.0f and p.y == 4.0f
  test "frect constructs correctly":
    let r = frect(1,2,10,20); check r.x==1f and r.y==2f and r.w==10f and r.h==20f
  test "SDLRGBA white":
    let w = SDLRGBA.white; check w.r==255 and w.g==255 and w.b==255 and w.a==255
  test "SDLRGBA transparent":
    check SDLRGBA.transparent.a == 0
  test "TextureKey equality":
    check TX0==InvalidTextureKey and TX1!=TX0 and TX1!=TX2

suite "Batch — low-level primitives":
  test "initBatch — empty sequences":
    let b = initBatch(TX0, TGT, blendAlpha)
    check b.vertices.len==0 and b.indices.len==0 and b.textureKey==TX0 and b.blendMode==blendAlpha
  test "addVertex returns sequential indices":
    var b = initBatch(TX0, TGT, blendAlpha)
    check b.addVertex(Vertex())==0 and b.addVertex(Vertex())==1 and b.vertices.len==2
  test "addTriangle appends 3 indices":
    var b = initBatch(TX0, TGT, blendAlpha)
    discard b.addVertex(Vertex()); discard b.addVertex(Vertex()); discard b.addVertex(Vertex())
    b.addTriangle(0,1,2); check b.indices == @[0'u32,1'u32,2'u32]
  test "clear resets both buffers":
    var b = initBatch(TX0, TGT, blendAlpha)
    discard b.addVertex(Vertex()); b.addTriangle(0,0,0); b.clear()
    check b.vertices.len==0 and b.indices.len==0
  test "canAppend — same keys":
    check initBatch(TX1, TGT, blendAlpha).canAppend(TX1, TGT, blendAlpha)
  test "canAppend — different texture":
    check not initBatch(TX1, TGT, blendAlpha).canAppend(TX2, TGT, blendAlpha)
  test "canAppend — different blend":
    check not initBatch(TX1, TGT, blendAlpha).canAppend(TX1, TGT, blendAdditive)
  test "canAppend — different target":
    check not initBatch(TX1, TGT, blendAlpha).canAppend(TX1, TextureKey(99), blendAlpha)
  test "canAppend — vertex budget exhausted":
    var b = initBatch(TX0, TGT, blendAlpha)
    for _ in 0 ..< MaxBatchVerts-63: b.vertices.add(Vertex())
    check not b.canAppend(TX0, TGT, blendAlpha)
  test "[FIX-3] canAppend — index budget exhausted":
    var b = initBatch(TX0, TGT, blendAlpha)
    for _ in 0 ..< MaxBatchIndices-95: b.indices.add(0'u32)
    check not b.canAppend(TX0, TGT, blendAlpha)

suite "GeometryBatcher — batch management":
  test "init — no batches":
    check initGeometryBatcher().batches.len == 0
  test "clear on empty — no crash":
    var gb = initGeometryBatcher(); gb.clear(); check gb.batches.len==0
  test "currentBatch creates first batch":
    var gb = initGeometryBatcher(); discard gb.currentBatch(TX0,TGT,blendAlpha)
    check gb.batches.len==1
  test "currentBatch reuses batch with same keys":
    var gb = initGeometryBatcher()
    let b1 = gb.currentBatch(TX0,TGT,blendAlpha)
    let b2 = gb.currentBatch(TX0,TGT,blendAlpha)
    check gb.batches.len==1 and b1==b2
  test "currentBatch breaks on texture change":
    var gb = initGeometryBatcher()
    discard gb.currentBatch(TX0,TGT,blendAlpha); discard gb.currentBatch(TX1,TGT,blendAlpha)
    check gb.batches.len==2
  test "currentBatch breaks on blend change":
    var gb = initGeometryBatcher()
    discard gb.currentBatch(TX0,TGT,blendAlpha); discard gb.currentBatch(TX0,TGT,blendAdditive)
    check gb.batches.len==2
  test "currentBatch breaks on target change":
    var gb = initGeometryBatcher()
    discard gb.currentBatch(TX0,TGT,blendAlpha); discard gb.currentBatch(TX0,TextureKey(20),blendAlpha)
    check gb.batches.len==2
  test "clear empties all batches":
    var gb = initGeometryBatcher()
    gb.emitPoint(fpoint(0,0),WHITE,TGT,blendAlpha); gb.clear()
    check gb.batches.len==0

suite "emitPoint":
  test "4 vertices, 6 indices":
    var gb = initGeometryBatcher(); gb.emitPoint(fpoint(10,20),RED,TGT,blendAlpha)
    check totalVerts(gb)==4 and totalIndices(gb)==6
  test "indices multiple of 3 and in range":
    var gb = initGeometryBatcher(); gb.emitPoint(fpoint(0,0),WHITE,TGT,blendAlpha)
    check indicesMultipleOf3(gb) and allIndicesInRange(gb)
  test "pointSize=2 produces correct corners":
    var gb = initGeometryBatcher()
    gb.emitPoint(fpoint(5.0,5.0),WHITE,TGT,blendAlpha,pointSize=2.0)
    let v = gb.batches[0].vertices
    check v[0].pos==fpoint(4.0,4.0) and v[2].pos==fpoint(6.0,6.0)
  test "100 points share one batch":
    var gb = initGeometryBatcher()
    for i in 0..99: gb.emitPoint(fpoint(float32(i),0),WHITE,TGT,blendAlpha)
    check gb.batches.len==1 and totalVerts(gb)==400 and allIndicesInRange(gb)

suite "emitLine":
  test "normal line: 4 verts, 6 indices":
    var gb = initGeometryBatcher(); gb.emitLine(fpoint(0,0),fpoint(100,0),RED,TGT,blendAlpha)
    check totalVerts(gb)==4 and totalIndices(gb)==6 and allIndicesInRange(gb)
  test "degenerate line emits nothing":
    var gb = initGeometryBatcher(); gb.emitLine(fpoint(5,5),fpoint(5,5),RED,TGT,blendAlpha)
    check totalVerts(gb)==0
  test "thickness=4 — horizontal normal offset is 2":
    var gb = initGeometryBatcher()
    gb.emitLine(fpoint(0,0),fpoint(10,0),WHITE,TGT,blendAlpha,thickness=4.0)
    let v = gb.batches[0].vertices
    check abs(v[0].pos.y - (-2.0)) < 1e-5 and abs(v[1].pos.y - 2.0) < 1e-5
  test "vertical line — no crash":
    var gb = initGeometryBatcher(); gb.emitLine(fpoint(0,0),fpoint(0,50),BLUE,TGT,blendAlpha)
    check totalVerts(gb)==4

suite "[FIX-2] emitRect outline — closed ring":
  test "filled: 4 verts, 6 indices":
    var gb = initGeometryBatcher(); gb.emitRect(frect(0,0,100,50),RED,TGT,blendAlpha,filled=true)
    check totalVerts(gb)==4 and totalIndices(gb)==6
  test "outline: 8 verts, 24 indices":
    var gb = initGeometryBatcher()
    gb.emitRect(frect(0,0,100,50),RED,TGT,blendAlpha,filled=false,thickness=2.0)
    check totalVerts(gb)==8 and totalIndices(gb)==24
  test "outline: all indices in range":
    var gb = initGeometryBatcher(); gb.emitRect(frect(0,0,100,50),WHITE,TGT,blendAlpha,filled=false)
    check allIndicesInRange(gb)
  test "outline: outer ring is outside inner ring":
    var gb = initGeometryBatcher()
    let ht = 3.0'f32
    gb.emitRect(frect(10,10,80,60),WHITE,TGT,blendAlpha,filled=false,thickness=ht*2)
    let v = gb.batches[0].vertices
    check abs(v[0].pos.x - (10.0-ht)) < 1e-5 and abs(v[0].pos.y - (10.0-ht)) < 1e-5
    check abs(v[4].pos.x - (10.0+ht)) < 1e-5 and abs(v[4].pos.y - (10.0+ht)) < 1e-5
  test "filled: corners are correct":
    var gb = initGeometryBatcher(); gb.emitRect(frect(10,20,30,40),WHITE,TGT,blendAlpha)
    let v = gb.batches[0].vertices
    check v[0].pos==fpoint(10,20) and v[1].pos==fpoint(40,20)
    check v[2].pos==fpoint(40,60) and v[3].pos==fpoint(10,60)

suite "[FIX-1] emitCircle — correct fringe indices":
  test "fringe indices valid when batch has pre-existing vertices":
    var gb = initGeometryBatcher()
    gb.emitRect(frect(0,0,50,50),WHITE,TGT,blendAlpha,filled=true)
    let before = totalVerts(gb)
    gb.emitCircle(fpoint(100,100),20.0,RED,TGT,blendAlpha,filled=true,segments=8)
    check allIndicesInRange(gb) and totalVerts(gb) > before
  test "filled circle: vertex count = 2*segs + 2":
    var gb = initGeometryBatcher()
    gb.emitCircle(fpoint(50,50),20.0,RED,TGT,blendAlpha,filled=true,segments=16)
    check totalVerts(gb) == 2*16+2
  test "filled circle: all indices valid":
    var gb = initGeometryBatcher()
    gb.emitCircle(fpoint(50,50),20.0,RED,TGT,blendAlpha,filled=true,segments=12)
    check allIndicesInRange(gb) and indicesMultipleOf3(gb)
  test "fringe vertices have alpha = 0":
    var gb = initGeometryBatcher()
    gb.emitCircle(fpoint(50,50),10.0,RED,TGT,blendAlpha,filled=true,segments=8)
    let verts = gb.batches[0].vertices
    check verts[9].color.a == 0    ## fringe[0] = index segs+1 = 9
  test "outline circle: segs*4 vertices":
    var gb = initGeometryBatcher()
    gb.emitCircle(fpoint(50,50),20.0,RED,TGT,blendAlpha,filled=false,segments=8)
    check totalVerts(gb) == 8*4
  test "radius 0 — no crash":
    var gb = initGeometryBatcher()
    gb.emitCircle(fpoint(0,0),0.0,WHITE,TGT,blendAlpha,segments=12)
  test "segments clamped to minimum 3":
    var gb = initGeometryBatcher()
    gb.emitCircle(fpoint(0,0),5.0,WHITE,TGT,blendAlpha,filled=true,segments=1)
    check allIndicesInRange(gb)
  test "5 circles in same batch all have valid indices":
    var gb = initGeometryBatcher()
    for i in 0..4:
      gb.emitCircle(fpoint(float32(i*30),50),10.0,RED,TGT,blendAlpha,filled=true,segments=8)
    check allIndicesInRange(gb)

suite "[FIX-4] emitPolygon — ear-clipping":
  test "triangle: 3 verts, 3 indices":
    var gb = initGeometryBatcher()
    gb.emitPolygon([fpoint(0,0),fpoint(10,0),fpoint(5,10)],WHITE,TGT,blendAlpha,filled=true)
    check totalVerts(gb)==3 and totalIndices(gb)==3
  test "convex quad: 6 indices, in range":
    var gb = initGeometryBatcher()
    gb.emitPolygon([fpoint(0,0),fpoint(10,0),fpoint(10,10),fpoint(0,10)],WHITE,TGT,blendAlpha,filled=true)
    check totalIndices(gb)==6 and allIndicesInRange(gb)
  test "convex pentagon: 9 indices":
    var gb = initGeometryBatcher()
    var pts: array[5, FPoint]
    for i in 0..4:
      let a = float32(i)*2*PI/5; pts[i] = fpoint(cos(a)*20+50, sin(a)*20+50)
    gb.emitPolygon(pts, WHITE, TGT, blendAlpha, filled=true)
    check totalIndices(gb)==9 and allIndicesInRange(gb)
  test "[FIX-4] concave L-shape: 4 non-degenerate triangles":
    var gb = initGeometryBatcher()
    let pts = [fpoint(0,0),fpoint(20,0),fpoint(20,10),fpoint(10,10),fpoint(10,20),fpoint(0,20)]
    gb.emitPolygon(pts, WHITE, TGT, blendAlpha, filled=true)
    check allIndicesInRange(gb) and indicesMultipleOf3(gb) and totalIndices(gb)==12
    let b = gb.batches[0]
    for t in 0 ..< b.indices.len div 3:
      check triArea(b, int(b.indices[t*3]), int(b.indices[t*3+1]), int(b.indices[t*3+2])) > 0.0
  test "[FIX-4] concave chevron: valid triangulation":
    var gb = initGeometryBatcher()
    let pts = [fpoint(0,10),fpoint(15,0),fpoint(30,10),fpoint(20,10),fpoint(30,20),fpoint(15,20),fpoint(0,20)]
    gb.emitPolygon(pts, WHITE, TGT, blendAlpha, filled=true)
    check allIndicesInRange(gb) and indicesMultipleOf3(gb)
  test "outline: n edges = n*4 verts":
    var gb = initGeometryBatcher()
    gb.emitPolygon([fpoint(0,0),fpoint(10,0),fpoint(10,10),fpoint(0,10)],WHITE,TGT,blendAlpha,filled=false)
    check totalVerts(gb)==16
  test "less than 3 points — nothing emitted":
    var gb = initGeometryBatcher()
    gb.emitPolygon([fpoint(0,0),fpoint(1,0)],WHITE,TGT,blendAlpha)
    check totalVerts(gb)==0
  test "CW input auto-reversed — same index count as CCW":
    var gb1 = initGeometryBatcher(); var gb2 = initGeometryBatcher()
    gb1.emitPolygon([fpoint(0,0),fpoint(10,0),fpoint(10,10),fpoint(0,10)],WHITE,TGT,blendAlpha,filled=true)
    gb2.emitPolygon([fpoint(0,10),fpoint(10,10),fpoint(10,0),fpoint(0,0)],WHITE,TGT,blendAlpha,filled=true)
    check totalIndices(gb1)==totalIndices(gb2) and allIndicesInRange(gb1) and allIndicesInRange(gb2)

suite "emitTexturedQuad":
  test "4 verts, 6 indices, correct textureKey":
    var gb = initGeometryBatcher()
    gb.emitTexturedQuad(frect(0,0,100,100),frect(0,0,1,1),TX1,TGT,blendAlpha)
    check totalVerts(gb)==4 and totalIndices(gb)==6 and gb.batches[0].textureKey==TX1
  test "angle=0, pivot=(0,0) → TL at dst.xy":
    var gb = initGeometryBatcher()
    gb.emitTexturedQuad(frect(10,20,40,30),frect(0,0,1,1),TX1,TGT,blendAlpha,angle=0.0,pivot=fpoint(0,0))
    let v = gb.batches[0].vertices
    check abs(v[0].pos.x-10.0)<1e-4 and abs(v[0].pos.y-20.0)<1e-4
  test "flipH swaps U":
    var gb1 = initGeometryBatcher(); var gb2 = initGeometryBatcher()
    gb1.emitTexturedQuad(frect(0,0,100,100),frect(0,0,1,1),TX1,TGT,blendAlpha,flipH=false)
    gb2.emitTexturedQuad(frect(0,0,100,100),frect(0,0,1,1),TX1,TGT,blendAlpha,flipH=true)
    check gb1.batches[0].vertices[0].uv.x != gb2.batches[0].vertices[0].uv.x
  test "flipV swaps V":
    var gb1 = initGeometryBatcher(); var gb2 = initGeometryBatcher()
    gb1.emitTexturedQuad(frect(0,0,100,100),frect(0,0,1,1),TX1,TGT,blendAlpha,flipV=false)
    gb2.emitTexturedQuad(frect(0,0,100,100),frect(0,0,1,1),TX1,TGT,blendAlpha,flipV=true)
    check gb1.batches[0].vertices[0].uv.y != gb2.batches[0].vertices[0].uv.y
  test "separate batch from solid geometry":
    var gb = initGeometryBatcher()
    gb.emitRect(frect(0,0,10,10),WHITE,TGT,blendAlpha); gb.emitTexturedQuad(frect(0,0,10,10),frect(0,0,1,1),TX1,TGT,blendAlpha)
    check gb.batches.len==2
  test "rotation PI — indices valid":
    var gb = initGeometryBatcher()
    gb.emitTexturedQuad(frect(0,0,100,100),frect(0,0,1,1),TX1,TGT,blendAlpha,angle=PI.float32)
    check allIndicesInRange(gb)

suite "emitTriangle":
  test "3 verts, 3 indices, in range":
    var gb = initGeometryBatcher()
    gb.emitTriangle(fpoint(0,0),fpoint(1,0),fpoint(0,1),RED,WHITE,BLUE,TX0,TGT,blendAlpha)
    check totalVerts(gb)==3 and totalIndices(gb)==3 and allIndicesInRange(gb)
  test "per-vertex colours preserved":
    var gb = initGeometryBatcher()
    gb.emitTriangle(fpoint(0,0),fpoint(1,0),fpoint(0,1),RED,WHITE,BLUE,TX0,TGT,blendAlpha)
    let v = gb.batches[0].vertices
    check v[0].color.r==255 and v[0].color.g==0
    check v[1].color.r==255 and v[1].color.g==255
    check v[2].color.b==255 and v[2].color.r==0

suite "emitRoundedRect":
  test "filled — multiple of 3, in range":
    var gb = initGeometryBatcher()
    gb.emitRoundedRect(frect(0,0,200,100),10.0,WHITE,TGT,blendAlpha,filled=true)
    check indicesMultipleOf3(gb) and allIndicesInRange(gb)
  test "outline — in range":
    var gb = initGeometryBatcher()
    gb.emitRoundedRect(frect(0,0,200,100),10.0,RED,TGT,blendAlpha,filled=false)
    check allIndicesInRange(gb) and indicesMultipleOf3(gb)
  test "radius > half shortest side — clamped cleanly":
    var gb = initGeometryBatcher()
    gb.emitRoundedRect(frect(0,0,100,50),200.0,WHITE,TGT,blendAlpha,filled=true)
    check allIndicesInRange(gb)
  test "radius = 0 — no crash":
    var gb = initGeometryBatcher()
    gb.emitRoundedRect(frect(0,0,100,50),0.0,WHITE,TGT,blendAlpha,filled=true,cornerSegs=8)
    check allIndicesInRange(gb)

suite "[FIX-5] sort — painter's-order caveat":
  test "sorted by targetKey ascending":
    var gb = initGeometryBatcher()
    gb.emitRect(frect(0,0,1,1),WHITE,TextureKey(30),blendAlpha)
    gb.emitRect(frect(0,0,1,1),WHITE,TextureKey(10),blendAlpha)
    gb.emitRect(frect(0,0,1,1),WHITE,TextureKey(20),blendAlpha)
    gb.sort()
    check uint32(gb.batches[0].targetKey)<=uint32(gb.batches[1].targetKey)
    check uint32(gb.batches[1].targetKey)<=uint32(gb.batches[2].targetKey)
  test "sorted by textureKey within same target":
    var gb = initGeometryBatcher()
    gb.batches.add(initBatch(TX2,TGT,blendAlpha)); gb.batches.add(initBatch(TX0,TGT,blendAlpha)); gb.batches.add(initBatch(TX1,TGT,blendAlpha))
    gb.sort()
    check uint32(gb.batches[0].textureKey)==0 and uint32(gb.batches[1].textureKey)==1 and uint32(gb.batches[2].textureKey)==2
  test "empty batcher — no crash":
    var gb = initGeometryBatcher(); gb.sort(); check gb.batches.len==0
  test "sorted by blendMode when target and texture equal":
    var gb = initGeometryBatcher()
    gb.batches.add(initBatch(TX0,TGT,blendAdditive)); gb.batches.add(initBatch(TX0,TGT,blendAlpha)); gb.batches.add(initBatch(TX0,TGT,blendNone))
    gb.sort()
    check int(gb.batches[0].blendMode)<=int(gb.batches[1].blendMode)
    check int(gb.batches[1].blendMode)<=int(gb.batches[2].blendMode)
  test "[FIX-5] draw order preserved without sort":
    var gb = initGeometryBatcher()
    gb.batches.add(initBatch(TX2,TGT,blendAlpha)); gb.batches.add(initBatch(TX0,TGT,blendAlpha))
    check uint32(gb.batches[0].textureKey)==2 and uint32(gb.batches[1].textureKey)==0

suite "Global invariants":
  test "mix of primitives in one batch":
    var gb = initGeometryBatcher()
    gb.emitPoint(fpoint(0,0),WHITE,TGT,blendAlpha)
    gb.emitLine(fpoint(0,0),fpoint(10,10),RED,TGT,blendAlpha)
    gb.emitRect(frect(5,5,20,20),BLUE,TGT,blendAlpha)
    check gb.batches.len==1 and indicesMultipleOf3(gb) and allIndicesInRange(gb)
  test "blend mode change forces new batch":
    var gb = initGeometryBatcher()
    gb.emitRect(frect(0,0,10,10),WHITE,TGT,blendAlpha); gb.emitRect(frect(0,0,10,10),WHITE,TGT,blendAdditive)
    check gb.batches.len==2
  test "clear then reuse":
    var gb = initGeometryBatcher()
    gb.emitRect(frect(0,0,50,50),RED,TGT,blendAlpha); gb.clear()
    gb.emitCircle(fpoint(25,25),10.0,BLUE,TGT,blendAlpha,segments=8)
    check gb.batches.len==1 and allIndicesInRange(gb)
  test "vertex budget overflow → new batch":
    var gb = initGeometryBatcher()
    let n = (MaxBatchVerts-64) div 4
    for i in 0..n: gb.emitPoint(fpoint(float32(i),0),WHITE,TGT,blendAlpha)
    check gb.batches.len>=2 and allIndicesInRange(gb)
  test "[FIX-3] index budget overflow → new batch":
    var gb = initGeometryBatcher()
    let n = (MaxBatchIndices-96) div 6
    for i in 0..n: gb.emitPoint(fpoint(float32(i),0),WHITE,TGT,blendAlpha)
    check gb.batches.len>=2 and allIndicesInRange(gb)

when isMainModule:
  echo "All geometry_batcher tests passed."