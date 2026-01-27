import std/[unittest]
include "../../src/ecs/table.nim"
include "../../src/ecs/plugins/scenetree.nim"

type Position = object
  x,y:float32

proc newPosition(x,y:float32):Position =
  Position(x:x,y:y)

suite "SceneTree extended torture":

  test "root setup":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(0)
    var tree: SceneTree
    world.setUp(tree, r)

    check tree.root != nil
    check tree.root.id.id == r.obj.id.toIdx

  test "parent pointer wiring":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(0)
    let a = world.createEntity(0)

    var tree: SceneTree
    world.setUp(tree, r)
    tree.addChild(a)

    let n = tree.dGetNode(a.obj.id.toIdx)
    check n.parent[] == tree.root.id

  test "dense + sparse hierarchy":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(0)
    let s = world.createSparseEntity(world.getComponentId(Position))

    var tree: SceneTree
    world.setUp(tree, r)
    tree.addChild(s)

    let root = tree.root
    check root.children.sLayer.get(s.id.int)

  test "recursive delete":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(0)
    let a = world.createEntity(0)
    let b = world.createEntity(0)

    var tree: SceneTree
    world.setUp(tree, r)
    tree.addChild(a)
    tree.addChild(a, b)

    world.deleteEntity(a)

    check tree.dGetNode(a.obj.id.toIdx) == nil
    check tree.dGetNode(b.obj.id.toIdx) == nil

  test "overrideNodes keeps hierarchy":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(0)
    let a = world.createEntity(0)

    var tree: SceneTree
    world.setUp(tree, r)
    tree.addChild(a)

    let old = a.obj.id.toIdx
    let b = world.createEntity(0)

    tree.overrideNodes(old.uint, b.obj.id.toIdx.uint)

    let n = tree.dGetNode(a.obj.id.toIdx)
    check n != nil
    check n.parent[] == tree.root.id

  test "freelist reuse":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(0)
    let a = world.createEntity(0)

    var tree: SceneTree
    world.setUp(tree, r)
    tree.addChild(a)

    world.deleteEntity(a)

    let b = world.createEntity(0)
    tree.addChild(b)

    let root = tree.root
    check root.children.dLayer.get(b.obj.id.toIdx.int)

  test "densify keeps parent":
    var world = newECSWorld()
    let pid = world.registerComponent(Position)

    let r = world.createEntity(0)
    var s = world.createSparseEntity(pid)

    var tree: SceneTree
    world.setUp(tree, r)
    tree.addChild(s)

    var d = world.makeDense(s)
    let n = tree.dGetNode(d.obj.id.toIdx)
    check n != nil
    check n.parent[] == tree.root.id

  test "sparsify keeps parent":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(0)
    var a = world.createEntity(0)

    var tree: SceneTree
    world.setUp(tree, r)
    tree.addChild(a)

    let s = world.makeSparse(a)
    let n = tree.sGetNode(s.id)

    check n != nil
    check n.parent[] == tree.root.id

  test "batch migration stable":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(0)
    let a = world.createEntity(0)
    let b = world.createEntity(0)

    var tree: SceneTree
    world.setUp(tree, r)
    tree.addChild(a)
    tree.addChild(b)
    var ents = @[a,b]
    var arch = world.archGraph.findArchetype(@[])
    
    world.migrateEntity(ents, arch)

    let na = tree.dGetNode(a.obj.id.toIdx)
    let nb = tree.dGetNode(b.obj.id.toIdx)

    check na.parent[] == tree.root.id
    check nb.parent[] == tree.root.id
