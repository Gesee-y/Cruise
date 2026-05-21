include "../../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../../src/profile/benchmarks.nim"

const SAMPLE = 1000
const WARMUP = 1
const ENTITY_COUNT = 2000

type
  A = object
    x: int

  C[N] = object
    x: int

proc insertManyDense(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Insert dense Component")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "Insert many " & $eCount & " dense entity",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      discard w.registerComponent(C[0]); discard w.registerComponent(C[1]); discard w.registerComponent(C[2]); discard w.registerComponent(C[3])
      discard w.registerComponent(C[4]); discard w.registerComponent(C[5]); discard w.registerComponent(C[6]); discard w.registerComponent(C[7])
      discard w.registerComponent(C[8]); discard w.registerComponent(C[9]); discard w.registerComponent(C[10]); discard w.registerComponent(C[11])
      discard w.registerComponent(C[12]); discard w.registerComponent(C[13]); discard w.registerComponent(C[14])

      var ents: seq[DenseHandle]
      for i in 0..<eCount:
        var e = w.createEntity()
        w.addComponent(e, C[0].toComponentId)
        w.addComponent(e, C[1].toComponentId)
        w.addComponent(e, C[2].toComponentId)
        w.addComponent(e, C[3].toComponentId)
        w.addComponent(e, C[4].toComponentId)
        w.addComponent(e, C[5].toComponentId)
        w.addComponent(e, C[6].toComponentId)
        w.addComponent(e, C[7].toComponentId)
        w.addComponent(e, C[8].toComponentId)
        w.addComponent(e, C[9].toComponentId)
        w.addComponent(e, C[10].toComponentId)
        w.addComponent(e, C[11].toComponentId)
        w.addComponent(e, C[12].toComponentId)
        w.addComponent(e, C[13].toComponentId)
        w.addComponent(e, C[14].toComponentId)
        ents.add(e)

      for e in ents:
        w.deleteEntity(e)

    ),
    (
      for i in 0..<eCount:
        var e = w.createEntity()
        w.addComponent(e, C[0].toComponentId)
        w.addComponent(e, C[1].toComponentId)
        w.addComponent(e, C[2].toComponentId)
        w.addComponent(e, C[3].toComponentId)
        w.addComponent(e, C[4].toComponentId)
        w.addComponent(e, C[5].toComponentId)
        w.addComponent(e, C[6].toComponentId)
        w.addComponent(e, C[7].toComponentId)
        w.addComponent(e, C[8].toComponentId)
        w.addComponent(e, C[9].toComponentId)
        w.addComponent(e, C[10].toComponentId)
        w.addComponent(e, C[11].toComponentId)
        w.addComponent(e, C[12].toComponentId)
        w.addComponent(e, C[13].toComponentId)
        w.addComponent(e, C[14].toComponentId)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc insertManySparse(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Insert sparse Component")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "Insert many " & $eCount & " sparse entity",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents: seq[SparseHandle]

      for i in 0..<eCount:
        var e = w.createSparseEntity()
        w.addComponent(e, C[0])
        w.addComponent(e, C[1])
        w.addComponent(e, C[2])
        w.addComponent(e, C[3])
        w.addComponent(e, C[4])
        w.addComponent(e, C[5])
        w.addComponent(e, C[6])
        w.addComponent(e, C[7])
        w.addComponent(e, C[8])
        w.addComponent(e, C[9])
        w.addComponent(e, C[10])
        w.addComponent(e, C[11])
        w.addComponent(e, C[12])
        w.addComponent(e, C[13])
        w.addComponent(e, C[14])
        ents.add(e)

      for e in ents:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        var e = w.createSparseEntity()
        w.addComponent(e, C[0])
        w.addComponent(e, C[1])
        w.addComponent(e, C[2])
        w.addComponent(e, C[3])
        w.addComponent(e, C[4])
        w.addComponent(e, C[5])
        w.addComponent(e, C[6])
        w.addComponent(e, C[7])
        w.addComponent(e, C[8])
        w.addComponent(e, C[9])
        w.addComponent(e, C[10])
        w.addComponent(e, C[11])
        w.addComponent(e, C[12])
        w.addComponent(e, C[13])
        w.addComponent(e, C[14])
    )
  )
  showDetailed(suite.benchmarks[^1])

proc insertOnlyLastDense(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Insert only last dense Component")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "Insert only last " & $eCount & " dense entity",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents: seq[DenseHandle]
      discard w.registerComponent(C[14])

      for i in 0..<eCount:
        var e = w.createEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13])
        w.addComponent(e, C[14].toComponentId)
        ents.add(e)

      for e in ents:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        var e = w.createEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13])
        w.addComponent(e, C[14].toComponentId)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc insertOnlyLastSparse(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Insert only last sparse Component")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "Insert only last " & $eCount & " sparse entity",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents: seq[SparseHandle]

      for i in 0..<eCount:
        var e = w.createSparseEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13])
        w.addComponent(e, C[14])
        ents.add(e)

      for e in ents:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        var e = w.createSparseEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13])
        w.addComponent(e, C[14])

    )
  )
  showDetailed(suite.benchmarks[^1])

insertManyDense(ENTITY_COUNT)
insertManySparse(ENTITY_COUNT)
insertOnlyLastDense(ENTITY_COUNT)
insertOnlyLastSparse(ENTITY_COUNT)