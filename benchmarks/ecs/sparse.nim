import times, math#, nimprof
include "../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

const
  Samples = 50
  Warmup  = 1
  ENTITY_COUNT = 10_00000

type
  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Acceleration = object
    x, y: float32

  Heal = object
    hp:int

let
  Pos = 0
  Vel = 1
  Acc = 2
  Health = 3

# ==============================
# Setup helpers
# ==============================

proc setupWorld(): ECSWorld =
  var world = newECSWorld()

  let posID = world.registerComponent(Position)
  let velID = world.registerComponent(Velocity)
  let accID = world.registerComponent(Acceleration)
  let hpID = world.registerComponent(Heal)

  return world

# ==============================
# Benchmarks
# ==============================

# ---------------------------------
# Entity creation
# ---------------------------------

proc runSparseBenchmarks() =
  var suite = initSuite("Cruise Sparse")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "create entity",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var ents:seq[SparseHandle]
      for i in 0..<ENTITY_COUNT:
        ents.add w.createSparseEntity(Position, Velocity)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<ENTITY_COUNT:
        discard w.createSparseEntity(Position, Velocity)
    )
  )
  showDetailed(suite.benchmarks[0])

  # ------------------------------
  # Create sparse entities batch
  # ------------------------------
  suite.add benchmarkWithSetup(
    "create entities batch 1k",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(ENTITY_COUNT, Position, Velocity)
      
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (discard w.createSparseEntities(ENTITY_COUNT, Position, Velocity))
  )
  showDetailed(suite.benchmarks[1])

  # ------------------------------
  # Delete sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "delete entity",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(ENTITY_COUNT, Position, Velocity)
    )
    ,
    for e in ents.mitems:
      w.deleteEntity(e)
  )
  showDetailed(suite.benchmarks[2])

  # ------------------------------
  # Add component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add component",
    Samples,
    Warmup,
    ( 
      var w = setupWorld()
      var ents = w.createSparseEntities(ENTITY_COUNT,Position)
      for e in ents.mitems:
        w.addComponent(e, Velocity)
      for e in ents.mitems:
        w.removeComponent(e, Velocity)),
    for e in ents.mitems:
      w.addComponent(e, Velocity)
  )

  showDetailed(suite.benchmarks[3])

  # ------------------------------
  # Add component batch
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add component batch",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var ents = w.createSparseEntities(ENTITY_COUNT, Position)),
    w.addComponent(ents, Velocity)
  )
  showDetailed(suite.benchmarks[suite.benchmarks.len-1])

  # ------------------------------
  # Remove component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "remove component",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var e = w.createSparseEntity(Position, Velocity)),
    for i in 0..<ENTITY_COUNT:
      w.removeComponent(e, Velocity)
  )
  showDetailed(suite.benchmarks[4])

  # ------------------------------
  # Add + Remove (stress mask ops)
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add remove component",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var ents = w.createSparseEntities(ENTITY_COUNT,Position)
      for e in ents.mitems:
        w.addComponent(e, Velocity)
      for e in ents.mitems:
        w.removeComponent(e, Velocity)),
    for e in ents.mitems:
      w.addComponent(e, Velocity)
      w.removeComponent(e, Velocity),
  )

  showDetailed(suite.benchmarks[5])

  suite.add benchmarkWithSetup(
    "iteration",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var posc = w.get(Position)
      var velc = w.get(Velocity)
      discard w.createSparseEntities(ENTITY_COUNT, Position, Velocity)),
    (
      for (sid, r) in w.sparseQuery(query(w, Position and Velocity)):
        let bid = posc.toSparse[sid]-1
        var posbx = addr posc.sparse[bid].data.x
        let velbx = addr velc.sparse[bid].data.x
        var posby = addr posc.sparse[bid].data.y
        let velby = addr velc.sparse[bid].data.y

        for i in r:
          posbx[i] += velbx[i]+1
          posby[i] += velby[i]+1
    )
  )
  showDetailed(suite.benchmarks[6])
  
  var s = 0'f32
  suite.add benchmarkWithSetup(
    "read",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var posc = w.get(Position)
      var ents = w.createSparseEntities(ENTITY_COUNT, Position)),
    (
      for e in ents:
        s += posc[e].x
    )
  )
  showDetailed(suite.benchmarks[7])

  suite.add benchmarkWithSetup(
    "write",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var posc = w.get(Position)
      var ents = w.createSparseEntities(ENTITY_COUNT, Position)),
    (
      for e in ents:
        posc[e] = Position()
    )
  )
  showDetailed(suite.benchmarks[8])

  # ==============================
  # Results
  # ==============================
  suite.showSummary()
#  suite.saveSummary("cr_sparse")

# ==============================
# Entry point
# ==============================

when isMainModule:
  runSparseBenchmarks()
