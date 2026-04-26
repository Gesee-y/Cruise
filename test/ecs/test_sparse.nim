import unittest, bitops
include "../../src/ecs/table.nim"

type
  Pos = object
    x:int
  Vel = object
    x:int
  Acc = object
    x:int

suite "Sparse ECS logic":

  test "allocate single sparse entity":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let e = w.createSparseEntity(Pos)
    check e.id == 0

    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)

    check mask[][0] == true

  test "allocate multiple sparse entities sequential":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let ents = w.createSparseEntities(10, Pos)
    check ents.len == 10

    for i,e in ents:
      check e.id == uint(i)

    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)

    for i in 0..<10:
      check ((mask[].getL0(0) shr i) and 1'u) == 1'u

  test "delete sparse entity and reuse id":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    var e1 = w.createSparseEntity(Pos)
    var e2 = w.createSparseEntity(Pos)

    w.deleteEntity(e1)

    let e3 = w.createSparseEntity(Pos)
    check e3.id == e1.id

  test "activate and deactivate sparse component":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)
    let vid = w.registerComponent(Vel)

    var e = w.createSparseEntity(Pos)
    w.addComponent(e, Vel)

    var pmask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)
    var vmask = w.registry.entries[vid].getSparseMaskOp(
      w.registry.entries[vid].rawPointer)

    check pmask[][0] == true
    check vmask[][0] == true
    w.removeComponent(e, Vel)

    check vmask[][0] == false

  test "batch allocate activates all bits":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let ents = w.createSparseEntities(64, Pos)
    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)

    check mask[].getL0(0) == (not 0'u)

  test "batch activation works":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)
    let vid = w.registerComponent(Vel)

    let ents = w.createSparseEntities(32, Pos)
    var ids: seq[uint]
    for e in ents: ids.add(e.id)

    w.activateComponentsSparse(ids, [vid])

    let vmask = w.registry.entries[vid].getSparseMaskOp(
      w.registry.entries[vid].rawPointer)

    for i in 0..<32:
      check ((vmask[].getL0(0) shr i) and 1'u) == 1'u

  test "batch deactivation works":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let ents = w.createSparseEntities(32, Pos)
    var ids: seq[uint]
    for e in ents: ids.add(e.id)

    w.deactivateComponentsSparse(ids, [pid])

    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)

    check mask[][0] == false
    check mask[].getL0(0) == 0'u

  test "free_list integrity after deletes":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    var ents = w.createSparseEntities(10, Pos)
    for i in 0..<ents.len:
      var e = ents[i]
      w.deleteEntity(e)

    check w.free_list.len == 64

    let e = w.createSparseEntity(Pos)
    check e.id < 10

  test "no ghost bits after delete":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    var e = w.createSparseEntity(Pos)
    w.deleteEntity(e)

    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)

    check mask[][0] == false
