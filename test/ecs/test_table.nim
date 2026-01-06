include "../../src/ecs/table.nim"

import unittest
import tables

############################################
# TEST COMPONENT TYPES
############################################

type
  Position = object
    x:int
    y:int

  Velocity = object
    vx:int
    vy:int

############################################
# HELPERS
############################################

proc newWorld(): ECSWorld =
  var w: ECSWorld
  w.registry = ComponentRegistry(entries: @[], cmap: initTable[string,int]())
  w.archetypes = initTable[ArchetypeMask, TablePartition]()
  w.pooltype = initTable[string,int]()
  w.free_list = @[]
  w.max_index = 0
  w.block_count = 0

  registerComponent[Position](w.registry)
  registerComponent[Velocity](w.registry)

  return w

############################################
# TESTS
############################################

suite "ECS Table – core invariants":

  test "World starts empty":
    let w = newWorld()
    check w.blockCount == 0
    check w.archetypes.len == 0
    check w.free_list.len == 0

  test "Create new archetype partition":
    var w = newWorld()
    let arch = maskOf(0)

    let p = createPartition(w, arch)
    check p.components == @[0]
    check w.archetypes.hasKey(arch)

  test "Allocate single entity":
    var w = newWorld()
    let arch = maskOf(0)

    let id = makeId(allocateEntity(w, arch, @[0]))
    check id == 0
    check w.blockCount == 1

  test "Allocate multiple entities in same archetype":
    var w = newWorld()
    let arch = maskOf(0)

    let ranges = allocateEntities(w, 10, arch, @[0])
    check ranges.len == 1
    check ranges[0][1].s == 0
    check ranges[0][1].e == 10

  test "Allocate entities creates new blocks when needed":
    var w = newWorld()
    let arch = maskOf(0)

    let n = DEFAULT_BLK_SIZE + 5
    let ranges = allocateEntities(w, n, arch, @[0])

    check w.blockCount >= 2
    check ranges.len == 2

  test "Activate and deactivate components":
    var w = newWorld()
    let arch = maskOf(0,1)

    let id = makeId(allocateEntity(w, arch, @[0,1]))
    activateComponents(w, id, @[0,1])
    deactivateComponents(w, id, @[1])

    let pos = getvalue[Position](w.registry.entries[0])
    let vel = getvalue[Velocity](w.registry.entries[1])

    let bid = id div DEFAULT_BLK_SIZE
    let lid = id mod DEFAULT_BLK_SIZE

    check ((pos.blocks[bid].mask shr lid) and 1) == 1
    check ((vel.blocks[bid].mask shr lid) and 1) == 0

  test "Delete row compacts data":
    var w = newWorld()
    let arch = maskOf(0)

    let id1 = makeId(allocateEntity(w, arch, @[0]))
    let id2 = makeId(allocateEntity(w, arch, @[0]))

    var pos = getvalue[Position](w.registry.entries[0])
    pos[id1] = Position(x: 1, y: 1)
    pos[id2] = Position(x: 9, y: 9)

    let moved = deleteRow(w, id1.int, arch)

    check moved == id2
    let p = pos[id1]
    check p.x == 9
    check p.y == 9

  test "Change partition moves entity correctly":
    var w = newWorld()
    let archA = maskOf(0)
    let archB = maskOf(0,1)

    let id = makeId(allocateEntity(w, archA, @[0]))
    var pos = getvalue[Position](w.registry.entries[0])
    pos[id] = Position(x: 42, y: 24)

    discard changePartition(w, id.int, archA, archB)

    let newPos = pos[id]
    check newPos.x == 42
    check newPos.y == 24

  test "Multiple archetypes coexist safely":
    var w = newWorld()
    let a1 = maskOf(0)
    let a2 = maskOf(1)

    let i1 = makeId(allocateEntity(w, a1, @[0]))
    let i2 = makeId(allocateEntity(w, a2, @[1]))

    var pos = getvalue[Position](w.registry.entries[0])
    var vel = getvalue[Velocity](w.registry.entries[1])

    pos[i1] = Position(x: 1, y: 2)
    vel[i2] = Velocity(vx: 3, vy: 4)

    check pos[i1].x == 1
    check vel[i2].vx == 3

  test "Block count only grows, never shrinks":
    var w = newWorld()
    let arch = maskOf(0)

    for i in 0..<DEFAULT_BLK_SIZE*2:
      discard makeId(allocateEntity(w, arch, @[0]))

    let bc = w.blockCount

    for i in 0..<DEFAULT_BLK_SIZE:
      discard deleteRow(w, i, arch)

    check w.blockCount == bc
