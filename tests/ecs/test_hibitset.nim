import std/[unittest, sequtils, algorithm, random, hashes]
include "../../src/ecs/table.nim"

randomize(1234)

suite "HiBitSet (Dense)":

  test "basic set/get/unset":
    var h = newHiBitSet(128)
    h.set(5)
    h.set(64)
    h.set(127)

    check h.get(5)
    check h[64]
    check h.get(127)
    check not h.get(3)

    h.unset(64)
    check not h.get(64)

  test "auto grow":
    var h = newHiBitSet(8)
    h.set(500)
    check h.get(500)
    check h.len >= 501

  test "clear":
    var h = newHiBitSet(128)
    for i in 0..50: h.set(i)
    h.clear()
    for i in 0..50:
      check not h.get(i)
    check h.card == 0

  test "cardinality":
    var h = newHiBitSet(256)
    for i in 0..100:
      if i mod 3 == 0: h.set(i)
    check h.card == 34

  test "items iterator":
    var h = newHiBitSet(256)
    let values = @[1, 5, 63, 64, 130]
    for v in values: h.set(v)

    var collected: seq[int]
    for x in h: collected.add(x)
    collected.sort()

    check collected == values.sorted()

  test "blkIter":
    var h = newHiBitSet(512)
    h.set(1)
    h.set(70)
    h.set(130)

    var blks: seq[int]
    for b in h.blkIter: blks.add(b)

    check blks.len == 3
    check (1 shr 6) in blks
    check (70 shr 6) in blks
    check (130 shr 6) in blks

  test "bitwise ops":
    var a = newHiBitSet(128)
    var b = newHiBitSet(128)

    a.set(1); a.set(2); a.set(3)
    b.set(3); b.set(4)

    let aand = a and b
    let oor  = a or b
    let xxor = a xor b

    check aand.card == 1
    check aand.get(3)

    check oor.card == 4
    check oor.get(4)

    check xxor.card == 3
    check xxor.get(1)
    check xxor.get(2)
    check xxor.get(4)

  test "not":
    var h = newHiBitSet(64)
    h.set(1)
    h.set(3)

    let n = not h
    check not n.get(1)
    check not n.get(3)
    check n.get(0)
    check n.get(2)


suite "SparseHiBitSet":

  test "basic set/get/unset":
    var h = newSparseHiBitSet()
    h.set(10)
    h.set(1_000_000)

    check h.get(10)
    check h.get(1_000_000)

    h.unset(10)
    check not h.get(10)

  test "clear and isEmpty":
    var h = newSparseHiBitSet()
    for i in 0..20: h.set(i)
    check not h.isEmpty
    h.clear()
    check h.isEmpty

  test "cardinality":
    var h = newSparseHiBitSet()
    for i in 0..200:
      if i mod 5 == 0: h.set(i)
    check h.card == 41

  test "items iterator":
    var h = newSparseHiBitSet()
    let values = @[2, 7, 99, 1000, 100000]
    for v in values: h.set(v)

    var collected: seq[int]
    for x in h: collected.add(x)
    collected.sort()

    check collected == values.sorted()

  test "blkIter":
    var h = newSparseHiBitSet()
    h.set(1)
    h.set(70)
    h.set(130)

    var blks: seq[int]
    for b in h.blkIter: blks.add(b)

    check blks.len == 3

  test "bitwise ops":
    var a = newSparseHiBitSet()
    var b = newSparseHiBitSet()

    a.set(1); a.set(2); a.set(3)
    b.set(3); b.set(4)

    let aand = a and b
    let oor  = a or b
    let xxor = a xor b

    check aand.card == 1
    check aand.get(3)

    check oor.card == 4
    check oor.get(4)

    check xxor.card == 3
    check xxor.get(1)
    check xxor.get(2)
    check xxor.get(4)


