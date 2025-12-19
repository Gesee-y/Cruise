import unittest, tables, math, times, random
include "../../src/plugins/plugins.nim"

type
  StressNode = ref object of PluginNode
    updated:int
    failChance:float

method update(n:StressNode) =
  if rand(0.0..1.0) < n.failChance:
  inc n.updated
    raise newException(ValueError, "random fail")

method getObject(n:StressNode):int = n.id

proc newStressNode(failChance=0.1): StressNode =
  StressNode(
    enabled:true,
    mainthread:false,
    status:PLUGIN_OFF,
    failChance:failChance
    deps:initTable[string, PluginNode](),
  )

suite "Stress tests for Plugin system":

  test "Randomized large plugin graph with circular refs":
    var p: Plugin
    const N = 50

    # Créer les nodes
    for _ in 0..<N:
      discard addSystem(p, newStressNode(0.2))

    for i in 0..<N:
      let target = rand(0..<N)
      discard addDependency(p, i, target) 

    smap(update, p)

    for n in p.idtonode:
      check StressNode(n).updated >= 0

  test "Random failures do not crash pmap":
    var p: Plugin
    const N = 30
    for _ in 0..<N:
      discard addSystem(p, newStressNode(0.5))

    pmap(update, p)

    var failedCount = 0
    for n in p.idtonode:
      if n is StressNode and hasFailed(n):
        inc failedCount

    echo "Stress test finished, failed nodes:", failedCount
    check failedCount >= 0

type
  ExtremeNode = ref object of PluginNode
    updated:int
    failChance:float

method update(n:ExtremeNode) =
  inc n.updated
  if rand(0.0..1.0) < n.failChance:
    raise newException(ValueError, "random fail")

method getObject(n:ExtremeNode):int = n.id

proc newExtremeNode(failChance=0.2): ExtremeNode =
  ExtremeNode(
    enabled:true,
    mainthread:rand(0..1) == 1,
    status:PLUGIN_OFF,
    deps:initTable[string, PluginNode](),
    failChance:failChance
  )

suite "Extreme stress test - 200+ nodes, cycles, random failures":

  test "Massive plugin graph execution":
    var p: Plugin
    const N = 250

    for _ in 0..<N:
      discard addSystem(p, newExtremeNode())

    for i in 0..<N:
      let target = rand(0..<N)
      discard addDependency(p, i, target)

      for _ in 0..<3:
        let t2 = rand(0..<N)
        discard addDependency(p, i, t2)

    computeParallelLevel(p)
    check p.parallel_cache.len > 0

    pmap(update, p)

    var failedCount = 0
    var executedCount = 0
    for n in p.idtonode:
      let en = ExtremeNode(n)
      inc executedCount, en.updated
      if hasFailed(en):
        inc failedCount

    echo "Extreme stress test finished."
    echo "Total nodes executed:", executedCount
    echo "Total nodes failed:", failedCount

    check executedCount >= N
    check failedCount >= 0
