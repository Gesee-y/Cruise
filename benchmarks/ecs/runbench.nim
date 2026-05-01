include "../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

const SAMPLE = 10000
const WARMUP = 1
const ENTITY_COUNT = 1000

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
  var suite = initSuite("Cruise Dense")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "create entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var node = w.archGraph.findArchetype([0, 1])
      var ents:seq[DenseHandle]
      for i in 0..<ENTITY_COUNT:
        ents.add w.createEntity(Position, Velocity)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<ENTITY_COUNT:
        discard w.createEntity(Position, Velocity)
    )
  )
  showDetailed(suite.benchmarks[0])

  suite.add benchmarkWithSetup(
    "create entity batch",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      discard w.createEntities(ENTITY_COUNT, Position, Velocity)
    )
  )
  showDetailed(suite.benchmarks[1])

  # ------------------------------
  # Delete dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "delete entity",
    Sample,
    Warmup,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
    )
    ,
    for e in ents.mitems:
      w.deleteEntity(e)
  )
  showDetailed(suite.benchmarks[2])

  suite.add benchmarkWithSetup(
    "query creation",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
    ),
    (
      discard query(w, Position and Velocity)
    )
  )
  showDetailed(suite.benchmarks[3])

  suite.add benchmarkWithSetup(
    "dense query creation",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
    ),
    (
      for (_,_) in w.denseQuery(query(w, Position and Velocity)):
        continue
    )
  )
  showDetailed(suite.benchmarks[4])

  suite.add benchmarkWithSetup(
    "iteration",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
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
  showDetailed(suite.benchmarks[5])

  var s = 0'f32
  suite.add benchmarkWithSetup(
    "read",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position)
      var posc = w.get(Position)
      
    ),
    (
      for e in ents:
        s += posc[e].x
    )
  )
  showDetailed(suite.benchmarks[6])
  
  suite.add benchmarkWithSetup(
    "write",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position)
      var posc = w.get(Position)
    ),
    (
      for e in ents:
        posc[e] = Position(x:s)
    )
  )
  showDetailed(suite.benchmarks[7])

  suite.add benchmarkWithSetup(
    "add component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      
      for e in ents:
        w.addComponent(e, Acceleration.toComponentId)
      for e in ents:
        w.removeComponent(e, Acceleration.toComponentId)
    ),
    (
      for e in ents:
        w.addComponent(e, Acceleration.toComponentId)
    )
  )
  showDetailed(suite.benchmarks[8])

  suite.add benchmarkWithSetup(
    "remove component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      
      for e in ents:
        w.addComponent(e, Velocity.toComponentId)
    ),
    (
      for e in ents:
        w.removeComponent(e, Velocity.toComponentId)
    )
  )
  showDetailed(suite.benchmarks[9])

  suite.add benchmarkWithSetup(
    "add remove component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      
      for e in ents:
        w.addComponent(e, Acceleration.toComponentId)
      for e in ents:
        w.removeComponent(e, Acceleration.toComponentId)
    ),
    (
      for e in ents:
        w.addComponent(e, Acceleration.toComponentId)
        w.removeComponent(e, Acceleration.toComponentId)
    )
  )
  showDetailed(suite.benchmarks[10])

  suite.add benchmarkWithSetup(
    "migrate_dense_entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var archBase = w.archGraph.findArchetype([toComponentId(Position), toComponentId(Velocity)])
      var archDest = w.archGraph.findArchetype([toComponentId(Position), toComponentId(Velocity), toComponentId(Acceleration)])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      
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
  showDetailed(suite.benchmarks[11])
  
  suite.add benchmarkWithSetup(
    "migrate dense entity batch",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var archBase = w.archGraph.findArchetype([toComponentId(Position), toComponentId(Velocity)])
      var archDest = w.archGraph.findArchetype([toComponentId(Position), toComponentId(Velocity), toComponentId(Acceleration)])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      
      migrateEntity(w, ents, archDest)
      migrateEntity(w, ents, archBase)
    ),
    (
      migrateEntity(w, ents, archDest)
    )
  )
  showDetailed(suite.benchmarks[12])
  suite.showSummary()
#  suite.saveSummary("cr_dense")

runDenseBenchmarks()
