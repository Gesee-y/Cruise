import std/tables
import std/assertions

include ../../src/CVM/allocator

proc expect(condition: bool; message: string) =
  assert condition, message

proc newAllocator(): CVramAllocator =
  result = CVramAllocator(active: initTable[uint, CAllocation]())

proc testLineEncoding() =
  let encoded = compactifyLineInfo(12, 34)
  expect decompactLineInfo(encoded) == (12, 34), "line information must round-trip"

proc testReuseAfterLifetime() =
  var allocator = newAllocator()
  let first = allocator.alloc(2, 1, 1, 1, 3)
  expect first == 0, "the first allocation starts at zero"

  let reused = allocator.alloc(2, 1, 4)
  expect reused == 0, "an expired allocation must be released before the next allocation"

proc testAnonymousRelease() =
  var allocator = newAllocator()
  let pos = allocator.alloc(2)
  allocator.free(pos, 2)
  expect allocator.alloc(2) == pos, "anonymous ranges must be reusable after free"

testLineEncoding()
testReuseAfterLifetime()
testAnonymousRelease()
