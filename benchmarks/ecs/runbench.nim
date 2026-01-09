include "../../src/ecs/table.nim"
import times, os

# =========================
# Benchmark template
# =========================

const SAMPLE = 10_000

template benchmark(benchmarkName: string, sample:int, code: untyped) =
  block:
    var elapsed = 0.0
    var allocated = 0.0
    code

    for i in 1..sample:
      let m0 = getOccupiedMem()
      let t0 = cpuTime()
      code
      elapsed += cpuTime() - t0
      allocated += (getOccupiedMem() - m0).float

    elapsed /= sample.float
    allocated /= sample.float
    echo "CPU Time [", benchmarkName, "] ",
         (elapsed * 1e9).float, " ns | ",
         allocated / 1024, " KB"

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


# =========================
# World setup
# =========================

proc setupWorld(entityCount: int): (ECSWorld, seq[ptr Entity], int, int, int) =
  var world = newECSWorld()

  let posID = world.registerComponent(Position)
  let velID = world.registerComponent(Velocity)
  let accID = world.registerComponent(Acceleration)

  # Dense archetype: Position + Velocity
  var comp = @[posID, velID]
  var entities: seq[ptr Entity]
  for i in 0..<entityCount:
    entities.add(createEntity(world, comp))

  for i in 0..<entityCount:
    discard allocateSparseEntity(world, @[0,1])

  return (world, entities, posID, velID, accID)


# =========================
# Benchmarks
# =========================

const ENTITY_COUNT = 100


# ---------------------------------
# Entity creation
# ---------------------------------

var world1 = newECSWorld()
let posId1 = world1.registerComponent(Position)
let velID1 = world1.registerComponent(Velocity)
let accID1 = world1.registerComponent(Acceleration)
var pp = world1.get(Position)
let pos = "Position"
let vel = "Velocity"
var comp = @[posID1, velID1, accID1]
benchmark("Create Entities (Position + Velocity)", SAMPLE):
  for i in 0..<ENTITY_COUNT:
    let e = createEntity(world1, comp)
    pp[e] = Position(x:1, y:1)
    world1.deleteEntity(e)


# ---------------------------------
# Dense iteration
# ---------------------------------
#[
let world2 = setupWorld(ENTITY_COUNT)
let posc2 = world2.get(Position)
let velc2 = world2.get(Velocity)

benchmark("Create Query signature (Position + Velocity)", SAMPLE):
  discard query(world2, Position and Velocity)

benchmark("Create Query signature (Position + Velocity)", SAMPLE):
  for (_,_) in world2.denseQuery(query(world2, Position and Velocity)):
    continue

let q2 = world2.denseQueryCache(query(world2, Position and Velocity))
benchmark("Dense Iteration (Position + Velocity)", SAMPLE):
  for (bid, r) in q2:
    var posbx = addr posc2.blocks[bid].data.x
    let velbx = addr velc2.blocks[bid].data.x
    var posby = addr posc2.blocks[bid].data.y
    let velby = addr velc2.blocks[bid].data.y

    for i in r:
      posbx[i] += velbx[i]+1
      posby[i] += velby[i]

let sq2 = world2.sparseQueryCache(query(world2, Position and Velocity))
benchmark("Sparse Iteration (Position + Velocity)", SAMPLE):
  for (bid, r) in sq2:
    var posbx = addr posc2.sparse[bid].data.x
    let velbx = addr velc2.sparse[bid].data.x
    var posby = addr posc2.sparse[bid].data.y
    let velby = addr velc2.sparse[bid].data.y

    for i in r.maskIter:
      posbx[i] += velbx[i]
      posby[i] += velby[i]


# ---------------------------------
# Dense write
# ---------------------------------

benchmark("Dense Write (Position update)", SAMPLE):
  let world = setupWorld(ENTITY_COUNT)

  for (_, range) in world.denseQuery(query(world, Position and Velocity)):
    for i in range:
      var p = world.get(Position, i)
      p.x += 1
      p.y += 1
      world.set(i, p)
]#

# ---------------------------------
# Add component (partition change)
# ---------------------------------

var (world, entities, posID, velID, accID) = setupWorld(ENTITY_COUNT)
let toAdd = @[accID]
let toRem = @[accID]
echo toAdd
benchmark("Add Component (Acceleration)", SAMPLE):

  for i in 0..<entities.len:
    var e = entities[i]
    addComponent(world, e, toAdd)
    removeComponent(world, e, toAdd)

#[
# ---------------------------------
# Sparse creation
# ---------------------------------

benchmark("Sparse Entity Creation", SAMPLE):
  var world: ECSWorld
  world.registry = newComponentRegistry()
  world.registerComponent(Position)

  for i in 0..<ENTITY_COUNT:
    let e = allocateSparseEntity(world, @[world.registry.cmap["Position"]])
    world.registry.entries[0].activateSparseBitOp(
      world.registry.entries[0].rawPointer, e
    )


# ---------------------------------
# Sparse query
# ---------------------------------

benchmark("Sparse Query (Position)", SAMPLE):
  let world = setupWorld(ENTITY_COUNT)

  let sig = buildQuerySignature(
    world,
    @[includeComp(world.registry.cmap["Position"])]
  )

  for (_, mask) in sparseQuery(world, sig):
    for _ in mask.maskIter:
      discard


# ---------------------------------
# Mixed load (dense + sparse)
# ---------------------------------

benchmark("Mixed Dense + Sparse Query", SAMPLE):
  let world = setupWorld(ENTITY_COUNT)

  let sig = buildQuerySignature(
    world,
    @[
      includeComp(world.registry.cmap["Position"]),
      includeComp(world.registry.cmap["Velocity"]),
      excludeComp(world.registry.cmap["Acceleration"])
    ]
  )

  for (_, range) in denseQuery(world, sig):
    for i in range:
      let p = world.get[Position](i)
      discard p.x

]#
#discard stdout.readLine()