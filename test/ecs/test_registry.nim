include "../../src/ecs/fragment.nim"
import tables
include "../../src/ecs/registry.nim"
import unittest

############################################
# TEST COMPONENT TYPE
############################################

type
  Position = object
    x:int
    y:int
  
  Velocity = object
    vx:int
    vy:int

const
  N = 8

############################################
# HELPERS
############################################

proc newRegistry(): ComponentRegistry =
  var r: ComponentRegistry
  new(r)
  r.entries = @[]
  r.cmap = initTable[string,int]()
  r

############################################
# TESTS
############################################

suite "ComponentRegistry – core behavior":

  test "Register single component":
    var reg = newRegistry()
    registerComponent[Position](reg)

    check reg.entries.len == 1
    check reg.cmap.hasKey("Position")
    check reg.cmap["Position"] == 0

  test "Retrieve component entry by index":
    var reg = newRegistry()
    registerComponent[Position](reg)

    let entry = reg.getEntry(0)
    check entry.rawPointer != nil

  test "Resize operation affects fragment array":
    var reg = newRegistry()
    registerComponent[Position](reg)

    let entry = reg.getEntry(0)
    entry.resizeOp(entry.rawPointer, 2)

    let frag = getvalue[Position](entry)
    check frag.blocks.len == 2

  test "New block at specific index":
    var reg = newRegistry()
    registerComponent[Position](reg)

    let entry = reg.getEntry(0)
    entry.resizeOp(entry.rawPointer, 1)
    entry.newBlockAtOp(entry.rawPointer, 0)

    let frag = getvalue[Position](entry)
    check frag.blocks[0] != nil
    check frag.blocks[0].offset == 0

  test "New block with offset":
    var reg = newRegistry()
    registerComponent[Position](reg)

    let entry = reg.getEntry(0)
    entry.newBlockOp(entry.rawPointer, 0)
    
    let frag = getvalue[Position](entry)
    check frag.blocks.len == 1

  test "Activate bit sets fragment mask":
    var reg = newRegistry()
    registerComponent[Position](reg)

    let entry = reg.getEntry(0)
    entry.newBlockOp(entry.rawPointer, 0)
    entry.activateBitOp(entry.rawPointer, 3)

    let frag = getvalue[Position](entry)
    let bid = 3 div N
    let lid = 3 mod N

    check ((frag.blocks[bid].mask shr lid) and 1) == 1

  test "Deactivate bit clears fragment mask":
    var reg = newRegistry()
    registerComponent[Position](reg)

    let entry = reg.getEntry(0)
    entry.newBlockOp(entry.rawPointer, 0)
    entry.activateBitOp(entry.rawPointer, 2)
    entry.deactivateBitOp(entry.rawPointer, 2)

    let frag = getvalue[Position](entry)
    let bid = 2 div N
    let lid = 2 mod N

    check ((frag.blocks[bid].mask shr lid) and 1) == 0

  test "Override values moves data correctly":
    var reg = newRegistry()
    registerComponent[Position](reg)

    let entry = reg.getEntry(0)
    entry.newBlockOp(entry.rawPointer, 0)

    var frag = getvalue[Position](entry)
    frag[0] = Position(x: 1, y: 1)
    frag[1] = Position(x: 9, y: 9)

    entry.overrideValsOp(entry.rawPointer, 0, 1)

    let p = frag[0]
    check p.x == 9
    check p.y == 9

  test "Multiple registry entries remain independent":

    var reg = newRegistry()
    registerComponent[Position](reg)
    registerComponent[Velocity](reg)

    check reg.entries.len == 2
    check reg.cmap["Position"] == 0
    check reg.cmap["Velocity"] == 1

    let posEntry = reg.getEntry(0)
    let velEntry = reg.getEntry(1)

    posEntry.newBlockOp(posEntry.rawPointer, 0)
    velEntry.newBlockOp(velEntry.rawPointer, 0)

    var posFrag = getvalue[Position](posEntry)
    var velFrag = getvalue[Velocity](velEntry)

    posFrag[0] = Position(x: 3, y: 4)
    velFrag[0] = Velocity(vx: 7, vy: 8)

    check posFrag[0].x == 3
    check velFrag[0].vx == 7
