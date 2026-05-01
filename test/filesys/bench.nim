## bench.nim
##
## Performance benchmarks for the FileSystem & Watcher module.
##
## Measures:
##   1. newFileTree      — construction cost vs tree size
##   2. diffTree (quiet) — diff cost when nothing has changed
##   3. diffTree (dirty) — diff cost with N files modified
##   4. poll (idle)      — per-frame overhead when nothing happens
##   5. dispatch latency — time from disk write to callback received
##
## Run:
##   nim c -d:release -r bench.nim
##
## Results are printed as a simple table to stdout.

import os, times, strutils, strformat, math, algorithm
include "../../src/filesys/filesystem.nim"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const
  BENCH_ROOT = "tmp_bench"
  WARMUP     = 3
  ITERATIONS = 20
  TIMEOUT = 300

proc now(): float = epochTime()

proc median(s: var seq[float]): float =
  s.sort()
  s[s.len div 2]

proc mean(s: seq[float]): float =
  s.foldl(a + b, 0.0) / s.len.float

template bench(iters: int; body: untyped): float =
  ## Runs `body` `iters` times and returns the median duration in ms.
  var samples: seq[float]
  for i in 0 ..< WARMUP + iters:
    let t0 = now()
    body
    let elapsed = (now() - t0) * 1000.0
    if i >= WARMUP:
      samples.add(elapsed)
  var s = samples
  median(s)

proc makeTree(root: string; dirs, filesPerDir: int) =
  ## Creates a synthetic directory tree on disk.
  createDir(root)
  writeFile(root / "root.txt", "root")
  for d in 0 ..< dirs:
    let dir = root / &"dir_{d:03}"
    createDir(dir)
    for f in 0 ..< filesPerDir:
      writeFile(dir / &"file_{f:04}.txt", "x")
      writeFile(dir / &"asset_{f:04}.png", "x")

proc cleanup() =
  removeDir(BENCH_ROOT)

proc separator() = echo "-".repeat(72)

proc header(s: string) =
  separator()
  echo "  " & s
  separator()

# ---------------------------------------------------------------------------
# 1. newFileTree — construction cost
# ---------------------------------------------------------------------------

proc benchConstruction() =
  header "1. newFileTree — construction cost"
  header &"""  {"Files":>10}  {"Dirs":>8}  {"Median (ms)":>14}"""
  separator()

  for (dirs, fpd) in [(10, 10), (10, 50), (50, 20)]:
    let root  = BENCH_ROOT / "construction"
    removeDir(root)
    makeTree(root, dirs, fpd)
    let total = dirs * fpd * 2

    let ms = bench(ITERATIONS):
      discard newFileTree(root)

    echo &"  {total:>10}  {dirs:>8}  {ms:>14.3f}"
    removeDir(root)

# ---------------------------------------------------------------------------
# 2. diffTree (quiet) — nothing changed
# ---------------------------------------------------------------------------

proc benchDiffQuiet() =
  header "2. diffTree — quiet tree (nothing changed)  ← per-frame cost"
  echo &"""  {"Files":>10}  {"Dirs":>8}  {"Median (ms)":>14} {"Median (us)":>14}"""
  separator()

  for (dirs, fpd) in [(10, 10), (50, 20)]:
    let root  = BENCH_ROOT / "diff_quiet"
    removeDir(root)
    makeTree(root, dirs, fpd)
    var tree  = newFileTree(root)
    let total = dirs * fpd * 2

    let ms = bench(ITERATIONS):
      discard tree.diffTree()

    echo &"  {total:>10}  {dirs:>8}  {ms:>14.3f}  {ms * 1000.0:>14.1f}"
    removeDir(root)

# ---------------------------------------------------------------------------
# 3. diffTree (dirty) — N files modified
# ---------------------------------------------------------------------------

proc benchDiffDirty() =
  header "3. diffTree — dirty tree (N files modified)"
  echo &"""  {"Changed":>10}  {"Total":>10}  {"Median (ms)":>14}"""
  separator()

  let dirs = 50
  let fpd  = 20
  let root = BENCH_ROOT / "diff_dirty"
  removeDir(root)
  makeTree(root, dirs, fpd)
  var tree  = newFileTree(root)
  let total = dirs * fpd * 2

  for nChanged in [1, 5, 10, 50, 100]:
    var targets: seq[string]
    for i in 0 ..< nChanged:
      targets.add(root / &"dir_{i mod dirs:03}" / &"file_{(i div dirs) mod fpd:04}.txt")

    let ms = bench(ITERATIONS):
      for p in targets:
        writeFile(p, "modified")
        setLastModificationTime(p, getTime())
      discard tree.diffTree()
      for p in targets:
        writeFile(p, "x")

    echo &"  {nChanged:>10}  {total:>10}  {ms:>14.3f}"

  removeDir(root)

# ---------------------------------------------------------------------------
# 4. poll (idle) — per-frame overhead
# ---------------------------------------------------------------------------

proc benchPollIdle() =
  header "4. poll(timeout=0) — idle overhead per frame"
  echo &"""  {"Median (µs)":>14}  {"@ 60 fps":>10}  {"@ 120 fps":>10}  {"@ 240 fps":>10}"""
  separator()

  let root = BENCH_ROOT / "poll_idle"
  removeDir(root)
  makeTree(root, 50, 20)
  var tree = newFileTree(root)
  var w    = newWatcher(tree)

  let ms = bench(ITERATIONS * 5):
    w.poll(timeout = 0)

  let us     = ms * 1000.0
  let pct60  = (ms / (1000.0 / 60.0))  * 100.0
  let pct120 = (ms / (1000.0 / 120.0)) * 100.0
  let pct240 = (ms / (1000.0 / 240.0)) * 100.0
  echo &"  {us:>14.1f}  {pct60:>9.2f}%  {pct120:>9.2f}%  {pct240:>9.2f}%"

  w.close()
  removeDir(root)

# ---------------------------------------------------------------------------
# 5. Dispatch latency — write to callback
# ---------------------------------------------------------------------------

proc benchLatency() =
  header "5. Dispatch latency — disk write → callback fired"
  echo &"""  {"#":>6}  {"Latency (ms)":>14}"""
  separator()

  let root = BENCH_ROOT / "latency"
  removeDir(root)
  createDir(root)
  var tree = newFileTree(root)
  var w    = newWatcher(tree)

  var latencies: seq[float]

  for i in 0 ..< 10:
    let target   = root / &"lat_{i}.txt"
    let t0       = now()
    var received = false

    w.onEvent(proc(ev: FileEvent) =
      if not received and ev.path.endsWith(".txt"):
        latencies.add((now() - t0) * 1000.0)
        received = true)

    writeFile(target, "x")

    let deadline = now() + 2.0
    while not received and now() < deadline:
      w.poll(timeout = 50)

    w.removeCallbacks()

    if received:
      echo &"  {i+1:>6}  {latencies[^1]:>14.2f}"
    else:
      echo &"  {i+1:>6}  {TIMEOUT:>14}"

  if latencies.len > 0:
    var s = latencies
    separator()
    echo &"""  {"median":>6}  {median(s):>14.2f}"""
    echo &"""  {"mean":>6}  {mean(latencies):>14.2f}"""
    echo &"""  {"min":>6}  {latencies.min:>14.2f}"""
    echo &"""  {"max":>6}  {latencies.max:>14.2f}"""

  w.close()
  removeDir(root)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo ""
echo "  FileSystem & Watcher — Performance Benchmark"
echo "  Nim " & NimVersion
echo ""

cleanup()
createDir(BENCH_ROOT)

benchConstruction()
echo ""
benchDiffQuiet()
echo ""
benchDiffDirty()
echo ""
benchPollIdle()
echo ""
benchLatency()
echo ""

cleanup()
echo "  Done."