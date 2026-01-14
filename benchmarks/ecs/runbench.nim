include "../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../src/profile/benchmarks.nim"

const SAMPLE = 10_00

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

  Timer = object
    remaining:float32


# =========================
# World setup
# =========================

proc setupWorld(entityCount: int): (ECSWorld, ref seq[DenseHandle], int, int, int, int, int, int) =
  var world = newECSWorld()

  let posID = world.registerComponent(Position)
  let velID = world.registerComponent(Velocity)
  let accID = world.registerComponent(Acceleration)
  let tagID = world.registerComponent(Tag)
  let timerID = world.registry.registerComponent(Timer)
  let hpID = world.registerComponent(Health)

  # Dense archetype: Position + Velocity
  var comp = @[posID, velID]
  var entities: ref seq[DenseHandle]
  new(entities)
  for i in 0..<entityCount:
    let e = createEntity(world, comp)
    entities[].add(e)

  return (world, entities, posID, velID, accID, tagID, timerID, hpID)


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

let res1 = benchmark("Create-Delete Entity (Position + Velocity) [" & $ENTITY_COUNT & "]", SAMPLE):
  for i in 0..<ENTITY_COUNT:
    let e = createEntity(world1, @[posID1, velID1, accID1])
    world1.deleteEntity(e)
showDetailed(res1)

var world100 = newECSWorld()
let posId100 = world100.registerComponent(Position)
let velID100 = world100.registerComponent(Velocity)
let accID100 = world100.registerComponent(Acceleration)
var comp = @[posID100, velID100, accID100]

let res100 = benchmark("Create-Delete Entities (Position + Velocity) [" & $ENTITY_COUNT & "]", SAMPLE):
  let ents = createEntities(world100, ENTITY_COUNT, comp)
  
  for e in ents:
    world100.deleteEntity(e)
showDetailed(res100)
# ---------------------------------
# Dense iteration
# ---------------------------------

let (world2,_,_,_,_,_,_,_) = setupWorld(ENTITY_COUNT)
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
      posby[i] += velby[i]+1
showDetailed(res4)

# ---------------------------------
# Dense write
# ---------------------------------

let (world8, entities8, posID8, velID8, accID8, tagID8, timerID8, hpID8) = setupWorld(ENTITY_COUNT)
var posc8 = world8.get(Position)
var s = 0.float32
let res8 = benchmark("Dense Read (Position)", SAMPLE):
  for e in entities8[]:
    s += posc8[e].x
showDetailed(res8)

let (world9, entities9, posID9, velID9, accID9, tagID9, timerID9, hpID9) = setupWorld(ENTITY_COUNT)
var posc9 = world9.get(Position)
let res9 = benchmark("Dense Write (Position update)", SAMPLE):
  for e in entities9[]:
    posc9[e] = Position()
showDetailed(res9)

# ---------------------------------
# Add component (partition change)
# ---------------------------------

var (world, entities, posID, velID, accID, tagID, timerID, hpID) = setupWorld(ENTITY_COUNT)
let toAdd = @[accID]
let toRem = @[accID]

let archBase = world.getArchetype(entities[0])
var graph = world.archGraph
let archDest = graph.addComponent(archBase, [ComponentId(accID)])#, ComponentId(tagID), ComponentId(timerID), ComponentId(hpID)])

let res7 = benchmark("Add Component (Acceleration)", SAMPLE):
  migrateEntity(world, entities[], archDest)
  migrateEntity(world, entities[], archBase)
showDetailed(res7)

var (world10, entities10, posID10, velID10, accID10, tagID10, timerID10, hpID10) = setupWorld(ENTITY_COUNT)
var d = world10.createEntity(0)

let res10 = benchmark("Make Dense/Sparse", SAMPLE):
  for _ in 0..<ENTITY_COUNT:
    var s = makeSparse(world10, d)
    d = makeDense(world10, s)
showDetailed(res10)


