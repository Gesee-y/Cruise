import ../../src/events/events 
import times, os, strutils, math

template benchmark(benchmarkName: string, sample:int, code: untyped) =
  block:
    var elapsed = 0.0
    code

    for i in 1..sample:
      let t0 = cpuTime()
      code
      elapsed += cpuTime() - t0
    
    elapsed /= sample.float
    #let elapsedStr = elapsed.formatFloat(format = ffDecimal, precision = 9)
    echo "CPU Time [", benchmarkName, "] ", elapsed*pow(10.0,9.0).float, "ns"

var added = 0
proc cb(x:int, t:int) = discard

notifier notif(a:int, b:int)

notif.connect(cb)
notif.connect(cb)
notif.connect(cb)
notif.connect(cb)
notif.connect(cb)

proc run_bench_emmision(n:int) =
  benchmark "emission",n:
    notif.emit((1,2))

run_bench_emmision(100000)