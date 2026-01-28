import times, math#, nimprof
include "../../src/ecs/table.nim"
include "../../src/ecs/plugins/scenetree.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

const ENTITY_COUNT = 1000
const Samples = 1000
const Warmup = 1

var suite = initSuite("Sparse ECS Operations")

# ------------------------------
# Create single sparse entity
# ------------------------------
suite.add benchmarkWithSetup(
  "tree_add_child_root",
  Samples,
  Warmup,
  (
    var w = newECSWorld()
    var root = w.createEntity()
    var tree = initSceneTree(root)
    var ents = newSeq[DenseHandle](ENTITY_COUNT)
    
    for i in 0..<ENTITY_COUNT:
      ents[i] = w.createEntity()

    for e in ents:
      tree.addChild(e)

    for e in ents:
      tree.deleteNode(e)
  ),
  (
    for e in ents:
      tree.addChild(e)
  )
)
showDetailed(suite.benchmarks[0])

suite.add benchmarkWithSetup(
  "tree_remove_node",
  Samples,
  Warmup,
  (
    var w = newECSWorld()
    var root = w.createEntity()
    var tree = initSceneTree(root)
    var ents = newSeq[DenseHandle](ENTITY_COUNT)
    
    for i in 0..<ENTITY_COUNT:
      ents[i] = w.createEntity()

    for e in ents:
      tree.addChild(e)
  ),
  (
    for e in ents:
      tree.deleteNode(e)
  )
)
showDetailed(suite.benchmarks[1])