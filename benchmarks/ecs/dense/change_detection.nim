import random
include "../../../src/ecs/table.nim"

# =========================
# Benchmark template
# =========================
include "../../../src/profile/benchmarks.nim"

const SAMPLE = 1000
const WARMUP = 1
const ENTITY_COUNT = 1000

type
  A = object
    x: int

  C[N] = object
    x: int

proc setup(n: int): ECSWorld =
  var world = newECSWorld()
  discard world.createEntities(n, A)
  world

proc setupSparse(n: int): ECSWorld =
  var world = newECSWorld()
  discard world.createSparseEntities(n, A)
  world

template benchIteration(world: var ECSWorld, sig: QuerySignature) =
  var ad = world.get(A)
  for bid, r in world.denseQuery(sig):
    var a = addr ad.blocks[bid].data.x
    for i in r:
      a[i] += 1

template benchSparseIteration(world: var ECSWorld, sig: QuerySignature) =
  var ad = world.get(A)
  for sid, r in world.sparseQuery(sig):
    let bid = ad.toSparse[sid]-1
    var a = addr ad.sparse[bid].data.x
    for i in r:
      a[i] += 1

proc buildAll(world: var ECSWorld, n: int): QuerySignature =
  var filter = newQueryFilter(n)
  for i in 0..<n:
    filter.dSet(i)

  var sig = world.query(A)
  sig.addFilter(filter)
  sig

proc buildFew(world: var ECSWorld, n: int): QuerySignature =
  var filter = newQueryFilter()
  randomize(42)
  for i in 0..<n:
    if rand(1.0) > 0.9: filter.dSet(i)

  var sig = world.query(A)
  sig.addFilter(filter)
  sig

proc buildSparseAll(world: var ECSWorld, n: int): QuerySignature =
  var filter = newQueryFilter(n)
  for i in 0..<n:
    filter.sSet(i)

  var sig = world.query(A)
  sig.addFilter(filter)
  sig

proc buildSparseFew(world: var ECSWorld, n: int): QuerySignature =
  var filter = newQueryFilter()
  randomize(42)
  for i in 0..<n:
    if rand(1.0) > 0.9: filter.sSet(i)

  var sig = world.query(A)
  sig.addFilter(filter)
  sig

proc buildNone(world: var ECSWorld, n: int): QuerySignature =
  var filter = newQueryFilter()
  var sig = world.query(A)
  sig.addFilter(filter)
  sig

proc filteringAll(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Filter all dense entities")
  suite.add benchmarkWithSetup(
    "Filter all " & $eCount & " dense entity",
    bSample,
    bWarm,
    (
      var world = setup(eCount)
      var sig = world.buildAll(eCount)
      var i: int

      # Warmup run 
      for bid, r in world.denseQuery(sig):
        discard addr i
    ),
    (
      benchIteration(world, sig)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc filteringFew(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Filter few dense entities")
  suite.add benchmarkWithSetup(
    "Filter few " & $eCount & " dense entity",
    bSample,
    bWarm,
    (
      var world = setup(eCount)
      var sig = world.buildFew(eCount)
      var i: int

      # Warmup run 
      for bid, r in world.denseQuery(sig):
        discard addr i
    ),
    (
      benchIteration(world, sig)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc filteringNone(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Filter none dense entities")
  suite.add benchmarkWithSetup(
    "Filter none " & $eCount & " dense entity",
    bSample,
    bWarm,
    (
      var world = setup(eCount)
      var sig = world.buildNone(eCount)
      var i: int

      # Warmup run 
      for bid, r in world.denseQuery(sig):
        discard addr i
    ),
    (
      benchIteration(world, sig)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc filteringSparseAll(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Filter all sparse entities")
  suite.add benchmarkWithSetup(
    "Filter all " & $eCount & " sparse entity",
    bSample,
    bWarm,
    (
      var world = setupSparse(eCount)
      var sig = world.buildSparseAll(eCount)
      var i: int

      # Warmup run 
      for bid, r in world.sparseQuery(sig):
        discard addr i
    ),
    (
      benchSparseIteration(world, sig)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc filteringSparseFew(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Filter few sparse entities")
  suite.add benchmarkWithSetup(
    "Filter few " & $eCount & " sparse entity",
    bSample,
    bWarm,
    (
      var world = setupSparse(eCount)
      var sig = world.buildSparseFew(eCount)
      var i: int

      # Warmup run 
      for bid, r in world.sparseQuery(sig):
        discard addr i
    ),
    (
      benchSparseIteration(world, sig)
    )
  )
  showDetailed(suite.benchmarks[^1])

proc filteringSparseNone(eCount=ENTITY_COUNT, bSample=SAMPLE, bWarm=WARMUP) =
  var suite = initSuite("Filter none sparse entities")
  suite.add benchmarkWithSetup(
    "Filter none " & $eCount & " sparse entity",
    bSample,
    bWarm,
    (
      var world = setupSparse(eCount)
      var sig = world.buildNone(eCount)
      var i: int

      # Warmup run 
      for bid, r in world.sparseQuery(sig):
        discard addr i
    ),
    (
      benchSparseIteration(world, sig)
    )
  )
  showDetailed(suite.benchmarks[^1])

filteringAll(5000)
filteringAll(50000)
filteringFew(5000)
filteringFew(50000)
filteringNone(5000)
filteringNone(50000)

filteringSparseAll(5000)
filteringSparseAll(50000)
filteringSparseFew(5000)
filteringSparseFew(50000)
filteringSparseNone(5000)
filteringSparseNone(50000)
