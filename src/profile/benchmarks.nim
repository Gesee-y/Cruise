########################################################################################################################################
######################################################## CRUISE PROFILER ###############################################################
########################################################################################################################################

import times, math, algorithm, strutils, tables

type
  Parameters* = object
    samples*: int
    warmup*: int
    maxTime*: float
    maxMem*: float
  
  Statistics* = object
    min*: float
    max*: float
    mean*: float
    median*: float
    stddev*: float
    q1*: float
    q3*: float
    iqr*: float
    
  Benchmark* = object
    name*: string
    params*: Parameters
    times*: seq[float]
    mems*: seq[float]
    timeStats*: Statistics
    memStats*: Statistics
    totalTime*: float
    totalMem*: float

  BenchmarkSuite* = object
    name*: string
    benchmarks*: seq[Benchmark]

  Comparison* = object
    baseline*: string
    candidate*: string
    timeRatio*: float      # candidate / baseline
    memRatio*: float
    timeImprovement*: float  # (baseline - candidate) / baseline
    memImprovement*: float
    isFaster*: bool
    usesLessMem*: bool



# ==================== Formatage ====================

proc prettyTime*(t: float): string =
  var fac = 1.0
  var suffix = "s"
  
  if t < 1e-6:
    fac = 1e9
    suffix = "ns"
  elif t < 1e-3:
    fac = 1e6
    suffix = "µs"
  elif t < 1:
    fac = 1e3
    suffix = "ms"
  
  let v = t * fac
  
  # Format avec précision adaptée
  if v < 10:
    result = v.formatFloat(ffDecimal, 2) & " " & suffix
  elif v < 100:
    result = v.formatFloat(ffDecimal, 1) & " " & suffix
  else:
    result = v.formatFloat(ffDecimal, 0) & " " & suffix

proc prettyMem*(m: float): string =
  if m < 1024:
    return m.formatFloat(ffDecimal, 2) & " B"
  elif m < 1024 * 1024:
    return (m / 1024).formatFloat(ffDecimal, 2) & " KB"
  else:
    return (m / (1024 * 1024)).formatFloat(ffDecimal, 2) & " MB"

proc prettyPercent*(p: float): string =
  let sign = if p >= 0: "+" else: ""
  return sign & (p * 100).formatFloat(ffDecimal, 1) & "%"

# ==================== Calcul de statistiques ====================

proc calculateStatistics*(values: seq[float]): Statistics =
  if values.len == 0:
    return
  
  var sorted = values
  sorted.sort()
  
  result.min = sorted[0]
  result.max = sorted[^1]
  
  var sum = 0.0
  var variance = 0.0
  for v in sorted:
    sum += v
    
  result.mean = sum / sorted.len.float

  for v in sorted:
    let diff = v - result.mean
    variance += diff * diff

  result.stddev = sqrt(variance/sorted.len.float)

  let mid = sorted.len div 2
  if sorted.len mod 2 == 0:
    result.median = (sorted[mid - 1] + sorted[mid]) / 2.0
  else:
    result.median = sorted[mid]
  
  # Quartiles
  let q1Idx = sorted.len div 4
  let q3Idx = (3 * sorted.len) div 4
  result.q1 = sorted[q1Idx]
  result.q3 = sorted[q3Idx]
  result.iqr = result.q3 - result.q1
  
proc finalize*(b: var Benchmark) =
  b.timeStats = calculateStatistics(b.times)
  b.memStats = calculateStatistics(b.mems)
  
  b.totalTime = 0.0
  for t in b.times:
    b.totalTime += t
  
  b.totalMem = 0.0
  for m in b.mems:
    b.totalMem += m

# ==================== Affichage ====================

proc showSummary*(b: Benchmark) =
  echo "╭─ ", b.name, " (", b.params.samples, " samples)"
  echo "├─ Time  : ", prettyTime(b.timeStats.median), 
       " (min: ", prettyTime(b.timeStats.min), 
       ", max: ", prettyTime(b.timeStats.max), ")"
  echo "├─ Memory: ", prettyMem(b.memStats.median),
       " (min: ", prettyMem(b.memStats.min),
       ", max: ", prettyMem(b.memStats.max), ")"
  echo "╰─ Stddev: ±", prettyTime(b.timeStats.stddev)

proc showDetailed*(b: Benchmark) =
  echo "=" .repeat(70)
  echo "Benchmark: ", b.name
  echo "Samples: ", b.params.samples, " (warmup: ", b.params.warmup, ")"
  echo ""
  
  echo "Time Statistics:"
  echo "  Min     : ", prettyTime(b.timeStats.min)
  echo "  Q1      : ", prettyTime(b.timeStats.q1)
  echo "  Median  : ", prettyTime(b.timeStats.median)
  echo "  Mean    : ", prettyTime(b.timeStats.mean)
  echo "  Q3      : ", prettyTime(b.timeStats.q3)
  echo "  Max     : ", prettyTime(b.timeStats.max)
  echo "  Stddev  : ±", prettyTime(b.timeStats.stddev)
  echo "  IQR     : ", prettyTime(b.timeStats.iqr)
  echo ""
  
  echo "Memory Statistics:"
  echo "  Min     : ", prettyMem(b.memStats.min)
  echo "  Median  : ", prettyMem(b.memStats.median)
  echo "  Mean    : ", prettyMem(b.memStats.mean)
  echo "  Max     : ", prettyMem(b.memStats.max)
  echo "  Stddev  : ±", prettyMem(b.memStats.stddev)
  echo "=" .repeat(70)

proc notNaN(v:float):float =
  if v.isNaN or v.classify == fcInf:
    return 0.0

  return v

proc compare*(baseline, candidate: Benchmark): Comparison =
  result.baseline = baseline.name
  result.candidate = candidate.name
  
  result.timeRatio = notNaN(candidate.timeStats.median / baseline.timeStats.median)
  result.memRatio = notNaN(candidate.memStats.median / baseline.memStats.median)
  
  result.timeImprovement = notNaN((baseline.timeStats.median - candidate.timeStats.median) / baseline.timeStats.median)
  result.memImprovement = notNaN((baseline.memStats.median - candidate.memStats.median) / baseline.memStats.median)
  
  result.isFaster = result.timeImprovement > 0
  result.usesLessMem = result.memImprovement > 0

proc showComparison*(cmp: Comparison) =
  echo ""
  echo "╔═", "═".repeat(66), "═╗"
  echo "║ ", "Comparison: ", cmp.baseline, " vs ", cmp.candidate, " ".repeat(max(0, 66 - 14 - cmp.baseline.len - cmp.candidate.len - 4)), "║"
  echo "╠═", "═".repeat(66), "═╣"
  
  # Time comparison
  let timeIcon = if cmp.isFaster: "✓" else: "✗"
  let timeColor = if cmp.isFaster: "" else: ""
  echo "║ Time   : ", timeIcon, " ", 
       (if cmp.isFaster: "FASTER" else: "SLOWER"), " by ", 
       prettyPercent(abs(cmp.timeImprovement)),
       " (", cmp.timeRatio.formatFloat(ffDecimal, 2), "x)",
       " ".repeat(max(0, 48 - (if cmp.isFaster: 7 else: 6) - prettyPercent(abs(cmp.timeImprovement)).len - 3 - cmp.timeRatio.formatFloat(ffDecimal, 2).len)), "║"
  
  # Memory comparison
  let memIcon = if cmp.usesLessMem: "✓" else: "✗"
  echo "║ Memory : ", memIcon, " ",
       (if cmp.usesLessMem: "LESS" else: "MORE"), " by ",
       prettyPercent(abs(cmp.memImprovement)),
       " (", cmp.memRatio.formatFloat(ffDecimal, 2), "x)",
       " ".repeat(max(0, 51 - (if cmp.usesLessMem: 4 else: 4) - prettyPercent(abs(cmp.memImprovement)).len - 3 - cmp.memRatio.formatFloat(ffDecimal, 2).len)), "║"
  
  echo "╚═", "═".repeat(66), "═╝"

template benchmark*(benchmarkName: string, sample, code: untyped): untyped =
  var bench = Benchmark()
  bench.name = benchmarkName
  bench.params = Parameters(samples: sample, warmup: 0)
  bench.times = newSeq[float](sample)
  bench.mems = newSeq[float](sample)
  
  block:
    code

  block:
    for i in 0..<sample:
      let m0 = getOccupiedMem()
      let t0 = cpuTime()
      code
      let elapsed = cpuTime() - t0
      let allocated = (getOccupiedMem() - m0).float
      
      bench.times[i] = elapsed
      bench.mems[i] = allocated
  
  finalize(bench)
  bench

template benchmark*(benchmarkName: string, sample, warm, code: untyped): untyped =
  var bench = Benchmark()
  bench.name = benchmarkName
  bench.params = Parameters(samples: sample, warmup: warm)
  bench.times = newSeqOfCap[float](sample)
  bench.mems = newSeqOfCap[float](sample)
  
  block:
    for i in 0..<warm:
      code
    
  block:
    for i in 0..<sample:
      let m0 = getOccupiedMem()
      let t0 = cpuTime()
      code
      let elapsed = cpuTime() - t0
      let allocated = (getOccupiedMem() - m0).float
      
      bench.times.add(elapsed)
      bench.mems.add(allocated)
  
  finalize(bench)
  bench

template benchmarkWithSetup*(benchmarkName: string, sample, 
                              setup, code: untyped): untyped =
  var bench = Benchmark()
  bench.name = benchmarkName
  bench.params = Parameters(samples: sample, warmup: 0)
  bench.times = newSeqOfCap[float](sample)
  bench.mems = newSeqOfCap[float](sample)
  
  block:
    setup
    code
  
  block:
    for i in 0..<sample:
      setup  # Setup avant chaque mesure
      
      let m0 = getOccupiedMem()
      let t0 = cpuTime()
      code
      let elapsed = cpuTime() - t0
      let allocated = (getOccupiedMem() - m0).float
      
      bench.times.add(elapsed)
      bench.mems.add(allocated)
  
  finalize(bench)
  bench

template benchmarkWithSetup*(benchmarkName: string, sample, warm,
                              setup, code: untyped): untyped =
  var bench = Benchmark()
  bench.name = benchmarkName
  bench.params = Parameters(samples: sample, warmup: warm)
  bench.times = newSeqOfCap[float](sample)
  bench.mems = newSeqOfCap[float](sample)
  
  block:
    for i in 0..<warm:
      setup
      code
    
    for i in 0..<sample:
      setup
      let m0 = getOccupiedMem()
      let t0 = cpuTime()
      code
      let elapsed = cpuTime() - t0
      let allocated = (getOccupiedMem() - m0).float
      
      bench.times.add(elapsed)
      bench.mems.add(allocated)
  
  finalize(bench)
  bench

proc initSuite*(name: string): BenchmarkSuite =
  result.name = name
  result.benchmarks = @[]

proc add*(suite: var BenchmarkSuite, bench: Benchmark) =
  suite.benchmarks.add(bench)

proc showSummary*(suite: BenchmarkSuite) =
  echo ""
  echo "╔═", "═".repeat(68), "═╗"
  echo "║ ", suite.name, " ".repeat(max(0, 68 - suite.name.len)), "║"
  echo "╠═", "═".repeat(68), "═╣"
  
  for bench in suite.benchmarks:
    let timeStr = prettyTime(bench.timeStats.median).alignLeft(12)
    let memStr = prettyMem(bench.memStats.median).alignLeft(12)
    let nameStr = bench.name.alignLeft(30)
    echo "║ ", nameStr, " │ ", timeStr, " │ ", memStr, " ║"
  
  echo "╚═", "═".repeat(68), "═╝"
