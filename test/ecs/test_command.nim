import unittest, math
include "../../src/ecs/table.nim"

suite "CommandBuffer / BatchMap":

  test "makeSignature packs fields correctly":
    let sig = makeSignature(3, 42, 7)
    check (sig shr 28) == 3
    check ((sig shr 12) and 0xFFFF) == 42
    check ((sig shr 2) and 0x3FF) == 7

  test "init and destroy batch map":
    var cb = initCommandBuffer()
    check cb.map.entries != nil
    check cb.map.currentGeneration == 1
    check cb.map.activeSignatures.len == 0
    cb.destroy()

  test "single command insertion":
    var cb = initCommandBuffer()

    let p = Payload(eid: 1, value: 3.14)
    cb.addCommand(1, 10, 0, p)

    check cb.map.activeSignatures.len == 1

    let sig = makeSignature(1, 10, 0)
    let idx = int(sig) and (MAP_CAPACITY - 1)
    let e = cb.map.entries[idx]

    check e.count == 1
    check e.data[0].eid == 1

    cb.destroy()

  test "multiple commands with same signature are batched":
    var cb = initCommandBuffer()

    for i in 0..<100:
      cb.addCommand(2, 5, 1, Payload(eid: i.uint64, value: i.float32))

    check cb.map.activeSignatures.len == 1

    let sig = makeSignature(2, 5, 1)
    let idx = int(sig) and (MAP_CAPACITY - 1)
    let e = cb.map.entries[idx]

    check e.count == 100
    for i in 0..<100:
      check e.data[i].eid == i.uint64

    cb.destroy()

  test "resize grows capacity correctly":
    var cb = initCommandBuffer()

    let sig = makeSignature(1, 1, 1)
    let idx = int(sig) and (MAP_CAPACITY - 1)

    for i in 0..<200:
      cb.addCommand(1, 1, 1, Payload(eid: i.uint64, value: 0))

    let e = cb.map.entries[idx]
    check e.count == 200
    check e.capacity >= 200

    cb.destroy()

  test "hash collision is resolved by linear probing":
    var cb = initCommandBuffer()

    # Force two signatures with same hash slot
    let baseSig = makeSignature(1, 1, 0)
    let mask = MAP_CAPACITY - 1
    let baseIdx = int(baseSig) and mask

    var otherArch = 1'u16
    var otherSig: uint32
    while true:
      otherArch.inc
      otherSig = makeSignature(1, otherArch, 0)
      if (int(otherSig) and mask) == baseIdx:
        break

    cb.addCommand(1, 1, 0, Payload(eid: 1, value: 1))
    cb.addCommand(1, otherArch, 0, Payload(eid: 2, value: 2))

    check cb.map.activeSignatures.len == 2

    var found1 = false
    var found2 = false
    for i in 0..<MAP_CAPACITY:
      let e = cb.map.entries[i]
      if e.key != 0:
        if e.data[0].eid == 1: found1 = true
        if e.data[0].eid == 2: found2 = true

    check found1
    check found2

    cb.destroy()

  test "generation separates batches":
    var cb = initCommandBuffer()

    cb.addCommand(1, 1, 0, Payload(eid: 1, value: 1))
    cb.map.currentGeneration.inc
    cb.addCommand(1, 1, 0, Payload(eid: 2, value: 2))

    check cb.map.activeSignatures.len == 2

    cb.destroy()

  test "stress insert many commands":
    var cb = initCommandBuffer()

    let N = 100_000
    for i in 0..<N:
      cb.addCommand((i mod 4).uint8, (i mod 32).uint16, 0,
                    Payload(eid: i.uint64, value: i.float32))

    var total = 0
    for i in 0..<MAP_CAPACITY:
      let e = cb.map.entries[i]
      if e.key != 0:
        total += int(e.count)

    check total == N

    cb.destroy()
