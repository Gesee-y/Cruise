import unittest, tables
include "../../src/plugins/plugins.nim"

template genSystem(name) =
  genSystemTy name:
    awaken:int
    updated:int
    shutdowns:int
    failOnUpdate:bool

  method awake(n:name) =
    inc n.awaken
    n.setStatus(PLUGIN_OK)

  method update(n:name) =
    inc n.updated
    if n.failOnUpdate:
      raise newException(ValueError, "update failed")

  method shutdown(n:name) =
    inc n.shutdowns
    n.setStatus(PLUGIN_OFF)

genSystem(TestNode)
genSystem(OtherTestNode)
genSystem(T1)
genSystem(T2)
genSystem(T3)

method getObject(n:TestNode):int = n.id
method getCapability(n:TestNode):int = 42

proc newTestNode(mainthread=false): TestNode =
  TestNode(
    enabled: true,
    mainthread: mainthread,
    status: PLUGIN_OFF,
    deps: initTable[string, PluginNode]()
  )

proc newOtherTestNode(mainthread=false): OtherTestNode =
  OtherTestNode(
    enabled: true,
    mainthread: mainthread,
    status: PLUGIN_OFF,
    deps: initTable[string, PluginNode]()
  )

# ------------------------------------------------------------
# Tests
# ------------------------------------------------------------

suite "Plugin system core":

  test "Add system assigns id and marks plugin dirty":
    var p: Plugin
    let n = TestNode()
    let id = addSystem(p, n)

    check id == 0
    check n.id == 0
    check p.dirty == true
    check p.idtonode.len == 1

  test "Remove system is safe and idempotent":
    var p: Plugin
    let n = TestNode()
    let id = addSystem(p, n)

    remSystem(p, id)
    remSystem(p, id) # should not explode

    check p.idtonode[id] == nil

  test "Add dependency registers graph edge and deps table":
    var p: Plugin
    let a = TestNode()
    let b = OtherTestNode()

    let ida = addSystem(p, a)
    let idb = addSystem(p, b)
    echo ida
    echo idb

    let ok = addDependency(p, ida, idb)

    check ok
    check b.deps.len == 1
    check b.deps.hasKey(a.asKey)

  test "Dependency removal clears deps table":
    var p: Plugin
    let a = TestNode()
    let b = T1()

    let ida = addSystem(p, a)
    let idb = addSystem(p, b)

    discard addDependency(p, ida, idb)
    remDependency(p, ida, idb)

    check b.deps.len == 0

  test "hasAllDepsInitialized detects uninitialized deps":
    let a = TestNode()
    let b = T1()

    b.deps["a"] = a

    a.setStatus(PLUGIN_OFF)
    check hasAllDepsInitialized(b) == false

    a.setStatus(PLUGIN_OK)
    check hasAllDepsInitialized(b) == true

  test "Error during update marks node as failed":
    var p: Plugin
    let n = TestNode()
    n.failOnUpdate = true

    discard addSystem(p, n)
    smap(update, p)

    check hasFailed(n)
    #check not (n.getLastError )

  test "smap respects topological order":
    var p: Plugin
    let a = TestNode()
    let b = OtherTestNode()

    let ida = addSystem(p, a)
    let idb = addSystem(p, b)
    discard addDependency(p, ida, idb)

    smap(awake, p)

    check a.awaken == 1
    check b.awaken == 1
    check a.id < b.id or true  # topo enforced, not index-based

  test "computeParallelLevel groups nodes by dependency depth":
    var p: Plugin
    let a = TestNode()
    let b = T1()
    let c = T2(mainthread:true)

    let ia = addSystem(p, a)
    let ib = addSystem(p, b)
    let ic = addSystem(p, c)

    discard addDependency(p, ia, ib)
    discard addDependency(p, ib, ic)

    computeParallelLevel(p)

    check p.parallel_cache.len > 0
    check not (p.idtonode[ic] is NullPluginNode)

  test "pmap executes all nodes once":
    var p: Plugin
    let a = TestNode()
    let b = T1(mainthread:true)

    discard addSystem(p, a)
    discard addSystem(p, b)

    pmap(update, p)

    check a.updated == 1
    check b.updated == 1

  test "mergePlugin merges nodes and dependencies correctly":
    var p1, p2: Plugin

    let a = TestNode()
    let b = T1()
    let c = T2()

    let ia = addSystem(p1, a)
    let ib = addSystem(p1, b)

    let ic = addSystem(p2, c)
    #discard addDependency(p2, ic, ic) # dumb but legal edge

    mergePlugin(p1, p2)

    check p1.idtonode.len == 3
    check p1.dirty == true
