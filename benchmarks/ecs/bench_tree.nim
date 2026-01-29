import times, math#, nimprof
include "../../src/ecs/table.nim"
include "../../src/ecs/plugins/scenetree.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

type
  Pos = object
    x,y:float64

  Vel = object
    dx,dy:float64

const ENTITY_COUNT = 10000
const Samples = 1000
const Warmup = 1

var suite = initSuite("Sparse ECS Operations")

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

suite.add benchmarkWithSetup(
  "tree_iter_dense",
  Samples,
  Warmup,
  (
    var w = newECSWorld()
    discard w.registerComponent(Pos)
    discard w.registerComponent(Vel)
    var posColumn = w.get(Pos)
    var velColumn = w.get(Vel)
    var root = w.createEntity()
    var tree = initSceneTree(root)
    var ents = newSeq[DenseHandle](ENTITY_COUNT)
    
    for i in 0..<ENTITY_COUNT:
      ents[i] = w.createEntity(0,1)

    for e in ents:
      tree.addChild(e)

    var sig = w.query(Pos and Vel)
    sig.addFilter(tree.getChildren(root)[])
  ),
  (
    for bid, r in w.denseQuery(sig):
      var posx = addr posColumn.blocks[bid].data.x
      var posy = addr posColumn.blocks[bid].data.y
      var velx = addr velColumn.blocks[bid].data.dx
      var vely = addr velColumn.blocks[bid].data.dy

      for i in r:
        posx[i] += velx[i]
        posy[i] += vely[i]
  )
)
showDetailed(suite.benchmarks[2])

suite.add benchmarkWithSetup(
  "tree_iter_sparse",
  Samples,
  Warmup,
  (
    var w = newECSWorld()
    discard w.registerComponent(Pos)
    discard w.registerComponent(Vel)
    var posColumn = w.get(Pos)
    var velColumn = w.get(Vel)
    var root = w.createEntity()
    var tree = initSceneTree(root)
    var ents = newSeq[SparseHandle](ENTITY_COUNT)
    
    for i in 0..<ENTITY_COUNT:
      ents[i] = w.createSparseEntity([0,1])

    for e in ents:
      tree.addChild(e)

    var sig = w.query(Pos and Vel)
    sig.addFilter(tree.getChildren(root)[])
  ),
  (
    for bid, r in w.sparseQuery(sig):
      let pid = posColumn.toSparse[bid]-1
      let vid = velColumn.toSparse[bid]-1
      var posx = addr posColumn.sparse[pid].data.x
      var posy = addr posColumn.sparse[pid].data.y
      var velx = addr velColumn.sparse[vid].data.dx
      var vely = addr velColumn.sparse[vid].data.dy

      for i in r:
        posx[i] += velx[i]
        posy[i] += vely[i]
  )
)
showDetailed(suite.benchmarks[3])
