include "../../src/ecs/table.nim"
import unittest

type
  Position = object
    x, y, z: float32

  Velocity = object
    dx, dy, dz: float32

proc newPosition(x, y, z: float32): Position =
  Position(x: x, y: y, z:z)

proc setComponent[T](blk: ptr T, i: uint, v: Position) =
  blk.data.x[i] = v.x * 2
  blk.data.y[i] = v.y / 2


#############################################
## BASIC CONSTRUCTION
#############################################

suite "FragmentArray construction":

  test "Empty array is valid":
    var arr = newSoAFragArr(Position, 8)
    check arr.blocks.len == 0
    check arr.sparse.len == 0

  test "Explicit block creation":
    var arr = newSoAFragArr(Position, 4)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    check arr.blocks.len == 1
    check not arr.blocks[0].isNil
    check arr.blocks[0].offset == 0


#############################################
## READ / WRITE SEMANTICS
#############################################

suite "Read / Write correctness":

  test "Write then read same index":
    var arr = newSoAFragArr(Position, 8)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[3] = Position(x:1, y:2, z:3)
    let p = arr[3]

    check p.x == 1
    check p.y == 2
    check p.z == 3

  test "Overwrite value replaces old one":
    var arr = newSoAFragArr(Position, 8)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[1] = Position(x:1)
    arr[1] = Position(x:42)

    check arr[1].x == 42


#############################################
## BLOCK BOUNDARIES
#############################################

suite "Block boundaries and offsets":

  test "Multiple blocks store correct offsets":
    var arr = newSoAFragArr(Position, 4)
    arr.blocks.setLen(3)
    arr.newBlockAt(0)
    arr.newBlockAt(1)
    arr.newBlockAt(2)

    arr[0]  = Position(x:0)
    arr[4]  = Position(x:4)
    arr[8]  = Position(x:8)

    check arr[0].x == 0
    check arr[4].x == 4
    check arr[8].x == 8

  test "Access outside block count fails":
    var arr = newSoAFragArr(Position, 4)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    expect IndexDefect:
      discard arr[7]


#############################################
## ITERATION
#############################################

suite "Iteration":

  test "Iterator yields all elements in order":
    var arr = newSoAFragArr(Position, 2)
    arr.blocks.setLen(2)
    arr.newBlockAt(0)
    arr.newBlockAt(1)

    arr[0] = Position(x:1)
    arr[1] = Position(x:2)
    arr[2] = Position(x:3)
    arr[3] = Position(x:4)

    var xs: seq[int]
    for p in arr.iter:
      xs.add(p.x.int)

    check xs == @[1,2,3,4]

  test "Pairs iterator returns correct indices":
    var arr = newSoAFragArr(Position, 2)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[0] = Position(x:10)
    arr[1] = Position(x:20)

    var seen: seq[(int,int)]
    for (i,p) in arr.pairs:
      seen.add((i,p.x.int))

    check seen == @[(0,10),(1,20)]


#############################################
## DENSE UINT INDEXING
#############################################

suite "Dense uint indexing":

  test "uint index maps to correct block and offset":
    var arr = newSoAFragArr(Position, 4)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    let idx = (0'u shl BLK_SHIFT) or 2'u
    arr[idx] = Position(x:99)

    check arr[idx].x == 99


#############################################
## CHANGE TRACKING (P = true)
#############################################

suite "Change tracking":

  test "Value mask updated on write":
    var arr = newSoAFragArr(Position, 8, true)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[5] = Position(x:7)

    let blk = arr.blocks[0]
    let bit = (blk.valMask[0] shr 5) and 1
    check bit == 1

  test "Multiple writes set multiple bits":
    var arr = newSoAFragArr(Position, 8, true)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[1] = Position(x:1)
    arr[6] = Position(x:2)

    let mask = arr.blocks[0].valMask[0]
    check (mask and (1'u shl 1)) != 0
    check (mask and (1'u shl 6)) != 0


#############################################
## SPARSE ACTIVATION
#############################################

suite "Sparse activation":

  test "Activate sparse bit":
    var arr = newSoAFragArr(Position, 8)
    arr.activateSparseBit(3)

    let bid = 3 div (sizeof(uint)*8)
    let id  = arr.toSparse[bid] - 1

    check (arr.sparse[id].mask and (1'u shl 3)) != 0

  test "Deactivate sparse bit clears mask":
    var arr = newSoAFragArr(Position, 8)
    arr.activateSparseBit(2)
    arr.deactivateSparseBit(2)

    let bid = 2 div (sizeof(uint)*8)
    let id  = arr.toSparse[bid] - 1

    check arr.sparse[id].mask == 0'u


#############################################
## MULTI-COMPONENT SAFETY
#############################################

suite "Different component types do not interfere":

  test "Position and Velocity arrays are independent":
    var pos = newSoAFragArr(Position, 4)
    var vel = newSoAFragArr(Velocity, 4)

    pos.blocks.setLen(1)
    vel.blocks.setLen(1)
    pos.newBlockAt(0)
    vel.newBlockAt(0)

    pos[1] = Position(x:1)
    vel[1] = Velocity(dx:5)

    check pos[1].x == 1
    check vel[1].dx == 5


#############################################
## STRESS-LIKE SANITY
#############################################

suite "High volume sanity":

  test "Write many values across blocks":
    var arr = newSoAFragArr(Position, 16)
    arr.blocks.setLen(4)
    for i in 0..<4:
      arr.newBlockAt(i)

    for i in 0..<64:
      arr[i] = Position(x:i.float32)

    for i in 0..<64:
      check arr[i].x == i.float32

type Pos = object
  x, y: float32

proc newPos(x, y: float32): Pos =
  Pos(x: x, y: y)

proc setComponent[T](blk: ptr T, i: uint, v: Pos) =
  blk.data.x[i] = v.x * 2
  blk.data.y[i] = v.y / 2


#############################################
## TESTS
#############################################

suite "P=true getter/setter semantics":

  test "Setter modifies stored data":
    var arr = newSoAFragArr(Pos, 8, true)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[3] = Pos(x:10, y:20)

    let blk = arr.blocks[0]

    check blk.data.x[3] == 20      # x * 2
    check blk.data.y[3] == 10      # y / 2

  test "Getter returns logical value via constructor":
    var arr = newSoAFragArr(Pos, 8, true)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[1] = Pos(x:4, y:8)

    let p = arr[1]

    # getter returns Pos constructed from stored data
    check p.x == 8
    check p.y == 4

  test "Multiple writes use setter every time":
    var arr = newSoAFragArr(Pos, 8, true)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[2] = Pos(x:1, y:2)
    arr[2] = Pos(x:3, y:6)

    let blk = arr.blocks[0]

    check blk.data.x[2] == 6
    check blk.data.y[2] == 3

  test "Change mask is updated when P=true":
    var arr = newSoAFragArr(Pos, 8, true)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    arr[5] = Pos(x:1, y:1)

    let blk = arr.blocks[0]
    let bit = (blk.valMask[0] shr 5) and 1

    check bit == 1

  test "Getter does not expose raw storage":
    var arr = newSoAFragArr(Pos, 8, true)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    # manually poison storage
    arr.blocks[0].data.x[0] = 100
    arr.blocks[0].data.y[0] = 50

    let p = arr[0]

    check p.x == 100
    check p.y == 50

    # now use setter
    arr[0] = Pos(x:10, y:20)
    let p2 = arr[0]

    check p2.x == 20
    check p2.y == 10


#############################################
## NEGATIVE SAFETY
#############################################

suite "P=true safety":

  test "Out of bounds still fails":
    var arr = newSoAFragArr(Pos, 4, true)
    arr.blocks.setLen(1)
    arr.newBlockAt(0)

    expect IndexDefect:
      discard arr[7]

