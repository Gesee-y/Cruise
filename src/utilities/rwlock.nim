import std/tables
import std/locks

# ############################################################################## #
#                           REENTRANT RW LOCK                                    #
# ############################################################################## #

type
  LockMode = enum
    ## Lock acquisition mode
    lmRead,
    lmWrite

  CondVar = Cond

  RWLock* = object
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

proc init*(l: var RWLock) =
  ## Initializes the RW lock.
  initLock(l.m)
  initCond(l.c)
  l.writer = 0
  l.writerCount = 0
  l.readers = 0
  l.waitingWriters = 0

proc deinit*(l: var RWLock) =
  ## Destroys the RW lock.
  deinitLock(l.m)
  deinitCond(l.c)

proc acquireRead*(l: var RWLock) =
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

proc acquireWrite*(l: var RWLock) =
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

proc release*(l: var RWLock, mode: LockMode) =
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

template withReadLock*(l: var RWLock, body: untyped) =
  ## Executes a block under a read lock.
  acquireRead(l)
  try:
    body
  finally:
    release(l, lmRead)

template withWriteLock*(l: var RWLock, body: untyped) =
  ## Executes a block under a write lock.
  acquireWrite(l)
  try:
    body
  finally:
    release(l, lmWrite)
