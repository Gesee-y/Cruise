import unittest, sequtils
include "../../src/ecs/table.nim"

type
  Position = object
    x, y: float32
  Velocity = object
    x, y: float32
  Health = object
    hp: int
  Dead = object

proc newPosition(x,y:float32):Position = Position() 
proc setComponent[T](blk: ptr T, i:uint, v:Position) =
  blk.data.x[i] = v.x*2
  blk.data.y[i] = v.y/2

proc initTestWorld(): ECSWorld =
  var world = newECSWorld()
  discard world.registerComponent(Position, true)
  discard world.registerComponent(Velocity)
  discard world.registerComponent(Health)
  discard world.registerComponent(Dead)
  
  #discard world.createEntity(0)
  #discard world.createEntity(0,1)
  #discard world.createEntity(0,2)
  #discard world.createEntity(1,2)
  #discard world.createEntity(0,1)
  #discard world.createEntity(1,2,3)
  #discard world.createEntity(0,3)

  #discard world.createSparseEntity(0)
  #discard world.createSparseEntity(0,1)
  #discard world.createSparseEntity(0,2)
  #discard world.createSparseEntity(1,2)
  #discard world.createSparseEntity(0,1)
  #discard world.createSparseEntity(1,2,3)
  #discard world.createSparseEntity(0,3)
  
  return world

var world = initTestWorld()

suite "QuerySignature building":

  test "include only":
    let sig = buildQuerySignature(world, @[
      includeComp(getComponentId(world, Position)),
      includeComp(getComponentId(world, Velocity))
    ])

    check sig.modified.len == 0
    check sig.notModified.len == 0
    check sig.includeMask[0] != 0
    check sig.excludeMask[0] == 0

  test "exclude only":
    let sig = buildQuerySignature(world, @[
      excludeComp(getComponentId(world, Dead))
    ])

    check sig.excludeMask[0] != 0

  test "modified implies include":
    let pid = getComponentId(world, Position)
    let sig = buildQuerySignature(world, @[
      modifiedComp(pid)
    ])

    check pid in sig.modified
    check (sig.includeMask and maskOf(pid))[0] != 0

suite "matchesArchetype":

  test "matches include":
    let arch = maskOf(0, 1)
    let sig = buildQuerySignature(world, @[ includeComp(getComponentId(world, Position)) ])
    check matchesArchetype(sig, arch)

  test "fails exclude":
    let arch = maskOf(0, 3)
    let sig = buildQuerySignature(world, @[ excludeComp(getComponentId(world, Dead)) ])
    check not matchesArchetype(sig, arch)

suite "Dense query basic":

  test "dense include":
    let e1 = world.createEntity(0, 1)
    let e2 = world.createEntity(0)
    let e3 = world.createEntity(1)

    let sig = query(world, Position)
    check denseQueryCount(world, sig) == 2

  test "dense include + exclude":
    let sig = query(world, Position and not Velocity)
    check denseQueryCount(world, sig) == 1

suite "Dense query change tracking":

  test "modified component only":
    let e1 = world.createEntity(0)
    let e2 = world.createEntity(0)
    var pos = world.get(Position, true)
    var c = 0

    pos[e1] = Position(x:1, y:2)
    #world.clearChanges()

    pos[e2] = Position(x:3, y:4)

    let sig = query(world, Modified[Position])
    for (bid, r) in denseQuery(world, sig):
      for _ in r:
        c += 1

    check c == 2

  test "not modified":
    let sig = query(world, Position and not Modified[Position])
    var c = 0
    for (bid, r) in denseQuery(world, sig):
      for _ in r:
        c += 1

    check c == 2

suite "Sparse query basic":

  test "sparse include":
    let s1 = world.createSparseEntity(0)
    let s2 = world.createSparseEntity(0, 1)
    let s3 = world.createSparseEntity(1)

    let sig = query(world, Position)
    check sparseQueryCount(world, sig) == 2

  test "sparse exclude":
    let sig = query(world, Position and not Velocity)
    check sparseQueryCount(world, sig) == 1

suite "Sparse query change tracking":

  test "modified sparse":
    let s1 = world.createSparseEntity(0)
    let s2 = world.createSparseEntity(0)
    var pos = world.get(Position, true)
    var c = 0

    #world.clearChanges()
    pos[s2] = Position(x:5, y:6)

    let sig = query(world, Modified[Position])
    check sparseQueryCount(world, sig) == 1

suite "Dense / Sparse equivalence":

  test "same semantic result":
    var d = world.createEntity(0, 1)
    var s = world.makeSparse(d)
    var c = 0

    let sig = query(world, Modified[Position])
    check sparseQueryCount(world, sig) == 2

    let d2 = world.makeDense(s)
    for (bid, r) in denseQuery(world, sig):
      for _ in r:
        c += 1

    check c == 3

suite "Query DSL":

  test "complex expression":
    let sig = query(world,
      Position and Modified[Velocity] and not Dead
    )

    check sig.components.len == 3
