include "../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

const SAMPLE = 100
const WARMUP = 1

# =========================
# Components
# =========================

type
  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Acceleration = object
    x, y: float32

  Tag = object

  Health = object
    hp:int

  Timer[T] = object
    remaining:T

proc newTimer[T](r:T):Timer[T] = Timer[T]() 
proc newPosition(x,y:float32):Position = Position() 
proc setComponent[T](blk: ptr T, i:uint, v:Position) =
  blk.data.x[i] = v.x*2
  blk.data.y[i] = v.y/2

# =========================
# World setup
# =========================


# =========================
# Benchmarks
# =========================

const ENTITY_COUNT = 10000

proc setupWorldNoEnt(): ECSWorld =
  var world = newECSWorld()

  let posID = world.registerComponent(Position)
  let velID = world.registerComponent(Velocity)
  let accID = world.registerComponent(Acceleration)

  return world


# ---------------------------------
# Entity creation
# ---------------------------------

proc runDenseBenchmarks() =
  var suite = initSuite("Sparse ECS Operations")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "dense_create_entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var node = w.archGraph.findArchetype([0, 1])
      var ents:seq[DenseHandle]
      for i in 0..<ENTITY_COUNT:
        ents.add w.createEntity(node)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<ENTITY_COUNT:
        discard w.createEntity(node)
    )
  )
  showDetailed(suite.benchmarks[0])

  suite.add benchmarkWithSetup(
    "dense_create_entity_batch",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var node = w.archGraph.findArchetype([0, 1])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, node)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      discard w.createEntities(ENTITY_COUNT, node)
    )
  )
  showDetailed(suite.benchmarks[1])

  suite.add benchmarkWithSetup(
    "query_creation",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var node = w.archGraph.findArchetype([0, 1])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, node)
    ),
    (
      discard query(w, Position and Velocity)
    )
  )
  showDetailed(suite.benchmarks[2])

  suite.add benchmarkWithSetup(
    "dense_query_creation",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var node = w.archGraph.findArchetype([0, 1])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, node)
    ),
    (
      for (_,_) in w.denseQuery(query(w, Position and Velocity)):
        continue
    )
  )
  showDetailed(suite.benchmarks[3])

  suite.add benchmarkWithSetup(
    "iterate_dense_entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var node = w.archGraph.findArchetype([0, 1])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, node)
      let q2 = w.denseQueryCache(query(w, Position and Velocity))
      var posc = w.get(Position)
      let velc = w.get(Velocity)
    ),
    (
      for (bid, r) in w.denseQuery(query(w, Position and Velocity)):
        var x = addr posc.blocks[bid].data.x
        let dx = addr velc.blocks[bid].data.x
        var y = addr posc.blocks[bid].data.y
        let dy = addr velc.blocks[bid].data.y

        for i in r:
          x[i] += dx[i]
          y[i] += dy[i]
    )
  )
  showDetailed(suite.benchmarks[4])

  var s = 0'f32
  suite.add benchmarkWithSetup(
    "read_dense_entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var node = w.archGraph.findArchetype([0, 1])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, node)
      var posc = w.get(Position)
      
    ),
    (
      for e in ents:
        s += posc[e].x
    )
  )
  showDetailed(suite.benchmarks[5])
  
  suite.add benchmarkWithSetup(
    "write_dense_entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var node = w.archGraph.findArchetype([0, 1])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, node)
      var posc = w.get(Position)
      
    ),
    (
      for e in ents:
        posc[e] = Position(x:s)
    )
  )
  showDetailed(suite.benchmarks[6])

  suite.add benchmarkWithSetup(
    "migrate_dense_entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var archBase = w.archGraph.findArchetype([0, 1])
      var archDest = w.archGraph.findArchetype([0, 1, 2])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, archBase)
      
      for e in ents:
        migrateEntity(w, e, archDest)
      for e in ents:
        migrateEntity(w, e, archBase)
    ),
    (
      for e in ents:
        migrateEntity(w, e, archDest)
    )
  )
  showDetailed(suite.benchmarks[7])
  
  suite.add benchmarkWithSetup(
    "migrate_dense_entity_batch",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var archBase = w.archGraph.findArchetype([0, 1])
      var archDest = w.archGraph.findArchetype([0, 1, 2])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, archBase)
      
      migrateEntity(w, ents, archDest)
      migrateEntity(w, ents, archBase)
    ),
    (
      migrateEntity(w, ents, archDest)
    )
  )
  showDetailed(suite.benchmarks[8])


runDenseBenchmarks()
