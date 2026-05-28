import unittest, tables
include "../../src/plugins/plugins.nim"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

type
  ResA = ref object of RootObj
    val: int
  ResB = ref object of RootObj
    val: int

proc freshManager(): PResourceManager =
  result = PResourceManager()
  
############################################################################################################################
#################################################### TESTS #################################################################
############################################################################################################################

suite "PResourceManager & Access Graph":

  test "basic read/write: writer before readers, readers parallel":
    var manager = PResourceManager()
    let r1 = manager.addResource(42)
    let sysA = 0
    let sysB = 1
    let sysC = 2

    manager.addWriteRequest(sysA, r1)
    manager.addReadRequest(sysB, r1)
    manager.addReadRequest(sysC, r1)
    manager.buildGlobalAccessGraph()
    let g = manager.cachedGraph

    check g.reachable(sysA, sysB)
    check g.reachable(sysA, sysC)
    check not g.reachable(sysB, sysC)
    check not g.reachable(sysC, sysB)
    check not g.has_cycle()

  test "write/write: exactly one ordering between two writers":
    var manager = PResourceManager()
    var obj = 1
    let r1 = manager.addResource(obj)
    let sysA = 0
    let sysB = 1

    manager.addWriteRequest(sysA, r1)
    manager.addWriteRequest(sysB, r1)
    manager.buildGlobalAccessGraph()
    let g = manager.cachedGraph

    check (g.reachable(sysA, sysB) xor g.reachable(sysB, sysA))
    check not g.has_cycle()

  test "multiple resources: transitive ordering A -> B -> C":
    var manager = PResourceManager()
    let r1 = manager.addResource(1)
    let r2 = manager.addResource(2)
    let sysA = 0
    let sysB = 1
    let sysC = 2

    manager.addWriteRequest(sysA, r1)
    manager.addReadRequest(sysB, r1)
    manager.addWriteRequest(sysB, r2)
    manager.addReadRequest(sysC, r2)
    manager.buildGlobalAccessGraph()
    let g = manager.cachedGraph

    check g.reachable(sysA, sysB)
    check g.reachable(sysB, sysC)
    check g.reachable(sysA, sysC)
    check not g.has_cycle()

  test "no conflict: fully parallel systems":
    var manager = PResourceManager()
    let r1 = manager.addResource(1)
    let r2 = manager.addResource(2.0)
    let sysA = 0
    let sysB = 1

    manager.addReadRequest(sysA, r1)
    manager.addReadRequest(sysB, r2)
    manager.buildGlobalAccessGraph()
    let g = manager.cachedGraph

    check not g.reachable(sysA, sysB)
    check not g.reachable(sysB, sysA)
    check not g.has_cycle()

  test "read+write same resource same sys raises assertion":
    var manager = PResourceManager()
    let r1 = manager.addResource(1)
    let sysA = 0

    manager.addReadRequest(sysA, r1)
    expect AssertionDefect:
      manager.addWriteRequest(sysA, r1)

  test "dirty flag: graph rebuilds after new request":
    var manager = PResourceManager()
    let r1 = manager.addResource(1)
    let sysA = 0
    let sysB = 1
    let sysC = 2

    manager.addWriteRequest(sysA, r1)
    manager.addReadRequest(sysB, r1)
    manager.buildGlobalAccessGraph()

    check not manager.dirty
    check manager.cachedGraph.reachable(sysA, sysB)

    manager.addReadRequest(sysC, r1)
    check manager.dirty

    manager.buildGlobalAccessGraph()
    check not manager.dirty
    check manager.cachedGraph.reachable(sysA, sysC)

  test "topo sort respects ordering constraints":
    var manager = PResourceManager()
    let r1 = manager.addResource(1)
    let r2 = manager.addResource(2.0)
    let sysA = 0
    let sysB = 1
    let sysC = 2

    manager.addWriteRequest(sysA, r1)
    manager.addReadRequest(sysB, r1)
    manager.addWriteRequest(sysB, r2)
    manager.addReadRequest(sysC, r2)
    manager.buildGlobalAccessGraph()
    var g = manager.cachedGraph
    let order = topo_sort(g)

    proc pos(s: seq[int], v: int): int =
      for i, x in s:
        if x == v: return i
      return -1

    check order.pos(sysA) < order.pos(sysB)
    check order.pos(sysB) < order.pos(sysC)

  test "triangle of write conflicts yields a DAG":
    var manager = PResourceManager()
    let r1 = manager.addResource(1)
    let r2 = manager.addResource(2.0)
    let r3 = manager.addResource(true)
    let sysA = 0
    let sysB = 1
    let sysC = 2

    manager.addWriteRequest(sysA, r1)
    manager.addWriteRequest(sysB, r1)
    manager.addWriteRequest(sysB, r2)
    manager.addWriteRequest(sysC, r2)
    manager.addWriteRequest(sysA, r3)
    manager.addWriteRequest(sysC, r3)
    manager.buildGlobalAccessGraph()

    check not manager.cachedGraph.has_cycle()

import std/[tables, unittest]

suite "mergeResourceManager":

  test "merge an absent type, resource cloned":
    var p1 = freshManager()
    var p2 = freshManager()

    let idA = p1.addResource(ResA(val: 1))
    let idB2 = p2.addResource(ResB(val: 7))
    p2.addReadRequest(sys = 0, id = idB2)

    let idmap = {0: 5}.toTable

    mergeResourceManager(p1, p2, idmap)

    check p1.toId.hasKey($ResB)
    let mergedIdx = p1.toId[$ResB][0]
    check p1.resources[mergedIdx].readRequests.contains(5)
    check not p1.resources[mergedIdx].readRequests.contains(0)

  test "Merge an existing type, new entry added":
    var p1 = freshManager()
    var p2 = freshManager()

    discard p1.addResource(ResA(val: 1))
    let idA2 = p2.addResource(ResA(val: 2))
    p2.addWriteRequest(sys = 0, id = idA2)

    let idmap = {0: 3}.toTable

    mergeResourceManager(p1, p2, idmap)

    check p1.toId[$ResA].len == 2
    let newIdx = p1.toId[$ResA][1]
    check p1.resources[newIdx].writeRequests.contains(3)

  test "Multiple systems correctly remapped":
    var p1 = freshManager()
    var p2 = freshManager()

    let idB = p2.addResource(ResB(val: 0))
    p2.addReadRequest(sys = 0, id = idB)
    p2.addReadRequest(sys = 1, id = idB)

    let idmap = {0: 10, 1: 20}.toTable

    mergeResourceManager(p1, p2, idmap)

    let idx = p1.toId[$ResB][0]
    check p1.resources[idx].readRequests.contains(10)
    check p1.resources[idx].readRequests.contains(20)
    check not p1.resources[idx].readRequests.contains(0)
    check not p1.resources[idx].readRequests.contains(1)

  test "p1.dirty = true after merge":
    var p1 = freshManager()
    var p2 = freshManager()
    p1.dirty = false   # reset manuel

    discard p2.addResource(ResA(val: 0))
    let idmap = initTable[int, int]()

    mergeResourceManager(p1, p2, idmap)
    check p1.dirty

  test "resource.dirty on merged resources":
    var p1 = freshManager()
    var p2 = freshManager()

    let id = p2.addResource(ResA(val: 5))
    p2.resources[id].dirty = false

    let idmap = initTable[int, int]()
    mergeResourceManager(p1, p2, idmap)

    let idx = p1.toId[$ResA][0]
    check p1.resources[idx].dirty

  test "merge with empty p2, p1 intact":
    var p1 = freshManager()
    var p2 = freshManager()

    discard p1.addResource(ResA(val: 42))
    p1.dirty = false

    let idmap = initTable[int, int]()
    mergeResourceManager(p1, p2, idmap)

    check p1.toId[$ResA].len == 1
    check not p1.dirty

  test "merge with empty p1, p2 cloned":
    var p1 = freshManager()
    var p2 = freshManager()

    let idB = p2.addResource(ResB(val: 99))
    p2.addWriteRequest(sys = 2, id = idB)

    let idmap = {2: 2}.toTable
    mergeResourceManager(p1, p2, idmap)

    check p1.toId.hasKey($ResB)
    let idx = p1.toId[$ResB][0]
    check p1.resources[idx].writeRequests.contains(2)
