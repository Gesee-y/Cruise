####################################################################################################################################################
############################################################# SCENETREE PLUGIN #####################################################################
####################################################################################################################################################

import ../table

type
  RootKind = enum
    rDense, rSparse

  RootNode = object
    case kind:RootKind
      of rDense:
        d:DenseHandle
      of rSparse:
        s:SparseHandle

  SceneID* = object
    kind:RootKind
    id*:uint

  SceneNode* = object
    id*: SceneID
    parent*: int
    children: QueryFilter

  SceneTree* = ref object
    root:int
    toDFilter:seq[int]
    toSFilter:seq[int]
    nodes:seq[SceneNode]
    freelist:seq[int]

  SomeSceneNode = SceneNode | var SceneNode | ptr SceneNode

const UPSIZE_OFFSET = 100

proc getKind(d:DenseHandle): RootKind = rDense
proc getKind(s:SparseHandle): RootKind = rSparse

proc getId(d:DenseHandle):uint = d.wid.uint
proc getId(s:SparseHandle):uint = s.id

proc reset*(tree: var SceneTree) =
  tree.root = -1
  tree.toDFilter = @[]
  tree.toSFilter = @[]
  tree.nodes = @[]
  tree.freelist = @[]

proc isRoot(tree: SceneTree, d:DenseHandle|SparseHandle):bool =
  let rid = tree.getRoot().id
  rid.kind == d.getKind and rid.id == d.getId()

proc dDestroyNode(tree:var SceneTree, id:uint)
proc sDestroyNode(tree:var SceneTree, id:uint)

proc dGetNode(tree:SceneTree, id:uint): ptr SceneNode =
  if id.int < tree.toDFilter.len and tree.toDFilter[id] > 0:
    return addr tree.nodes[tree.toDFilter[id]-1]
    
  return nil

proc sGetNode(tree:SceneTree, id:uint): ptr SceneNode =
  if id.int < tree.toSFilter.len and tree.toSFilter[id] > 0:
    return addr tree.nodes[tree.toSFilter[id]-1]

  return nil

proc toDenseID*(world: ECSWorld, h: QueryFilter | ptr QueryFilter): QueryFilter =
  result = newQueryFilter()
  for i in h.dLayer:
    result.dLayer.set(world.entities[i].id.toIdx)

proc toDenseID*(world: ECSWorld, h: QueryFilter | ptr QueryFilter, dst: var QueryFilter) =
  for i in h.dLayer:
    dst.dLayer.set(world.entities[i].id.toIdx)

proc getNode*(tree:SceneTree, id:SceneID): ptr SceneNode =
  case id.kind:
    of rDense:
      return tree.dGetNode(id.id)
    of rSparse:
      return tree.sGetNode(id.id)

proc getParent*(tree:SceneTree, n:SomeSceneNode):ptr SceneNode =
  if n.parent == -1: return nil
  return addr tree.nodes[n.parent]

proc getChildren*(n:SomeSceneNode): ptr QueryFilter =
  return addr n.children

proc unsetChild*(par:var SceneNode|ptr SceneNode, child:SomeSceneNode) =
  case child.id.kind:
    of rDense:
      par.children.dLayer.unset(child.id.id.int)
    of rSparse:
      par.children.sLayer.unset(child.id.id.int)

proc getFreeId(tree:var SceneTree):int =
  if tree.freelist.len > 0:
    return tree.freelist.pop()

  let id = tree.nodes.len
  tree.nodes.setLen(tree.nodes.len+UPSIZE_OFFSET)
  tree.nodes[^1].children = newQueryFilter()
  for i in id+1..<tree.nodes.len:
    tree.freelist.add(i)
  return id

proc dDestroyNode(tree:var SceneTree, id:uint) =
  let filID = tree.toDFilter[id]-1
  var node = addr tree.nodes[filID]
  var par = tree.getParent(node)

  if not par.isNil: par.unsetChild(node)
  tree.freelist.add(filID)

  for i in node.children.dLayer:
    dDestroyNode(tree, i.uint)
    tree.toDFilter[i] = 0

  for i in node.children.sLayer:
    sDestroyNode(tree, i.uint)
    tree.toSFilter[i] = 0

proc sDestroyNode(tree:var SceneTree, id:uint) =
  let filID = tree.toSFilter[id]-1
  var node = addr tree.nodes[filID]
  var par = tree.getParent(node)

  if not par.isNil: par.unsetChild(node)
  tree.freelist.add(filID)
  tree.toSFilter[id] = 0

  for i in node.children.dLayer:
    dDestroyNode(tree, i.uint)
    tree.toDFilter[i] = 0

  for i in node.children.sLayer:
    sDestroyNode(tree, i.uint)
    tree.toSFilter[i] = 0

proc overrideNodes(tree:var SceneTree, id1, id2:uint) =
  if id1.int >= tree.toDFilter.len: 
    tree.toDFilter.setLen(id1+1)
    tree.toDFilter[id1] = tree.getFreeId() + 1
  if id2.int >= tree.toDFilter.len: return
  
  let f1 = tree.toDFilter[id1]-1
  let f2 = tree.toDFilter[id2]-1
  tree.toDFilter[id2] = 0
  
  if f2 != -1 and f1 != f2:
    var n = addr tree.nodes[f2]
    var par = tree.getParent(n)

    if par != nil:
      par.children.dLayer.unset(id2.int)
      par.children.dLayer.set(id1.int)
    
    n.id.id = id1
    tree.toDFilter[id1] = f2+1

proc makeNode(tree:var SceneTree, d:DenseHandle, id:int): SceneNode =
  let hid = d.wid.uint
  assert hid.int >= tree.toDFilter.len or tree.toDFilter[hid] == 0
  result.id = SceneID(kind:rDense, id:hid)
  result.parent = -1
  result.children = newQueryFilter()

proc makeNode(tree:var SceneTree, s:SparseHandle): SceneNode =
  let hid = s.id
  assert hid.int >= tree.toSFilter.len or tree.toSFilter[hid] == 0
  result.id = SceneID(kind:rSparse, id:hid)
  result.parent = -1
  result.children = newQueryFilter()

proc setUpNode(tree:var SceneTree, id:int, d:DenseHandle)=
  tree.nodes[id].id = SceneID(kind:rDense, id:d.getId)
  tree.nodes[id].parent = -1
  tree.nodes[id].children.clear()

proc setUpNode(tree:var SceneTree, id:int, s:SparseHandle)=
  tree.nodes[id].id = SceneID(kind:rSparse, id:s.getId)
  tree.nodes[id].parent = -1
  tree.nodes[id].children.clear()

#=###################################################################################################################################=#
#=####################################################### EXPORTED API ##############################################################=#
#=###################################################################################################################################=#

proc setRoot*(tree: var SceneTree, h:DenseHandle|SparseHandle) =
  tree.reset()
  var id = tree.getFreeId()
  tree.setUpNode(id, h)
  
  tree.root = id

  case h.getKind:
    of rDense:
      let hid = tree.nodes[id].id.id.int
      if hid >= tree.toDFilter.len:
        tree.toDFilter.setLen(hid+1)

      tree.toDFilter[hid] = id+1
    of rSparse:
      let hid = tree.nodes[id].id.id.int
      if hid >= tree.toSFilter.len:
        tree.toSFilter.setLen(hid+1)

      tree.toSFilter[hid] = id+1

proc getRoot*(tree: SceneTree): ptr SceneNode =
  return addr tree.nodes[tree.root]

proc initSceneTree*(root:DenseHandle|SparseHandle): SceneTree =
  var tree:SceneTree
  new(tree)
  tree.setRoot(root)

  return tree

proc addChild*(tree:var SceneTree, node:ptr SceneNode, h:DenseHandle|SparseHandle, id:int) =
  tree.setUpNode(id, h)

  case node.id.kind:
    of rDense:
      tree.nodes[id].parent = tree.toDFilter[node.id.id]-1
    of rSparse:
      tree.nodes[id].parent = tree.toSFilter[node.id.id]-1

  case h.getKind:
    of rDense:
      let hid = tree.nodes[id].id.id.int
      if hid >= tree.toDFilter.len:
        tree.toDFilter.setLen(hid+1)

      tree.toDFilter[hid] = id+1
      node.children.dLayer.set(hid)
    of rSparse:
      let hid = tree.nodes[id].id.id.int
      if hid >= tree.toSFilter.len:
        tree.toSFilter.setLen(hid+1)

      tree.toSFilter[hid] = id+1
      node.children.sLayer.set(hid)

proc addChild*(tree:var SceneTree, h:DenseHandle|SparseHandle) =
  var id = tree.getFreeId()
  tree.addChild(tree.getRoot, h, id)

proc addChild*(tree:var SceneTree, d:DenseHandle, h:DenseHandle|SparseHandle) =
  var id = tree.getFreeId()
  var node = addr tree.nodes[tree.toDFilter[d.wid]-1]
  tree.addChild(node, h, id)

proc addChild*(tree:var SceneTree, s:SparseHandle, h:DenseHandle|SparseHandle) =
  var id = tree.getFreeId()
  var node = addr tree.nodes[tree.toSFilter[s.id]-1]
  tree.addChild(node, h, id)
  
proc getParent*(tree:SceneTree, d:DenseHandle):ptr SceneNode =
  return tree.getParent(tree.nodes[tree.toDFilter[d.wid]-1])

proc getParent*(tree:SceneTree, s:SparseHandle):ptr SceneNode =
  return tree.getParent(tree.nodes[tree.toSFilter[s.id]-1])

proc getChildren*(tree:SceneTree, d:DenseHandle): ptr QueryFilter =
  return getChildren(tree.nodes[tree.toDFilter[d.wid]-1])

proc getChildren*(tree:SceneTree, s:SparseHandle): ptr QueryFilter =
  return getChildren(tree.nodes[tree.toSFilter[s.id]-1])

proc deleteNode*(tree: var SceneTree, d:DenseHandle) =
  if tree.isRoot(d):
    tree.reset()
    return
  tree.dDestroyNode(d.wid.uint)
  tree.toDFilter[d.getId] = 0

proc deleteNode*(tree: var SceneTree, s:SparseHandle) =
  if tree.isRoot(s):
    tree.reset()
    return
  tree.sDestroyNode(s.id)
  tree.toSFilter[s.getId] = 0

template setUp*(world:var ECSWorld, tree:var SceneTree) =
  world.addResource(tree)
  var ev = world.events
  discard ev.onDenseEntityDestroyed(
    proc (ev:DenseEntityDestroyedEvent) =
      let w = ev.entity.world
      var tr = getResource[SceneTree](w)
      let id = ev.entity.wid
      if tr.isRoot(ev.entity):
        tr.reset()
        return
      dDestroyNode(tr, id.uint)
      tr.toDFilter[id] = 0
  )

  discard ev.onSparseEntityDestroyed(
    proc (ev:SparseEntityDestroyedEvent) =
      let id = ev.entity.id
      if tree.isRoot(ev.entity):
        tree.reset()
        return
      sDestroyNode(tree, id.uint)
      tree.toSFilter[id] = 0
  )

  discard ev.onDensified(
    proc (ev:DensifiedEvent) =
      let id = ev.oldSparse.id
      let nid = ev.newDense.wid.uint
      if id.int < tree.toSFilter.len and tree.toSFilter[id] > 0:
        var n = tree.sGetNode(id)
        var par = tree.getParent(n)

        if not par.isNil:
          par.children.sLayer.unset(id.int)
          par.children.dLayer.set(nid.int)

        n.id = SceneID(kind:rDense, id:nid.uint)

        if nid.int >= tree.toDFilter.len:
          tree.toDFilter.setLen(nid+1)

        tree.toDFilter[nid] = tree.toSFilter[id]
  )

  discard ev.onSparsified(
    proc (ev:SparsifiedEvent) =
      let id = ev.oldDense.wid.uint
      let nid = ev.newSparse.id
      if id.int < tree.toDFilter.len and tree.toDFilter[id] > 0:
        var n = tree.dGetNode(id)
        var par = tree.getParent(n)

        if not par.isNil:
          par.children.dLayer.unset(id.int)
          par.children.sLayer.set(nid.int)

        n.id = SceneID(kind:rSparse, id:nid)
        if nid.int >= tree.toSFilter.len:
          tree.toSFilter.setLen(nid+1)

        tree.toSFilter[nid] = tree.toDFilter[id]
  )
