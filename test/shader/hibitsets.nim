import std/[unittest, sequtils, bitops]
include "../../src/shadert/hibitset.nim"

# ── reproduced helpers expected from the main module ─────────────────────────
# (bits manip only, no external deps needed for tests)
proc getTrailingZeroBits(x: uint8): int =
  if x == 0: return 8
  result = 0
  var v = x
  while (v and 1) == 0:
    inc result
    v = v shr 1

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

proc freshSet(): CAHiBitSet =
  ## Returns a zero-initialised bitset.
  result = CAHiBitSet()

proc setBits(h: var CAHiBitSet, indices: openArray[int]) =
  for i in indices: h.set(i)

proc allGet(h: CAHiBitSet, indices: openArray[int]): bool =
  for i in indices:
    if not h.get(i): return false
  true

proc noneGet(h: CAHiBitSet, indices: openArray[int]): bool =
  for i in indices:
    if h.get(i): return false
  true

# ─────────────────────────────────────────────────────────────────────────────
# 1. Primitives : set / get / unset
# ─────────────────────────────────────────────────────────────────────────────

suite "set / get / unset":

  test "get on empty bitset returns false":
    var h = freshSet()
    check not h.get(0)
    check not h.get(7)
    check not h.get(63)

  test "set a single bit then get returns true":
    var h = freshSet()
    h.set(0)
    check h.get(0)

  test "set bit 0 does not affect bit 1":
    var h = freshSet()
    h.set(0)
    check not h.get(1)

  test "set multiple non-overlapping bits":
    var h = freshSet()
    setBits(h, [0, 3, 7, 15, 63])
    check allGet(h, [0, 3, 7, 15, 63])
    check noneGet(h, [1, 2, 4, 5, 6, 8, 62])

  test "set triggers auto-growth":
    var h = freshSet()
    h.set(255)
    check h.get(255)
    check not h.get(254)

  test "unset a previously set bit":
    var h = freshSet()
    h.set(5)
    h.unset(5)
    check not h.get(5)

  test "unset propagates to layer1 when l0 block becomes empty":
    var h = freshSet()
    h.set(0)                 # l0[0] bit 0
    h.unset(0)
    check h.layer1[0] == 0  # layer1 bit must be cleared

  test "unset propagates to layer2 when l1 block becomes empty":
    var h = freshSet()
    h.set(0)
    h.unset(0)
    check h.layer2[0] == 0

  test "unset on unset bit is a no-op":
    var h = freshSet()
    h.unset(42)              # must not raise
    check not h.get(42)

  test "unset out-of-range is a no-op":
    var h = freshSet()
    h.unset(9999)            # must not raise / access-violation

  test "set same index twice remains set":
    var h = freshSet()
    h.set(10)
    h.set(10)
    check h.get(10)

# ─────────────────────────────────────────────────────────────────────────────
# 2. setL0Block / getL0
# ─────────────────────────────────────────────────────────────────────────────

suite "setL0Block / getL0":

  test "setL0Block writes the raw byte":
    var h = freshSet()
    h.setL0Block(0, 0b1010'u8)
    check h.getL0(0) == 0b1010'u8

  test "setL0Block updates layer1":
    var h = freshSet()
    h.setL0Block(0, 0xFF'u8)
    check (h.layer1[0] and 1'u8) != 0

  test "setL0Block clears layer1 when value is 0":
    var h = freshSet()
    h.setL0Block(0, 0xFF'u8)
    h.setL0Block(0, 0x00'u8)
    check (h.layer1[0] and 1'u8) == 0

  test "setL0Block updates layer2":
    var h = freshSet()
    h.setL0Block(0, 0xFF'u8)
    check (h.layer2[0] and 1'u8) != 0

  test "getL0 on out-of-range index returns 0":
    var h = freshSet()
    check h.getL0(999) == 0

# ─────────────────────────────────────────────────────────────────────────────
# 3. len
# ─────────────────────────────────────────────────────────────────────────────

suite "len":

  test "fresh bitset has len 0":
    var h = freshSet()
    check h.len == 0

  test "len grows after set":
    var h = freshSet()
    h.set(3)
    check h.len >= 4

  test "len is always a multiple of L0_BITS":
    var h = freshSet()
    h.set(7)
    check (h.len mod L0_BITS) == 0

# ─────────────────────────────────────────────────────────────────────────────
# 4. getSpace
# ─────────────────────────────────────────────────────────────────────────────

suite "getSpace":

  test "empty bitset: space starts at 0 for size 4":
    var h = freshSet()
    let s = h.getSpace(4)
    check s == 0

  test "after marking first 4 slots, next space advances":
    var h = freshSet()
    for i in 0..<4: h.set(i)
    let s = h.getSpace(4)
    check s >= 4

  test "getSpace(8) returns a contiguous 8-slot region on a fresh bitset":
    var h = freshSet()
    let s = h.getSpace(8)
    check s >= 0            # valid offset returned

  test "getSpace honours already-filled slots":
    var h = freshSet()
    # Fill bits 0..3
    for i in 0..<4: h.set(i)
    let s = h.getSpace(4)
    # The returned start must not overlap [0,3]
    check s >= 4

  test "getSpace(16) on fresh bitset":
    var h = freshSet()
    let s = h.getSpace(16)
    check s >= 0

# ─────────────────────────────────────────────────────────────────────────────
# 5. fillAlloc / freeRange
# ─────────────────────────────────────────────────────────────────────────────

suite "fillAlloc / freeRange":

  test "fillAlloc marks a single aligned slot (size 1)":
    var h = freshSet()
    h.fillAlloc(0, 1)
    check h.get(0)
    check h.get(1)
    check not h.get(2)

  test "fillAlloc marks 4 aligned slots (one L0 block)":
    var h = freshSet()
    h.fillAlloc(0, 4)
    for i in 0..<8:
      check h.get(i)
    check not h.get(8)

  test "fillAlloc marks 16 aligned slots (one L1 block)":
    var h = freshSet()
    h.fillAlloc(0, 16)
    for i in 0..<32:
      check h.get(i)
    check not h.get(32)

  test "fillAlloc marks 64 aligned slots (one L2 block)":
    var h = freshSet()
    h.fillAlloc(0, 64)
    for i in 0..<128:
      check h.get(i)
    check not h.get(128)

  test "fillAlloc with unaligned start":
    var h = freshSet()
    h.fillAlloc(2, 6)          # bits 2..14
    for i in 2..<14:
      check h.get(i)
    check not h.get(0)
    check not h.get(1)
    check not h.get(15)

  test "fillAlloc large range spanning multiple L2 blocks":
    var h = freshSet()
    h.fillAlloc(0, 128)
    for i in 0..<256:
      check h.get(i)
    check not h.get(256)

  test "freeRange releases a single slot":
    var h = freshSet()
    h.fillAlloc(0, 4)
    h.freeRange(0, 1)
    check not h.get(0)
    check h.get(2)

  test "freeRange releases a full L0 block":
    var h = freshSet()
    h.fillAlloc(0, 4)
    h.freeRange(0, 4)
    for i in 0..<4:
      check not h.get(i)
    check h.layer1[0] == 0

  test "freeRange releases a full L1 block":
    var h = freshSet()
    h.fillAlloc(0, 16)
    h.freeRange(0, 16)
    for i in 0..<16:
      check not h.get(i)
    check h.layer2[0] == 0

  test "freeRange releases a full L2 block":
    var h = freshSet()
    h.fillAlloc(0, 64)
    h.freeRange(0, 64)
    for i in 0..<64:
      check not h.get(i)
    check h.layer2[0] == 0

  test "freeRange with unaligned suffix":
    var h = freshSet()
    h.fillAlloc(0, 8)
    h.freeRange(0, 5)          # free bits 0..10
    for i in 0..<10:
      check not h.get(i)
    for i in 10..<16:
      check h.get(i)

  test "freeRange out-of-range start is a no-op":
    var h = freshSet()
    h.freeRange(9999, 4)       # must not raise

  test "fillAlloc then freeRange then fillAlloc reuses space":
    var h = freshSet()
    h.fillAlloc(0, 4)
    h.freeRange(0, 4)
    h.fillAlloc(0, 4)
    for i in 0..<4:
      check h.get(i)


suite "clear":

  test "clear resets all bits":
    var h = freshSet()
    setBits(h, [0, 5, 15, 63, 127])
    h.clear()
    check noneGet(h, [0, 5, 15, 63, 127])

  test "clear zeroes all three layers":
    var h = freshSet()
    h.fillAlloc(0, 64)
    h.clear()
    for b in h.layer0: check b == 0
    for b in h.layer1: check b == 0
    for b in h.layer2: check b == 0

  test "can set bits after clear":
    var h = freshSet()
    h.fillAlloc(0, 16)
    h.clear()
    h.set(3)
    check h.get(3)

# ─────────────────────────────────────────────────────────────────────────────
# 8. Cas limites & stress
# ─────────────────────────────────────────────────────────────────────────────

suite "edge cases":

  test "set and unset all bits in a 64-slot range":
    var h = freshSet()
    for i in 0..<64: h.set(i)
    for i in 0..<64: h.unset(i)
    check h.layer2[0] == 0

  test "alternating set/unset on the same index":
    var h = freshSet()
    for _ in 0..<100:
      h.set(7)
      check h.get(7)
      h.unset(7)
      check not h.get(7)

  test "sparse set across multiple L2 regions":
    var h = freshSet()
    let indices = [0, 64, 128, 192, 255]
    setBits(h, indices)
    check allGet(h, indices)

  test "fillAlloc size 0 is a no-op":
    var h = freshSet()
    h.fillAlloc(0, 0)
    check not h.get(0)

  test "freeRange size 0 is a no-op":
    var h = freshSet()
    h.fillAlloc(0, 4)
    h.freeRange(0, 0)
    check h.get(0)

  test "freeRange does not affect bits outside the range":
    var h = freshSet()
    h.fillAlloc(0, 8)
    h.freeRange(2, 4)     # free bits 2..10
    check h.get(0)
    check h.get(1)
    check h.get(11)
    check h.get(12)

  test "stress: set 256 bits then free all":
    var h = freshSet()
    for i in 0..<256: h.set(i)
    h.freeRange(0, 256)
    for i in 0..<256: check not h.get(i)
    check h.layer2[0] == 0
    check h.layer2[1] == 0
    check h.layer2[2] == 0
    check h.layer2[3] == 0