import std/tables
import std/locks
import std/typetraits
import std/strformat
import std/macros
import std/sequtils
import std/algorithm

# ############################################################################## #
#                           REENTRANT RW LOCK                                    #
# ############################################################################## #

type
  LockMode = enum
    ## Lock acquisition mode
    lmRead,
    lmWrite

  CondVar = Cond

  TRWLock* = object
    ## Reentrant reader-writer lock with writer priority.
    ##
    ## - Supports recursive acquisition by the owning writer thread
    ## - Writers are given priority over incoming readers
    ## - Readers are blocked while writers are waiting
    m: Lock            ## Mutex protecting internal state
    c: CondVar         ## Condition variable for signaling
    writer: int        ## Thread ID of current writer (0 if none)
    writerCount: int   ## Reentrancy counter for writer
    readers: int       ## Number of active readers
    waitingWriters: int ## Number of writers waiting (priority control)

proc init*(l: var TRWLock) =
  ## Initializes the RW lock.
  initLock(l.m)
  initCond(l.c)
  l.writer = 0
  l.writerCount = 0
  l.readers = 0
  l.waitingWriters = 0

proc deinit*(l: var TRWLock) =
  ## Destroys the RW lock.
  deinitLock(l.m)
  deinitCond(l.c)

proc acquireRead*(l: var TRWLock) =
  ## Acquires the lock in read mode.
  ## Blocks if a writer is active or waiting.
  ## The owning writer thread may reenter as a reader.
  let tid = getThreadId()
  acquire(l.m)
  
  block outer:
    # Writer reentrancy: writer can acquire read lock
    if l.writer == tid:
      l.writerCount.inc()
      break outer
    
    # Wait while a writer exists or writers are queued
    while l.writer != 0 or l.waitingWriters > 0:
      wait(l.c, l.m)
    
    l.readers.inc()

  release(l.m)

proc acquireWrite*(l: var TRWLock) =
  ## Acquires the lock in write mode.
  ## Writer has priority over readers.
  ## Supports recursive acquisition by the same thread.
  let tid = getThreadId()
  acquire(l.m)

  if l.writer == tid:
    # Recursive write lock
    l.writerCount.inc()
  else:
    l.waitingWriters.inc()
    
    # Wait until no readers or writer remain
    while l.readers > 0 or l.writer != 0:
      wait(l.c, l.m)

    l.waitingWriters.dec()
    l.writer = tid
    l.writerCount = 1

  release(l.m)

proc release*(l: var TRWLock, mode: LockMode) =
  ## Releases a read or write lock.
  ## Automatically handles writer reentrancy.
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
      # Writer releasing a read-level reentrant lock
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
  ## Executes a block under a read lock.
  acquireRead(l)
  try:
    body
  finally:
    release(l, lmRead)

template withWriteLock*(l: var TRWLock, body: untyped) =
  ## Executes a block under a write lock.
  acquireWrite(l)
  try:
    body
  finally:
    release(l, lmWrite)

# ############################################################################## #
#                           LOCK TREE IMPLEMENTATION                             #
# ############################################################################## #

type
  LockNode* = ref object
    ## Node in the hierarchical lock tree.
    lck: TRWLock
    children: Table[string, LockNode]
    isLeaf*: bool

  LockTree*[T] = object
    ## Typed hierarchical lock tree.
    ## The structure mirrors the fields of type T.
      root*: LockNode

  LockGuard* = object
    ## Guard object (currently unused, but useful for RAII extensions).
    node: LockNode
    mode: LockMode

proc makeNode*[T](val: T): LockNode =
  ## Creates a leaf lock node.
  result = new LockNode
  init(result.lck)
  result.isLeaf = true

proc makeNode*[T: tuple | object](obj: T): LockNode =
  ## Creates a lock node by recursively inspecting object or tuple fields.
  result = new LockNode
  init(result.lck)
  
  var hasFields = false
  for name, value in fieldPairs(obj):
    hasFields = true
    result.children[name] = makeNode(value)

  result.isLeaf = not hasFields

proc newLockTree*[T](ty: typedesc[T]): LockTree[T] =
  ## Creates a new lock tree from a type description.
  let dummy = default(T)
  let root = makeNode(dummy)
  LockTree[T](root: root)

proc getNode*(tree: LockTree, path: varargs[string]): LockNode =
  ## Retrieves a node by path.
  ## Raises if the path is invalid or goes beyond leaf nodes.
  result = tree.root
  for p in path:
    if result.isLeaf:
      raise newException(ValueError, "Path goes deeper than the tree structure.")
    if not result.children.hasKey(p):
      raise newException(KeyError, &"Key '{p}' not found")
    result = result.children[p]

proc lockImpl*(ln: var LockNode, mode: LockMode) =
  ## Recursively acquires locks on a node and all its descendants.
  if mode == lmWrite:
    acquireWrite(ln.lck)
  else:
    acquireRead(ln.lck)
  
  if not ln.isLeaf:
    for key in ln.children.keys():
      var child = ln.children[key]
      lockImpl(child, mode)

proc unlockImpl*(ln: var LockNode, mode: LockMode) =
  ## Recursively releases locks on a node and its descendants.
  if not ln.isLeaf:
    for key in ln.children.keys():
      var child = ln.children[key]
      unlockImpl(child, mode)
  
  release(ln.lck, mode)

proc readLock*(tree: var LockTree, path: varargs[string]) =
  ## Convenience APIs for tree-based locking
  lockImpl(getNode(tree, path), lmRead)

proc writeLock*(tree: var LockTree, path: varargs[string]) =
  lockImpl(getNode(tree, path), lmWrite)

proc unlock*(tree: var LockTree, path: varargs[string], mode: LockMode) =
  unlockImpl(getNode(tree, path), mode)

template withReadLock*(tree: var LockTree, path: varargs[string], body: untyped) =
  ## Executes a block under a read lock for a given tree path.
  let node = getNode(tree, path)
  lockImpl(node, lmRead)
  try:
    body
  finally:
    unlockImpl(node, lmRead)

template withWriteLock*(tree: var LockTree, path: varargs[string], body: untyped) =
  ## Executes a block under a write lock for a given tree path.
  let node = getNode(tree, path)
  lockImpl(node, lmWrite)
  try:
    body
  finally:
    unlockImpl(node, lmWrite)

proc lockBatchImpl*(nodes: varargs[LockNode], mode: LockMode) =
  ## Acquires multiple locks in a deterministic order to avoid deadlocks.
  var sortedNodes = @nodes
  sortedNodes.sort(proc (x, y: LockNode): int =
    cmp(cast[int](x), cast[int](y))
  )

  for node in sortedNodes:
    lockImpl(node, mode)

proc unlockBatchImpl*(nodes: varargs[LockNode], mode: LockMode) =
  ## Releases a batch of locks.
  for node in nodes:
    unlockImpl(node, mode)

template withReadLockBatch*(
  tree: var LockTree,
  paths: varargs[seq[string]],
  body: untyped
) =
  ## Executes a block under multiple read locks.
  var nodes: seq[LockNode]
  for p in paths:
    nodes.add(getNode(tree, p))
  lockBatchImpl(nodes, lmRead)
  try:
    body
  finally:
    unlockBatchImpl(nodes, lmRead)

template withWriteLockBatch*(
  tree: var LockTree,
  paths: varargs[seq[string]],
  body: untyped
) =
  ## Executes a block under multiple write locks.
  var nodes: seq[LockNode]
  for p in paths:
    nodes.add(getNode(tree, p))
  lockBatchImpl(nodes, lmWrite)
  try:
    body
  finally:
    unlockBatchImpl(nodes, lmWrite)

# ###############################################################################
#                                   DEBUG                                      #
# ###############################################################################

proc printTree*(ln: LockNode, indent: int = 0) =
  ## Prints the lock tree structure for debugging.
  let prefix = "  ".repeat(indent)
  echo prefix & "[Node/Leaf]"
  if not ln.isLeaf:
    for name, child in ln.children.pairs:
      echo prefix & "  " & name & " ->"
      printTree(child, indent + 2)
