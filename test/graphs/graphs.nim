import std/unittest
include "../../src/graph/graph.nim"

suite "DiGraph basic operations":

  test "add_vertex allocates unique ids":
    var g: DiGraph
    let a = g.add_vertex()
    let b = g.add_vertex()
    check a == 0
    check b == 1
    check g.isValid(a)
    check g.isValid(b)

  test "add_edge creates correct forward/back links":
    var g: DiGraph
    let a = g.add_vertex()
    let b = g.add_vertex()

    check g.add_edge(a, b) == true
    check g.indegrees[b] == 1
    check g.outedges[a].len == 1
    check g.inedges[b].len == 1
    check g.outedges[a][0].idx == b
    check g.inedges[b][0].idx == a

    # Back indices must be consistent
    let backA = g.outedges[a][0].back
    let backB = g.inedges[b][0].back
    check g.inedges[b][backA].idx == a
    check g.outedges[a][backB].idx == b

  test "rem_edge removes both directions correctly":
    var g: DiGraph
    let a = g.add_vertex()
    let b = g.add_vertex()

    discard g.add_edge(a, b)
    g.rem_edge(a, b)

    check g.outedges[a].len == 0
    check g.inedges[b].len == 0
    check g.indegrees[b] == 0

  test "cycle detection":
    var g: DiGraph
    let a = g.add_vertex()
    let b = g.add_vertex()
    let c = g.add_vertex()

    check g.add_edge(a, b) == true
    check g.add_edge(b, c) == true

    # This should create a cycle and fail
    check g.add_edge(c, a) == false

  test "topo_sort correctness":
    var g: DiGraph
    let a = g.add_vertex()
    let b = g.add_vertex()
    let c = g.add_vertex()

    discard g.add_edge(a, b)
    discard g.add_edge(a, c)
    discard g.add_edge(b, c)

    let sorted = g.DFSTopoSort()
    # Valid topological order must respect a → b → c
    let pos = proc(x:int): int = sorted.find(x)

    check pos(a) < pos(b)
    check pos(b) < pos(c)

    debugPrint(g)

  test "rem_vertex removes all its incoming and outgoing edges":
    var g: DiGraph
    let a = g.add_vertex()
    let b = g.add_vertex()
    let c = g.add_vertex()

    discard g.add_edge(a, b)
    discard g.add_edge(b, c)
    discard g.add_edge(a, c)

    g.rem_vertex(b)

    check g.isValid(a)
    check not g.isValid(b)
    check g.isValid(c)

    # All edges touching b must be gone
    for e in g.outedges:
      for info in e:
        check info.idx != b

    for e in g.inedges:
      for info in e:
        check info.idx != b

    # indegrees must be updated
    check g.indegrees[c] == 1   # only edge a→c should remain

  test "free_list reuse vertices":
    var g: DiGraph
    let a = g.add_vertex()
    let b = g.add_vertex()
    g.rem_vertex(a)

    let c = g.add_vertex()
    check c == a   # reused
