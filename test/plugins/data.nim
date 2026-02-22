import unittest
include "../../src/plugins/plugins.nim"

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
    let r2 = manager.addResource(2)
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
    let r2 = manager.addResource(2)
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
    let r2 = manager.addResource(2)
    let r3 = manager.addResource(3)
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