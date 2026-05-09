##########################################################################################################################################################
################################################################ BENCHMARKS ##############################################################################
##########################################################################################################################################################
##
## Comparative benchmarks: CLSeq / CLArray  vs  CPUSeq / CPUArray.
##
## Each benchmark is run at several payload sizes so you can observe how
## throughput scales and at what size the GPU starts to win over the CPU.
##
## Workloads
## ---------
##   1. Element-wise binary ops   : a + b, a * b
##   2. Scalar broadcast          : a * scalar, a + scalar
##   3. Unary / trig              : sin, sqrt, exp
##   4. Chained expression        : (a + b) * c - d   (3 kernels / passes)
##   5. Chained expression (into) : same, but reusing output buffers (GPU only)
##   6. Reduction                 : sum, min, max
##   7. Dot product               : dot(a, b)
##   8. In-place ops              : a += b, a *= scalar
##   9. Static CLArray            : fixed-size N=1024 array ops
##
## Sizes tested (number of float32 elements):
##   SMALL  =     1_024   (  4 KB) — GPU launch overhead dominates
##   MEDIUM =   262_144   (  1 MB) — crossover zone
##   LARGE  = 8_388_608   ( 32 MB) — GPU should pull ahead
##   HUGE   = 33_554_432  (128 MB) — memory-bandwidth bound
##
## Output format
## -------------
##   [bench name]  size=N   CPU: X ms   GPU: Y ms   speedup: Z×
##
## Timings are wall-clock milliseconds averaged over REPEAT runs.
## The first run is always excluded (warm-up: JIT kernel compilation, CPU cache).

import times, strformat, math, sequtils
#import ../../src/gpuarray/gpuarrays
import ../../src/gpuarray/backends/cpu       ## CPUSeq / CPUArray
import ../../src/gpuarray/backends/cl     ## CLSeq  / CLArray

##########################################################################################################################################################
## CONFIG
##########################################################################################################################################################

const
  REPEAT = 5          ## number of timed repetitions (first is warm-up)
  SMALL  =        1_024
  MEDIUM =      262_144
  LARGE  =    8_388_608
  HUGE   =   33_554_432
  SIZES  = [SMALL, MEDIUM, LARGE, HUGE]

##########################################################################################################################################################
## TIMING HELPERS
##########################################################################################################################################################

template bench(label: string, size: int, body: untyped): float =
  ## Run `body` REPEAT times, discard first (warm-up), return average ms.
  var total = 0.0
  for i in 0..<REPEAT:
    let t0 = cpuTime()
    body
    let elapsed = (cpuTime() - t0) * 1000.0
    if i > 0: total += elapsed   ## skip warm-up run
  total / float(REPEAT - 1)

proc printResult(label, sizeName: string, n, cpuMs, gpuMs: float) =
  let speedup = cpuMs / gpuMs
  let winner  = if speedup >= 1.0: &"GPU {speedup:.2f}×" else: &"CPU {1.0/speedup:.2f}×"
  echo &"  {label:<35} n={n:>10}   CPU: {cpuMs:>8.2f} ms   GPU: {gpuMs:>8.2f} ms   [{winner}]"

proc sizeName(n: int): string =
  case n
  of SMALL:  "SMALL"
  of MEDIUM: "MEDIUM"
  of LARGE:  "LARGE"
  of HUGE:   "HUGE"
  else:      $n

##########################################################################################################################################################
## DATA GENERATORS
##########################################################################################################################################################

proc makeFloatSeq(n: int): seq[float32] =
  ## Deterministic float32 data in (0, 1) — safe for trig / log / sqrt.
  result = newSeq[float32](n)
  for i in 0..<n:
    result[i] = float32(0.1 + 0.8 * (float(i mod 1000) / 1000.0))

##########################################################################################################################################################
## 1. ELEMENT-WISE BINARY OPS
##########################################################################################################################################################

proc benchBinaryOps() =
  echo "\n=== 1. Element-wise binary ops (a + b, a * b) ==="
  for n in SIZES:
    let data = makeFloatSeq(n)

    # CPU
    let ca = toGPU[CPUSData[float32], float32](data)  ## CPUSeq
    let cb = toGPU[CPUSData[float32], float32](data)
    let cpuAdd = bench("add", n): discard ca + cb
    let cpuMul = bench("mul", n): discard ca * cb

    # GPU
    let ga = toGPU[CLSData[float32], float32](data)   ## CLSeq
    let gb = toGPU[CLSData[float32], float32](data)
    let gpuAdd = bench("add", n): discard ga + gb
    let gpuMul = bench("mul", n): discard ga * gb

    printResult("add", sizeName(n), float(n), cpuAdd, gpuAdd)
    printResult("mul", sizeName(n), float(n), cpuMul, gpuMul)

##########################################################################################################################################################
## 2. SCALAR BROADCAST
##########################################################################################################################################################

proc benchScalarOps() =
  echo "\n=== 2. Scalar broadcast (a * 2.0, a + 0.5) ==="
  for n in SIZES:
    let data = makeFloatSeq(n)
    let ca = toGPU[CPUSData[float32], float32](data)
    let ga = toGPU[CLSData[float32], float32](data)

    let cpuMul = bench("scalar *", n): discard ca * 2.0f32
    let gpuMul = bench("scalar *", n): discard ga * 2.0f32
    printResult("scalar *", sizeName(n), float(n), cpuMul, gpuMul)

    let cpuAdd = bench("scalar +", n): discard ca + 0.5f32
    let gpuAdd = bench("scalar +", n): discard ga + 0.5f32
    printResult("scalar +", sizeName(n), float(n), cpuAdd, gpuAdd)

##########################################################################################################################################################
## 3. UNARY / TRIG
##########################################################################################################################################################

proc benchUnaryOps() =
  echo "\n=== 3. Unary / trig (sin, sqrt, exp) ==="
  for n in SIZES:
    let data = makeFloatSeq(n)
    let ca = toGPU[CPUSData[float32], float32](data)
    let ga = toGPU[CLSData[float32], float32](data)

    let cpuSin  = bench("sin",  n): discard ca.sin()
    let gpuSin  = bench("sin",  n): discard ga.sin()
    printResult("sin", sizeName(n), float(n), cpuSin, gpuSin)

    let cpuSqrt = bench("sqrt", n): discard ca.sqrt()
    let gpuSqrt = bench("sqrt", n): discard ga.sqrt()
    printResult("sqrt", sizeName(n), float(n), cpuSqrt, gpuSqrt)

    let cpuExp  = bench("exp",  n): discard ca.exp()
    let gpuExp  = bench("exp",  n): discard ga.exp()
    printResult("exp", sizeName(n), float(n), cpuExp, gpuExp)

##########################################################################################################################################################
## 4. CHAINED EXPRESSION — allocating  (a + b) * c - d
##########################################################################################################################################################

proc benchChainedAlloc() =
  echo "\n=== 4. Chained expression — allocating: (a + b) * c - d ==="
  for n in SIZES:
    let data = makeFloatSeq(n)
    let ca = toGPU[CPUSData[float32], float32](data)
    let cb = ca; let cc = ca; let cd = ca
    let ga = toGPU[CLSData[float32], float32](data)
    let gb = ga; let gc = ga; let gd = ga

    let cpuT = bench("chain-alloc", n): discard (ca + cb) * cc - cd
    let gpuT = bench("chain-alloc", n): discard (ga + gb) * gc - gd
    printResult("(a+b)*c-d  alloc", sizeName(n), float(n), cpuT, gpuT)

##########################################################################################################################################################
## 5. CHAINED EXPRESSION — buffer reuse via `into` (GPU only meaningful here)
##########################################################################################################################################################

proc benchChainedInto() =
  echo "\n=== 5. Chained expression — into (buffer reuse): (a + b) * c - d ==="
  for n in SIZES:
    let data = makeFloatSeq(n)

    # CPU — CPUSeq has no `into` variants, simulate with pre-allocated tmp
    let ca = toGPU[CPUSData[float32], float32](data)
    let cb = ca; let cc = ca; let cd = ca
    var cpuTmp1 = newCPUSeq[float32](n)
    var cpuTmp2 = newCPUSeq[float32](n)
    let cpuT = bench("chain-into", n):
      cpuTmp1 = ca + cb        ## CPUSeq has no into — still allocates
      cpuTmp2 = cpuTmp1 * cc
      discard cpuTmp2 - cd

    # GPU — fully allocation-free inner loop
    let ga = toGPU[CLSData[float32], float32](data)
    let gb = ga; let gc = ga; let gd = ga
    var tmp1 = newCLSeq[float32](n)
    var tmp2 = newCLSeq[float32](n)
    var tmp3 = newCLSeq[float32](n)
    let gpuT = bench("chain-into", n):
      add(ga, gb, tmp1)        ## tmp1 = a + b   — zero allocation
      mul(tmp1, gc, tmp2)      ## tmp2 = tmp1 * c — zero allocation
      sub(tmp2, gd, tmp3)      ## tmp3 = tmp2 - d — zero allocation

    printResult("(a+b)*c-d  into", sizeName(n), float(n), cpuT, gpuT)

##########################################################################################################################################################
## 6. REDUCTIONS
##########################################################################################################################################################

proc benchReductions() =
  echo "\n=== 6. Reductions (sum, min, max) ==="
  for n in SIZES:
    let data = makeFloatSeq(n)
    let ca = toGPU[CPUSData[float32], float32](data)
    let ga = toGPU[CLSData[float32], float32](data)

    let cpuSum = bench("sum", n): discard ca.toSeq.foldl(a + b, 0.0f32)
    let gpuSum = bench("sum", n): discard ga.sum()
    printResult("sum", sizeName(n), float(n), cpuSum, gpuSum)

    let cpuMin = bench("min", n): discard ca.toSeq.foldl(min(a, b), high(float32))
    let gpuMin = bench("min", n): discard ga.min()
    printResult("min", sizeName(n), float(n), cpuMin, gpuMin)

    let cpuMax = bench("max", n): discard ca.toSeq.foldl(max(a, b), low(float32))
    let gpuMax = bench("max", n): discard ga.max()
    printResult("max", sizeName(n), float(n), cpuMax, gpuMax)

##########################################################################################################################################################
## 7. DOT PRODUCT
##########################################################################################################################################################

proc benchDot() =
  echo "\n=== 7. Dot product ==="
  for n in SIZES:
    let data = makeFloatSeq(n)
    let ca = toGPU[CPUSData[float32], float32](data)
    let cb = ca
    let ga = toGPU[CLSData[float32], float32](data)
    let gb = ga

    let cpuDot = bench("dot", n):
      var s = 0.0f32
      let sa = ca.toSeq; let sb = cb.toSeq
      for i in 0..<n: s += sa[i] * sb[i]
    let gpuDot = bench("dot", n): discard ga.dot(gb)
    printResult("dot", sizeName(n), float(n), cpuDot, gpuDot)

##########################################################################################################################################################
## 8. IN-PLACE OPS  +=  *=
##########################################################################################################################################################

proc benchInPlace() =
  echo "\n=== 8. In-place ops (a += b, a *= scalar) ==="
  for n in SIZES:
    let data = makeFloatSeq(n)

    # CPU — no native += on CPUSeq, simulate
    var ca = toGPU[CPUSData[float32], float32](data)
    let cb = ca
    let cpuAddEq = bench("+=", n): ca = ca + cb
    let cpuMulEq = bench("*=", n): ca = ca * 2.0f32

    # GPU — true in-place, zero allocation
    var ga = toGPU[CLSData[float32], float32](data)
    let gb = ga
    let gpuAddEq = bench("+=", n): ga += gb
    let gpuMulEq = bench("*=", n): ga *= 2.0f32

    printResult("+=", sizeName(n), float(n), cpuAddEq, gpuAddEq)
    printResult("*= scalar", sizeName(n), float(n), cpuMulEq, gpuMulEq)

##########################################################################################################################################################
## 9. STATIC CLArray  (N = 1024)
##########################################################################################################################################################

proc benchCLArray() =
  const N = 1024
  echo &"\n=== 9. Static CLArray[{N}] vs CPUArray[{N}] ==="

  let rawA = makeFloatSeq(N)
  var arrA: array[N, float32]
  var arrB: array[N, float32]
  for i in 0..<N: arrA[i] = rawA[i]; arrB[i] = rawA[i]

  let cpuA = toGPU[N, CPUAData[N, float32], float32](arrA)
  let cpuB = cpuA
  let clA  = toGPU[N, CLAData[N,float32], float32](arrA)   ## CLArray[N, float32]
  let clB  = clA

  let cpuAdd  = bench("CLArray +",   N): discard cpuA + cpuB
  let gpuAdd  = bench("CLArray +",   N): discard clA  + clB
  printResult("CLArray[1024] +", "FIXED", float(N), cpuAdd, gpuAdd)

  let cpuSin  = bench("CLArray sin", N): discard cpuA.sin()
  let gpuSin  = bench("CLArray sin", N): discard clA.sin()
  printResult("CLArray[1024] sin", "FIXED", float(N), cpuSin, gpuSin)

  let cpuMul  = bench("CLArray *s",  N): discard cpuA * 3.0f32
  let gpuMul  = bench("CLArray *s",  N): discard clA  * 3.0f32
  printResult("CLArray[1024] * scalar", "FIXED", float(N), cpuMul, gpuMul)

##########################################################################################################################################################
## MAIN
##########################################################################################################################################################

when isMainModule:
  echo "Initialising OpenCL..."
  initOpenCL()
  echo "OpenCL ready.\n"
  echo "===================================================================================="
  echo "  GPUArrays benchmark — CLSeq / CLArray  vs  CPUSeq / CPUArray"
  echo "  Repeats per bench: ", REPEAT, " (first excluded as warm-up)"
  echo "===================================================================================="

  benchBinaryOps()
  benchScalarOps()
  benchUnaryOps()
  benchChainedAlloc()
  benchChainedInto()
  benchReductions()
  benchDot()
  benchInPlace()
  benchCLArray()

  echo "\n===================================================================================="
  echo "  Done."
  echo "===================================================================================="
  shutdownOpenCL()