include "../../../src/ecs/table.nim"

import times, os

const SAMPLE = 100000

template benchmark(benchmarkName: string, sample:int, code: untyped) =
  block:
    var elapsed = 0.0
    var allocated = 0.0

    code

    for i in 1..sample:
      let m0 = getOccupiedMem()
      let t0 = cpuTime()
      code
      elapsed += cpuTime() - t0
      allocated += (getOccupiedMem() - m0).float
    
    elapsed /= sample.float
    allocated /= sample.float
    echo "CPU Time [", benchmarkName, "] ", elapsed*1e9, "ns with ", allocated/1024, "Kb"


var graph = initArchetypeGraph()
var emptyMask: ArchetypeMask

let mask1 = emptyMask.withComponent(0).withComponent(5).withComponent(10)
let node1 = graph.findArchetype(mask1)

benchmark "Lookup repeated (hot cache)", SAMPLE:
  discard graph.findArchetypeFast(mask1)

var mask2 = emptyMask.withComponent(1).withComponent(6).withComponent(11)
discard graph.findArchetype(mask2)  # Créer l'archétype

benchmark "Lookup alterned (cache thrashing)", SAMPLE:
  discard graph.findArchetypeFast(mask1)
  discard graph.findArchetypeFast(mask2)

benchmark "Incremental navigation (cached)", SAMPLE:
  var n = graph.root
  n = graph.addComponent(n, ComponentId(0))
  n = graph.addComponent(n, ComponentId(5))
  n = graph.addComponent(n, ComponentId(10))

var counter = 20
benchmark "New archetype", SAMPLE:
  let m = emptyMask.withComponent(ComponentId(counter))
                   .withComponent(ComponentId(counter + 1))
  discard graph.findArchetype(m)
  counter += 2
  counter = counter mod 100

benchmark "Add component (edge cached)", SAMPLE:
  discard graph.addComponent(node1, ComponentId(15))

let node2 = graph.addComponent(node1, ComponentId(15))
benchmark "Remove component", SAMPLE:
  discard graph.removeComponent(node2, ComponentId(15))

let comp = @[ComponentId(0), ComponentId(5), ComponentId(10)]
benchmark "Lookup with array", SAMPLE:
  discard graph.findArchetype(comp)
