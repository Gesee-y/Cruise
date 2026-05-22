######################################################################################################################################
################################################### ECS ARCHETYPE GRAPH ##############################################################
######################################################################################################################################

type
  ArchetypeNode* = object
    id: uint16
    mask*: ArchetypeMask
    partition: TablePartition
    edges: array[MAX_COMPONENTS, int]
    removeEdges: array[MAX_COMPONENTS, int]
    edgeMask: ArchetypeMask
    componentIds: seq[int]
    lastEdge:int
    lastRemEdge:int
  
  ArchetypeGraph* = ref object
    root: uint16
    nodes*: seq[ArchetypeNode]
    maskToId: Table[ArchetypeMask, uint16]
    requiredComps: array[MAX_COMPONENTS, seq[int]]
    lru_active: bool
    lastMask: ArchetypeMask
    lastNode: uint16
    version: int

proc addRequired(m: var ArchetypeMask, comps: seq[int], registry: ptr array[MAX_COMPONENTS, seq[int]]) =
  for c in comps:
    if not m.hasComponent(c):
      m.withComponentInPlace(c)
      m.addRequired(registry[c], registry)

template hasEdge(node: ArchetypeNode, comp: int): bool =
  node.edges[comp] > 0

template setEdge(node: ArchetypeNode, comp: int) =
  let idx = comp shr 6
  let bit = comp and 63
  node.edgeMask[idx] = node.edgeMask[idx] or (1'u64 shl bit)

template getEdge(node: ArchetypeNode, comp: int): int =
  node.edges[comp]

template setEdgePtr(node: var ArchetypeNode, comp: int, target: uint16) =
  node.edges[comp] = target.int

template getRemoveEdge(node: ArchetypeNode, comp: int): int =
  node.removeEdges[comp]

template setRemoveEdgePtr(node: ArchetypeNode, comp: int, target: uint16) =
  node.removeEdges[comp] = target.int
  
proc setRequired(g: var ArchetypeGraph, comp: int, req: int) =
  g.requiredComps[comp].add(req)

proc isValidMask(g: ArchetypeGraph, m: ArchetypeMask): bool =
  for i in m.getComponents:
    for j in g.requiredComps[i]:
      if not m.hasComponent(j): return false

  return true

proc createNode(graph: var ArchetypeGraph, mask: ArchetypeMask, id:uint16=graph.nodes.len.uint16): uint16 {.inline.} =
  check(graph.nodes.len < int(high(uint16)),
    "createNode: archetype count has reached the uint16 maximum (" & $high(uint16) &
    "). Cannot create more archetypes. The ECS supports at most 65 535 distinct " &
    "component combinations.")

  var res = ArchetypeNode(
    id: id,
    mask: mask,
    partition: nil,
    componentIds: mask.getComponents(),
    lastEdge: -1,
    lastRemEdge: -1,
  )

  if not graph.isValidMask(mask): 
      raise newException(ValueError, "Cannot create node because of all components requirement aren't fullfiled.")

  for i in 0..<MAX_COMPONENTS:
    res.edges[i] = -1
    res.removeEdges[i] = -1
  
  if id.int >= graph.nodes.len:
    graph.nodes.setLen(id+1)

  graph.nodes[id] = res
  graph.maskToId[mask] = id
  graph.version += 1
  id

macro initArchetypeGraph*(): ArchetypeGraph =
  return quote("@") do:
    var emptyMask: ArchetypeMask
    var res: ArchetypeGraph
    new(res)
    
    for (m, id) in `@ARCHETYPE_ID_REGISTRY`.pairs:
      discard res.createNode(m, id.uint16)
    res

proc addComponent*(graph: var ArchetypeGraph, 
                   node: uint16, 
                   comp: int): uint16 {.inline.} =
  if graph.nodes[node].hasEdge(comp):
    return getEdge(graph.nodes[node], comp).uint16
  
  var newMask = graph.nodes[node].mask.withComponent(comp)
  var registry = addr graph.requiredComps
  newMask.addRequired(graph.requiredComps[comp], registry)
  
  if newMask in graph.maskToId:
    result = graph.maskToId[newMask]
  else:
    result = graph.createNode(newMask)

  var remNode: uint16 = node

  if graph.requiredComps[comp].len > 0:
    newMask.withoutComponentInPlace(comp)
    if newMask in graph.maskToId:
      remNode = graph.maskToId[newMask]
    else:
      remNode = graph.createNode(newMask)
  
  graph.nodes[node].setEdgePtr(comp, result)
  graph.nodes[result].setRemoveEdgePtr(comp, remNode)
  graph.nodes[node].lastEdge = comp

proc addComponent*(graph: var ArchetypeGraph, 
                   node: uint16, 
                   comps: openArray[int]): uint16 =
  var res = node
  for id in comps:
    res = graph.addComponent(res, id)

  return res

proc removeComponent*(graph: var ArchetypeGraph, 
                      node: uint16, 
                      comp: int): uint16 {.inline.} =
  check(comp >= 0 and comp < MAX_COMPONENTS,
    "removeComponent: component ID=" & $comp &
    " is out of valid range [0, " & $MAX_COMPONENTS & ").")
  checkWarn(graph.nodes[node].mask.hasComponent(comp),
    "removeComponent: archetype id=" & $node &
    " does not have component ID=" & $comp &
    ". Removing a non-existent component is a no-op migration " &
    "and may indicate a logic error in the calling code.")
  let res = getRemoveEdge(graph.nodes[node], comp)
  if res > 0:
    result = res.uint16
    graph.nodes[node].lastRemEdge = comp
    return result
  
  let newMask = graph.nodes[node].mask.withoutComponent(comp)
  
  if newMask in graph.maskToId:
    result = graph.maskToId[newMask]
  else:
    if not graph.isValidMask(newMask): 
      raise newException(ValueError, "Cannot remove components because some still require it.")
    result = graph.createNode(newMask)
  
  graph.nodes[node].setRemoveEdgePtr(comp, result)
  graph.nodes[result].setEdgePtr(comp, node)
  graph.nodes[node].lastRemEdge = comp

proc removeComponent*(graph: var ArchetypeGraph, 
                   node: uint16, 
                   comps: openArray[int]): uint16 =
  var res = node
  for id in comps:
    res = graph.removeComponent(res, id)

  return res

macro findArchetype*(graph: var ArchetypeGraph, 
                    components: static openArray[int]): uint16 =
  let (m, id) = toArchetypeIDC(components)
  
  return quote("@") do:
    if `@id` >= `@graph`.nodes.len or (`@graph`.nodes[`@id`].id == 0 and `@id` != 0):
      discard `@graph`.createNode(`@m`, `@id`.uint16)
    
    `@id`.uint16

proc findArchetype*(graph: var ArchetypeGraph, 
                    components: openArray[int]): uint16 =
  result = graph.root
  for comp in components:
    result = graph.addComponent(result, comp)

proc findArchetype*(graph: var ArchetypeGraph, 
                    mask: ArchetypeMask): uint16 =
  if mask in graph.maskToId:
    return graph.maskToId[mask]

  return graph.findArchetype(mask.getComponents())

proc findArchetypeFast*(graph: var ArchetypeGraph, 
                        mask: ArchetypeMask): uint16 {.inline.} =
  if graph.lastMask == mask and graph.lru_active:
    return graph.lastNode
  
  let idPtr = graph.maskToId.getOrDefault(mask, uint16.high)
  graph.lru_active = true
  if idPtr != uint16.high:
    result = idPtr
    graph.lastMask = mask
    graph.lastNode = result
  else:
    result = graph.findArchetype(mask)

{.push inline.}

proc setPartition*(node: var ArchetypeNode, partition: TablePartition) =
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
  for i, node in graph.nodes:
    if node.id > 0 or i == 0:
      yield node

proc warmupTransitions*(graph: var ArchetypeGraph, 
                        baseComponents: openArray[int],
                        transitionComponents: openArray[int]) =
  var baseNode = graph.findArchetype(baseComponents)
  for comp in transitionComponents:
    discard graph.addComponent(baseNode, comp)

