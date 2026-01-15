import std/tables
import std/locks
import std/typetraits
import std/strformat
import std/macros
import std/sequtils
import std/algorithm

##################################################
#             CORE: TRW LOCK (Thread-Reentrant)  #
##################################################
# Implémentation d'un Read-Write Lock Réentrant.

type
  LockMode = enum lmRead, lmWrite
  CondVar = Cond

  TRWLock* = object
    m: Lock         # Mutex pour protéger l'état interne
    c: CondVar      # Condition variable pour le signalement
    writer: int     # TID du thread écrivain (0 si aucun)
    writerCount: int # Compteur de réentrance pour l'écrivain
    readers: int    # Nombre total de lecteurs actifs
    waitingWriters: int # Nombre d'écrivains en attente (pour la priorité)

proc init*(l: var TRWLock) =
  initLock(l.m)
  initCond(l.c)
  l.writer = 0
  l.writerCount = 0
  l.readers = 0
  l.waitingWriters = 0

proc deinit*(l: var TRWLock) =
  deinitLock(l.m)
  deinitCond(l.c)

proc acquireRead*(l: var TRWLock) =
  let tid = getThreadId()
  acquire(l.m)
  
  block outer:
    if l.writer == tid:
      l.writerCount.inc()
      break outer
    
    # S'il y a un écrivain (autre thread) OU des écrivains en attente, on attend
    while l.writer != 0 or l.waitingWriters > 0:
      wait(l.c, l.m)
    
    l.readers.inc()

  release(l.m)

proc acquireWrite*(l: var TRWLock) =
  let tid = getThreadId()
  acquire(l.m)

  if l.writer == tid:
    l.writerCount.inc()
  else:
    l.waitingWriters.inc()
    
    while l.readers > 0 or l.writer != 0:
      wait(l.c, l.m)
    l.waitingWriters.dec()
    l.writer = tid
    l.writerCount = 1

  release(l.m)

proc release*(l: var TRWLock, mode: LockMode) =
  let tid = getThreadId()
  acquire(l.m)

  case mode
  of lmWrite:
    
    if l.writer == tid:
      dec l.writerCount
      if l.writerCount == 0:
        l.writer = 0
        broadcast(l.c)
  of lmRead:
    if l.writer == tid:
      dec l.writerCount
      if l.writerCount == 0:
        l.writer = 0
        broadcast(l.c)
    else:
      doAssert(l.readers > 0, "Release read lock without readers")
      dec l.readers
      if l.readers == 0:
        signal(l.c)

  release(l.m)

template withReadLock*(l: var TRWLock, body: untyped) =
  acquireRead(l)
  try:
    body
  finally:
    release(l, lmRead)

template withWriteLock*(l: var TRWLock, body: untyped) =
  acquireWrite(l)
  try:
    body
  finally:
    release(l, lmWrite)

##################################################
#              LOCK TREE IMPLEMENTATION           #
##################################################

type
  LockNode* = ref object
    lck: TRWLock
    children: Table[string, LockNode]
    isLeaf*: bool 

  LockTree*[T] = object
    root*: LockNode

  LockGuard* = object
    node: LockNode
    mode: LockMode

proc makeNode*[T](val: T): LockNode =
  result = new LockNode
  init(result.lck)
  result.isLeaf = true

proc makeNode*[T: tuple | object](obj: T): LockNode =
  result = new LockNode
  init(result.lck)
  
  var hasFields = false
  for name, value in fieldPairs(obj):
    hasFields = true
    result.children[name] = makeNode(value)

  result.isLeaf = not hasFields

proc newLockTree*[T](ty: typedesc[T]): LockTree[T] =
  let dummy = default(T) 
  var root = makeNode(dummy)
  return LockTree[T](root: root)

proc getNode*(tree: LockTree, path: varargs[string]): LockNode =
  result = tree.root
  for p in path:
    if result.isLeaf:
      raise newException(ValueError, "Path goes deeper than the tree structure.")
    if not result.children.hasKey(p):
      raise newException(KeyError, &"Key '{p}' not found")
    result = result.children[p]

proc lockImpl*(ln: var LockNode, mode: LockMode) =
  if mode == lmWrite:
    acquireWrite(ln.lck)
  else:
    acquireRead(ln.lck)
  
  if not ln.isLeaf:
    for key in ln.children.keys():
      var child = ln.children[key]
      lockImpl(child, mode)

proc unlockImpl*(ln: var LockNode, mode: LockMode) =
  if not ln.isLeaf:
    for key in ln.children.keys():
      var child = ln.children[key]
      unlockImpl(child, mode)
  
  release(ln.lck, mode)

proc readLock*(tree: var LockTree, path: varargs[string]) = lockImpl(getNode(tree, path), lmRead)
proc writeLock*(tree: var LockTree, path: varargs[string]) = lockImpl(getNode(tree, path), lmWrite)
proc unlock*(tree: var LockTree, path: varargs[string], mode: LockMode) = unlockImpl(getNode(tree, path), mode)

template withReadLock*(tree: var LockTree, path: varargs[string], body: untyped) =
  var node = getNode(tree, path)
  lockImpl(node, lmRead)
  try:
    body
  finally:
    unlockImpl(node, lmRead)

template withWriteLock*(tree: var LockTree, path: varargs[string], body: untyped) =
  let node = getNode(tree, path)
  lockImpl(node, lmWrite)
  try:
    body
  finally:
    unlockImpl(node, lmWrite)

proc lockBatchImpl*(nodes: varargs[LockNode], mode: LockMode) =
  var sortedNodes = @nodes
  sortedNodes.sort(proc (x, y: LockNode): int = cmp(cast[int](x), cast[int](y)))

  for i in 0..<sortedNodes.len:
    var node = sortedNodes[i]
    lockImpl(node, mode)

proc unlockBatchImpl*(nodes: varargs[LockNode], mode: LockMode) =
  for i in 0..<nodes.len:
    var node = nodes[i]
    unlockImpl(node, mode)

template withReadLockBatch*(tree: var LockTree, paths: varargs[seq[string]], body: untyped) =
  var nodes: seq[LockNode]
  for p in paths:
    nodes.add(getNode(tree, p))
  lockBatchImpl(nodes, lmRead)
  try:
    body
  finally:
    unlockBatchImpl(nodes, lmRead)

template withWriteLockBatch*(tree: var LockTree, paths: varargs[seq[string]], body: untyped) =
  var nodes: seq[LockNode]
  for p in paths:
    nodes.add(getNode(tree, p))
  lockBatchImpl(nodes, lmWrite)
  try:
    body
  finally:
    unlockBatchImpl(nodes, lmWrite)

# --- Debug ---
proc printTree*(ln: LockNode, indent: int = 0) =
  let prefix = "  ".repeat(indent)
  echo prefix & "[Node/Leaf] (Active)"
  if not ln.isLeaf:
    for name, child in ln.children.pairs:
      echo prefix & "  " & name & " ->"
      printTree(child, indent + 2)
