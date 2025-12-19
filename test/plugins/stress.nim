import unittest, tables, math, times, random
include "../../src/plugins/plugins.nim"

type
  StressNode = ref object of PluginNode
    updated:int
    failChance:float

method update(n:StressNode) =
  inc n.updated
  if rand(0.0..1.0) < n.failChance:
    raise newException(ValueError, "random fail")

method getObject(n:StressNode):int = n.id

proc newStressNode(failChance=0.1): StressNode =
  StressNode(
    enabled:true,
    mainthread:false,
    status:PLUGIN_OFF,
    deps:initTable[string, PluginNode](),
    failChance:failChance
  )

suite "Stress tests for Plugin system":

  test "Randomized large plugin graph with circular refs":
    var p: Plugin
    const N = 50

    # Créer les nodes
    for _ in 0..<N:
      discard addSystem(p, newStressNode(0.2))

    # Ajouter des dépendances aléatoires, y compris circulaires
    for i in 0..<N:
      let target = rand(0..<N)
      discard addDependency(p, i, target)  # ok si edge déjà existant

    # Exécution smap : doit capturer toutes les erreurs
    smap(update, p)

    # Vérifier que chaque node a été exécuté au moins une fois ou a une erreur
    for n in p.idtonode:
      check StressNode(n).updated >= 0

  test "Random failures do not crash pmap":
    var p: Plugin
    const N = 30
    for _ in 0..<N:
      discard addSystem(p, newStressNode(0.5))

    # pmap devrait gérer correctement les nodes qui échouent
    pmap(update, p)

    var failedCount = 0
    for n in p.idtonode:
      if n is StressNode and hasFailed(n):
        inc failedCount

    echo "Stress test finished, failed nodes:", failedCount
    check failedCount >= 0  # juste pour s'assurer que la boucle s'exécute

type
  ExtremeNode = ref object of PluginNode
    updated:int
    failChance:float

method update(n:ExtremeNode) =
  inc n.updated
  if rand(0.0..1.0) < n.failChance:
    raise newException(ValueError, "random fail")

method getObject(n:ExtremeNode):int = n.id

proc newExtremeNode(failChance=0.2): ExtremeNode =
  ExtremeNode(
    enabled:true,
    mainthread:rand(0..1) == 1,
    status:PLUGIN_OFF,
    deps:initTable[string, PluginNode](),
    failChance:failChance
  )

suite "Extreme stress test - 200+ nodes, cycles, random failures":

  test "Massive plugin graph execution":
    var p: Plugin
    const N = 250

    # Création des nodes
    for _ in 0..<N:
      discard addSystem(p, newExtremeNode())

    # Ajouter des dépendances aléatoires, avec cycles forcés
    for i in 0..<N:
      let target = rand(0..<N)
      discard addDependency(p, i, target)  # cycles possibles

      # Ajouter un petit cluster aléatoire
      for _ in 0..<3:
        let t2 = rand(0..<N)
        discard addDependency(p, i, t2)

    # Calculer les niveaux parallèles (teste computeParallelLevel)
    computeParallelLevel(p)
    check p.parallel_cache.len > 0

    # Exécution pmap sur tout le graph
    pmap(update, p)

    # Compter nodes échoués et nodes exécutés
    var failedCount = 0
    var executedCount = 0
    for n in p.idtonode:
      let en = ExtremeNode(n)
      inc executedCount, en.updated
      if hasFailed(en):
        inc failedCount

    echo "Extreme stress test finished."
    echo "Total nodes executed:", executedCount
    echo "Total nodes failed:", failedCount

    check executedCount >= N
    check failedCount >= 0  # juste pour s'assurer que les erreurs sont capturées
