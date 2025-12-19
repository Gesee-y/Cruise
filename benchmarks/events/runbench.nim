import ../../src/events/events 
import times, os, strutils, math

const SAMPLE = 10000

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
    echo "CPU Time [", benchmarkName, "] ", elapsed*pow(10.0,9.0).float, "ns with ", allocated/1024, "Kb"

var added = 0
proc cb(x:int, t:int) = discard

notifier notif(a:int, b:int)

notif.connect(cb)
notif.connect(cb)
notif.connect(cb)
notif.connect(cb)
notif.connect(cb)

proc run_bench_emission(n:int) =
  notifier notif(a:int, b:int)
  
  benchmark "emission without listeners",n:
    notif.emit((1,2))

  for i in 1..1:
    notif.connect(cb)

  benchmark "emission with 1 listeners",n:
    notif.emit((1,2))

  for i in 1..9:
    notif.connect(cb)

  benchmark "emission with 10 listeners",n:
    notif.emit((1,2))

  for i in 1..90:
    notif.connect(cb)

  benchmark "emission with 100 listeners",n:
    notif.emit((1,2))

#benchmark "emission deferred", SAMPLE:
#  notif.emitDefer((1,2))

#benchmark "defer flush",SAMPLE*100:
#  notif.flush()

run_bench_emission(SAMPLE)

notifier notif2(a:int, b:int)
benchmark "map", SAMPLE:
  map(notif2, proc(a,b: int): int = a + b, int)

notifier notif3(a:int, b:int)
benchmark "filter", SAMPLE:
  filter(notif3, proc(a,b: int): bool = a > b)

notifier notif4(a:int, b:int)
notifier notif5(a:int, b:int)
benchmark "merge", SAMPLE:
  merge(notif4,notif5)

notifier notif6(a:int, b:int)
notifier notif7(a:int, b:int)
benchmark "zip", SAMPLE:
  zip(notif6,notif7, proc(a,b: tuple[a:int, b:int]): int = a.a + b.b, int)

benchmark "Value mode", SAMPLE:
  enable_value(notif)
  notif[0] = (1, 2)

benchmark "Emit mode", SAMPLE:
  # mode par défaut
  notif.emit((1, 2))