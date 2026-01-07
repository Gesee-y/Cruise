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
  var w: ECSWorld
  new(w)
  new(w.registry)
  registerComponent[Pos](w.registry)
  registerComponent[Vel](w.registry)
  registerComponent[Acc](w.registry)
  return w

# ==========================================================
# ENTITY CREATION
# ==========================================================
suite "ECS Entity creation":

  test "Create entity with one component":
    var world = initWorld()
    let e = createEntity(world, [Pos(x:1, y:2)])

    let idx = int(e.id and ((1'u shl 32)-1))
    check world.entities[idx] == e
    check e.archetype[0] == 1'u

  test "Create entity with multiple components":
    var world = initWorld()
    let e = createEntity(world, Pos(x:3,y:4), Vel(vx:1,vy:1))

    let idx = int(e.id and ((1'u shl 32)-1))
    check world.entities[idx] == e
    check e.archetype.countBits() == 2

# ==========================================================
# COMPONENT ACCESS
# ==========================================================
suite "Component access":

  test "Read / write component through entity":
    var world = initWorld()
    let e = createEntity(world, Pos(x:10,y:20))

    world.registry.entries[0] # force instantiation
    var pos = castTo(world.registry.entries[0].rawPointer, Pos, DEFAULT_BLK_SIZE)

    pos[e].x = 42
    check pos[e].x == 42
    check pos[e].y == 20

# ==========================================================
# DELETE ENTITY
# ==========================================================
suite "Entity deletion":

  test "Delete entity swaps correctly":
    var world = initWorld()

    let a = createEntity(world, Pos(x:1,y:1))
    let b = createEntity(world, Pos(x:2,y:2))
    let c = createEntity(world, Pos(x:3,y:3))

    let bidB = b.id
    deleteEntity(world, b)

    let idxC = int(c.id and ((1'u shl 32)-1))
    check world.entities[idxC] == c
    check c.id != bidB

  test "Delete last entity":
    var world = initWorld()
    let a = createEntity(world, Pos(x:5,y:5))
    deleteEntity(world, a)
    check world.entities.len == 0 or world.entities[0].isNil

# ==========================================================
# ADD COMPONENT
# ==========================================================
suite "Add component":

  test "Add new component changes archetype and id":
    var world = initWorld()
    let e = createEntity(world, Pos(x:1,y:1))
    let oldId = e.id

    addComponent(world, e, Vel(vx:2,vy:3))
    check e.id != oldId
    check e.archetype.countBits() == 2

  test "Add existing component does nothing":
    var world = initWorld()
    let e = createEntity(world, Pos(x:1,y:1))
    let oldId = e.id

    addComponent(world, e, Pos(x:9,y:9))
    check e.id == oldId
    check e.archetype.countBits() == 1

# ==========================================================
# REMOVE COMPONENT
# ==========================================================
suite "Remove component":

  test "Remove existing component":
    var world = initWorld()
    let e = createEntity(world, Pos(x:1,y:1), Vel(vx:1,vy:1))
    let oldId = e.id

    removeComponent(world, e, Vel)
    check e.id != oldId
    check e.archetype.countBits() == 1

  test "Remove absent component does nothing":
    var world = initWorld()
    let e = createEntity(world, Pos(x:1,y:1))
    let oldId = e.id

    removeComponent(world, e, Vel)
    check e.id == oldId
    check e.archetype.countBits() == 1

# ==========================================================
# STRESS TESTS
# ==========================================================
suite "Stress tests":

  test "Ping-pong archetype":
    var world = initWorld()
    let e = createEntity(world, Pos(x:0,y:0))

    for i in 0..<10000:
      addComponent(world, e, Vel(vx:i,vy:i))
      removeComponent(world, e, Vel)

    check e.archetype.countBits() == 1

  test "Mass create / delete":
    var world = initWorld()
    var ents: seq[Entity]

    for i in 0..<10000:
      ents.add(createEntity(world, Pos(x:i,y:i)))

    for i in 0..<5000:
      deleteEntity(world, ents[i])

    var alive = 0
    for e in world.entities:
      if not e.isNil: inc alive

    check alive == 5000

# ==========================================================
# QUERY INTEGRATION
# ==========================================================
suite "Query integration":

  test "Query reflects add/remove":
    var world = initWorld()
    let e = createEntity(world, Pos(x:1,y:1))

    var q1 = query(world, Pos)
    check denseQueryCount(world, q1) == 1

    addComponent(world, e, Vel(vx:1,vy:1))
    var q2 = query(world, Pos and Vel)
    check denseQueryCount(world, q2) == 1

    removeComponent(world, e, Vel)
    check denseQueryCount(world, q2) == 0
