import std/tables
import std/locks
import std/typetraits
import std/strformat
import std/macros
import std/sequtils
import std/algorithm

################################################################################
#                           REENTRANT RW LOCK                                  #
################################################################################

type
  ## Lock acquisition mode
  LockMode = enum
    lmRead,
    lmWrite

  CondVar = Cond

  ## Reentrant reader-writer lock with writer priority.
  ##
  ## - Supports recursive acquisition by the owning writer thread
  ## - Writers are given priority over incoming readers
  ## - Readers are blocked while writers are waiting
  TRWLock* = object
    m: Lock            ## Mutex protecting internal state
    c: CondVar         ## Condition variable for signaling
    writer: int        ## Thread ID of current writer (0 if none)
    writerCount: int   ## Reentrancy counter for writer
    readers: int       ## Number of active readers
    waitingWriters: int ## Number of writers waiting (priority control)

## Initializes the RW lock.
proc init*(l: var TRWLock) =
  initLock(l.m)
  initCond(l.c)
  l.writer = 0
  l.writerCount = 0
  l.readers = 0
  l.waitingWriters = 0

## Destroys the RW lock.
proc deinit*(l: var TRWLock) =
  deinitLock(l.m)
  deinitCond(l.c)

## Acquires the lock in read mode.
## Blocks if a writer is active or waiting.
## The owning writer thread may reenter as a reader.
proc acquireRead*(l: var TRWLock) =
  let tid = getThreadId()
  acquire(l.m)
  
  block outer:
    ## Writer reentrancy: writer can acquire read lock
    if l.writer == tid:
      l.writerCount.inc()
      break outer
    
    ## Wait while a writer exists or writers are queued
    while l.writer != 0 or l.waitingWriters > 0:
      wait(l.c, l.m)
    
    l.readers.inc()

  release(l.m)

## Acquires the lock in write mode.
## Writer has priority over readers.
## Supports recursive acquisition by the same thread.
proc acquireWrite*(l: var TRWLock) =
  let tid = getThreadId()
  acquire(l.m)

  if l.writer == tid:
    ## Recursive write lock
    l.writerCount.inc()
  else:
    l.waitingWriters.inc()
    
    ## Wait until no readers or writer remain
    while l.readers > 0 or l.writer != 0:
      wait(l.c, l.m)

    l.waitingWriters.dec()
    l.writer = tid
    l.writerCount = 1

  release(l.m)

## Releases a read or write lock.
## Automatically handles writer reentrancy.
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
      ## Writer releasing a read-level reentrant lock
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

## Executes a block under a read lock.
template withReadLock*(l: var TRWLock, body: untyped) =
  acquireRead(l)
  try:
    body
  finally:
    release(l, lmRead)

## Executes a block under a write lock.
template withWriteLock*(l: var TRWLock, body: untyped) =
  acquireWrite(l)
  try:
    body
  finally:
    release(l, lmWrite)

################################################################################
#                           LOCK TREE IMPLEMENTATION                            #
################################################################################

type
  ## Node in the hierarchical lock tree.
  LockNode* = ref object
    lck: TRWLock
    children: Table[string, LockNode]
    isLeaf*: bool

  ## Typed hierarchical lock tree.
  ## The structure mirrors the fields of type T.
  LockTree*[T] = object
    root*: LockNode

  ## Guard object (currently unused, but useful for RAII extensions).
  LockGuard* = object
    node: LockNode
    mode: LockMode

## Creates a leaf lock node.
proc makeNode*[T](val: T): LockNode =
  result = new LockNode
  init(result.lck)
  result.isLeaf = true

## Creates a lock node by recursively inspecting object or tuple fields.
proc makeNode*[T: tuple | object](obj: T): LockNode =
  result = new LockNode
  init(result.lck)
  
  var hasFields = false
  for name, value in fieldPairs(obj):
    hasFields = true
    result.children[name] = makeNode(value)

  result.isLeaf = not hasFields

## Creates a new lock tree from a type description.
proc newLockTree*[T](ty: typedesc[T]): LockTree[T] =
  let dummy = default(T)
  let root = makeNode(dummy)
  LockTree[T](root: root)

## Retrieves a node by path.
## Raises if the path is invalid or goes beyond leaf nodes.
proc getNode*(tree: LockTree, path: varargs[string]): LockNode =
  result = tree.root
  for p in path:
    if result.isLeaf:
      raise newException(ValueError, "Path goes deeper than the tree structure.")
    if not result.children.hasKey(p):
      raise newException(KeyError, &"Key '{p}' not found")
    result = result.children[p]

## Recursively acquires locks on a node and all its descendants.
proc lockImpl*(ln: var LockNode, mode: LockMode) =
  if mode == lmWrite:
    acquireWrite(ln.lck)
  else:
    acquireRead(ln.lck)
  
  if not ln.isLeaf:
    for key in ln.children.keys():
      var child = ln.children[key]
      lockImpl(child, mode)

## Recursively releases locks on a node and its descendants.
proc unlockImpl*(ln: var LockNode, mode: LockMode) =
  if not ln.isLeaf:
    for key in ln.children.keys():
      var child = ln.children[key]
      unlockImpl(child, mode)
  
  release(ln.lck, mode)

## Convenience APIs for tree-based locking
proc readLock*(tree: var LockTree, path: varargs[string]) =
  lockImpl(getNode(tree, path), lmRead)

proc writeLock*(tree: var LockTree, path: varargs[string]) =
  lockImpl(getNode(tree, path), lmWrite)

proc unlock*(tree: var LockTree, path: varargs[string], mode: LockMode) =
  unlockImpl(getNode(tree, path), mode)

## Executes a block under a read lock for a given tree path.
template withReadLock*(tree: var LockTree, path: varargs[string], body: untyped) =
  let node = getNode(tree, path)
  lockImpl(node, lmRead)
  try:
    body
  finally:
    unlockImpl(node, lmRead)

## Executes a block under a write lock for a given tree path.
template withWriteLock*(tree: var LockTree, path: varargs[string], body: untyped) =
  let node = getNode(tree, path)
  lockImpl(node, lmWrite)
  try:
    body
  finally:
    unlockImpl(node, lmWrite)

## Acquires multiple locks in a deterministic order to avoid deadlocks.
proc lockBatchImpl*(nodes: varargs[LockNode], mode: LockMode) =
  var sortedNodes = @nodes
  sortedNodes.sort(proc (x, y: LockNode): int =
    cmp(cast[int](x), cast[int](y))
  )

  for node in sortedNodes:
    lockImpl(node, mode)

## Releases a batch of locks.
proc unlockBatchImpl*(nodes: varargs[LockNode], mode: LockMode) =
  for node in nodes:
    unlockImpl(node, mode)

## Executes a block under multiple read locks.
template withReadLockBatch*(
  tree: var LockTree,
  paths: varargs[seq[string]],
  body: untyped
) =
  var nodes: seq[LockNode]
  for p in paths:
    nodes.add(getNode(tree, p))
  lockBatchImpl(nodes, lmRead)
  try:
    body
  finally:
    unlockBatchImpl(nodes, lmRead)

## Executes a block under multiple write locks.
template withWriteLockBatch*(
  tree: var LockTree,
  paths: varargs[seq[string]],
  body: untyped
) =
  var nodes: seq[LockNode]
  for p in paths:
    nodes.add(getNode(tree, p))
  lockBatchImpl(nodes, lmWrite)
  try:
    body
  finally:
    unlockBatchImpl(nodes, lmWrite)

################################################################################
#                                   DEBUG                                      #
################################################################################

## Prints the lock tree structure for debugging.
proc printTree*(ln: LockNode, indent: int = 0) =
  let prefix = "  ".repeat(indent)
  echo prefix & "[Node/Leaf]"
  if not ln.isLeaf:
    for name, child in ln.children.pairs:
      echo prefix & "  " & name & " ->"
      printTree(child, indent + 2)
