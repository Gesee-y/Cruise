include "../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

const SAMPLE = 10_000

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

const ENTITY_COUNT = 10000


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

#let res1 = benchmark("Create-Delete Entities (Position + Velocity) [" & $ENTITY_COUNT & "]", SAMPLE):
#  for i in 0..<ENTITY_COUNT:
#    let e = createEntity(world1, comp)
#    world1.deleteEntity(e)
#showDetailed(res1)

# ---------------------------------
# Dense iteration
# ---------------------------------

let (world2,_,_,_,_) = setupWorld(ENTITY_COUNT)
let posc2 = world2.get(Position)
let velc2 = world2.get(Velocity)

let res2 = benchmark("Create Query signature (Position + Velocity)", SAMPLE):
  discard query(world2, Position and Velocity)
showDetailed(res2)

let res3 = benchmark("Create Query signature (Position + Velocity)", SAMPLE):
  for (_,_) in world2.denseQuery(query(world2, Position and Velocity)):
    continue
showDetailed(res3)

let q2 = world2.denseQueryCache(query(world2, Position and Velocity))
let res4 = benchmark("Dense Iteration (Position + Velocity)", SAMPLE):
  for (bid, r) in q2:
    var posbx = addr posc2.blocks[bid].data.x
    let velbx = addr velc2.blocks[bid].data.x
    var posby = addr posc2.blocks[bid].data.y
    let velby = addr velc2.blocks[bid].data.y

    for i in r:
      posbx[i] += velbx[i]+1
      posby[i] += velby[i]
showDetailed(res4)

let sq2 = world2.sparseQueryCache(query(world2, Position and Velocity))
let res5 = benchmark("Sparse Iteration (Position + Velocity)", SAMPLE):
  for (bid, r) in sq2:
    var posbx = addr posc2.sparse[bid].data.x
    let velbx = addr velc2.sparse[bid].data.x
    var posby = addr posc2.sparse[bid].data.y
    let velby = addr velc2.sparse[bid].data.y

    for i in r.maskIter:
      posbx[i] += velbx[i]
      posby[i] += velby[i]
showDetailed(res5)

#[
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
#[
var (world, entities, posID, velID, accID) = setupWorld(ENTITY_COUNT)
let toAdd = @[accID]
let toRem = @[accID]

let res7 = benchmark("Add Component (Acceleration)", SAMPLE):

  for e in entities:
    addComponent(world, e, toAdd)
    removeComponent(world, e, toAdd)
showDetailed(res7)


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