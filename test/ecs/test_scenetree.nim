import std/[unittest]
include "../../src/ecs/table.nim"
include "../../src/ecs/plugins/scenetree.nim"

type
  Position = object
    x,y:float32

proc newPosition(x,y:float32):Position =
  Position(x:x,y:y)

suite "SceneTree with real ECS":

  test "dense root attach":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    var tree: SceneTree
    let e = world.createEntity(0)

    world.setUp(tree, e)
    tree.addChild(e)

    let node = tree.getNode(SceneID(kind:rDense,id:e.obj.id.toIdx))
    check node.id.id == e.obj.id.toIdx

  test "dense parent child":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    var tree: SceneTree
    let a = world.createEntity(0)
    let b = world.createEntity(0)

    world.setUp(tree, a)
    tree.addChild(a)
    tree.addChild(a, b)

    let root = addr tree.nodes[tree.toDFilter[a.obj.id.toIdx]-1]
    check root.children.dLayer.get(b.obj.id.toIdx.int)

  test "sparse root attach":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    var tree: SceneTree
    let s = world.createSparseEntity(world.getComponentId(Position))

    world.setUp(tree, s)
    tree.addChild(s)

    let node = tree.getNode(SceneID(kind:rSparse,id:s.id))
    check node.id.id == s.id

  test "mixed hierarchy":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    var tree: SceneTree
    let d = world.createEntity(0)
    let s = world.createSparseEntity(0)

    world.setUp(tree, d)
    tree.addChild(d)
    tree.addChild(d, s)

    let root = tree.getNode(SceneID(kind:rDense,id:d.obj.id.toIdx))
    check root.children.sLayer.get(s.id.int)

  test "delete propagates":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    var tree: SceneTree
    let a = world.createEntity(0)
    let b = world.createEntity(0)

    world.setUp(tree, a)
    tree.addChild(a)
    tree.addChild(tree.getNode(SceneID(kind:rDense,id:a.obj.id.toIdx)), b)

    world.deleteEntity(b)

    let root = tree.getNode(SceneID(kind:rDense,id:a.obj.id.toIdx))
    check not root.children.dLayer.get(b.obj.id.toIdx.int)

  test "recursive delete":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    var tree: SceneTree
    let a = world.createEntity(0)
    let b = world.createEntity(0)
    let c = world.createEntity(0)

    world.setUp(tree, a)
    tree.addChild(a)
    tree.addChild(tree.getNode(SceneID(kind:rDense,id:a.obj.id.toIdx)), b)
    tree.addChild(tree.getNode(SceneID(kind:rDense,id:b.obj.id.toIdx)), c)

    world.deleteEntity(b)

    let root = tree.getNode(SceneID(kind:rDense,id:a.obj.id.toIdx))
    check not root.children.dLayer.get(b.obj.id.toIdx.int)

  test "migration updates tree":
    var world = newECSWorld()
    let pid = world.registerComponent(Position)

    var tree: SceneTree
    let e = world.createEntity()

    world.setUp(tree, e)
    tree.addChild(e)

    world.addComponent(e, pid)

    let node = tree.getNode(SceneID(kind:rDense,id:e.obj.id.toIdx))
    check node.id.id == e.obj.id.toIdx

  test "freelist reuse":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    var tree: SceneTree
    let a = world.createEntity(0)
    let b = world.createEntity(0)

    world.setUp(tree, a)
    tree.addChild(a)
    tree.addChild(tree.getNode(SceneID(kind:rDense,id:a.obj.id.toIdx)), b)

    world.deleteEntity(b)
    let c = world.createEntity(0)

    tree.addChild(tree.getNode(SceneID(kind:rDense,id:a.obj.id.toIdx)), c)

    let root = tree.getNode(SceneID(kind:rDense,id:a.obj.id.toIdx))
    check root.children.dLayer.get(c.obj.id.toIdx.int)
