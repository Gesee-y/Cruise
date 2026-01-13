include "../../../src/ecs/table.nim"

import times, os

type
  Vec3 = object
    x, y, z: float32

const S = 4096


var vecs = newSoAFragArr(Vec3, S)

const SAMPLE = 10000
const N = 10000

template benchmark(benchmarkName: string, sample:int, code: untyped) =
  block:
    var elapsed = 0.0
    var allocated = 0.0

    for i in 1..sample:
      let m0 = getOccupiedMem()
      let t0 = cpuTime()
      code
      elapsed += cpuTime() - t0
      allocated += (getOccupiedMem() - m0).float
    
    elapsed /= sample.float
    allocated /= sample.float
    echo "CPU Time [", benchmarkName, "] ", elapsed*1e9, "ns with ", allocated/1024, "Kb"

var offs = 0
benchmark "Create blocks", 10:
  discard vecs.newBlock(offs)
  offs += 1024

var idx: array[N, uint]
benchmark("Get blocks 10k", SAMPLE):
  for i in 0..<N:
    let b = vecs.getBlockIdx(i)
    idx[i] = ((b shl BLK_SHIFT) or (i mod S)).uint

let d = Vec3(x: 0.float32, y: 0.float32, z: 0.float32)
benchmark("Insertion 10k", SAMPLE):
  for i in idx:
    vecs[i] = d

benchmark("Random Access 10k", SAMPLE):
  var sum: Vec3
  for i in idx:
    let v = vecs[i]
    sum.x += v.x
    sum.y += v.y
    sum.z += v.z

benchmark("Sequential Iter 10k", SAMPLE):
  var sum: Vec3
  for v in vecs.iter:
    sum.x += v.x
    sum.y += v.y
    sum.z += v.z

benchmark("Mass Update 10k", SAMPLE):
  for i in idx:
    vecs[i] = Vec3(x: 1.0, y: 2.0, z: 3.0)

benchmark("MQuery iter 10k", SAMPLE):
  for blk in vecs.blocks:
    var x:array[S,float32] = blk.data.x
    var y = blk.data.y
    for i in 0..<S:
      x[i] += x[i]
      y[i] += y[i]
