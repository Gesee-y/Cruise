######################################################################################################################################
################################################### ECS ARCHETYPE GRAPH ##############################################################
######################################################################################################################################
##
## Archetype graph for the Cruise ECS.
##
## An archetype is a unique combination of component types. The archetype
## graph stores these as nodes connected by add/remove edges, enabling O(1)
## archetype transitions when components are added or removed.
##
## Each node caches both **add-edges** (``edges``) and **remove-edges**
## (``removeEdges``) for every component, so repeated transitions are
## instantaneous.
##
## Usage example
## =============
##
## .. code-block:: nim
##   import cruise/ecs/archetypes
##
##   var graph = initArchetypeGraph()
##
##   # Build: ∅ →(+Pos)→ {Pos} →(+Vel)→ {Pos,Vel}
##   let posNode = graph.addComponent(graph.root, posId)
##   let pvNode  = graph.addComponent(posNode, velId)
##
##   # Navigate back: {Pos,Vel} →(−Vel)→ {Pos}
##   let backNode = graph.removeComponent(pvNode, velId)
##   assert backNode == posNode
##
##   # Fast lookup by mask (uses LRU cache)
##   let found = graph.findArchetypeFast(pvNode.getMask())
##   assert found == pvNode

import std/[tables, hashes]
import ./types
import ./mask
import ./registry
export types, mask

# ──── NOTE ─────────────────────────────────────────────────────────────── #
# Type definitions for ArchetypeNode and ArchetypeGraph live in types.nim. #
# This file contains the graph operations (add, remove, find, etc.).       #
# ─────────────────────────────────────────────────────────────────────── #

# ─── Edge helpers ────────────────────────────────────────────────────────── #

template hasEdge*(node: ArchetypeNode, comp: int): bool =
  let idx = comp shr 6
  let bit = comp and 63
  (node.edgeMask[idx] and (1'u64 shl bit)) != 0

template setEdge*(node: ArchetypeNode, comp: int) =
  let idx = comp shr 6
  let bit = comp and 63
  node.edgeMask[idx] = node.edgeMask[idx] or (1'u64 shl bit)

template getEdge*(node: ArchetypeNode, comp: int): ArchetypeNode =
  node.edges[comp]

template setEdgePtr*(node: ArchetypeNode, comp: int, target: ArchetypeNode) =
  node.edges[comp] = target
  node.setEdge(comp)

template getRemoveEdge*(node: ArchetypeNode, comp: int): ArchetypeNode =
  node.removeEdges[comp]

template setRemoveEdgePtr*(node: ArchetypeNode, comp: int, target: ArchetypeNode) =
  node.removeEdges[comp] = target

# ─── Graph construction ─────────────────────────────────────────────────── #

proc initArchetypeGraph*(): ArchetypeGraph =
  ## Create a new archetype graph with an empty root node (∅).
  var emptyMask: ArchetypeMask
  new(result)

  result.root = ArchetypeNode(
    id: 0,
    mask: emptyMask,
    partition: nil,
    componentIds: @[],
    lastEdge: -1,
    lastRemEdge: -1,
  )

  result.nodes = @[result.root]
  result.maskToId[emptyMask] = 0

proc createNode*(graph: var ArchetypeGraph, mask: ArchetypeMask,
    id: uint16 = graph.nodes.len.uint16): ArchetypeNode {.inline.} =
  ## Create a new archetype node for the given mask.
  result = ArchetypeNode(
    id: id,
    mask: mask,
    partition: nil,
    componentIds: mask.getComponents(),
    lastEdge: -1,
    lastRemEdge: -1,
  )

  if id.int >= graph.nodes.len:
    graph.nodes.setLen(id+1)

  graph.nodes[id] = result
  graph.maskToId[mask] = id

# ─── Component transitions ──────────────────────────────────────────────── #

proc addComponent*(graph: var ArchetypeGraph,
                   node: ArchetypeNode,
                   comp: int): ArchetypeNode {.inline.} =
  ## Navigate (or create) the archetype obtained by adding ``comp`` to ``node``.
  if node.hasEdge(comp):
    return node.getEdge(comp)

  let newMask = node.mask.withComponent(comp)

  if newMask in graph.maskToId:
    result = graph.nodes[graph.maskToId[newMask]]
  else:
    result = graph.createNode(newMask)

  node.setEdgePtr(comp, result)
  result.setRemoveEdgePtr(comp, node)
  node.lastEdge = comp

proc addComponent*(graph: var ArchetypeGraph,
                   node: ArchetypeNode,
                   comps: openArray[int]): ArchetypeNode =
  ## Add multiple components in sequence.
  var res = node
  for id in comps:
    res = graph.addComponent(res, id)
  return res

proc removeComponent*(graph: var ArchetypeGraph,
                      node: ArchetypeNode,
                      comp: int): ArchetypeNode {.inline.} =
  ## Navigate (or create) the archetype obtained by removing ``comp`` from ``node``.
  result = node.getRemoveEdge(comp)
  if result != nil:
    node.lastRemEdge = comp
    return result

  let newMask = node.mask.withoutComponent(comp)

  if newMask in graph.maskToId:
    result = graph.nodes[graph.maskToId[newMask]]
  else:
    result = graph.createNode(newMask)

  node.setRemoveEdgePtr(comp, result)
  result.setEdgePtr(comp, node)
  node.lastRemEdge = comp

proc removeComponent*(graph: var ArchetypeGraph,
                   node: ArchetypeNode,
                   comps: openArray[int]): ArchetypeNode =
  ## Remove multiple components in sequence.
  var res = node
  for id in comps:
    res = graph.removeComponent(res, id)
  return res

# ─── Archetype lookup ────────────────────────────────────────────────────── #

proc findArchetype*(graph: var ArchetypeGraph,
                    components: static openArray[int]): ArchetypeNode =
  ## Find (or create) the archetype for a **compile-time known** component set.
  let id = toArchetypeID(components)
  if id >= graph.nodes.len or graph.nodes[id].isNil:
    var newMask: ArchetypeMask
    for c in components:
      newMask.withComponentInPlace(c)

    discard graph.createNode(newMask, id.uint16)

  graph.nodes[id]

proc findArchetype*(graph: var ArchetypeGraph,
                    components: openArray[int]): ArchetypeNode =
  ## Find (or create) the archetype by walking from root.
  result = graph.root
  for comp in components:
    result = graph.addComponent(result, comp)

proc findArchetype*(graph: var ArchetypeGraph,
                    mask: ArchetypeMask): ArchetypeNode =
  ## Find (or create) the archetype for a given mask.
  if mask in graph.maskToId:
    return graph.nodes[graph.maskToId[mask]]

  return graph.findArchetype(mask.getComponents())

proc findArchetypeFast*(graph: var ArchetypeGraph,
                        mask: ArchetypeMask): ArchetypeNode {.inline.} =
  ## Fast archetype lookup with single-entry LRU cache.
  if graph.lastMask == mask and graph.lru_active:
    return graph.lastNode

  let idPtr = graph.maskToId.getOrDefault(mask, uint16.high)
  graph.lru_active = true
  if idPtr != uint16.high:
    result = graph.nodes[idPtr]
    graph.lastMask = mask
    graph.lastNode = result
  else:
    result = graph.findArchetype(mask.getComponents())

# ─── Accessors ──────────────────────────────────────────────────────────── #

{.push inline.}

proc setPartition*(node: ArchetypeNode, partition: TablePartition) =
  node.partition = partition

proc getPartition*(node: ArchetypeNode): TablePartition =
  node.partition

proc getMask*(node: ArchetypeNode): ArchetypeMask =
  node.mask

proc getComponentIds*(node: ArchetypeNode): seq[int] =
  node.componentIds

proc componentCount*(node: ArchetypeNode): int =
  node.componentIds.len

proc nodeCount*(graph: ArchetypeGraph): int =
  graph.nodes.len

{.pop.}

proc `$`*(mask: ArchetypeMask): string =
  result = "{"
  let comps = mask.getComponents()
  for i, comp in comps:
    if i > 0:
      result.add(", ")
    result.add($comp)
  result.add("}")

proc `$`*(node: ArchetypeNode): string =
  "Node[" & $node.id & "]" & $node.mask

iterator archetypes*(graph: ArchetypeGraph): ArchetypeNode =
  ## Iterate over all archetype nodes in the graph.
  for node in graph.nodes:
    yield node

proc warmupTransitions*(graph: var ArchetypeGraph,
                        baseComponents: openArray[int],
                        transitionComponents: openArray[int]) =
  ## Pre-populate add-edges for expected transitions.
  let baseNode = graph.findArchetype(baseComponents)
  for comp in transitionComponents:
    discard graph.addComponent(baseNode, comp)
