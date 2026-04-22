## hotreload.nim
##
## Event-driven file system watcher built on top of FileTree.
##
## Each OS backend is isolated in its own `when` branch:
##   - Linux   : inotify via a raw fd registered into ioselectors
##   - macOS   : kqueue/vnode via ioselectors registerVnode
##   - Windows : FindFirstChangeNotificationW + WaitForSingleObject +
##               tree diff (see note below)
##
## Windows note:
##   ReadDirectoryChangesW in synchronous mode blocks until the *next* change
##   after being called, ignoring what WaitForSingleObject already signalled.
##   We therefore use FindFirstChangeNotificationW purely as a waitable handle,
##   then diff the FileTree against the real disk state to produce typed events.
##   FILE_NOTIFY_CHANGE_FILE_NAME covers create + delete for files.
##   FILE_NOTIFY_CHANGE_DIR_NAME  covers create + delete for directories.
##   FILE_NOTIFY_CHANGE_LAST_WRITE covers modifications.
##
## The watcher is intentionally *not* async by itself.
## The caller decides how and when to drive poll().
##
## Basic usage:
##
##   var tree = newFileTree("assets")
##   var w    = newWatcher(tree)
##   w.onEvent(proc(ev: WatchEvent) = echo ev.path, " -> ", ev.kind)
##   while true:
##     w.poll(timeout = 100)

# ---------------------------------------------------------------------------
# OS-specific implementation types
# ---------------------------------------------------------------------------

when defined(windows):
  import winlean

  type
    WatcherImpl = object
      notifyHandle: Handle
      rootPath:     string
      knownFiles:   seq[string]  ## absolute paths snapshot from last poll
      knownDirs:    seq[string]

elif defined(macosx) or defined(bsd):
  import ioselectors

  type
    WatcherImpl = object
      selector: Selector[string]
      fdMap:    Table[int, string]
      rootPath: string

else: # Linux
  import selectors, tables, posix

  const
    IN_CREATE   = 0x00000100'u32
    IN_DELETE   = 0x00000200'u32
    IN_MODIFY   = 0x00000020'u32
    IN_MOVED_TO = 0x00000080'u32
    IN_ONLYDIR  = 0x01000000'u32
    IN_ISDIR    = 0x40000000'u32

  type
    InotifyEvent {.packed.} = object
      wd:     cint
      mask:   uint32
      cookie: uint32
      len:    uint32

    WatcherImpl = object
      inoFd:    cint
      selector: Selector[string]
      wdMap:    Table[cint, string]
      rootPath: string

  const IN_NONBLOCK = 0x00004000'u32

  proc inotify_init1(flags: cint): cint {.importc, header: "<sys/inotify.h>".}

  proc inotify_init(): cint {.importc, header: "<sys/inotify.h>".}
  proc inotify_add_watch(fd: cint; path: cstring; mask: uint32): cint {.
      importc, header: "<sys/inotify.h>".}
  proc inotify_rm_watch(fd: cint; wd: cint): cint {.
      importc, header: "<sys/inotify.h>".}

# ---------------------------------------------------------------------------
# Public types
# ---------------------------------------------------------------------------

type
  WatchEventKind* = enum
    wekCreated  ## A new file or directory appeared
    wekModified ## An existing file was written to
    wekDeleted  ## A file or directory was removed
    wekRenamed  ## A file or directory was renamed (path = new name)

  WatchEvent* = object
    kind*:  WatchEventKind
    path*:  string  ## Absolute path concerned by the event
    isDir*: bool    ## True when the path refers to a directory

  WatchCallback* = proc(ev: WatchEvent) {.closure.}

  Watcher* = ref object
    tree*:      ptr FileTree
    callbacks*: seq[WatchCallback]
    ext*:       string
    implData:   WatcherImpl

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc fire(w: Watcher; ev: WatchEvent) =
  if w.ext.len > 0 and not ev.isDir and not ev.path.endsWith(w.ext):
    return
  for cb in w.callbacks:
    cb(ev)

# ---------------------------------------------------------------------------
# Windows backend
# ---------------------------------------------------------------------------

when defined(windows):

  const
    FILE_NOTIFY_CHANGE_FILE_NAME  = 0x00000001'i32
    FILE_NOTIFY_CHANGE_DIR_NAME   = 0x00000002'i32
    FILE_NOTIFY_CHANGE_LAST_WRITE = 0x00000010'i32
    WAIT_TIMEOUT_VAL              = 0x00000102'u32

  proc findFirstChangeNotificationW(
    lpPathName:     WideCString,
    bWatchSubtree:  WINBOOL,
    dwNotifyFilter: DWORD
  ): Handle {.importc: "FindFirstChangeNotificationW", dynlib: "kernel32", stdcall.}

  proc findNextChangeNotification(hChangeHandle: Handle): WINBOOL {.
      importc: "FindNextChangeNotification", dynlib: "kernel32", stdcall.}

  proc findCloseChangeNotification(hChangeHandle: Handle): WINBOOL {.
      importc: "FindCloseChangeNotification", dynlib: "kernel32", stdcall.}

  proc waitForSingleObject(hHandle: Handle; dwMilliseconds: DWORD): DWORD {.
      importc: "WaitForSingleObject", dynlib: "kernel32", stdcall.}

  proc newWatcherImpl(rootPath: string; tree: var FileTree): WatcherImpl =
    result.rootPath   = rootPath
    result.knownFiles = tree.allFiles.mapIt(it.name)
    result.knownDirs  = tree.allDirs.mapIt(it.name)
    let filter = DWORD(FILE_NOTIFY_CHANGE_FILE_NAME or
                       FILE_NOTIFY_CHANGE_DIR_NAME  or
                       FILE_NOTIFY_CHANGE_LAST_WRITE)
    result.notifyHandle = findFirstChangeNotificationW(
      newWideCString(rootPath), true.WINBOOL, filter)
    if result.notifyHandle == Handle(-1):
      raiseOSError(osLastError())

  proc pollImpl(w: Watcher; timeout: int): seq[WatchEvent] =
    ## Waits up to *timeout* ms for any change, then diffs tree vs disk.
    
    let inf = 0xFFFFFFFF'u32
    let ms     = if timeout < 0: DWORD(inf) else: DWORD(timeout)
    #let status = waitForSingleObject(w.implData.notifyHandle, ms)
    # Re-arm before doing any work so we don't miss the next event.
    while waitForSingleObject(w.implData.notifyHandle, ms) != WAIT_TIMEOUT_VAL.DWORD:
      discard findNextChangeNotification(w.implData.notifyHandle)

    # Rebuild the tree from disk — this is the source of truth.
    let diff = w.tree[].diffTree()
    w.tree[].updateTree(diff)

    # Created files / deleted files.
    for p in diff.createdFiles:
        result.add(WatchEvent(kind: wekCreated, path: p, isDir: false))
    for p in diff.deletedFiles:
      result.add(WatchEvent(kind: wekDeleted, path: p, isDir: false))

    # Created dirs / deleted dirs.
    for p in diff.createdDirs:
      result.add(WatchEvent(kind: wekCreated, path: p, isDir: true))
    for p in diff.deletedDirs:
      result.add(WatchEvent(kind: wekDeleted, path: p, isDir: true))

    # Modified files: present in both snapshots but mtime changed on disk.
    for p in diff.modifiedFiles:
      result.add(WatchEvent(kind: wekModified, path: p, isDir: false))

  proc closeImpl(w: Watcher) =
    discard findCloseChangeNotification(w.implData.notifyHandle)

# ---------------------------------------------------------------------------
# macOS / BSD backend (kqueue vnode)
# ---------------------------------------------------------------------------

elif defined(macosx) or defined(bsd):

  proc watchNodeKqueue(impl: var WatcherImpl; path: string) =
    let fd = open(path.cstring, 0)
    if fd < 0: return
    impl.selector.registerVnode(fd,
      {Event.VnodeWrite, Event.VnodeDelete,
       Event.VnodeExtend, Event.VnodeRename, Event.VnodeAttrib},
      path)
    impl.fdMap[fd.int] = path

  proc newWatcherImpl(rootPath: string; tree: var FileTree): WatcherImpl =
    result.rootPath = rootPath
    result.selector = newSelector[string]()
    watchNodeKqueue(result, rootPath)
    for d in tree.allDirs:  watchNodeKqueue(result, d.name)
    for f in tree.allFiles: watchNodeKqueue(result, f.name)

  proc pollImpl(w: Watcher; timeout: int): seq[WatchEvent] =
    let ready = w.implData.selector.select(timeout)
    if ready.len == 0: return result
    # Rebuild the tree from disk — this is the source of truth.
    let diff = w.tree[].diffTree()
    w.tree[].updateTree(diff)

    # Created files / deleted files.
    for p in diff.createdFiles:
        result.add(WatchEvent(kind: wekCreated, path: p, isDir: false))
    for p in diff.deletedFiles:
      result.add(WatchEvent(kind: wekDeleted, path: p, isDir: false))

    # Created dirs / deleted dirs.
    for p in diff.createdDirs:
      result.add(WatchEvent(kind: wekCreated, path: p, isDir: true))
    for p in diff.deletedDirs:
      result.add(WatchEvent(kind: wekDeleted, path: p, isDir: true))

    # Modified files: present in both snapshots but mtime changed on disk.
    for p in diff.modifiedFiles:
      result.add(WatchEvent(kind: wekModified, path: p, isDir: false))

  proc closeImpl(w: Watcher) =
    w.implData.selector.close()

# ---------------------------------------------------------------------------
# Linux backend (inotify)
# ---------------------------------------------------------------------------

else:

  proc watchDirInotify(impl: var WatcherImpl; path: string) =
    let mask = IN_CREATE or IN_DELETE or IN_MODIFY or IN_MOVED_TO
    let wd   = inotify_add_watch(impl.inoFd, path.cstring, mask)
    if wd >= 0:
      impl.wdMap[wd] = path

  proc newWatcherImpl(rootPath: string; tree: var FileTree): WatcherImpl =
    result.rootPath = rootPath
    result.inoFd = inotify_init1(IN_NONBLOCK.cint)
    if result.inoFd < 0:
      result.inoFd = inotify_init()  # fallback si inotify_init1 indisponible
    if result.inoFd < 0:
      raise newException(OSError, "inotify_init failed")
    result.selector = newSelector[string]()
    result.selector.registerHandle(result.inoFd.int, {Event.Read}, rootPath)
    watchDirInotify(result, rootPath)
    for d in tree.allDirs:
      watchDirInotify(result, d.name)

  proc pollImpl(w: Watcher; timeout: int): seq[WatchEvent] =
    var ready = w.implData.selector.select(timeout)
    if ready.len == 0: return

    #while true:
    #  let more = w.implData.selector.select(0)
    #  if more.len == 0: break
    #  ready.add(more)

    # Diff après avoir drainé
    let diff = w.tree[].diffTree()
    w.tree[].updateTree(diff)

    for p in diff.createdFiles:
      result.add(WatchEvent(kind: wekCreated, path: p, isDir: false))
    for p in diff.deletedFiles:
      result.add(WatchEvent(kind: wekDeleted, path: p, isDir: false))
    for p in diff.createdDirs:
      result.add(WatchEvent(kind: wekCreated, path: p, isDir: true))
    for p in diff.deletedDirs:
      result.add(WatchEvent(kind: wekDeleted, path: p, isDir: true))
    for p in diff.modifiedFiles:
      result.add(WatchEvent(kind: wekModified, path: p, isDir: false))

  proc closeImpl(w: Watcher) =
    w.implData.selector.close()
    discard close(w.implData.inoFd)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc newWatcher*(tree: var FileTree; ext: string = ""): Watcher =
  ## Creates a new Watcher for *tree*.
  ##
  ## *ext* is an optional extension filter (e.g. ".png").
  ## Directory events always pass through regardless of the filter.
  ##
  ## The caller drives the loop by calling `poll` from their own thread
  ## or game loop tick.
  result = Watcher(tree: addr tree, ext: ext)
  result.implData = newWatcherImpl(tree.root.name, tree)

proc onEvent*(w: Watcher; cb: WatchCallback) =
  ## Registers *cb* to be called on every dispatched event.
  ## Multiple callbacks are called in registration order.
  w.callbacks.add(cb)

proc removeCallbacks*(w: Watcher) =
  ## Removes all registered callbacks.
  w.callbacks.setLen(0)

proc poll*(w: Watcher; timeout: int = 100) =
  ## Polls for file system events and dispatches them to callbacks.
  ##
  ## *timeout* — max ms to block. 0 = non-blocking, -1 = block forever.
  ## Does not spawn any thread.
  let events = pollImpl(w, timeout)
  for ev in events:
    w.fire(ev)

proc close*(w: Watcher) =
  ## Releases OS resources. The FileTree is not modified.
  closeImpl(w)