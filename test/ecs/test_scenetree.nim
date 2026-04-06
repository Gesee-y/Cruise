import std/[unittest]
import "../../src/ecs/table.nim"
include "../../src/ecs/plugins/scenetree.nim"

type Position = object
  x,y:float32

proc newPosition(x,y:float32):Position =
  Position(x:x,y:y)

suite "SceneTree extended torture":

  test "root setup":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(Position)
    var tree = initSceneTree(r)
    world.setUp(tree)

    check tree.getRoot != nil
    check tree.getRoot.id.id == r.wid.uint

  test "parent pointer wiring":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(Position)
    let a = world.createEntity(Position)

    var tree = initSceneTree(r)
    world.setUp(tree)
    tree.addChild(a)

    let n = tree.dGetNode(a.wid.uint)
    check tree.getParent(n).id == tree.getRoot.id

  test "dense + sparse hierarchy":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(Position)
    let s = world.createSparseEntity(Position)

    var tree = initSceneTree(r)
    world.setUp(tree)
    tree.addChild(s)

    let root = tree.getRoot
    echo root.children
    check root.children.sLayer.get(s.id.int)

  test "recursive delete":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(Position)
    let a = world.createEntity(Position)
    let b = world.createEntity(Position)

    var tree = initSceneTree(r)
    world.setUp(tree)
    tree.addChild(a)
    tree.addChild(a, b)

    world.deleteEntity(a)

    check tree.dGetNode(a.wid.uint) == nil
    check tree.dGetNode(b.wid.uint) == nil

  test "overrideNodes keeps hierarchy":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(Position)
    let a = world.createEntity(Position)

    var tree = initSceneTree(r)
    world.setUp(tree)
    tree.addChild(a)

    let old = a.wid
    let b = world.createEntity(Position)

    tree.overrideNodes(old.uint, b.wid.uint)

    let n = tree.dGetNode(a.wid.uint)
    check n != nil
    check tree.getParent(n).id == tree.getRoot.id

  test "freelist reuse":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(Position)
    let a = world.createEntity(Position)

    var tree = initSceneTree(r)
    world.setUp(tree)
    tree.addChild(a)

    world.deleteEntity(a)

    let b = world.createEntity(Position)
    tree.addChild(b)

    let root = tree.getRoot
    check root.children.dLayer.get(b.wid.int)

  test "densify keeps parent":
    var world = newECSWorld()
    let pid = world.registerComponent(Position)

    let r = world.createEntity(Position)
    var s = world.createSparseEntity(Position)

    var tree = initSceneTree(r)
    world.setUp(tree)
    tree.addChild(s)

    var d = world.makeDense(s)
    let n = tree.dGetNode(d.wid.uint)
    check n != nil
    check tree.getParent(n).id == tree.getRoot.id

  test "sparsify keeps parent":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(Position)
    var a = world.createEntity(Position)

    var tree = initSceneTree(r)
    world.setUp(tree)
    tree.addChild(a)

    let s = world.makeSparse(a)
    let n = tree.sGetNode(s.id)

    check n != nil
    check tree.getParent(n).id == tree.getRoot.id

  test "batch migration stable":
    var world = newECSWorld()
    discard world.registerComponent(Position)

    let r = world.createEntity(Position)
    let a = world.createEntity(Position)
    let b = world.createEntity(Position)

    var tree = initSceneTree(r)
    world.setUp(tree)
    tree.addChild(a)
    tree.addChild(b)
    var ents = @[a,b]
    var arch = world.archGraph.findArchetype([])
    
    world.migrateEntity(ents, arch)

    let na = tree.dGetNode(a.wid.uint)
    let nb = tree.dGetNode(b.wid.uint)

    check tree.getParent(na).id == tree.getRoot.id
    check tree.getParent(nb).id == tree.getRoot.id
