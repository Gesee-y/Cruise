include "../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

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

proc iterBase(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  suite.add benchmarkWithSetup(
    "iteration dense",
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

proc iterSparseBase(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  suite.add benchmarkWithSetup(
    "iteration sparse",
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
        var x = addr posc.sparse[bid].data.x
        let dx = addr velc.sparse[bid].data.x

        for i in r:
          x[i] += dx[i]
    )
  )
  showDetailed(suite.benchmarks[^1])  