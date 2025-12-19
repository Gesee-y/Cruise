import unittest, tables
include "../../src/plugins/plugins.nim"

# ------------------------------------------------------------
# Mocks pour les layouts
# ------------------------------------------------------------
type
  MockSceneTreeLayout = ref object of DataLayout
    addedNodes: seq[int]
    removedNodes: seq[int]

  MockDataChange = object of DataChange
    added:seq[int]
    deleted:seq[int]

  MockECSLayout = ref object of DataLayout
    changes: MockDataChange
    worldNodes: seq[int]

  MockPhysicLayout = ref object of DataLayout
    physicsNodes: seq[int]


makeAsKey(MockSceneTreeLayout)
makeAsKey(MockECSLayout)
makeAsKey(MockPhysicLayout)

method getChanges(l: MockECSLayout): MockDataChange =
  result = l.changes

method update(l: MockSceneTreeLayout) =
  let ecs = getDependency[MockECSLayout](l) # récupère l’ECSLayout
  let changes = MockDataChange(ecs.getChanges())

  for added in changes.added:
    l.addedNodes.add(added)
  for removed in changes.deleted:
    l.removedNodes.add(removed)

method update(l: MockPhysicLayout) =
  let ecs = getDependency[MockECSLayout](l)
  let tree = getDependency[MockSceneTreeLayout](l)
  let changes = MockDataChange(ecs.getChanges())

  for id in changes.added:
    if not tree.addedNodes.contains(id):
      continue
    l.physicsNodes.add(id)

proc newDataChange(addedNodes, deletedNodes: seq[int]): MockDataChange =
  var c: MockDataChange
  # On simule les champs added/deleted
  c.added = addedNodes
  c.deleted = deletedNodes
  return c

proc newMockSceneTreeLayout():MockSceneTreeLayout =
  var v:MockSceneTreeLayout
  new v
  v.addedNodes = newSeq[int](0)
  v.removedNodes = newSeq[int](0)

  return v

proc newMockECSLayout():MockECSLayout =
  var v:MockECSLayout
  new v

  v.worldNodes = newSeq[int](0)
  v.changes = newDataChange(newSeq[int](0), newSeq[int](0))

  return v

proc newMockPhysicLayout():MockPhysicLayout =
  var v:MockPhysicLayout
  new v

  v.physicsNodes = newSeq[int](0)

  return v

# ------------------------------------------------------------
# Tests
# ------------------------------------------------------------
suite "DataLayout / World state coherence":

  test "Dependencies between layouts are registered":
    var plugin: Plugin
    var ecs = newMockECSLayout()
    var tree = newMockSceneTreeLayout()
    var phys = newMockPhysicLayout()

    let idECS = addSystem(plugin, ecs)
    let idTree = addSystem(plugin, tree)
    let idPhys = addSystem(plugin, phys)

    discard addDependency(plugin, idECS, idTree)
    discard addDependency(plugin, idTree, idPhys)
    discard addDependency(plugin, idECS, idPhys)

    check tree.deps.hasKey(ecs.asKey)
    check phys.deps.hasKey(tree.asKey)
    check phys.deps.hasKey(ecs.asKey)

  test "SceneTreeLayout update propagates ECS changes":
    var plugin: Plugin
    var ecs = newMockECSLayout()
    var tree = newMockSceneTreeLayout()

    ecs.changes = newDataChange(@[1,2,3], @[4])
    let idECS = addSystem(plugin, ecs)
    let idTree = addSystem(plugin, tree)
    discard addDependency(plugin, idECS, idTree)

    update(tree)

    check tree.addedNodes == @[1,2,3]
    check tree.removedNodes == @[4]

  test "PhysicLayout update synchronizes with ECS and SceneTree":
    var plugin: Plugin
    var ecs = MockECSLayout()
    var tree = MockSceneTreeLayout()
    var phys = MockPhysicLayout()

    ecs.changes = newDataChange(@[10,20], @[])
    let idECS = addSystem(plugin, ecs)
    let idTree = addSystem(plugin, tree)
    let idPhys = addSystem(plugin, phys)

    discard addDependency(plugin, idECS, idTree)
    discard addDependency(plugin, idTree, idPhys)
    discard addDependency(plugin, idECS, idPhys)

    # Propagation
    update(tree)
    update(phys)

    check phys.physicsNodes.contains(10)
    check phys.physicsNodes.contains(20)
    check phys.physicsNodes.len == 2

  test "Deleted nodes in ECS are removed from SceneTree":
    var plugin: Plugin
    var ecs = MockECSLayout()
    var tree = MockSceneTreeLayout()

    ecs.changes = newDataChange(@[], @[7])
    let idECS = addSystem(plugin, ecs)
    let idTree = addSystem(plugin, tree)
    discard addDependency(plugin, idECS, idTree)

    update(tree)

    check tree.removedNodes == @[7]
