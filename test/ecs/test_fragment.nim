include "../../src/ecs/fragment.nim"
import unittest

############################################
# TEST TYPES
############################################

type
  Position = object
    x:int
    y:int

const
  N = 8

############################################
# HELPERS
############################################

proc newArray(): SoAFragmentArray[N, tuple[x: array[N,int], y: array[N,int]], Position] =
  var a: SoAFragmentArray[N, tuple[x: array[N,int], y: array[N,int]], Position]
  new(a)
  a.blocks = @[]
  a.sparse = @[]
  a.mask = @[0.uint]
  a

############################################
# TESTS
############################################

suite "SoAFragmentArray – core behavior":

  test "Create empty array":
    let a = newArray()
    check a.blocks.len == 0
    check a.sparse.len == 0

  test "Insert first block":
    var a = newArray()
    let ok = newBlock(a, 0)
    check ok
    check a.blocks.len == 1
    check a.blocks[0].offset == 0

  test "Reject overlapping block":
    var a = newArray()
    discard newBlock(a, 0)
    let ok = newBlock(a, 4)
    check ok == false

  test "Insert non-overlapping blocks":
    var a = newArray()
    check newBlock(a, 0)
    check newBlock(a, N)
    check newBlock(a, 2*N)
    check a.blocks.len == 3

  test "Block index calculation":
    var a = newArray()
    discard newBlock(a, 0)
    discard newBlock(a, N)
    check getBlockIdx(a, 0) == 0
    check getBlockIdx(a, N+1) == 1

  test "Write and read component values":
    var a = newArray()
    discard newBlock(a, 0)

    a[0] = Position(x: 1, y: 2)
    a[3] = Position(x: 10, y: 20)

    let p0 = a[0]
    let p3 = a[3]

    check p0.x == 1
    check p0.y == 2
    check p3.x == 10
    check p3.y == 20

  test "Override values works":
    var a = newArray()
    discard newBlock(a, 0)

    a[0] = Position(x: 1, y: 1)
    a[1] = Position(x: 9, y: 9)

    overrideVals(a.blocks[0], 0, 1)
    let p = a[0]
    check p.x == 9
    check p.y == 9

  test "Activate and deactivate bits":
    var a = newArray()
    discard newBlock(a, 0)

    activateBit(a, 2)
    let bid = 2 div N
    let lid = 2 mod N

    check ((a.blocks[bid].mask shr lid) and 1) == 1

    deactivateBit(a, 2)
    check ((a.blocks[bid].mask shr lid) and 1) == 0

  test "Indexing with uint encoding":
    var a = newArray()
    discard newBlock(a, 0)

    a[0] = Position(x: 5, y: 6)

    let idx = (uint(0) shl BLK_SHIFT) or uint(0)
    let p = a[idx]

    check p.x == 5
    check p.y == 6

  test "Fragment iteration yields correct values":
    var a = newArray()
    discard newBlock(a, 0)

    for i in 0..<N:
      a[i] = Position(x: i, y: i*2)

    var sum = 0
    for p in a.iter:
      sum += p.x

    check sum == (N*(N-1)) div 2

  test "Pairs iterator yields correct indices":
    var a = newArray()
    discard newBlock(a, 0)

    a[4] = Position(x: 42, y: 0)

    for (i, p) in pairs(a):
      if i == 4:
        check p.x == 42

  test "Resize increases block count":
    var a = newArray()
    resize(a, 3)
    check a.blocks.len == 3

  test "Sparse block creation and free":
    var a = newArray()
    newSparseBlock(a, 0)
    check a.sparse.len == 1

    freeSparseBlock(a, 0)
    check a.sparse[0] == nil
