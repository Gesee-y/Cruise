import unittest, sequtils, bitops
include "../../src/ecs/table.nim"

# === DUMMY COMPONENTS ===
type
  Pos = object
    x, y: int

  Vel = object
    vx, vy: int

  Acc = object
    ax, ay: int

# === WORLD SETUP ===
proc initWorld(): ECSWorld =
  var w = newECSWorld()
  discard w.registerComponent(Pos)
  discard w.registerComponent(Vel)
  discard w.registerComponent(Acc)
  return w

# ==========================================================
# ENTITY CREATION
# ==========================================================
suite "ECS Entity creation":

  test "Create entity with one component":
    var world = initWorld()
    let e = createEntity(world, 0)

    let idx = int(e.obj.id and ((1'u shl 32)-1))
    check world.handles[idx] == e.obj
    check e.obj.archetypeID == 1'u

  test "Create entity with multiple components":
    var world = initWorld()
    let e = createEntity(world, 0, 1)

    let idx = int(e.obj.id and ((1'u shl 32)-1))
    check world.handles[idx] == e.obj
    check e.obj.archetypeID == 2'u

# ==========================================================
# COMPONENT ACCESS
# ==========================================================
suite "Component access":

  test "Read / write component through entity":
    var world = initWorld()
    let e = createEntity(world, 0)

    var pos = castTo(world.registry.entries[0].rawPointer, Pos, DEFAULT_BLK_SIZE)

    pos[e] = Pos(x:42, y:20)
    check pos[e].x == 42
    check pos[e].y == 20

# ==========================================================
# DELETE ENTITY
# ==========================================================
suite "Entity deletion":

  test "Delete entity swaps correctly":
    var world = initWorld()

    let a = createEntity(world, 0)
    let b = createEntity(world, 0)
    let c = createEntity(world, 0)

    let bidB = b.obj.id
    deleteEntity(world, b)

    let idxC = int(c.obj.id and ((1'u shl 32)-1))
    check world.handles[idxC] == c.obj
    check c.obj.id == bidB

  test "Delete last entity":
    var world = initWorld()
    let a = createEntity(world, 0)
    deleteEntity(world, a)
    check world.archGraph.nodes[a.obj.archetypeID].partition.zones[0].r.e == 0

# ==========================================================
# ADD COMPONENT
# ==========================================================
suite "Add component":

  test "Add new component changes archetype and id":
    var world = initWorld()
    let e = createEntity(world, 0)
    let oldId = e.obj.id

    addComponent(world, e, 1)
    check e.obj.id != oldId
    check e.obj.archetypeID == 2'u

  test "Add existing component does nothing":
    var world = initWorld()
    let e = createEntity(world, 0)
    let oldId = e.obj.id

    addComponent(world, e, 0)
    check e.obj.id == oldId
    check e.obj.archetypeID == 1'u

# ==========================================================
# REMOVE COMPONENT
# ==========================================================
suite "Remove component":

  test "Remove existing component":
    var world = initWorld()
    let e = createEntity(world, 0, 1)
    let oldId = e.obj.id

    removeComponent(world, e, 1)
    check e.obj.id != oldId
    check e.obj.archetypeID == 1'u

  test "Remove absent component does nothing":
    var world = initWorld()
    let e = createEntity(world, 0)
    let oldId = e.obj.id

    removeComponent(world, e, 1)
    check e.obj.id == oldId
    check e.obj.archetypeID == 1'u

# ==========================================================
# STRESS TESTS
# ==========================================================
suite "Stress tests":

  test "Ping-pong archetype":
    var world = initWorld()
    let e = createEntity(world, 0)

    for i in 0..<10000:
      addComponent(world, e, 1)
      removeComponent(world, e, 1)

    check e.obj.archetypeID == 1'u

  test "Mass create / delete":
    var world = initWorld()
    var ents: seq[DenseHandle]

    for i in 0..<10000:
      ents.add(createEntity(world, 0))

    for i in 0..<5000:
      deleteEntity(world, ents[i])

    var alive = 0
    for e in ents:
      if world.isAlive(e): inc alive

    check alive == 5000

# ==========================================================
# QUERY INTEGRATION
# ==========================================================
suite "Query integration":

  test "Query reflects add/remove":
    var world = initWorld()
    let e = createEntity(world, 0)

    var q1 = query(world, Pos)
    check denseQueryCount(world, q1) == 1

    addComponent(world, e, 1)
    var q2 = query(world, Pos and Vel)
    check denseQueryCount(world, q2) == 1

    removeComponent(world, e, 1)
    check denseQueryCount(world, q2) == 0
