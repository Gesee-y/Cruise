####################################################################################################################################################
############################################################# SCENETREE PLUGIN #####################################################################
####################################################################################################################################################

type
  RootKind = enum
    rDense, rSparse

  RootNode = object
    case kind:RootKind
      of rDense:
        d:DenseHandle
      of rSparse:
        s:SparseHandle

  SceneID = object
    kind:RootKind
    id:uint

  SceneNode = object
    id: SceneID
    parent: int
    children: QueryFilter

  SceneTree = object
    root:int
    toDFilter:seq[int]
    toSFilter:seq[int]
    nodes:seq[SceneNode]
    freelist:seq[int]

  SomeSceneNode = SceneNode | var SceneNode | ptr SceneNode

const UPSIZE_OFFSET = 100

proc getKind(d:DenseHandle): RootKind = rDense
proc getKind(s:SparseHandle): RootKind = rSparse

proc getId(d:DenseHandle):uint = d.obj.id.toIdx
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

proc getNode(tree:SceneTree, id:SceneID): ptr SceneNode =
  case id.kind:
    of rDense:
      return tree.dGetNode(id.id)
    of rSparse:
      return tree.sGetNode(id.id)

proc getParent(tree:SceneTree, n:SomeSceneNode):ptr SceneNode =
  if n.parent == -1: return nil
  return addr tree.nodes[n.parent]

proc getChildren(n:SomeSceneNode): ptr QueryFilter =
  return addr n.children

proc unsetChild(par:var SceneNode|ptr SceneNode, child:SomeSceneNode) =
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
  let hid = d.obj.id.toIdx
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
  var node = addr tree.nodes[tree.toDFilter[d.obj.id.toIdx]-1]
  tree.addChild(node, h, id)

proc addChild*(tree:var SceneTree, s:SparseHandle, h:DenseHandle|SparseHandle) =
  var id = tree.getFreeId()
  var node = addr tree.nodes[tree.toSFilter[s.id]-1]
  tree.addChild(node, h, id)
  
proc getParent*(tree:SceneTree, d:DenseHandle):ptr SceneNode =
  return tree.getParent(tree.nodes[tree.toDFilter[d.obj.id.toIdx]-1])

proc getParent*(tree:SceneTree, s:SparseHandle):ptr SceneNode =
  return tree.getParent(tree.nodes[tree.toSFilter[s.id]-1])

proc getChildren*(tree:SceneTree, d:DenseHandle): ptr QueryFilter =
  return getChildren(tree.nodes[tree.toDFilter[d.obj.id.toIdx]-1])

proc getChildren*(tree:SceneTree, s:SparseHandle): ptr QueryFilter =
  return getChildren(tree.nodes[tree.toSFilter[s.id]-1])

proc deleteNode*(tree: var SceneTree, d:DenseHandle) =
  if tree.isRoot(d):
    tree.reset()
    return
  tree.dDestroyNode(d.obj.id.toIdx.uint)
  tree.toDFilter[d.getId] = 0

proc deleteNode*(tree: var SceneTree, s:SparseHandle) =
  if tree.isRoot(s):
    tree.reset()
    return
  tree.sDestroyNode(s.id)
  tree.toSFilter[s.getId] = 0

template setUp*(world:var ECSWorld, tree:var SceneTree) =

  discard world.events.onDenseEntityDestroyed(
    proc (ev:DenseEntityDestroyedEvent) =
      let id = ev.entity.obj.id.toIdx
      if tree.isRoot(ev.entity):
        tree.reset()
        return
      dDestroyNode(tree, id.uint)
      tree.overrideNodes(id.uint, ev.last)
      tree.toDFilter[id] = 0
  )

  discard world.events.onSparseEntityDestroyed(
    proc (ev:SparseEntityDestroyedEvent) =
      let id = ev.entity.id
      if tree.isRoot(ev.entity):
        tree.reset()
        return
      sDestroyNode(tree, id.uint)
      tree.toSFilter[id] = 0
  )

  discard world.events.onDenseEntityMigrated(
    proc (ev:DenseEntityMigratedEvent) =
      let id = ev.entity.obj.id.toIdx
      let oldId = ev.oldId.toIdx
      if oldId.int < tree.toDFilter.len and tree.toDFilter[oldId] > 0:
        if id.int < tree.toDFilter.len and tree.toDFilter[id] > 0:
          var n = addr tree.nodes[tree.toDFilter[id]-1]
          tree.getParent(n).unsetChild(n)

        tree.overrideNodes(id, ev.oldId.toIdx.uint)
        tree.overrideNodes(ev.oldId.toIdx.uint, ev.lastId)
  )

  discard world.events.onDenseEntityMigratedBatch(
    proc (ev:DenseEntityMigratedBatchEvent) =
      for i in 0..<ev.newIds.len:
        let id = ev.newIds[i].toIdx
        let oldId = ev.ids[i].toIdx
        let lastId = ev.oldIds[i].toIdx
        if oldId.int < tree.toDFilter.len and tree.toDFilter[oldId] > 0:
          var n = tree.nodes[tree.toDFilter[oldId]-1]
          var par = tree.getParent(n)
          if not par.isNil: par.unsetChild(n)

          tree.overrideNodes(id, oldId.uint)
          tree.overrideNodes(oldId.uint, lastId)
  )

  discard world.events.onDensified(
    proc (ev:DensifiedEvent) =
      let id = ev.oldSparse.id
      let nid = ev.newDense.obj.id.toIdx
      if id.int < tree.toSFilter.len and tree.toSFilter[id] > 0:
        var n = tree.sGetNode(id)
        var par = tree.getParent(n)

        if not par.isNil:
          par.children.sLayer.unset(id.int)
          par.children.dLayer.set(nid.int)

        n.id = SceneID(kind:rDense, id:nid)

        if nid.int >= tree.toDFilter.len:
          tree.toDFilter.setLen(nid+1)

        tree.toDFilter[nid] = tree.toSFilter[id]
  )

  discard world.events.onSparsified(
    proc (ev:SparsifiedEvent) =
      let id = ev.oldDense.obj.id.toIdx
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
