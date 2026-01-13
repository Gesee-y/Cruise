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

    let e = w.createSparseEntity([pid])
    check e.id == 0

    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)

    check mask.len == 1
    check (mask[0] and 1'u) == 1'u

  test "allocate multiple sparse entities sequential":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let ents = w.createSparseEntities(10, [pid])
    check ents.len == 10

    for i,e in ents:
      check e.id == uint(i)

    let mask = w.registry.entries[pid].getSparseChunkMaskOp(
      w.registry.entries[pid].rawPointer, 0)

    for i in 0..<10:
      check ((mask shr i) and 1'u) == 1'u

  test "delete sparse entity and reuse id":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let e1 = w.createSparseEntity([pid])
    let e2 = w.createSparseEntity([pid])

    w.deleteEntity(e1)

    let e3 = w.createSparseEntity([pid])
    check e3.id == e1.id

  test "activate and deactivate sparse component":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)
    let vid = w.registerComponent(Vel)

    var e = w.createSparseEntity([pid])
    w.addComponent(e, vid)

    var pmask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)
    var vmask = w.registry.entries[vid].getSparseMaskOp(
      w.registry.entries[vid].rawPointer)

    check (pmask[0] and 1'u) == 1'u
    check (vmask[0] and 1'u) == 1'u

    w.removeComponent(e, vid)

    vmask = w.registry.entries[vid].getSparseMaskOp(
      w.registry.entries[vid].rawPointer)

    check (vmask[0] and 1'u) == 0'u

  test "batch allocate activates all bits":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let ents = w.createSparseEntities(64, [pid])
    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)
    let cmask = w.registry.entries[pid].getSparseChunkMaskOp(
      w.registry.entries[pid].rawPointer, 0)

    check mask.len == 1
    check cmask == (not 0'u)

  test "batch activation works":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)
    let vid = w.registerComponent(Vel)

    let ents = w.createSparseEntities(32, [pid])
    var ids: seq[uint]
    for e in ents: ids.add(e.id)

    w.activateComponentsSparse(ids, [vid])

    let vmask = w.registry.entries[vid].getSparseChunkMaskOp(
      w.registry.entries[vid].rawPointer,0)

    for i in 0..<32:
      check ((vmask shr i) and 1'u) == 1'u

  test "batch deactivation works":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let ents = w.createSparseEntities(32, [pid])
    var ids: seq[uint]
    for e in ents: ids.add(e.id)

    w.deactivateComponentsSparse(ids, [pid])

    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)
    let cmask = w.registry.entries[pid].getSparseChunkMaskOp(
      w.registry.entries[pid].rawPointer, 0)

    check mask[0] == 0'u
    check cmask == 0'u

  test "free_list integrity after deletes":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let ents = w.createSparseEntities(10, [pid])
    for e in ents:
      w.deleteEntity(e)

    check w.free_list.len == 64

    let e = w.createSparseEntity([pid])
    check e.id < 10

  test "no ghost bits after delete":
    var w = newECSWorld()
    let pid = w.registerComponent(Pos)

    let e = w.createSparseEntity([pid])
    w.deleteEntity(e)

    let mask = w.registry.entries[pid].getSparseMaskOp(
      w.registry.entries[pid].rawPointer)

    check (mask[0] and 1'u) == 0'u
