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
    parent: SceneID
    children: QueryFilter
  
  SceneTree = object
    root:RootNode
    toDFilter:seq[int]
    toSFilter:seq[int]
    nodes:seq[SceneNode]
    freelist:seq[int]

  SomeSceneNode = SceneNode | var SceneNode | ptr SceneNode

proc dDestroyNode(tree:var SceneTree, id:uint)
proc sDestroyNode(tree:var SceneTree, id:uint)

proc getNode(tree:SceneTree, id:SceneID): ptr SceneNode =
  case id.kind:
    of rDense:
      return addr tree.nodes[tree.toDFilter[id.id]-1]
    of rSparse:
      return addr tree.nodes[tree.toSFilter[id.id]-1]

proc getParent(tree:SceneTree, n:SomeSceneNode):ptr SceneNode =
  return tree.getNode(n.parent)

proc getChildren(n:SomeSceneNode): ptr QueryFilter =
  return addr n.children

proc unsetChild(par:var SceneNode|ptr SceneNode, child:SomeSceneNode) =
  case child.id.kind:
    of rDense:
      par.children.dLayer.unset(child.id.id.int)
    of rSparse:
      par.children.sLayer.unset(child.id.id.int)

proc dDestroyNode(tree:var SceneTree, id:uint) =
  let filID = tree.toDFilter[id]-1
  var node = addr tree.nodes[filID]
  var par = tree.getParent(node)

  par.unsetChild(node)
  tree.freelist.add(filID)
  tree.toDFilter[id.toIdx] = 0

  for i in node.children.dLayer:
    dDestroyNode(tree, i.uint)

  for i in node.children.sLayer:
    sDestroyNode(tree, i.uint)

proc sDestroyNode(tree:var SceneTree, id:uint) =
  let filID = tree.toSFilter[id]-1
  var node = addr tree.nodes[filID]
  var par = tree.getParent(node)

  par.unsetChild(node)
  tree.freelist.add(filID)
  tree.toSFilter[id] = 0

  for i in node.children.dLayer:
    dDestroyNode(tree, i.uint)

  for i in node.children.sLayer:
    sDestroyNode(tree, i.uint)

proc overrideNodes(tree:var SceneTree, id1, id2:uint) =
  let f1 = tree.toDFilter[id1]-1
  let f2 = tree.toDFilter[id2]-1
  tree.toDFilter[id2] = 0
  
  if f2 != -1:
    var n = addr tree.nodes[f2]
    var par = tree.getParent(n)

    par.children.dLayer.unset(id2.int)
    par.children.dLayer.set(id1.int)
    n.id.id = id1

    tree.nodes[f1] = tree.nodes[f2]

proc makeNode(tree:var SceneTree, d:DenseHandle): SceneNode =
  let hid = d.obj.id.toIdx
  assert hid.int >= tree.toDFilter.len or tree.toDFilter[hid] == 0
  return SceneNode(id:SceneID(kind:rDense, id:hid), children:newQueryFilter())

proc makeNode(tree:var SceneTree, s:SparseHandle): SceneNode =
  let hid = s.id
  assert hid.int >= tree.toSFilter.len or tree.toSFilter[hid] == 0
  return SceneNode(id:SceneID(kind:rSparse, id:hid), children:newQueryFilter())

proc getFreeId(tree:var SceneTree):int =
  if tree.freelist.len > 0:
    return tree.freelist.pop()

  tree.nodes.setLen(tree.nodes.len+1)
  return tree.nodes.len-1

#=###################################################################################################################################=#
#=####################################################### EXPORTED API ##############################################################=#
#=###################################################################################################################################=#

proc addChild*(tree:var SceneTree, h:DenseHandle|SparseHandle) =
  var n = tree.makeNode(h)
  var id = tree.getFreeId()
  tree.nodes[id] = n

  case n.id.kind:
    of rDense:
      if n.id.id.int >= tree.toDFilter.len:
        tree.toDFilter.setLen(n.id.id+1)

      tree.toDFilter[n.id.id] = id+1
    of rSparse:
      if n.id.id.int >= tree.toSFilter.len:
        tree.toSFilter.setLen(n.id.id+1)

      tree.toSFilter[n.id.id] = id+1

proc addChild*(tree:var SceneTree, node:ptr SceneNode, h:DenseHandle|SparseHandle) =
  var n = tree.makeNode(h)
  var id = tree.getFreeId()
  tree.nodes[id] = n

  case n.id.kind:
    of rDense:
      let hid = n.id.id.int
      if hid >= tree.toDFilter.len:
        tree.toDFilter.setLen(hid+1)

      tree.toDFilter[hid] = id+1
      node.children.dLayer.set(hid)
    of rSparse:
      let hid = n.id.id.int
      if hid >= tree.toSFilter.len:
        tree.toSFilter.setLen(hid+1)

      tree.toSFilter[hid] = id+1
      node.children.sLayer.set(hid)

proc addChild*(tree:var SceneTree, d:DenseHandle, h:DenseHandle|SparseHandle) =
  var node = addr tree.nodes[tree.toDFilter[d.obj.id.toIdx]-1]
  var n = tree.makeNode(h)
  var id = tree.getFreeId()
  tree.nodes[id] = n

  case n.id.kind:
    of rDense:
      let hid = n.id.id.int
      if hid >= tree.toDFilter.len:
        tree.toDFilter.setLen(hid+1)

      tree.toDFilter[hid] = id+1
      tree.nodes[tree.toDFilter[d.obj.id.toIdx]-1].children.dLayer.set(hid)
    of rSparse:
      let hid = n.id.id.int
      if hid >= tree.toSFilter.len:
        tree.toSFilter.setLen(hid+1)

      tree.toSFilter[hid] = id+1
      tree.nodes[tree.toSFilter[d.obj.id.toIdx]-1].children.sLayer.set(hid)

proc getParent(tree:SceneTree, d:DenseHandle): ptr SceneNode =
  return tree.getParent(tree.nodes[tree.toDFilter[d.obj.id.toIdx]])

proc getParent(tree:SceneTree, s:SparseHandle): ptr SceneNode =
  return tree.getParent(tree.nodes[tree.toSFilter[s.id]])

proc getChildren(tree:SceneTree, d:DenseHandle): ptr QueryFilter =
  return getChildren(tree.nodes[tree.toDFilter[d.obj.id.toIdx]])

proc getChildren(tree:SceneTree, s:SparseHandle): ptr QueryFilter =
  return getChildren(tree.nodes[tree.toSFilter[s.id]])

proc deleteNode*(tree: var SceneTree, d:DenseHandle) =
  tree.dDestroyNode(d.obj.id.toIdx.uint)

proc deleteNode*(tree: var SceneTree, s:SparseHandle) =
  tree.sDestroyNode(s.id)

template setUp*(world:var ECSWorld, tree:var SceneTree, root:DenseHandle|SparseHandle) =
  discard world.events.onDenseEntityDestroyed(
    proc (ev:DenseEntityDestroyedEvent) =
      let id = ev.entity.obj.id.toIdx
      dDestroyNode(tree, id.uint)
      tree.overrideNodes(id.uint, ev.last)
  )

  discard world.events.onSparseEntityDestroyed(
    proc (ev:SparseEntityDestroyedEvent) =
      let id = ev.entity.id
      sDestroyNode(tree, id.uint)
  )

  discard world.events.onDenseEntityMigrated(
    proc (ev:DenseEntityMigratedEvent) =
      let id = ev.entity.obj.id.toIdx
      tree.overrideNodes(id, ev.oldId.toIdx.uint)
      tree.overrideNodes(ev.oldId.toIdx.uint, ev.lastId)
  )
