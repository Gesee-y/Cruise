######################################################################################################################################
################################################### ECS ARCHETYPE GRAPH ##############################################################
######################################################################################################################################

type
  ArchetypeNode* = ref object
    id: uint16
    mask: ArchetypeMask
    partition: TablePartition
    edges: ptr UncheckedArray[ArchetypeNode]
    removeEdges: ptr UncheckedArray[ArchetypeNode]
    edgeMask: array[4, uint64]
    componentIds: seq[ComponentId]
    lastEdge:int
    lastRemEdge:int
  
  ArchetypeGraph* = ref object
    root: ArchetypeNode
    nodes: seq[ArchetypeNode]
    maskToId: Table[ArchetypeMask, uint16]
    lastMask: ArchetypeMask
    lastNode: ArchetypeNode

{.push inline.}

proc hasEdge(node: ArchetypeNode, comp: ComponentId): bool =
  let idx = comp shr 6
  let bit = comp and 63
  return (node.edgeMask[idx] and (1'u64 shl bit)) != 0

proc setEdge(node: ArchetypeNode, comp: ComponentId) =
  let idx = comp shr 6
  let bit = comp and 63
  node.edgeMask[idx] = node.edgeMask[idx] or (1'u64 shl bit)

proc getEdge(node: ArchetypeNode, comp: ComponentId): ArchetypeNode =
  if node.edges == nil: return nil
  return node.edges[comp]

proc setEdgePtr(node: ArchetypeNode, comp: ComponentId, target: ArchetypeNode) =
  if node.edges == nil:
    node.edges = cast[ptr UncheckedArray[ArchetypeNode]](
      alloc0(MAX_COMPONENTS * sizeof(ArchetypeNode))
    )
  node.edges[comp] = target
  node.setEdge(comp)

proc getRemoveEdge(node: ArchetypeNode, comp: ComponentId): ArchetypeNode =
  if node.removeEdges == nil: return nil
  return node.removeEdges[comp]

proc setRemoveEdgePtr(node: ArchetypeNode, comp: ComponentId, target: ArchetypeNode) =
  if node.removeEdges == nil:
    node.removeEdges = cast[ptr UncheckedArray[ArchetypeNode]](
      alloc0(MAX_COMPONENTS * sizeof(ArchetypeNode))
    )
  node.removeEdges[comp] = target

{.pop.}

proc initArchetypeGraph*(): ArchetypeGraph =
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

proc createNode(graph: var ArchetypeGraph, mask: ArchetypeMask): ArchetypeNode {.inline.} =
  let id = graph.nodes.len.uint16
  
  result = ArchetypeNode(
    id: id,
    mask: mask,
    partition: nil,
    componentIds: mask.getComponents(),
    lastEdge: -1,
    lastRemEdge: -1,
  )
  
  graph.nodes.add(result)
  graph.maskToId[mask] = id

proc addComponent*(graph: var ArchetypeGraph, 
                   node: ArchetypeNode, 
                   comp: ComponentId): ArchetypeNode {.inline.} =
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
                   comps: openArray[ComponentId]): ArchetypeNode =
  var res = node
  for id in comps:
    res = graph.addComponent(res, id)

  return res

proc removeComponent*(graph: var ArchetypeGraph, 
                      node: ArchetypeNode, 
                      comp: ComponentId): ArchetypeNode {.inline.} =  
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
                   comps: openArray[ComponentId]): ArchetypeNode =
  var res = node
  for id in comps:
    res = graph.removeComponent(res, id)

  return res

proc findArchetype*(graph: var ArchetypeGraph, 
                    components: openArray[ComponentId]): ArchetypeNode =
  result = graph.root
  for comp in components:
    result = graph.addComponent(result, comp)

proc findArchetype*(graph: var ArchetypeGraph, 
                    mask: ArchetypeMask): ArchetypeNode =
  if mask in graph.maskToId:
    return graph.nodes[graph.maskToId[mask]]
  
  return graph.findArchetype(mask.getComponents())

proc findArchetypeFast*(graph: var ArchetypeGraph, 
                        mask: ArchetypeMask): ArchetypeNode {.inline.} =
  if graph.lastMask == mask:
    return graph.lastNode
  
  let idPtr = graph.maskToId.getOrDefault(mask, uint16.high)
  if idPtr != uint16.high:
    result = graph.nodes[idPtr]
    graph.lastMask = mask
    graph.lastNode = result
  else:
    result = graph.findArchetype(mask.getComponents())

{.push inline.}

proc setPartition*(node: ArchetypeNode, partition: TablePartition) =
  node.partition = partition

proc getPartition*(node: ArchetypeNode): TablePartition =
  node.partition

proc getMask*(node: ArchetypeNode): ArchetypeMask =
  node.mask

proc getComponentIds*(node: ArchetypeNode): seq[ComponentId] =
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
  for node in graph.nodes:
    yield node

proc warmupTransitions*(graph: var ArchetypeGraph, 
                        baseComponents: openArray[ComponentId],
                        transitionComponents: openArray[ComponentId]) =
  let baseNode = graph.findArchetype(baseComponents)
  for comp in transitionComponents:
    discard graph.addComponent(baseNode, comp)

