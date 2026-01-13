import times, math#, nimprof
include "../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

const
  Samples = 10_0
  Warmup  = 1_0

type
  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Acceleration = object
    x, y: float32

  Heal = object
    hp:int


# Fake component ids pour les tests
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

const ENTITY_COUNT = 100000

# ---------------------------------
# Entity creation
# ---------------------------------

proc runSparseBenchmarks() =
  var suite = initSuite("Sparse ECS Operations")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "sparse_create_entity",
    Samples,
    Warmup,
    (var w = setupWorld()),
    (
      for i in 0..<ENTITY_COUNT:
        discard w.createSparseEntity([Pos, Vel]))
  )
  showDetailed(suite.benchmarks[0])

  # ------------------------------
  # Create sparse entities batch
  # ------------------------------
  suite.add benchmarkWithSetup(
    "sparse_create_entities_batch_1k",
    Samples,
    Warmup,
    (var w = setupWorld()),
    (discard w.createSparseEntities(ENTITY_COUNT, [Pos, Vel]))
  )
  showDetailed(suite.benchmarks[1])

  # ------------------------------
  # Delete sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "sparse_delete_entity",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var e = w.createSparseEntity([Pos, Vel]))
    ,
    for i in 0..<ENTITY_COUNT:
      w.deleteEntity(e)
  )
  showDetailed(suite.benchmarks[2])

  # ------------------------------
  # Add component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "sparse_add_component",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var e = w.createSparseEntity([Pos])),
    for i in 0..<ENTITY_COUNT:
      w.addComponent(e, Vel)
  )
  showDetailed(suite.benchmarks[3])

  # ------------------------------
  # Remove component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "sparse_remove_component",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var e = w.createSparseEntity([Pos, Vel])),
    for i in 0..<ENTITY_COUNT:
      w.removeComponent(e, Vel)
  )
  showDetailed(suite.benchmarks[4])

  # ------------------------------
  # Add + Remove (stress mask ops)
  # ------------------------------
  suite.add benchmarkWithSetup(
    "sparse_add_remove_component",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var e = w.createSparseEntity([Pos])),
    block:
      for i in 0..<ENTITY_COUNT:
        w.addComponent(e, Vel)
        w.removeComponent(e, Vel)
  )
  showDetailed(suite.benchmarks[5])

  suite.add benchmarkWithSetup(
    "sparse_iterations",
    Samples,
    Warmup,
    (
      var w = setupWorld()
      var posc = w.get(Position)
      var velc = w.get(Velocity)
      discard w.createSparseEntities(ENTITY_COUNT, [Pos, Vel])),
    (
      for (sid, r) in w.sparseQuery(query(w, Position and Velocity)):
        let bid = posc.toSparse[sid]
        var posbx = addr posc.sparse[bid].data.x
        let velbx = addr velc.sparse[bid].data.x
        var posby = addr posc.sparse[bid].data.y
        let velby = addr velc.sparse[bid].data.y

        for i in r.maskIter:
          posbx[i] += velbx[i]+1
          posby[i] += velby[i]+1
    )
  )
  showDetailed(suite.benchmarks[6])

  # ==============================
  # Results
  # ==============================
  suite.showSummary()

# ==============================
# Entry point
# ==============================

when isMainModule:
  runSparseBenchmarks()
