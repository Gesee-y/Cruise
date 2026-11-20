import std/[assertions, syncio]

include ../../src/CVM/hibitset

proc expect(condition: bool; message: string) =
  assert condition, message

proc testBitsAndHierarchy() =
  var bits = CAHiBitSet()

  expect bits.len == 0, "a new bitset must be empty"
  expect not bits.get(0), "an out-of-range bit is free"

  bits.set(0)
  bits.set(17)
  expect bits.get(0), "set must mark the requested bit"
  expect bits.get(17), "set must grow every hierarchy layer"
  expect bits.getL0(0) == 0x1, "layer 0 must contain the low bit"

  bits.unset(0)
  expect not bits.get(0), "unset must release a marked bit"
  expect bits.get(17), "unset must not change unrelated bits"

  bits.setL0Block(3, 0xF)
  expect bits.get(12) and bits.get(15), "setting a layer-0 block marks all its bits"

  bits.clear()
  expect not bits.get(15) and not bits.get(17), "clear must reset every layer"

proc testAllocationRanges() =
  var bits = CAHiBitSet()
  let first = bits.getSpace(2)
  expect first == 0, "the first allocation must start at slot zero"
  bits.fillAlloc(first, 2)

  let second = bits.getSpace(2)
  expect second == 4, "a second allocation must not overlap the first one"
  bits.fillAlloc(second, 2)
  bits.freeRange(first, 2)

  expect bits.getSpace(2) == 0, "a freed range must be reusable"

testBitsAndHierarchy()
testAllocationRanges()
echo "[OK] Passed"