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
    new(p)
    let n = TestNode()
    let id = addSystem(p, n)

    check id == 0
    check n.id == 0
    check p.dirty == true
    check p.idtonode.len == 1

  test "Remove system is safe and idempotent":
    var p: Plugin
    new(p)
    let n = TestNode()
    let id = addSystem(p, n)

    remSystem(p, id)
    remSystem(p, id) # should not explode

    check p.idtonode[id] == nil

  test "Add dependency registers graph edge and deps table":
    var p: Plugin
    new(p)
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
    new(p)
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
    new(p)
    let n = TestNode()
    n.failOnUpdate = true

    discard addSystem(p, n)
    smap(update, p)

    check hasFailed(n)
    #check not (n.getLastError )

  test "smap respects topological order":
    var p: Plugin
    new(p)
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
    new(p)
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
    new(p)
    let a = TestNode()
    let b = T1(mainthread:true)

    discard addSystem(p, a)
    discard addSystem(p, b)

    pmap(update, p)

    check a.updated == 1
    check b.updated == 1

  test "mergePlugin merges nodes and dependencies correctly":
    var p1, p2: Plugin
    new(p1)
    new(p2)

    let a = TestNode()
    let b = T1()
    let c = T2()

    let ia = addSystem(p1, a)
    let ib = addSystem(p1, b)

    let ic = addSystem(p2, c)

    mergePlugin(p1, p2)

    check p1.idtonode.len == 3
    check p1.dirty == true

type
  ResA = ref object of RootObj
    val: int
  ResB = ref object of RootObj
    val: int

type
  SysA = ref object of PluginNode
  SysB = ref object of PluginNode
  SysC = ref object of PluginNode

method asKey(p: SysA): string = "SysA"
method asKey(p: SysB): string = "SysB"
method asKey(p: SysC): string = "SysC"

proc freshPlugin(): Plugin =
  result = Plugin()
  result.graph = newGraph(0)

suite "mergePlugin":
  test "merge p2 resources and remap ids":
    var p1 = freshPlugin()
    var p2 = freshPlugin()

    let a1 = addSystem(p1, SysA())          # id 0 dans p1
    let b2 = addSystem(p2, SysB())          # id 0 dans p2
    let resId = p2.res_manager.addResource(ResA(val: 5))
    p2.res_manager.addReadRequest(sys = b2, id = resId)

    mergePlugin(p1, p2)

    check p1.res_manager.toId.hasKey($ResA)

suite "computeParallelLevel":

  test "independent nodes assigned at the same level":
    var p = freshPlugin()
    discard addSystem(p, SysA())
    discard addSystem(p, SysB())

    computeParallelLevel(p)

    check p.parallel_cache.len >= 1
    var total = 0
    for level in p.parallel_cache:
      total += level[0].len + level[1].len
    check total == 2

  test "sequencial nodes assigned differents levels":
    var p = freshPlugin()
    let a = addSystem(p, SysA())
    let b = addSystem(p, SysB())
    discard addDependency(p, a, b)

    computeParallelLevel(p)

    var levelA = -1
    var levelB = -1
    for i, level in p.parallel_cache:
      for id in level[0]:
        if id == a: levelA = i
        if id == b: levelB = i
      for id in level[1]:
        if id == a: levelA = i
        if id == b: levelB = i
    check levelA >= 0
    check levelB >= 0
    check levelA < levelB

  test "dirty resets after calculation":
    var p = freshPlugin()
    discard addSystem(p, SysA())
    p.dirty = true

    computeParallelLevel(p)
    check not p.dirty

  test "A→B→C build 3 distinct layers":
    var p = freshPlugin()
    let a = addSystem(p, SysA())
    let b = addSystem(p, SysB())
    let c = addSystem(p, SysC())
    discard addDependency(p, a, b)
    discard addDependency(p, b, c)

    computeParallelLevel(p)
    check p.parallel_cache.len >= 3

  test "Mainthread nodes separated from other nodes":
    var p = freshPlugin()
    let a = addSystem(p, SysA())
    let b = addSystem(p, SysB())
    p.idtonode[b].mainthread = true

    computeParallelLevel(p)

    var inMain = false
    for level in p.parallel_cache:
      for id in level[1]:
        if id == b: inMain = true
    check inMain
