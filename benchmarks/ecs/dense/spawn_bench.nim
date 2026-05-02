include "../../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../../src/profile/benchmarks.nim"

const SAMPLE = 10000
const WARMUP = 1
const ENTITY_COUNT = 1000

type
  A = object
    x: int

  C[N] = object
    x: int

# ---------------------------------
# Entity creation
# ---------------------------------

proc spawnOneZst(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Spawn dense entities")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "spawn one " & $eCount & " entity zst",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      
      var ents:seq[DenseHandle]
      for i in 0..<eCount:
        ents.add w.createEntity(A)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        discard w.createEntity(A)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc spawnManyZst(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Spawn dense entities")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "spawn many " & $eCount & " entity zst",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      
      var ents:seq[DenseHandle]
      for i in 0..<eCount:
        ents.add w.createEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13], C[14])
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        discard w.createEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13], C[14])
    )
  )
  showDetailed(suite.benchmarks[^1])

proc spawnOne(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Spawn dense entities")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "spawn one " & $eCount & " entity",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      
      var ents:seq[DenseHandle]
      for i in 0..<eCount:
        ents.add w.createEntity(A)
      for e in ents.mitems:
        w.deleteEntity(e)

      var a = w.get(A)
    ),
    (
      for i in 0..<eCount:
        let e = w.createEntity(A)
        a[e] = A(x:1)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc spawnMany(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Spawn dense entities")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "spawn many " & $eCount & " entity",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      
      var ents:seq[DenseHandle]
      for i in 0..<eCount:
        ents.add w.createEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13], C[14])
      for e in ents.mitems:
        w.deleteEntity(e)

      var c0 = w.get(C[0])
      var c1 = w.get(C[1])
      var c2 = w.get(C[2])
      var c3 = w.get(C[3])
      var c4 = w.get(C[4])
      var c5 = w.get(C[5])
      var c6 = w.get(C[6])
      var c7 = w.get(C[7])
      var c8 = w.get(C[8])
      var c9 = w.get(C[9])
      var c10 = w.get(C[10])
      var c11 = w.get(C[11])
      var c12 = w.get(C[12])
      var c13 = w.get(C[13])
      var c14 = w.get(C[14])
    ),
    (
      for i in 0..<eCount:
        let e = w.createEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13], C[14])

        c0[e] = C[0](x: 1)
        c1[e] = C[1](x: 1)
        c2[e] = C[2](x: 1)
        c3[e] = C[3](x: 1)
        c4[e] = C[4](x: 1)
        c5[e] = C[5](x: 1)
        c6[e] = C[6](x: 1)
        c7[e] = C[7](x: 1)
        c8[e] = C[8](x: 1)
        c9[e] = C[9](x: 1)
        c10[e] = C[10](x: 1)
        c11[e] = C[11](x: 1)
        c12[e] = C[12](x: 1)
        c13[e] = C[13](x: 1)
        c14[e] = C[14](x: 1)
    )
  )
  showDetailed(suite.benchmarks[^1])

spawnOneZst(eCount=10_000)
spawnManyZst(eCount=2_000)
spawnOne(eCount=10_000)
spawnMany(eCount=2_000)