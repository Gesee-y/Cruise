import std/[times, memfiles, strformat]
include "../../src/graph/graph.nim"

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

const
  N = 1000
  M = 1000
  samples = 10000

#############################################################################
# benchmark : add_vertex
#############################################################################
var g1: DiGraph
benchmark("add_vertex", samples):
  for i in 1..N:
    discard g1.add_vertex()

#############################################################################
# benchmark : add_edge
#############################################################################
var g2: DiGraph
for i in 1..N:
  discard g2.add_vertex()
benchmark("add_edge", samples):
  for i in 0..<M:
    let u = i mod N
    let v = (i*37) mod N
    discard g2.add_edge(u, v)

#############################################################################
# benchmark : rem_edge
#############################################################################
var g3: DiGraph
for i in 1..N:
  discard g3.add_vertex()
for i in 0..<M:
  discard g3.add_edge(i mod N, (i*13) mod N)

benchmark("rem_edge", samples):
  for i in 0..<M:
    g3.rem_edge(i mod N, (i*13) mod N)

#############################################################################
# benchmark : rem_vertex
#############################################################################
var g4: DiGraph
for i in 1..N:
  discard g4.add_vertex()
for i in 0..<M:
  discard g4.add_edge(i mod N, (i*31) mod N)

benchmark("rem_vertex", samples):
  for i in 0..<N:
    g4.rem_vertex(i)

#############################################################################
# benchmark : topo_sort
#############################################################################
var g5: DiGraph
for i in 1..N:
  discard g5.add_vertex()
for i in 0..<M:
  discard g5.add_edge(i mod N, (i+1) mod N)

benchmark("topo_sort", samples):
  let res = g5.topo_sort()

#############################################################################
# benchmark : cycle detection
#############################################################################
var g6: DiGraph
for i in 1..N:
  discard g6.add_vertex()
for i in 0..<M:
  discard g6.add_edge(i mod N, (i+1) mod N)

benchmark("has_cycle", samples):
  discard g6.has_cycle()
