######################################################################################################################################
################################################### ECS ARCHETYPE GRAPH ##############################################################
######################################################################################################################################

type
  ArchetypeNode* = ref object
    id: uint16
    mask: ArchetypeMask
    partition: TablePartition
    edges: array[MAX_COMPONENTS, ArchetypeNode]
    removeEdges: array[MAX_COMPONENTS, ArchetypeNode]
    edgeMask: ArchetypeMask
    componentIds: seq[int]
    lastEdge:int
    lastRemEdge:int
  
  ArchetypeGraph* = ref object
    root: ArchetypeNode
    nodes: seq[ArchetypeNode]
    maskToId: Table[ArchetypeMask, uint16]
    requiredComps: array[MAX_COMPONENTS, seq[int]]
    lru_active: bool
    lastMask: ArchetypeMask
    lastNode: ArchetypeNode


template hasEdge(node: ArchetypeNode, comp: int): bool =
  let idx = comp shr 6
  let bit = comp and 63
  (node.edgeMask[idx] and (1'u64 shl bit)) != 0

template setEdge(node: ArchetypeNode, comp: int) =
  let idx = comp shr 6
  let bit = comp and 63
  node.edgeMask[idx] = node.edgeMask[idx] or (1'u64 shl bit)

template getEdge(node: ArchetypeNode, comp: int): ArchetypeNode =
  node.edges[comp]

template setEdgePtr(node: ArchetypeNode, comp: int, target: ArchetypeNode) =
  node.edges[comp] = target
  node.setEdge(comp)

template getRemoveEdge(node: ArchetypeNode, comp: int): ArchetypeNode =
  node.removeEdges[comp]

template setRemoveEdgePtr(node: ArchetypeNode, comp: int, target: ArchetypeNode) =
  node.removeEdges[comp] = target
  
proc setRequired(g: var ArchetypeGraph, comp: int, req: int) =
  g.requiredComps[comp].add(req)

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

proc createNode(graph: var ArchetypeGraph, mask: ArchetypeMask, id:uint16=graph.nodes.len.uint16): ArchetypeNode {.inline.} =
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

proc addComponent*(graph: var ArchetypeGraph, 
                   node: ArchetypeNode, 
                   comp: int): ArchetypeNode {.inline.} =
  if node.hasEdge(comp):
    return node.getEdge(comp)
  
  var newMask = node.mask.withComponent(comp)
  for r in graph.requiredComps[comp]:
    newMask.withComponentInPlace(r)
  
  if newMask in graph.maskToId:
    result = graph.nodes[graph.maskToId[newMask]]
  else:
    result = graph.createNode(newMask)

  var remNode: ArchetypeNode

  if graph.requiredComps[comp].len > 0:
    newMask.withoutComponentInPlace(comp)
    if newMask in graph.maskToId:
      remNode = graph.nodes[graph.maskToId[newMask]]
    else:
      remNode = graph.createNode(newMask)
  else:
    remNode = node
  
  node.setEdgePtr(comp, result)
  result.setRemoveEdgePtr(comp, remNode)
  node.lastEdge = comp

proc addComponent*(graph: var ArchetypeGraph, 
                   node: ArchetypeNode, 
                   comps: openArray[int]): ArchetypeNode =
  var res = node
  for id in comps:
    res = graph.addComponent(res, id)

  return res

proc removeComponent*(graph: var ArchetypeGraph, 
                      node: ArchetypeNode, 
                      comp: int): ArchetypeNode {.inline.} =  
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
  var res = node
  for id in comps:
    res = graph.removeComponent(res, id)

  return res

macro findArchetype*(graph: var ArchetypeGraph, 
                    components: static openArray[int]): ArchetypeNode =
  let (m, id) = toArchetypeIDC(components)
  
  return quote("@") do:
    if `@id` >= `@graph`.nodes.len or `@graph`.nodes[`@id`].isNil:
      discard `@graph`.createNode(`@m`, `@id`.uint16)
    
    `@graph`.nodes[`@id`]

proc findArchetype*(graph: var ArchetypeGraph, 
                    components: openArray[int]): ArchetypeNode =
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
  for node in graph.nodes:
    yield node

proc warmupTransitions*(graph: var ArchetypeGraph, 
                        baseComponents: openArray[int],
                        transitionComponents: openArray[int]) =
  let baseNode = graph.findArchetype(baseComponents)
  for comp in transitionComponents:
    discard graph.addComponent(baseNode, comp)

