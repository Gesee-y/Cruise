# ########################################################################################################## #
# ############################################## TRIE IMPLEMENTATION ####################################### #
# ########################################################################################################## #

type
  TNode = object
    data: Variable
    parent: int
    children: Table[string, int]

  Trie = object
    nodes: seq[TNode]
    roots: TNode

proc newTrie(): Trie =
  result = Trie()
  result.nodes.add(TNode(parent: -1))

proc addNode(t: var Trie, data: string): int =
  var root = 0
  if data in t.nodes[root].children:
    root = t.nodes[root].children.getOrDefault(data, 0)
  else:
    let n = t.nodes.len
    t.nodes.add(TNode(parent: root))
    t.nodes[root].children[data] = n
    root = n

  return root

proc addNode(t: var Trie, data: seq[string]): int =
  result = 0
  if data.len <= 0: return -1

  for d in data:
    if d in t.nodes[result].children:
      result = t.nodes[result].children.getOrDefault(d)
    else:
      let n = t.nodes.len
      t.nodes.add(TNode(parent: result))
      t.nodes[result].children[d] = n
      result = n


proc fetchNode(t: Trie, data: seq[string]): int =
  if data.len <= 0: return -1

  result = 0
  for d in data:
    result = t.nodes[result].children.getOrDefault(d, -1)
    if result == -1: break

proc fetchNode(t: Trie, data: string): int =
  result = t.nodes[0].children.getOrDefault(data, -1)

proc getAllSuffix(t: Trie, node: TNode, stack: var seq[int]) =
  for v in node.children.values:
    stack.add(v)
    t.getAllSuffix(t.nodes[v], stack)

iterator iterateSuffix(t: Trie, node: TNode): int {.sideEffect.} =
  var stack: seq[int] = @[]
  t.getAllSuffix(node, stack)
  for v in stack:
    yield v

iterator iterateSuffix(t: Trie, data: seq[string]): int {.sideEffect.} =
  let node = t.fetchNode(data)
  if node != -1:
    var stack: seq[int] = @[]
    t.getAllSuffix(t.nodes[node], stack)
    for v in stack:
      yield v
