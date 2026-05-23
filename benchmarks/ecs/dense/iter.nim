import "../../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
import "../../../src/profile/benchmarks.nim"

import macros
const SAMPLE = 1000
const WARMUP = 1
const ENTITY_COUNT = 10000

# =========================
# Components
# =========================

type
  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Pos[N: static int] = object
    x, y: float32

  Vel[N: static int] = object
    x, y: float32

  A[N: static int] = object
    f: float32

macro initVariant(w: untyped, eCount: untyped, n: static int) =
  var code = newNimNode(nnkStmtList)
  for i in 0..<n:
    code.add quote do:
      discard `w`.createEntities(`eCount`, A[`i`], A[`n`])

  return code

macro initSparseVariant(w: untyped, eCount: untyped, n: static int) =
  var code = newNimNode(nnkStmtList)
  for i in 0..<n:
    code.add quote do:
      discard `w`.createSparseEntities(`eCount`, A[`i`], A[`n`])

  return code

proc iterBase(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter dense entities")
  suite.add benchmarkWithSetup(
    "iteration dense",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[DenseHandle] = w.createEntities(eCount, Position, Velocity)
      let q2 = w.denseQueryCache(query(w, Position and Velocity))
      var posc = w.get(Position, true)
      let velc = w.get(Velocity)
    ),
    (
      for (bid, r) in w.denseQuery(query(w, Position and Velocity)):
        var x = addr posc.blocks[bid].data.x
        let dx = addr velc.blocks[bid].data.x

        for i in r:
          x[i] += dx[i]
    )
  )
  showDetailed(suite.benchmarks[^1]) 

proc iterBaseNoDetection(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter dense entities no detection")
  suite.add benchmarkWithSetup(
    "iteration dense no detection",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[DenseHandle] = w.createEntities(eCount, Position, Velocity)
      let q2 = w.denseQueryCache(query(w, Position and Velocity))
      var posc = w.get(Position)
      let velc = w.get(Velocity)
    ),
    (
      for (bid, r) in w.denseQuery(query(w, Position and Velocity)):
        var x = addr posc.blocks[bid].data.x
        let dx = addr velc.blocks[bid].data.x

        for i in r:
          x[i] += dx[i]
    )
  )
  showDetailed(suite.benchmarks[^1])

proc iterWide(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter dense entities wide")
  suite.add benchmarkWithSetup(
    "iteration dense wide",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[DenseHandle] = w.createEntities(eCount, Pos[0], Vel[0], Pos[1], Vel[1], Pos[2], Vel[2], Pos[3], Vel[3])
      let q2 = w.denseQueryCache(query(w, Pos[0] and Vel[0] and Pos[1] and Vel[1] and Pos[2] and Vel[2] and Pos[3] and Vel[3]))
      var pos0c = w.get(Pos[0], true)
      let vel0c = w.get(Vel[0])
      var pos1c = w.get(Pos[1], true)
      let vel1c = w.get(Vel[1])
      var pos2c = w.get(Pos[2], true)
      let vel2c = w.get(Vel[2])
      var pos3c = w.get(Pos[3], true)
      let vel3c = w.get(Vel[3])
    ),
    (
      for (bid, r) in q2:
        var x0 = addr pos0c.blocks[bid].data.x
        let dx0 = addr vel0c.blocks[bid].data.x
        var x1 = addr pos1c.blocks[bid].data.x
        let dx1 = addr vel1c.blocks[bid].data.x
        var x2 = addr pos2c.blocks[bid].data.x
        let dx2 = addr vel2c.blocks[bid].data.x
        var x3 = addr pos3c.blocks[bid].data.x
        let dx3 = addr vel3c.blocks[bid].data.x

        for i in r:
          x0[i] += dx0[i]
          x1[i] += dx1[i]
          x2[i] += dx2[i]
          x3[i] += dx3[i]
    )
  )
  showDetailed(suite.benchmarks[^1])  

proc iterWideNoDetection(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter dense entities wide no detection")
  suite.add benchmarkWithSetup(
    "iteration dense wide no detection",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[DenseHandle] = w.createEntities(eCount, Pos[0], Vel[0], Pos[1], Vel[1], Pos[2], Vel[2], Pos[3], Vel[3])
      let q2 = w.denseQueryCache(query(w, Pos[0] and Vel[0] and Pos[1] and Vel[1] and Pos[2] and Vel[2] and Pos[3] and Vel[3]))
      var pos0c = w.get(Pos[0])
      let vel0c = w.get(Vel[0])
      var pos1c = w.get(Pos[1])
      let vel1c = w.get(Vel[1])
      var pos2c = w.get(Pos[2])
      let vel2c = w.get(Vel[2])
      var pos3c = w.get(Pos[3])
      let vel3c = w.get(Vel[3])
    ),
    (
      for (bid, r) in q2:
        var x0 = addr pos0c.blocks[bid].data.x
        let dx0 = addr vel0c.blocks[bid].data.x
        var x1 = addr pos1c.blocks[bid].data.x
        let dx1 = addr vel1c.blocks[bid].data.x
        var x2 = addr pos2c.blocks[bid].data.x
        let dx2 = addr vel2c.blocks[bid].data.x
        var x3 = addr pos3c.blocks[bid].data.x
        let dx3 = addr vel3c.blocks[bid].data.x

        for i in r:
          x0[i] += dx0[i]
          x1[i] += dx1[i]
          x2[i] += dx2[i]
          x3[i] += dx3[i]
    )
  )
  showDetailed(suite.benchmarks[^1]) 

proc iterFrag(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter dense entities frag")
  suite.add benchmarkWithSetup(
    "iteration dense frag",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      w.initVariant(eCount, 26)
      var a26 = w.get(A[26])
      for (bid, r) in w.denseQuery(query(w, A[26])):
        var x = addr a26.blocks[bid].data.f

        for i in r:
          x[i] *= 2
    ),
    (
      for (bid, r) in w.denseQuery(query(w, A[26])):
        var x = addr a26.blocks[bid].data.f

        for i in r:
          x[i] *= 2
    )
  )
  showDetailed(suite.benchmarks[^1])

proc iterSparseBase(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter sparse entities")
  suite.add benchmarkWithSetup(
    "iteration sparse",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(eCount, Position, Velocity)
      let q2 = w.denseQueryCache(query(w, Position and Velocity))
      var posc = w.get(Position, true)
      let velc = w.get(Velocity)
    ),
    (
      for (sid, r) in w.sparseQuery(query(w, Position and Velocity)):
        let pid = posc.toSparse[sid]-1
        let vid = velc.toSparse[sid]-1
        var x = addr posc.sparse[pid].data.x
        let dx = addr velc.sparse[vid].data.x

        for i in r:
          x[i] += dx[i]
    )
  )
  showDetailed(suite.benchmarks[^1])

proc iterSparseBaseNoDetection(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter sparse entities no detection")
  suite.add benchmarkWithSetup(
    "iteration sparse no detection",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(eCount, Position, Velocity)
      let q2 = w.denseQueryCache(query(w, Position and Velocity))
      var posc = w.get(Position)
      let velc = w.get(Velocity)
    ),
    (
      for (sid, r) in w.sparseQuery(query(w, Position and Velocity)):
        let pid = posc.toSparse[sid]-1
        let vid = velc.toSparse[sid]-1
        var x = addr posc.sparse[pid].data.x
        let dx = addr velc.sparse[vid].data.x

        for i in r:
          x[i] += dx[i]
    )
  )
  showDetailed(suite.benchmarks[^1])

proc iterSparseWide(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter sparse wide entities")
  suite.add benchmarkWithSetup(
    "iteration sparse wide",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(eCount, Pos[0], Vel[0], Pos[1], Vel[1], Pos[2], Vel[2], Pos[3], Vel[3])
      let sig = w.query(Pos[0] and Vel[0] and Pos[1] and Vel[1] and Pos[2] and Vel[2] and Pos[3] and Vel[3])
      var pos0c = w.get(Pos[0], true)
      let vel0c = w.get(Vel[0])
      var pos1c = w.get(Pos[1], true)
      let vel1c = w.get(Vel[1])
      var pos2c = w.get(Pos[2], true)
      let vel2c = w.get(Vel[2])
      var pos3c = w.get(Pos[3], true)
      let vel3c = w.get(Vel[3])
    ),
    (
      for (sid, r) in w.sparseQuery(sig):
        let pid0 = pos0c.toSparse[sid]-1
        let pid1 = pos1c.toSparse[sid]-1
        let pid2 = pos2c.toSparse[sid]-1
        let pid3 = pos3c.toSparse[sid]-1

        let vid0 = vel0c.toSparse[sid]-1
        let vid1 = vel1c.toSparse[sid]-1
        let vid2 = vel2c.toSparse[sid]-1
        let vid3 = vel3c.toSparse[sid]-1
        var x0 = addr pos0c.sparse[pid0].data.x
        let dx0 = addr vel0c.sparse[vid0].data.x
        var x1 = addr pos1c.sparse[pid1].data.x
        let dx1 = addr vel1c.sparse[vid1].data.x
        var x2 = addr pos2c.sparse[pid2].data.x
        let dx2 = addr vel2c.sparse[vid2].data.x
        var x3 = addr pos3c.sparse[pid3].data.x
        let dx3 = addr vel3c.sparse[vid3].data.x

        for i in r:
          x0[i] += dx0[i]
          x1[i] += dx1[i]
          x2[i] += dx2[i]
          x3[i] += dx3[i]
    )
  )
  showDetailed(suite.benchmarks[^1])  

proc iterSparseWideNoDetection(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter sparse wide entities no detection")
  suite.add benchmarkWithSetup(
    "iteration sparse wide no detection",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(eCount, Pos[0], Vel[0], Pos[1], Vel[1], Pos[2], Vel[2], Pos[3], Vel[3])
      let sig = w.query(Pos[0] and Vel[0] and Pos[1] and Vel[1] and Pos[2] and Vel[2] and Pos[3] and Vel[3])
      var pos0c = w.get(Pos[0])
      let vel0c = w.get(Vel[0])
      var pos1c = w.get(Pos[1])
      let vel1c = w.get(Vel[1])
      var pos2c = w.get(Pos[2])
      let vel2c = w.get(Vel[2])
      var pos3c = w.get(Pos[3])
      let vel3c = w.get(Vel[3])
    ),
    (
      for (sid, r) in w.sparseQuery(sig):
        let pid0 = pos0c.toSparse[sid]-1
        let pid1 = pos1c.toSparse[sid]-1
        let pid2 = pos2c.toSparse[sid]-1
        let pid3 = pos3c.toSparse[sid]-1

        let vid0 = vel0c.toSparse[sid]-1
        let vid1 = vel1c.toSparse[sid]-1
        let vid2 = vel2c.toSparse[sid]-1
        let vid3 = vel3c.toSparse[sid]-1
        var x0 = addr pos0c.sparse[pid0].data.x
        let dx0 = addr vel0c.sparse[vid0].data.x
        var x1 = addr pos1c.sparse[pid1].data.x
        let dx1 = addr vel1c.sparse[vid1].data.x
        var x2 = addr pos2c.sparse[pid2].data.x
        let dx2 = addr vel2c.sparse[vid2].data.x
        var x3 = addr pos3c.sparse[pid3].data.x
        let dx3 = addr vel3c.sparse[vid3].data.x

        for i in r:
          x0[i] += dx0[i]
          x1[i] += dx1[i]
          x2[i] += dx2[i]
          x3[i] += dx3[i]
    )
  )
  showDetailed(suite.benchmarks[^1])

proc iterSparseFrag(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("iter sparse entities frag")
  suite.add benchmarkWithSetup(
    "iteration sparse frag",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      w.initSparseVariant(eCount, 26)
      var a26 = w.get(A[26])
    ),
    (
      for (bid, r) in w.sparseQuery(query(w, A[26])):
        var x = addr a26.sparse[a26.toSparse[bid]-1].data.f

        for i in r:
          x[i] *= 2
    )
  )
  showDetailed(suite.benchmarks[^1])

iterBase(10000)
iterSparseBase(10000)
iterWide(10000)
iterSparseWide(10000)
iterFrag(20)

iterBaseNoDetection(10000)
iterSparseBaseNoDetection(10000)
iterWideNoDetection(10000)
iterSparseWideNoDetection(10000)
iterSparseFrag(20)
