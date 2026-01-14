#######################################################################################################################################
##################################################### HIERARCHICAL CONCEPT ############################################################
#######################################################################################################################################

import algorithm

type
  Hierarchical* = concept h
    proc getParent[T](h:T)
    proc getChildren[T](h:T)

#######################################################################################################################################
##################################################### HIERARCHICAL OPERATIONS #########################################################
#######################################################################################################################################

proc addChild*[H: Hierarchical](parent: H, child: H) =
  if child.parent != nil:
    child.parent.removeChild(child)
  child.parent = parent
  parent.children.add(child)

proc removeChild*[H: Hierarchical](parent: H, child: H) =
  for i in 0..<parent.children.len:
    if parent.children[i] == child:
      parent.children.delete(i)
      child.parent = nil
      break

proc getParent*[H: Hierarchical](node: H): H =
  node.parent

proc getChildren*[H: Hierarchical](node: H): seq[H] =
  node.children

proc getChildCount*[H: Hierarchical](node: H): int =
  node.children.len

proc getChild*[H: Hierarchical](node: H, index: int): H =
  if index >= 0 and index < node.children.len:
    return node.children[index]
  nil

proc dfs*[H: Hierarchical](node: H, visit: proc(n: H)) =
  visit(node)
  for child in node.children:
    child.dfs(visit)

proc dfsPreOrder*[H: Hierarchical](node: H, visit: proc(n: H)) =
  visit(node)
  for child in node.children:
    child.dfsPreOrder(visit)

proc dfsPostOrder*[H: Hierarchical](node: H, visit: proc(n: H)) =
  for child in node.children:
    child.dfsPostOrder(visit)
  visit(node)

proc bfs*[H: Hierarchical](node: H, visit: proc(n: H)) =
  var queue: seq[H] = @[node]
  var index = 0
  
  while index < queue.len:
    let current = queue[index]
    visit(current)
    
    for child in current.children:
      queue.add(child)
    
    inc index

iterator dfs*[H: Hierarchical](node: H): H =
  var stack: seq[H] = @[node]
  
  while stack.len > 0:
    let current = stack.pop()
    yield current
    
    for i in countdown(current.children.high, 0):
      stack.add(current.children[i])

iterator dfsPreOrder*[H: Hierarchical](node: H): H =
  var stack: seq[H] = @[node]
  
  while stack.len > 0:
    let current = stack.pop()
    yield current
    
    for i in countdown(current.children.high, 0):
      stack.add(current.children[i])

iterator dfsPostOrder*[H: Hierarchical](node: H): H =
  var stack: seq[H] = @[node]
  var visited: seq[H] = @[]
  
  while stack.len > 0:
    let current = stack[^1]
    
    # Vérifier si tous les enfants ont été visités
    var allChildrenVisited = true
    for child in current.children:
      if child notin visited:
        allChildrenVisited = false
        stack.add(child)
    
    if allChildrenVisited or current.children.len == 0:
      discard stack.pop()
      visited.add(current)
      yield current

iterator bfs*[H: Hierarchical](node: H): H =
  var queue: seq[H] = @[node]
  var index = 0
  
  while index < queue.len:
    let current = queue[index]
    yield current
    
    for child in current.children:
      queue.add(child)
    
    inc index

proc findNode*[H: Hierarchical](node: H, predicate: proc(n: H): bool): H =
  if predicate(node):
    return node
  
  for child in node.children:
    let found = child.findNode(predicate)
    if found != nil:
      return found
  
  nil

proc getAllNodes*[H: Hierarchical](node: H, predicate: proc(n: H): bool): seq[H] =
  var results: seq[H] = @[]
  
  node.dfs(proc(n: H) =
    if predicate(n):
      results.add(n)
  )
  
  results

# Profondeur du nœud dans l'arbre
proc getDepth*[H: Hierarchical](node: H): int =
  var depth = 0
  var current = node.parent
  
  while current != nil:
    inc depth
    current = current.parent
  
  depth

proc getRoot*[H: Hierarchical](node: H): H =
  var current = node
  while current.parent != nil:
    current = current.parent
  current

proc isAncestorOf*[H: Hierarchical](node: H, other: H): bool =
  var current = other.parent
  while current != nil:
    if current == node:
      return true
    current = current.parent
  false

proc getPath*[H: Hierarchical](node: H): seq[H] =
  var path: seq[H] = @[]
  var current = node
  
  while current != nil:
    path.insert(current, 0)
    current = current.parent
  
  path

# Détacher du parent
proc detach*[H: Hierarchical](node: H) =
  if node.parent != nil:
    node.parent.removeChild(node)

# Remplacer un enfant par un autre
proc replaceChild*[H: Hierarchical](parent: H, oldChild: H, newChild: H) =
  for i in 0..<parent.children.len:
    if parent.children[i] == oldChild:
      oldChild.parent = nil
      newChild.parent = parent
      parent.children[i] = newChild
      break

# Compter tous les descendants
proc countDescendants*[H: Hierarchical](node: H): int =
  var count = 0
  for child in node.children:
    count += 1 + child.countDescendants()
  count

# Obtenir tous les descendants
proc getAllDescendants*[H: Hierarchical](node: H): seq[H] =
  var descendants: seq[H] = @[]
  node.dfs(proc(n: H) =
    if n != node:
      descendants.add(n)
  )
  descendants

#######################################################################################################################################
##################################################### NODE WRAPPER (OPTIONAL) #########################################################
#######################################################################################################################################

type
  Node*[T] = ref object
    obj*: T
    priority*: int
    parent*: Node[T]
    children*: seq[Node[T]]

# Constructeur
proc newNode*[T](obj: T, priority: int = 0): Node[T] =
  Node[T](obj: obj, priority: priority, parent: nil, children: @[])

# Recherche par objet (spécifique à Node)
proc findChild*[T](node: Node[T], obj: T): Node[T] =
  for child in node.children:
    if child.obj == obj:
      return child
  nil

# Tri par priorité (spécifique à Node)
proc sortChildrenByPriority*[T](node: Node[T], ascending: bool = true) =
  if ascending:
    node.children.sort(proc(a, b: Node[T]): int = cmp(a.priority, b.priority))
  else:
    node.children.sort(proc(a, b: Node[T]): int = cmp(b.priority, a.priority))

echo tuple[]