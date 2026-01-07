include "../../src/ecs/fragment.nim"
import unittest

############################################
# Test component
############################################

type TestComp = object
  x: int
  y: int

############################################
# Tests
############################################

suite "SoAFragmentArray core behavior":

  test "SoA macro splits fields correctly":
    var f = newSoAFragArr(TestComp,8)
    f.blocks.setLen(1)
    f.newBlockAt(0)

    f[0] = TestComp(x: 1, y: 2)
    f[1] = TestComp(x: 3, y: 4)

    check f[0].x == 1
    check f[0].y == 2
    check f[1].x == 3
    check f[1].y == 4

  test "newBlockAt sets correct offset":
    var f = newSoAFragArr(TestComp,8)
    f.blocks.setLen(3)
    f.newBlockAt(2)

    check f.blocks[2].offset == 16

  test "newBlock inserts blocks in sorted order":
    var f = newSoAFragArr(TestComp,8)

    discard f.newBlock(16)
    discard f.newBlock(0)
    discard f.newBlock(8)

    check f.blocks.len == 3
    check f.blocks[0].offset == 0
    check f.blocks[1].offset == 8
    check f.blocks[2].offset == 16

  test "int and uint indexing are equivalent":
    var f = newSoAFragArr(TestComp,8)
    f.blocks.setLen(1)
    f.newBlockAt(0)

    f[3] = TestComp(x: 42, y: 7)

    let u = (0'u shl BLK_SHIFT) or 3'u
    check f[3].x == f[u].x
    check f[3].y == f[u].y

  test "activateBit sets dense block and global mask":
    var f = newSoAFragArr(TestComp,8)
    f.blocks.setLen(1)
    f.newBlockAt(0)

    f.activateBit(3)

    check (f.blocks[0].mask and (1'u shl 3)) != 0
    check f.mask.len == 1
    check (f.mask[0] and 1'u) != 0

  test "deactivateBit clears block mask and global mask when empty":
    var f = newSoAFragArr(TestComp,8)
    f.blocks.setLen(1)
    f.newBlockAt(0)

    f.activateBit(2)
    f.deactivateBit(2)

    check f.blocks[0].mask == 0
    check f.mask[0] == 0

  test "multiple active bits keep global mask alive":
    var f = newSoAFragArr(TestComp,8)
    f.blocks.setLen(1)
    f.newBlockAt(0)

    f.activateBit(1)
    f.activateBit(3)
    f.deactivateBit(1)

    check (f.blocks[0].mask and (1'u shl 3)) != 0
    check f.mask[0] != 0

  test "overrideVals copies all fields":
    var f = newSoAFragArr(TestComp,8)
    f.blocks.setLen(1)
    f.newBlockAt(0)

    f[0] = TestComp(x: 1, y: 2)
    f[5] = TestComp(x: 9, y: 8)

    overrideVals(f.blocks[0], 0, 5)

    check f[0].x == 9
    check f[0].y == 8

  test "iterator iterates over full block":
    var f = newSoAFragArr(TestComp,4)
    f.blocks.setLen(1)
    f.newBlockAt(0)

    for i in 0..<4:
      f[i] = TestComp(x: i, y: i*10)

    var sum = 0
    for v in f.iter:
      sum += v.x

    check sum == 6

  test "pairs iterator yields correct global indices":
    var f = newSoAFragArr(TestComp,4)
    f.blocks.setLen(2)
    f.newBlockAt(0)
    f.newBlockAt(1)

    f[0] = TestComp(x: 1, y: 0)
    f[5] = TestComp(x: 6, y: 0)

    var seen = 0
    for (i, v) in f.pairs:
      if v.x != 0:
        check i == v.x-1
        inc seen

    check seen == 2

  test "sparse block creation sets sparse mask correctly":
    var f = newSoAFragArr(TestComp,8)

    f.newSparseBlock(0, 0b101'u)

    check f.sparse.len == 1
    check f.sparse[0].mask == 0b101'u
    check f.sparseMask.len == 1
    check f.sparseMask[0] != 0

  test "activateSparseBit sets sparse masks":
    var f = newSoAFragArr(TestComp,8)

    f.newSparseBlock(0, 0)
    f.activateSparseBit(3)

    check (f.sparse[0].mask and (1'u shl 3)) != 0
    check f.sparseMask[0] != 0
