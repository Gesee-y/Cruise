include "../../src/ecs/table.nim"

import unittest

type
  Pos = object
    x,y:float

  Vel = object
    dx,dy:float

  Acc = object
    ax,ay:float

proc initECSWorld(): ECSWorld =
  var world = newECSWorld()
  discard world.registerComponent(Pos)
  discard world.registerComponent(Vel)
  discard world.registerComponent(Acc)
  world

suite "Dense ECS Allocation Tests":

  test "createPartition initializes partition only once":
    var world = initECSWorld()

    let arch = world.archGraph.findArchetypeFast(maskOf(0, 1))

    let p1 = createPartition(world, arch)
    let p2 = createPartition(world, arch)

    check p1 == p2
    check p1.components.len == 2
    check p1.components.contains(0)
    check p1.components.contains(1)


  test "allocateEntities creates correct number of rows":
    var world = initECSWorld()
    let arch = maskOf(0, 1, 2)

    let res = allocateEntities(world, 100, arch)
    var total = 0
    for (_, r) in res:
      total += r.e - r.s

    check total == 100


  test "allocateEntities respects block boundaries":
    var world = initECSWorld()
    let arch = maskOf(0)

    let n = DEFAULT_BLK_SIZE * 2 + 13
    let res = allocateEntities(world, n, arch)

    var seen = 0
    for (_, r) in res:
      check r.e <= DEFAULT_BLK_SIZE
      check r.s < r.e
      seen += r.e - r.s

    check seen == n


  test "allocateEntity increments fill_index correctly":
    var world = initECSWorld()
    let arch = maskOf(0)
    let node = world.archGraph.findArchetypeFast(arch)

    for i in 0..<DEFAULT_BLK_SIZE:
      discard allocateEntity(world, arch)

    check node.partition.fill_index == 1


  test "deleteRow performs swap-back correctly":
    var world = initECSWorld()
    let arch = maskOf(0)

    let h1 = world.createEntity(arch)
    let h2 = world.createEntity(arch)

    let lastId = deleteRow(world, h1.obj.id, h1.obj.archetypeId)

    check lastId == h2.obj.id or lastId == h1.obj.id


suite "Dense ECS Migration Tests":

  test "changePartition moves entity to new archetype":
    var world = initECSWorld()
    let archA = maskOf(0)
    let archB = maskOf(0, 1)

    let h = world.createEntity(archA)
    let nodeB = world.archGraph.findArchetypeFast(archB)

    migrateEntity(world, h, nodeB)

    check h.obj.archetypeId == nodeB.id


  test "batch changePartition preserves entity count":
    var world = initECSWorld()
    let archA = maskOf(0)
    let archB = maskOf(0, 1)

    var ents = world.createEntities(128, archA)
    let nodeB = world.archGraph.findArchetypeFast(archB)

    migrateEntity(world, ents, nodeB)

    for e in ents:
      check e.obj.archetypeId == nodeB.id


suite "Sparse ECS Allocation Tests":

  test "allocateSparseEntity reuses free list":
    var world = initECSWorld()
    let comps = @[0, 1]

    let a = world.allocateSparseEntity(comps)
    deleteSparseRow(world, a, maskOf(comps))

    let b = world.allocateSparseEntity(comps)

    check a == b


  test "allocateSparseEntities returns correct ranges":
    var world = initECSWorld()
    let comps = @[0]

    let res = allocateSparseEntities(world, 100, comps)
    var total = 0

    for r in res:
      total += r.e - r.s

    check total == 100

suite "Dense <-> Sparse Conversion Tests":

  test "makeDense transfers all components":
    var world = initECSWorld()
    var s = world.createSparseEntity(0, 1, 2)

    let d = world.makeDense(s)

    check d.obj.archetypeId ==
      world.archGraph.findArchetypeFast(maskOf(0,1,2)).id


  test "makeSparse transfers all components":
    var world = initECSWorld()
    let d = world.createEntity(0, 1)

    var s = world.makeSparse(d)

    check s.mask[0] == 3'u

suite "Safety and Regression Tests":

  test "deleteRow on empty partition fails":
    var world = initECSWorld()
    let arch = maskOf(0)
    let node = world.archGraph.findArchetypeFast(arch)

    expect AssertionError:
      discard deleteRow(world, 0, node.id)


  test "changePartition rejects invalid archetype":
    var world = initECSWorld()
    let h = world.createEntity(maskOf(0))

    expect AssertionError:
      discard changePartition(world, h.obj.id, 9999, nil)
