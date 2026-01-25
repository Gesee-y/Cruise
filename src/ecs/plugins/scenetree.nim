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
      return addr tree.nodes[tree.toDFilter[id.id]]
    of rSparse:
      return addr tree.nodes[tree.toSFilter[id.id]]

proc getParent(tree:SceneTree, n:SomeSceneNode):ptr SceneNode =
  return tree.getNode(n.parent)

proc unsetChild(par:var SceneNode|ptr SceneNode, child:SomeSceneNode) =
  case child.id.kind:
    of rDense:
      par.children.dLayer.unset(child.id.id)
    of rSparse:
      par.children.sLayer.unset(child.id.id)

proc dDestroyNode(tree:var SceneTree, id:uint) =
  let filID = tree.toDFilter[id]-1
  var node = addr tree.nodes[filID]
  var par = tree.getParent(node)

  par.unsetChild(node)
  freelist.add(filID)
  tree.toDFilter[ev.entity.obj.id.toIdx] = 0

  for i in qf.dLayer:
    dDestroyNode(tree, i.uint)

  for i in qf.sLayer:
    sDestroyNode(tree, i.uint)

proc sDestroyNode(tree:var SceneTree, id:uint) =
  let filID = tree.toSFilter[id]-1
  var node = addr tree.nodes[filID]
  var par = tree.getParent(node)

  par.unsetChild(node)
  freelist.add(filID)
  tree.toSFilter[ev.entity.obj.id.toIdx] = 0

  for i in qf.dLayer:
    dDestroyNode(tree, i.uint)

  for i in qf.sLayer:
    sDestroyNode(tree, i.uint)

proc overrideNodes(tree:var SceneTree, id1, id2:uint) =
  let f1 = tree.toDFilter[id1]-1
  let f2 = tree.toDFilter[id2]-1
  tree.toDFilter[id2] = 0
  
  if f2 != -1:
    var n = addr tree.nodes[f2]
    var par = tree.getParent(n)

    par.children.dLayer.unset(id2)
    par.children.dLayer.set(id1)
    n.id.id = id1

    tree.nodes[f1] = tree.nodes[f2]

#=###################################################################################################################################=#
#=####################################################### EXPORTED API ##############################################################=#
#=###################################################################################################################################=#

proc makeNode(d:DenseHandle) =
  return SceneNode(id:SceneID(kind:rDense, id:d.obj.id), children:newQueryFilter())

proc makeNode(s:SparseHandle) =
  return SceneNode(id:SceneID(kind:rSparse, id:s.id), children:newQueryFilter())

proc getFreeId(tree:var SceneTree):int =
  if tree.freelist.len > 0:
    return tree.freelist.pop()

  f.nodes.setLen(f.nodes.len+1)
  return f.nodes.len-1

proc addChild*(tree:var SceneTree, h:DenseHandle|SparseHandle) =
  var n = makeNode(h)
  var id = tree.getFreeId()
  tree.nodes[id] = n

  case n.id.kind:
    of rDense:
      if n.id.id.toIdx >= tree.toDFilter.len:
        tree.toDFilter.setLen(n.id.id.toIdx)

      tree.toDFilter[n.id.id.toIdx] = id+1
    of rSparse:
      if n.id.id.int >= tree.toSFilter.len:
        tree.toSFilter.setLen(n.id.id)

      tree.toSFilter[n.id.id] = id+1

proc addChild*(tree:var SceneTree, node:var SceneNode|ptr SceneNode, h:DenseHandle|SparseHandle) =
  var n = makeNode(h)
  var id = tree.getFreeId()
  tree.nodes[id] = n

  case n.id.kind:
    of rDense:
      let hid = n.id.id.toIdx
      if hid >= tree.toDFilter.len:
        tree.toDFilter.setLen(hid)

      tree.toDFilter[hid] = id+1
      node.children.dLayer.set(hid)
    of rSparse:
      let hid = n.id.id
      if hid.int >= tree.toSFilter.len:
        tree.toSFilter.setLen(hid)

      tree.toSFilter[hid] = id+1
      node.children.sLayer.set(hid)

template setUp*(world:var ECSWorld, tree:var SceneTree, root:DenseHandle|SparseHandle) =
  world.event.onDenseEntityDestroyed(
    proc (ev:DenseEntityDestroyedEvent) =
      let id = ev.entity.obj.id.toIdx
      dDestroyNode(tree, id.uint)
      tree.overrideNodes(id.uint, ev.last)
  )

  world.event.onSparseEntityDestroyed(
    proc (ev:SparseEntityDestroyedEvent) =
      let id = ev.entity.id
      sDestroyNode(tree, id.uint)
  )

  world.event.onDenseEntityMigrated(
    proc (ev:DenseEntityMigratedEvent) =
      let id = ev.entity.obj.id.toIdx
      tree.overrideNodes(id, ev.oldId.toIdx.uint)
      tree.overrideNodes(ev.oldId.toIdx.uint, ev.last)
  )
