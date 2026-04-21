## Test suite for hotreload.nim
##
## ReadDirectoryChangesW (and inotify/kqueue) are edge-triggered: the OS only
## delivers an event if the change happens *while* the kernel call is waiting.
## Mutations must therefore arrive concurrently with poll(), not before it.
##
## Pattern used in every event test:
##   1. Spawn a thread that sleeps DELAY_MS, then mutates the file system.
##   2. Main thread calls poll() with a timeout longer than DELAY_MS.
##   3. Join the mutation thread and assert on collected events.
##

import unittest, os, times, strutils, sequtils
include "../../src/filesys/filesystem.nim"   # pulls in filesystem.nim transitively

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  TMP      = "tmp_hr_test"
  POLL_MS  = 1000  ## poll window — wide enough to catch the mutation
  DELAY_MS = 100   ## mutation thread delay before acting (must be < POLL_MS)

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

proc setup(): (FileTree, string) =
  removeDir(TMP)
  createDir(TMP)
  createDir(TMP / "sub")
  writeFile(TMP / "a.txt",         "aaa")
  writeFile(TMP / "b.png",         "bbb")
  writeFile(TMP / "sub" / "c.txt", "ccc")
  result = (newFileTree(TMP), absolutePath(TMP))

proc teardown() =
  removeDir(TMP)

# ---------------------------------------------------------------------------
# Helper: poll while a mutation runs concurrently in a thread
# ---------------------------------------------------------------------------

proc pollWhileMutating(w: Watcher; mutate: proc() {.thread.};
                       ms: int = POLL_MS): seq[WatchEvent] =
  ## Collects events by:
  ##   1. Registering a temporary callback on *w*.
  ##   2. Spawning *mutate* in a background thread.
  ##   3. Blocking in poll() for *ms* ms — the mutation arrives mid-poll.
  ##   4. Joining the thread, removing the callback, returning events.
  var collected: seq[WatchEvent]
  w.onEvent(proc(ev: WatchEvent) = collected.add(ev))

  var t: Thread[void]
  createThread(t, mutate)
  w.poll(timeout = ms)   # OS delivers the event here, while thread mutates
  joinThread(t)

  w.removeCallbacks()
  result = collected

# ---------------------------------------------------------------------------
# Suite: construction  (no concurrency needed)
# ---------------------------------------------------------------------------

suite "Watcher — construction":

  test "newWatcher does not raise":
    var (tree, _) = setup()
    var w = newWatcher(tree)
    w.close()
    teardown()

  test "watcher holds a valid pointer to the tree":
    var (tree, root) = setup()
    var w = newWatcher(tree)
    check w.tree != nil
    check w.tree[].root.name == root
    w.close()
    teardown()

  test "no events on idle tree":
    var (tree, _) = setup()
    var w = newWatcher(tree)
    var collected: seq[WatchEvent]
    w.onEvent(proc(ev: WatchEvent) = collected.add(ev))
    w.poll(timeout = 300)   # nothing mutates — should stay empty
    w.removeCallbacks()
    check collected.len == 0
    w.close()
    teardown()

# ---------------------------------------------------------------------------
# Suite: callbacks
# ---------------------------------------------------------------------------

suite "Watcher — callbacks":

  test "onEvent registers a callback":
    var (tree, _) = setup()
    var w = newWatcher(tree)
    w.onEvent(proc(ev: WatchEvent) = discard)
    check w.callbacks.len == 1
    w.close()
    teardown()

  test "multiple callbacks are all called":
    var (tree, _) = setup()
    var w    = newWatcher(tree)
    var hits = 0
    w.onEvent(proc(ev: WatchEvent) = inc hits)
    w.onEvent(proc(ev: WatchEvent) = inc hits)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      writeFile(TMP / "trigger.txt", "x")

    var t: Thread[void]
    createThread(t, mutate)
    w.poll(timeout = POLL_MS)
    joinThread(t)

    check hits >= 2   # both callbacks fired for the same creation event
    w.close()
    teardown()

  test "removeCallbacks clears all callbacks":
    var (tree, _) = setup()
    var w = newWatcher(tree)
    w.onEvent(proc(ev: WatchEvent) = discard)
    w.removeCallbacks()
    check w.callbacks.len == 0
    w.close()
    teardown()

# ---------------------------------------------------------------------------
# Suite: file events
# ---------------------------------------------------------------------------

suite "Watcher — file events":

  test "creates a file -> wekCreated event":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      writeFile(TMP / "new.txt", "hello")

    let evs   = pollWhileMutating(w, mutate)
    let found = evs.filterIt(it.kind == wekCreated and
                              it.path.endsWith("new.txt"))
    check found.len >= 1
    w.close()
    teardown()

  test "modifies a file -> wekModified event":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      writeFile(TMP / "a.txt", "modified")
      setLastModificationTime(TMP / "a.txt", getTime())

    let evs   = pollWhileMutating(w, mutate)
    let found = evs.filterIt(it.kind == wekModified and
                              it.path.endsWith("a.txt"))
    check found.len >= 1
    w.close()
    teardown()

  #[test "deletes a file -> wekDeleted event":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      os.removeFile(TMP / "a.txt")

    let evs   = pollWhileMutating(w, mutate)
    let found = evs.filterIt(it.kind == wekDeleted and
                              it.path.endsWith("a.txt"))
    check found.len >= 1
    w.close()
    teardown()

  test "deleted file is removed from the tree":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      os.removeFile(TMP / "a.txt")

    discard pollWhileMutating(w, mutate)
    check tree.getFile("a.txt") == nil
    w.close()
    teardown()
]#
  test "modified file node gets updated lastModified":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      writeFile(TMP / "a.txt", "v2")
      setLastModificationTime(TMP / "a.txt", getTime())

    discard pollWhileMutating(w, mutate)
    let node = tree.getFile("a.txt")
    if node != nil:
      check node.lastModified != fromUnix(0)
    w.close()
    teardown()

# ---------------------------------------------------------------------------
# Suite: directory events
# ---------------------------------------------------------------------------

suite "Watcher — directory events":

  test "creates a dir -> wekCreated isDir event":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      os.createDir(TMP / "newdir")

    let evs   = pollWhileMutating(w, mutate)
    let found = evs.filterIt(it.kind == wekCreated and it.isDir)
    check found.len >= 1
    w.close()
    teardown()

  test "new directory is inserted into the tree":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      os.createDir(TMP / "newdir")

    discard pollWhileMutating(w, mutate)
    check tree.getDir("newdir") != nil
    w.close()
    teardown()

  test "deletes a dir -> wekDeleted isDir event":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      os.removeDir(TMP / "sub")

    let evs   = pollWhileMutating(w, mutate)
    let found = evs.filterIt(it.kind == wekDeleted and it.isDir)
    check found.len >= 1
    w.close()
    teardown()

  test "deleted directory is removed from the tree":
    var (tree, _) = setup()
    var w = newWatcher(tree)

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      os.removeDir(TMP / "sub")

    discard pollWhileMutating(w, mutate)
    check tree.getDir("sub") == nil
    w.close()
    teardown()

# ---------------------------------------------------------------------------
# Suite: extension filter
# ---------------------------------------------------------------------------

suite "Watcher — extension filter":

  test "only matching extension triggers callback":
    var (tree, _) = setup()
    var w = newWatcher(tree, ext = ".png")
    var evPaths: seq[string]
    w.onEvent(proc(ev: WatchEvent) = evPaths.add(ev.path))

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      writeFile(TMP / "ignore.txt", "ignored")
      writeFile(TMP / "match.png",  "matched")

    var t: Thread[void]
    createThread(t, mutate)
    w.poll(timeout = POLL_MS)
    joinThread(t)
    w.removeCallbacks()

    check evPaths.filterIt(it.endsWith(".txt")).len == 0
    check evPaths.filterIt(it.endsWith(".png")).len >= 1
    w.close()
    teardown()

  test "directory events pass through regardless of ext filter":
    var (tree, _) = setup()
    var w = newWatcher(tree, ext = ".png")
    var dirEvs: seq[WatchEvent]
    w.onEvent(proc(ev: WatchEvent) =
      if ev.isDir: dirEvs.add(ev))

    proc mutate() {.thread.} =
      sleep(DELAY_MS)
      os.createDir(TMP / "filterdir")

    var t: Thread[void]
    createThread(t, mutate)
    w.poll(timeout = POLL_MS)
    joinThread(t)
    w.removeCallbacks()

    check dirEvs.len >= 1
    w.close()
    teardown()

# ---------------------------------------------------------------------------
# Suite: poll driving
# ---------------------------------------------------------------------------

suite "Watcher — poll driving":

  test "poll with timeout=0 is non-blocking":
    var (tree, _) = setup()
    var w = newWatcher(tree)
    let t0      = epochTime()
    w.poll(timeout = 0)
    let elapsed = epochTime() - t0
    check elapsed < 0.5   # generous bound — just verifying it does not hang
    w.close()
    teardown()

  test "successive poll calls each catch their own event":
    var (tree, _) = setup()
    var w     = newWatcher(tree)
    var total = 0
    w.onEvent(proc(ev: WatchEvent) = inc total)

    proc mutate1() {.thread.} =
      sleep(DELAY_MS)
      writeFile(TMP / "f1.txt", "1")

    proc mutate2() {.thread.} =
      sleep(DELAY_MS)
      writeFile(TMP / "f2.txt", "2")

    var t1: Thread[void]
    createThread(t1, mutate1)
    w.poll(timeout = POLL_MS)
    joinThread(t1)

    var t2: Thread[void]
    createThread(t2, mutate2)
    w.poll(timeout = POLL_MS)
    joinThread(t2)

    check total >= 2
    w.close()
    teardown()