include "../../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../../src/profile/benchmarks.nim"

const SAMPLE = 100
const WARMUP = 1
const ENTITY_COUNT = 10000

type
  A = object
    x: int

  Mat4 = object
    m1,m2,m3,m4,m5,m6,m7,m8,m9,m10,m11,m12,m13,m14,m15,m16: float32

  Mat[N: static int] = object
    m1,m2,m3,m4,m5,m6,m7,m8,m9,m10,m11,m12,m13,m14,m15,m16: float32

  B = object
    m: Mat4

  C = object
    m: Mat4

  D = object
    m: Mat4

  E = object
    m: Mat4

  F = object
    m: Mat4

  Z[N: static int] = object


proc addRemoveDense(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("add remove dense")
  suite.add benchmarkWithSetup(
    "add/remove dense",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[DenseHandle] = w.createEntities(eCount)
      
      for e in ents:
        w.addComponent(e, A)
      for e in ents:
        w.removeComponent(e, A)
    ),
    (
      for e in ents:
        w.addComponent(e, A)
        w.removeComponent(e, A)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc addRemoveSparse(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("add remove sparse")
  suite.add benchmarkWithSetup(
    "add/remove sparse",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(eCount)
      
      for e in ents.mitems:
        w.addComponent(e, A)
      for e in ents.mitems:
        w.removeComponent(e, A)
    ),
    (
      for e in ents.mitems:
        w.addComponent(e, A)
        w.removeComponent(e, A)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc addRemoveBigDense(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("add remove big dense")
  suite.add benchmarkWithSetup(
    "add/remove big dense",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[DenseHandle] = w.createEntities(eCount, Mat[0], Mat[1], Mat[2], Mat[3], Mat[4])
      
      for e in ents:
        w.addComponent(e, Mat4)
      for e in ents:
        w.removeComponent(e, Mat4)
    ),
    (
      for e in ents:
        w.addComponent(e, Mat4)
        w.removeComponent(e, Mat4)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc addRemoveBigSparse(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("add remove big sparse")
  suite.add benchmarkWithSetup(
    "add/remove big sparse",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(eCount, Mat[0], Mat[1], Mat[2], Mat[3], Mat[4])
      
      for e in ents.mitems:
        w.addComponent(e, Mat4)
      for e in ents.mitems:
        w.removeComponent(e, Mat4)
    ),
    (
      for e in ents.mitems:
        w.addComponent(e, Mat4)
        w.removeComponent(e, Mat4)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc addRemoveVeryBigDense(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("add remove very big dense")
  suite.add benchmarkWithSetup(
    "add/remove very big dense",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[DenseHandle] = w.createEntities(eCount, Mat[0], Mat[1], Mat[2], Mat[3], Mat[4], 
        Mat[5], Mat[6], Mat[7], Mat[8], Mat[9], Mat[10], Mat[11], Mat[12], Mat[13], Mat[14], Mat[15], Mat[16], Mat[17], Mat[18], Mat[19],
        Mat[20], Mat[21], Mat[22], Mat[23], Mat[24], Mat[25], Mat[26], Mat[27], Mat[28], Mat[29], Mat[30], Mat[31], Mat[32], Mat[33], Mat[34],
        Z[0], Z[1], Z[2], Z[3], Z[4], Z[5], Z[6], B, C, D, E, F)
      
      for e in ents:
        w.addComponent(e, Mat[43], Mat[44], Mat[45], Mat[46], Mat[47], Mat[48], Mat[49])
      for e in ents:
        w.removeComponent(e, Mat[43], Mat[44], Mat[45], Mat[46], Mat[47], Mat[48], Mat[49])
    ),
    (
      for e in ents:
        w.addComponent(e, Mat[43], Mat[44], Mat[45], Mat[46], Mat[47], Mat[48], Mat[49])
        w.removeComponent(e, Mat[43], Mat[44], Mat[45], Mat[46], Mat[47], Mat[48], Mat[49])
        w.removeComponent(e, Z[0], Z[1], Z[2], Z[3], Z[4], Z[5], Z[6])
    )
  )
  showDetailed(suite.benchmarks[^1])

proc addRemoveVeryBigSparse(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("add remove very big sparse")
  suite.add benchmarkWithSetup(
    "add/remove very big sparse",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(eCount, Mat[0], Mat[1], Mat[2], Mat[3], Mat[4], 
        Mat[5], Mat[6], Mat[7], Mat[8], Mat[9], Mat[10], Mat[11], Mat[12], Mat[13], Mat[14], Mat[15], Mat[16], Mat[17], Mat[18], Mat[19],
        Mat[20], Mat[21], Mat[22], Mat[23], Mat[24], Mat[25], Mat[26], Mat[27], Mat[28], Mat[29], Mat[30], Mat[31], Mat[32], Mat[33], Mat[34],
        Z[0], Z[1], Z[2], Z[3], Z[4], Z[5], Z[6], B, C, D, E, F)
      
      for e in ents.mitems:
        w.addComponent(e, Mat[43], Mat[44], Mat[45], Mat[46], Mat[47], Mat[48], Mat[49])
      for e in ents.mitems:
        w.removeComponent(e, Mat[43], Mat[44], Mat[45], Mat[46], Mat[47], Mat[48], Mat[49])
    ),
    (
      for e in ents.mitems:
        w.addComponent(e, Mat[43], Mat[44], Mat[45], Mat[46], Mat[47], Mat[48], Mat[49])
        w.removeComponent(e, Mat[43], Mat[44], Mat[45], Mat[46], Mat[47], Mat[48], Mat[49])
        w.removeComponent(e, Z[0], Z[1], Z[2], Z[3], Z[4], Z[5], Z[6])
    )
  )
  showDetailed(suite.benchmarks[^1])

addRemoveDense()
addRemoveSparse()
addRemoveBigDense()
addRemoveBigSparse()
addRemoveVeryBigDense()
addRemoveVeryBigSparse()
