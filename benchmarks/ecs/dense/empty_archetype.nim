include "../../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../../src/profile/benchmarks.nim"

const SAMPLE = 100
const WARMUP = 1
const ENTITY_COUNT = 10000

type
  A[N: static int] = object

template benchIteration(world: var ECSWorld) =
  var ad = world.get(A[0])
  for bid, r in world.denseQuery(world.query(A[0] and A[1] and A[2] and A[3] and A[4] and A[5] and A[6] and A[7] and A[8] and A[9] and A[10] and A[11] and A[12])):
    discard addr ad

template benchSparseIteration(world: var ECSWorld) =
  var ad = world.get(A[0])
  for sid, r in world.sparseQuery(world.query(A[0] and A[1] and A[2] and A[3] and A[4] and A[5] and A[6] and A[7] and A[8] and A[9] and A[10] and A[11] and A[12])):
    discard addr ad

proc addDenseArchetypes(world: var ECSWorld, count: uint16): seq[DenseHandle] =
  var ents: seq[DenseHandle]
  for i in 0'u16..count:
    let e = world.createEntity()
    ents.add(e)
    world.addComponent(e, A[0])
    world.addComponent(e, A[1])
    world.addComponent(e, A[2])
    world.addComponent(e, A[3])
    world.addComponent(e, A[4])
    world.addComponent(e, A[5])
    world.addComponent(e, A[6])
    world.addComponent(e, A[7])
    world.addComponent(e, A[8])
    world.addComponent(e, A[9])
    world.addComponent(e, A[10])
    world.addComponent(e, A[11])
    world.addComponent(e, A[12])
    
    if (i and (1 shl 1).uint16) != 0:
      world.addComponent(e, A[13])
    
    if (i and (1 shl 2)) != 0:
      world.addComponent(e, A[14])
    
    if (i and (1 shl 3)) != 0:
      world.addComponent(e, A[15])
    
    if (i and (1 shl 4)) != 0:
      world.addComponent(e, A[16])
    
    if (i and (1 shl 5)) != 0:
      world.addComponent(e, A[18])
    
    if (i and (1 shl 6)) != 0:
      world.addComponent(e, A[19])
    
    if (i and (1 shl 7)) != 0:
      world.addComponent(e, A[20])
    
    if (i and (1 shl 8)) != 0:
      world.addComponent(e, A[21])
    
    if (i and (1 shl 9)) != 0:
      world.addComponent(e, A[22])
    
    if (i and (1 shl 10)) != 0:
      world.addComponent(e, A[23])
    
    if (i and (1 shl 11)) != 0:
      world.addComponent(e, A[24])
    
    if (i and (1 shl 12)) != 0:
      world.addComponent(e, A[25])
    
    if (i and (1 shl 13)) != 0:
      world.addComponent(e, A[26])
    
    if (i and (1 shl 14)) != 0:
      world.addComponent(e, A[27])
    
    if (i and (1 shl 15)) != 0:
      world.addComponent(e, A[28])

  ents

proc addSparseArchetypes(world: var ECSWorld, count: uint16): seq[SparseHandle] =
  var ents: seq[SparseHandle]
  for i in 0'u16..count:
    var e = world.createSparseEntity()
    world.addComponent(e, A[0])
    world.addComponent(e, A[1])
    world.addComponent(e, A[2])
    world.addComponent(e, A[3])
    world.addComponent(e, A[4])
    world.addComponent(e, A[5])
    world.addComponent(e, A[6])
    world.addComponent(e, A[7])
    world.addComponent(e, A[8])
    world.addComponent(e, A[9])
    world.addComponent(e, A[10])
    world.addComponent(e, A[11])
    world.addComponent(e, A[12])
    
    if (i and (1 shl 1).uint16) != 0:
      world.addComponent(e, A[13])
    
    if (i and (1 shl 2)) != 0:
      world.addComponent(e, A[14])
    
    if (i and (1 shl 3)) != 0:
      world.addComponent(e, A[15])
    
    if (i and (1 shl 4)) != 0:
      world.addComponent(e, A[16])
    
    if (i and (1 shl 5)) != 0:
      world.addComponent(e, A[18])
    
    if (i and (1 shl 6)) != 0:
      world.addComponent(e, A[19])
    
    if (i and (1 shl 7)) != 0:
      world.addComponent(e, A[20])
    
    if (i and (1 shl 8)) != 0:
      world.addComponent(e, A[21])
    
    if (i and (1 shl 9)) != 0:
      world.addComponent(e, A[22])
    
    if (i and (1 shl 10)) != 0:
      world.addComponent(e, A[23])
    
    if (i and (1 shl 11)) != 0:
      world.addComponent(e, A[24])
    
    if (i and (1 shl 12)) != 0:
      world.addComponent(e, A[25])
    
    if (i and (1 shl 13)) != 0:
      world.addComponent(e, A[26])
    
    if (i and (1 shl 14)) != 0:
      world.addComponent(e, A[27])
    
    if (i and (1 shl 15)) != 0:
      world.addComponent(e, A[28])

  ents

proc emptyArchetypes(count: uint16, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("empty archetype dense")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "empty archetype dense " & $count,
    bSample,
    bWarm,
    (
      var world = newECSWorld()
      var ents = world.addDenseArchetypes(count)
      for e in ents:
        world.deleteEntity(e)

      let e = world.createEntity()
      world.addComponent(e, A[0])
      world.addComponent(e, A[1])
      world.addComponent(e, A[2])
      world.addComponent(e, A[3])
      world.addComponent(e, A[4])
      world.addComponent(e, A[5])
      world.addComponent(e, A[6])
      world.addComponent(e, A[7])
      world.addComponent(e, A[8])
      world.addComponent(e, A[9])
      world.addComponent(e, A[10])
      world.addComponent(e, A[11])
      world.addComponent(e, A[12])
      world.benchIteration()
    ),
    (
      world.benchIteration()
    )
  )
  showDetailed(suite.benchmarks[^1])

proc emptySparseArchetypes(count: uint16, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("empty archetype sparse")

  # ------------------------------
  # Create single dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "empty archetype sparse " & $count ,
    bSample,
    bWarm,
    (
      var world = newECSWorld()
      var ents = world.addSparseArchetypes(count)
      for e in ents:
        world.deleteEntity(e)

      var e = world.createSparseEntity()
      world.addComponent(e, A[0])
      world.addComponent(e, A[1])
      world.addComponent(e, A[2])
      world.addComponent(e, A[3])
      world.addComponent(e, A[4])
      world.addComponent(e, A[5])
      world.addComponent(e, A[6])
      world.addComponent(e, A[7])
      world.addComponent(e, A[8])
      world.addComponent(e, A[9])
      world.addComponent(e, A[10])
      world.addComponent(e, A[11])
      world.addComponent(e, A[12])
      world.benchSparseIteration()
    ),
    (
      world.benchSparseIteration()
    )
  )
  showDetailed(suite.benchmarks[^1])

emptyArchetypes(100)
emptyArchetypes(1000)
emptyArchetypes(10000)
emptySparseArchetypes(100)
emptySparseArchetypes(1000)
emptySparseArchetypes(10000)