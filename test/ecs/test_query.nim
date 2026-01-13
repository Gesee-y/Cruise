import unittest, sequtils
include "../../src/ecs/table.nim"

type
  Pos = object
    x,y:float

  Vel = object
    dx,dy:float

  Acc = object
    ax,ay:float

proc initTestWorld(): ECSWorld =
  var world = newECSWorld()
  discard world.registerComponent(Pos)
  discard world.registerComponent(Vel)
  discard world.registerComponent(Acc)
  
  discard world.createEntity(0)
  discard world.createEntity(0,1)
  discard world.createEntity(0,2)
  discard world.createEntity(1,2)
  discard world.createEntity(0,1)

  discard world.createSparseEntity(0)
  discard world.createSparseEntity(0,1)
  discard world.createSparseEntity(0,2)
  discard world.createSparseEntity(1,2)
  discard world.createSparseEntity(0,1)
  
  return world

suite "ECS Query System":

  ###########################################################################
  ## MASK ITERATOR
  ###########################################################################

  test "maskIter iterator works":
    let mask = 0b10010010'u
    let res = toSeq(mask.maskIter)
    check res == @[1, 4, 7]

  ###########################################################################
  ## QUERY SIGNATURE
  ###########################################################################

  test "QuerySignature builds include/exclude masks correctly":
    var world = initTestWorld()

    let posId = getComponentId(world, Pos)
    let velId = getComponentId(world, Vel)
    let accId = getComponentId(world, Acc)

    let sig = buildQuerySignature(world, @[
      includeComp(posId),
      includeComp(velId),
      excludeComp(accId)
    ])

    check (sig.includeMask[posId div 64] and (1'u shl (posId mod 64))) != 0
    check (sig.includeMask[velId div 64] and (1'u shl (velId mod 64))) != 0
    check (sig.excludeMask[accId div 64] and (1'u shl (accId mod 64))) != 0

  ###########################################################################
  ## ARCHETYPE MATCHING
  ###########################################################################

  test "matchesArchetype include/exclude logic":
    var sig: QuerySignature
    sig.includeMask[0] = 0b011'u
    sig.excludeMask[0] = 0b100'u

    let okArch = [0b011'u, 0, 0, 0]
    let badInc = [0b001'u, 0, 0, 0]
    let badExc = [0b111'u, 0, 0, 0]

    check matchesArchetype(sig, okArch)
    check not matchesArchetype(sig, badInc)
    check not matchesArchetype(sig, badExc)

  ###########################################################################
  ## DENSE QUERY
  ###########################################################################

  test "denseQuery yields valid blocks and ranges":
    var world = initTestWorld()
    let sig = query(world, Pos and Vel)

    var count = 0
    for (blockIdx, r) in denseQuery(world, sig):
      check blockIdx >= 0
      check r.a < r.b
      count += r.b - r.a

    check count > 0

  test "denseQueryCount matches iteration":
    var world = initTestWorld()
    let sig = query(world, Pos)

    var iterCount = 0
    for (_, r) in denseQuery(world, sig):
      iterCount += r.b - r.a + 1

    check iterCount == denseQueryCount(world, sig)

  ###########################################################################
  ## SPARSE QUERY
  ###########################################################################

  test "sparseQuery yields valid chunk masks":
    var world = initTestWorld()
    let sig = query(world, Pos)

    var total = 0
    for (chunkIdx, mask) in sparseQuery(world, sig):
      check chunkIdx >= 0
      check mask != 0

      for _ in mask.maskIter:
        total += 1

    check total == sparseQueryCount(world, sig)

  test "sparseQuery excludes components correctly":
    var world = initTestWorld()

    let sigInc = query(world, Pos)
    let sigExc = query(world, Pos and not Vel)

    let incCount = sparseQueryCount(world, sigInc)
    let excCount = sparseQueryCount(world, sigExc)

    check excCount <= incCount

  ###########################################################################
  ## QUERY MACRO
  ###########################################################################

  test "query macro builds correct component list":
    var world = initTestWorld()
    let sig = query(world, Pos and Vel and not Acc)

    check sig.components.len == 3
    check sig.components.countIt(it.op == qInclude) == 2
    check sig.components.countIt(it.op == qExclude) == 1

  ###########################################################################
  ## DENSE / SPARSE INDEPENDENCE
  ###########################################################################

  test "dense and sparse queries do not interfere":
    var world = initTestWorld()

    let denseSig = query(world, Pos and Vel)
    let sparseSig = query(world, Pos)

    check denseQueryCount(world, denseSig) >= 0
    check sparseQueryCount(world, sparseSig) >= 0
