include "../../src/ecs/table.nim"
import unittest

test "archetype graph initializes with root only":
  let g = initArchetypeGraph()

  check g.root == 0
  check g.nodes[g.root].id == 0
  check g.nodes[g.root].componentCount == 0
  check g.nodeCount == 1

test "add single component creates new node":
  var g = initArchetypeGraph()
  let n1 = g.addComponent(g.root, 1)

  check n1 != g.root
  check g.nodes[n1].componentCount == 1
  check cast[seq[int]](g.nodes[n1].getComponentIds()) == @[1]
  check g.nodeCount == 2

test "adding same component twice does not create new node":
  var g = initArchetypeGraph()
  let n1 = g.addComponent(g.root, 1)
  let n2 = g.addComponent(g.root, 1)

  check n1 == n2
  check g.nodeCount == 2

test "component order does not create duplicate archetypes":
  var g = initArchetypeGraph()

  let a = g.findArchetype([1, 2])
  let b = g.findArchetype([2, 1])

  check a == b
  check g.nodes[a].componentCount == 2
  check g.nodeCount == 2  # {}, {1,2}, The graph create only the immediate node, not the in betweens

test "remove component returns to previous archetype":
  var g = initArchetypeGraph()

  let a = g.findArchetype([1, 2])
  let b = g.removeComponent(a, 2)

  check g.nodes[b].componentCount == 1
  check cast[seq[int]](g.nodes[b].getComponentIds()) == @[1]

test "add then remove returns same node":
  var g = initArchetypeGraph()

  let base = g.findArchetype([1])
  let plus = g.addComponent(base, 2)
  let back = g.removeComponent(plus, 2)

  check back == base

test "edges and removeEdges are consistent":
  var g = initArchetypeGraph()
  let a = g.findArchetype([1])
  let b = g.addComponent(a, 2)

  check g.nodes[a].hasEdge(2)
  check g.nodes[a].getEdge(2).uint16 == b
  check g.nodes[b].getRemoveEdge(2).uint16 == a

test "findArchetypeFast cache works":
  var g = initArchetypeGraph()
  let m = maskOf([1, 2, 3])

  let a = g.findArchetypeFast(m)
  let b = g.findArchetypeFast(m)

  check a == b
  check g.lastMask == m
  check g.lastNode == a

test "remove does not create duplicate nodes":
  var g = initArchetypeGraph()

  let a = g.findArchetype([1, 2])
  let b = g.removeComponent(a, 2)
  let c = g.findArchetype([1])

  check b == c
  check g.nodeCount == 3

test "warmupTransitions creates all edges":
  var g = initArchetypeGraph()

  g.warmupTransitions([1], [2, 3, 4])
  let base = g.findArchetype([1])

  for c in [2,3,4]:
    check g.nodes[base].hasEdge(c)

test "graph contains all subsets":
  var g = initArchetypeGraph()
  let comps = [1,2,3]

  discard g.findArchetype(comps)

  for node in g.archetypes():
    let mask = node.getMask()
    for c in mask.getComponents():
      check c in comps
