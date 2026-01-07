include "../../src/ecs/table.nim"

import unittest
import tables

##############################################
# Test components
############################################

type
  Position = object
    x, y: int

  Velocity = object
    dx, dy: int

############################################
# Helpers
############################################

proc setupWorld(): ECSWorld =
  var w: ECSWorld
  new(w.registry)
  registerComponent[Position](w.registry)
  registerComponent[Velocity](w.registry)
  w

############################################
# Tests
############################################

suite "ECS Table allocation":

  test "allocate single dense entity":
    var w = setupWorld()
    let arch = maskOf(0)

    let (bid, r) = w.allocateEntity(arch, @[0])

    check r.e - r.s == 1
    check bid == 0

  test "allocate multiple dense entities across blocks":
    var w = setupWorld()
    let arch = maskOf(0)

    let res = w.allocateEntities(DEFAULT_BLK_SIZE + 10, arch, @[0])

    check res.len == 2
    check res[0][1].e == DEFAULT_BLK_SIZE
    check res[1][1].e == 10

  test "activate and deactivate dense components":
    var w = setupWorld()
    let arch = maskOf(0, 1)

    let (bid, r) = w.allocateEntity(arch, @[0,1])
    let id = makeId((bid, r))

    w.activateComponents(id, @[0,1])
    w.deactivateComponents(id, @[1])

    let pos = getvalue[Position](w.registry.entries[0])
    let vel = getvalue[Velocity](w.registry.entries[1])

    check pos.mask.len > 0
    check vel.mask.len > 0

  test "delete dense row swaps last element":
    var w = setupWorld()
    let arch = maskOf(0)

    let (_, r1) = w.allocateEntity(arch, @[0])
    let (_, r2) = w.allocateEntity(arch, @[0])

    let id1 = r1.e-1
    let id2 = r2.e-1

    var pos = getvalue[Position](w.registry.entries[0])
    pos[id2] = Position(x: 99, y: 99)

    let last = w.deleteRow(id1, arch)

    check pos[id1].x == 99
    check last == id2.uint

suite "ECS Table sparse allocation":

  test "allocate sparse entity":
    var w = setupWorld()

    let id = w.allocateSparseEntity(@[0])

    check w.free_list.len == 0
    check id >= 0

  test "sparse delete reuses index":
    var w = setupWorld()

    let a = w.allocateSparseEntity(@[0])
    let b = w.allocateSparseEntity(@[0])

    w.deleteSparseRow(a.uint, @[0])

    let c = w.allocateSparseEntity(@[0])

    check c == a

  test "sparse activation sets sparse mask":
    var w = setupWorld()

    let id = w.allocateSparseEntity(@[0])
    w.activateComponentsSparse(id, @[0])

    let pos = getvalue[Position](w.registry.entries[0])
    let bid = id div (sizeof(uint)*8)

    check pos.sparse[bid].mask != 0

suite "ECS Table partition changes":

  test "change partition moves entity":
    var w = setupWorld()

    let archA = maskOf(0)
    let archB = maskOf(0,1)

    let (_, r) = w.allocateEntity(archA, @[0])
    let id = r.e-1

    var pos = getvalue[Position](w.registry.entries[0])
    pos[id] = Position(x: 7, y: 8)

    let (last, new_id, bid) = w.changePartition(id, archA, archB)
    let newIdx = (bid shl BLK_SHIFT) or new_id

    check pos[newIdx].x == 7
    check last >= 0

  test "partition removal shrinks correctly":
    var w = setupWorld()

    let arch = maskOf(0)
    let (_, r1) = w.allocateEntity(arch, @[0])
    let (_, r2) = w.allocateEntity(arch, @[0])

    discard w.deleteRow(r1.e-1, arch)

    let p = w.archetypes[arch]
    check p.zones[p.fill_index].r.e == 1
