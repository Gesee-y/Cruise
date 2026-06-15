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
  var w = newECSWorld()
  discard w.registerComponent(Position, true)
  discard w.registerComponent(Velocity)
  discard w.registerComponent(Health)
  discard w.registerComponent(Dead)

  #discard w.createEntity(Position)
  #discard w.createEntity(Position,1)
  #discard w.createEntity(Position,2)
  #discard w.createEntity(1,2)
  #discard w.createEntity(Position,1)
  #discard w.createEntity(1,2,3)
  #discard w.createEntity(Position,3)

  #discard w.createSparseEntity(Position)
  #discard w.createSparseEntity(Position,1)
  #discard w.createSparseEntity(Position,2)
  #discard w.createSparseEntity(Velocity,2)
  #discard w.createSparseEntity(Position,1)
  #discard w.createSparseEntity(Velocity,2,3)
  #discard w.createSparseEntity(Position,3)

  return w

var w = initTestWorld()

suite "QueryFilter":

  test "dense and sparse set/get":
    var q = newQueryFilter()

    q.dSet(3)
    q.sSet(7)

    check q.dGet(3)
    check q.sGet(7)
    check not q.dGet(2)

  test "logic ops":
    var a = newQueryFilter()
    var b = newQueryFilter()

    a.dSet(1); b.dSet(2)
    a.sSet(1); b.sSet(2)

    let c = a or b
    check c.dGet(1)
    check c.dGet(2)
    check c.sGet(1)
    check c.sGet(2)

suite "QuerySignature building":

  test "include only":
    let sig = buildQuerySignature[(Position, Velocity)](w, @[
      includeComp(Position.toComponentID),
      includeComp(Velocity.toComponentID)
    ])

    check sig.modified.len == 0
    check sig.notModified.len == 0
    check sig.includeMask[0] != 0
    check sig.excludeMask[0] == 0

  test "exclude only":
    let sig = buildQuerySignature[()](w, @[
      excludeComp(toComponentID(Dead))
    ])

    check sig.excludeMask[0] != 0

  test "modified implies include":
    let pid = toComponentID(Position)
    let sig = buildQuerySignature[(Position,)](w, @[
      modifiedComp(pid)
    ])

    check pid in sig.modified
    check (sig.includeMask and maskOf(pid))[0] != 0

suite "matchesArchetype":

  test "matches include":
    let arch = maskOf(0, 1)
    let sig = buildQuerySignature[(Position,)](w, @[ includeComp(toComponentID(Position)) ])
    check matchesArchetype(sig, arch)

  test "fails exclude":
    let arch = maskOf(0, 3)
    let sig = buildQuerySignature[()](w, @[ excludeComp(toComponentID(Dead)) ])
    check not matchesArchetype(sig, arch)

suite "Dense query basic":

  test "dense include":
    let e1 = w.createEntity(Position, Velocity)
    let e2 = w.createEntity(Position)
    let e3 = w.createEntity(Velocity)

    let sig = query(w, Position)
    check denseQueryCount(w, sig) == 2

  test "dense filter":
    var q = newQueryFilter()
    let e = w.createEntity(Position)
    q.set(e)

    var sig = query(w, Position)
    sig.addFilter(q)
    check denseQueryCount(w, sig) == 1

  test "dense include + exclude":
    let sig = query(w, Position and not Velocity)
    check denseQueryCount(w, sig) == 2

  test "dense query sugar":
    var sig = w.query(Position and not Velocity)
    var cnt = 0

    for (bid, r, pblk) in w.executeDQuery(sig):
      for i in r:
        cnt += 1

    check cnt == 2

suite "Dense query change tracking":

  test "modified component only":
    let e1 = w.createEntity(Position)
    let e2 = w.createEntity(Position)
    var pos = w.get(Position, true)
    var c = 0

    pos[e1] = Position(x:1, y:2)
    #w.clearChanges()

    pos[e2] = Position(x:3, y:4)

    let sig = query(w, Modified[Position])
    for (bid, r) in denseQuery(w, sig):
      for _ in r:
        c += 1

    check c == 2

  test "not modified":
    let sig = query(w, Position and not Modified[Position])
    var c = 0
    for (bid, r) in denseQuery(w, sig):
      for _ in r:
        c += 1

    check c == 3

suite "Sparse query basic":

  test "sparse include":
    let s1 = w.createSparseEntity(Position)
    let s2 = w.createSparseEntity(Position, Velocity)
    let s3 = w.createSparseEntity(Velocity)

    let sig = query(w, Position)
    check sparseQueryCount(w, sig) == 2

  test "sparse exclude":
    let sig = query(w, Position and not Velocity)
    check sparseQueryCount(w, sig) == 1

  test "sparse query sugar":
    var sig = w.query(Position and not Velocity)
    var cnt = 0

    for (bid, r, pblk) in w.executeSQuery(sig):
      for i in r:
        cnt += 1

    check cnt == 1

suite "Sparse query change tracking":

  test "modified sparse":
    let s1 = w.createSparseEntity(Position)
    let s2 = w.createSparseEntity(Position)
    var pos = w.get(Position, true)
    var c = 0

    #w.clearChanges()
    pos[s2] = Position(x:5, y:6)

    let sig = query(w, Modified[Position])
    check sparseQueryCount(w, sig) == 1

suite "Dense / Sparse equivalence":

  test "same semantic result":
    var d = w.createEntity(Position, Velocity)
    var s = w.makeSparse(d)
    var c = 0

    let sig = query(w, Modified[Position])
    check sparseQueryCount(w, sig) == 1

    let d2 = w.makeDense(s)
    for (bid, r) in denseQuery(w, sig):
      for _ in r:
        c += 1

    check c == 2

suite "Query DSL":

  test "complex expression":
    let sig = query(w,
      Position and Modified[Velocity] and not Dead
    )

    check sig.components.len == 3
