include "../../../src/ecs/table.nim"

import times, os

const SAMPLE = 1000000

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

# ==================== Tests ====================

echo "=== Archetype Graph Ultra-Optimisé ==="

var graph = initArchetypeGraph()
var emptyMask: ArchetypeMask

# Warmup
let mask1 = emptyMask.withComponent(0).withComponent(5).withComponent(10)
let node1 = graph.findArchetype(mask1)

echo "\n=== Benchmarks ==="

# Benchmark 1: Lookup répété (même mask)
benchmark "Lookup répété (hot cache)", SAMPLE:
  discard graph.findArchetypeFast(mask1)

# Benchmark 2: Lookup alterné (cache miss)
var mask2 = emptyMask.withComponent(1).withComponent(6).withComponent(11)
discard graph.findArchetype(mask2)  # Créer l'archétype

benchmark "Lookup alterné (cache thrashing)", SAMPLE:
  discard graph.findArchetypeFast(mask1)
  discard graph.findArchetypeFast(mask2)

# Benchmark 2: Navigation incrémentale (edges cachés)
benchmark "Navigation incrémentale (cached)", SAMPLE:
  var n = graph.root
  n = graph.addComponent(n, ComponentId(0))
  n = graph.addComponent(n, ComponentId(5))
  n = graph.addComponent(n, ComponentId(10))

# Benchmark 3: Création nouveau archétype
var counter = 20
benchmark "Création nouveau archétype", SAMPLE:
  let m = emptyMask.withComponent(ComponentId(counter))
                   .withComponent(ComponentId(counter + 1))
  discard graph.findArchetype(m)
  counter += 2
  counter = counter mod 100

# Benchmark 4: Ajout composant (edge existe)
benchmark "Ajout composant (edge cached)", SAMPLE:
  discard graph.addComponent(node1, ComponentId(15))

# Benchmark 5: Retrait composant
let node2 = graph.addComponent(node1, ComponentId(15))
benchmark "Retrait composant", SAMPLE:
  discard graph.removeComponent(node2, ComponentId(15))

# Benchmark 6: Lookup par array de composants
let comp = @[ComponentId(0), ComponentId(5), ComponentId(10)]
benchmark "Lookup par array", SAMPLE:
  discard graph.findArchetype(comp)

echo "\n=== Statistiques ==="
echo "Nodes créés: ", graph.nodeCount()
echo "Taille node: ", sizeof(ArchetypeNode), " bytes"
echo "Taille edges (lazy): ", MAX_COMPONENTS * sizeof(pointer), " bytes"

# Test de cohérence
echo "\n=== Tests de cohérence ==="
let node3 = graph.findArchetype(mask1)
echo "Cache fonctionne? ", node1 == node3

let node4 = graph.addComponent(node1, ComponentId(20))
let node5 = graph.removeComponent(node4, ComponentId(5))
echo "Transitions bidirectionnelles? ", node5.mask.hasComponent(0) and 
                                        node5.mask.hasComponent(10) and 
                                        node5.mask.hasComponent(20) and
                                        not node5.mask.hasComponent(5)