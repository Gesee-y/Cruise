include "../../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../../src/profile/benchmarks.nim"

const SAMPLE = 100
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

      var ents: seq[DenseHandle]
      for i in 0..<eCount:
        var e = w.createEntity()
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
        var e = w.createEntity()
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

proc insertManyDenseTyped(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Insert dense Component typed")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "Insert many " & $eCount & " dense entity typed",
    bSample,
    bWarm,
    (
      var w = newECSWorld()

      var ents: seq[TDHandle[maskOf(C[0],C[1],C[2],C[3],C[4],C[5],C[6],C[7],C[8],C[9],C[10],C[11],C[12],C[13],C[14])]]
      for i in 0..<eCount:
        var e = w.createTEntity()
        var e1 = w.addComponent(e, C[0])
        var e2 = w.addComponent(e1, C[1])
        var e3 = w.addComponent(e2, C[2])
        var e4 = w.addComponent(e3, C[3])
        var e5 = w.addComponent(e4, C[4])
        var e6 = w.addComponent(e5, C[5])
        var e7 = w.addComponent(e6, C[6])
        var e8 = w.addComponent(e7, C[7])
        var e9 = w.addComponent(e8, C[8])
        var e10 = w.addComponent(e9, C[9])
        var e11 = w.addComponent(e10, C[10])
        var e12 = w.addComponent(e11, C[11])
        var e13 = w.addComponent(e12, C[12])
        var e14 = w.addComponent(e13, C[13])
        var e15 = w.addComponent(e14, C[14])
        ents.add(e15)

      for e in ents:
        w.deleteEntity(e)

    ),
    (
      for i in 0..<eCount:
        var e = w.createTEntity()
        var e1 = w.addComponent(e, C[0])
        var e2 = w.addComponent(e1, C[1])
        var e3 = w.addComponent(e2, C[2])
        var e4 = w.addComponent(e3, C[3])
        var e5 = w.addComponent(e4, C[4])
        var e6 = w.addComponent(e5, C[5])
        var e7 = w.addComponent(e6, C[6])
        var e8 = w.addComponent(e7, C[7])
        var e9 = w.addComponent(e8, C[8])
        var e10 = w.addComponent(e9, C[9])
        var e11 = w.addComponent(e10, C[10])
        var e12 = w.addComponent(e11, C[11])
        var e13 = w.addComponent(e12, C[12])
        var e14 = w.addComponent(e13, C[13])
        var e15 = w.addComponent(e14, C[14])
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

proc insertManySparseTyped(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Insert sparse Component typed")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "Insert many " & $eCount & " sparse entity typed",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents: seq[TSHandle[maskOf(C[0],C[1],C[2],C[3],C[4],C[5],C[6],C[7],C[8],C[9],C[10],C[11],C[12],C[13],C[14])]]

      for i in 0..<eCount:
        var e = w.createTSparseEntity()
        var e1 = w.addComponent(e, C[0])
        var e2 = w.addComponent(e1, C[1])
        var e3 = w.addComponent(e2, C[2])
        var e4 = w.addComponent(e3, C[3])
        var e5 = w.addComponent(e4, C[4])
        var e6 = w.addComponent(e5, C[5])
        var e7 = w.addComponent(e6, C[6])
        var e8 = w.addComponent(e7, C[7])
        var e9 = w.addComponent(e8, C[8])
        var e10 = w.addComponent(e9, C[9])
        var e11 = w.addComponent(e10, C[10])
        var e12 = w.addComponent(e11, C[11])
        var e13 = w.addComponent(e12, C[12])
        var e14 = w.addComponent(e13, C[13])
        var e15 = w.addComponent(e14, C[14])
        ents.add(e15)

      for e in ents:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        var e = w.createTSparseEntity()
        var e1 = w.addComponent(e, C[0])
        var e2 = w.addComponent(e1, C[1])
        var e3 = w.addComponent(e2, C[2])
        var e4 = w.addComponent(e3, C[3])
        var e5 = w.addComponent(e4, C[4])
        var e6 = w.addComponent(e5, C[5])
        var e7 = w.addComponent(e6, C[6])
        var e8 = w.addComponent(e7, C[7])
        var e9 = w.addComponent(e8, C[8])
        var e10 = w.addComponent(e9, C[9])
        var e11 = w.addComponent(e10, C[10])
        var e12 = w.addComponent(e11, C[11])
        var e13 = w.addComponent(e12, C[12])
        var e14 = w.addComponent(e13, C[13])
        var e15 = w.addComponent(e14, C[14])
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

      for i in 0..<eCount:
        var e = w.createEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13])
        w.addComponent(e, C[14])
        ents.add(e)

      for e in ents:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        var e = w.createEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[6],
          C[9], C[10], C[11], C[12], C[13])
        w.addComponent(e, C[14])
    )
  )
  showDetailed(suite.benchmarks[^1])

proc insertOnlyLastDenseTyped(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Insert only last dense Component typed")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "Insert only last " & $eCount & " dense entity typed",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents: seq[TDHandle[maskOf(C[0],C[1],C[2],C[3],C[4],C[5],C[6],C[7],C[8],C[9],C[10],C[11],C[12],C[13],C[14])]]

      for i in 0..<eCount:
        var e = w.createTEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[8],
          C[9], C[10], C[11], C[12], C[13])
        let e1 = w.addComponent(e, C[14])
        ents.add(e1)

      for e in ents:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        var e = w.createTEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[8],
          C[9], C[10], C[11], C[12], C[13])
        discard w.addComponent(e, C[14])
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
        var e = w.createSparseEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[8],
          C[9], C[10], C[11], C[12], C[13])
        w.addComponent(e, C[14])
        ents.add(e)

      for e in ents:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        var e = w.createSparseEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[8],
          C[9], C[10], C[11], C[12], C[13])
        w.addComponent(e, C[14])

    )
  )
  showDetailed(suite.benchmarks[^1])

proc insertOnlyLastSparseTyped(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Insert only last sparse Component typed")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "Insert only last " & $eCount & " sparse entity typed",
    bSample,
    bWarm,
    (
      var w = newECSWorld()
      var ents: seq[TSHandle[maskOf(C[0],C[1],C[2],C[3],C[4],C[5],C[6],C[7],C[8],C[9],C[10],C[11],C[12],C[13], C[14])]]

      for i in 0..<eCount:
        var e = w.createTSparseEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[8],
          C[9], C[10], C[11], C[12], C[13])
        let e1 = w.addComponent(e, C[14])
        ents.add(e1)

      for e in ents:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<eCount:
        var e = w.createTSparseEntity(C[0], C[1], C[2], C[3], C[4], C[5], C[6], C[7], C[8],
          C[9], C[10], C[11], C[12], C[13])
        discard w.addComponent(e, C[14])
    )
  )
  showDetailed(suite.benchmarks[^1])


insertManyDense(ENTITY_COUNT)
insertManySparse(ENTITY_COUNT)
insertOnlyLastDense(ENTITY_COUNT)
insertOnlyLastSparse(ENTITY_COUNT)

insertManyDenseTyped(ENTITY_COUNT)
insertManySparseTyped(ENTITY_COUNT)
insertOnlyLastDenseTyped(ENTITY_COUNT)
insertOnlyLastSparseTyped(ENTITY_COUNT)