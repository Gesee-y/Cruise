## hotreload.nim
##
## Event-driven file system watcher built on top of FileTree.
##
## Architecture
## ============
##
##   A dedicated OS thread (watchThread) continuously listens for raw kernel
##   events and pushes typed FileEvents into a shared Channel[seq[FileEvent]].
##   The caller drives consumption by calling poll(), which drains the channel,
##   applies each event surgically via applyEvent(), and dispatches callbacks.
##
##   Channel flow:
##
##     OS thread                      │  Channel[seq[FileEvent]]  │  Caller thread
##     ──────────────────────────────  │  ─────────────────────── │  ─────────────
##     inotify read()                 │                           │
##     kqueue kevent()          push ─▶  [[ev,ev], [ev], ...]   ─▶ drain in poll()
##     ReadDirectoryChangesW          │                           │  applyEvent()
##                                    │                           │  fire callbacks
##
##   Each send() carries a seq[FileEvent] — one batch per OS read cycle.
##   This matches the Windows model where a single ReadDirectoryChangesW call
##   may return multiple FILE_NOTIFY_INFORMATION records, and keeps the Linux
##   and macOS backends consistent with it.
##
## OS backends
## ===========
##
##   Linux   : inotify — per-directory watches; IN_MOVED_FROM/TO paired by
##             cookie to produce fekRenamed; IN_Q_OVERFLOW → fekOverflow.
##
##   macOS   : kqueue/vnode — file and directory vnodes registered via
##             ioselectors registerVnode; rename detected via VnodeRename;
##             new subdirs registered dynamically on creation.
##
##   Windows : ReadDirectoryChangesW in async (OVERLAPPED) mode — the watch
##             thread issues an overlapped request then blocks on
##             GetOverlappedResult.  FILE_ACTION_RENAMED_OLD_NAME and
##             FILE_ACTION_RENAMED_NEW_NAME are paired to form a single
##             fekRenamed event.  ERROR_NOTIFY_ENUM_DIR → fekOverflow.
##             FindFirstChangeNotificationW is no longer used.
##
## Fallback
## ========
##
##   fekOverflow causes applyEvent() to call diffTree() for a full resync.
##   This also runs once at watcher creation to establish the initial baseline.
##
## Threading
## =========
##
##   The Watcher is intentionally *not* async by itself.
##   The watch thread owns all OS handles and pushes events; poll() is called
##   from the caller's thread (game loop tick, main thread, etc.).
##   No locking is needed beyond the Channel itself.
##
## Basic usage
## ===========
##
##   var tree = newFileTree("assets")
##   var w    = newWatcher(tree)
##   w.onEvent(proc(ev: WatchEvent) = echo ev.path, " -> ", ev.kind)
##   while true:
##     w.poll(timeout = 100)

import times

# ---------------------------------------------------------------------------
# OS-specific imports and implementation types
# ---------------------------------------------------------------------------

when defined(windows):
  import winlean

  type
    WatcherImpl = object
      ## Holds the OVERLAPPED handle and the buffer used by
      ## ReadDirectoryChangesW.  The watch thread is stored in the Watcher
      ## itself (see below).
      rootPath:     string
      dirHandle:    Handle       ## Handle opened with FILE_FLAG_OVERLAPPED
      overlapped:   OVERLAPPED
      ## Rename pairing: when FILE_ACTION_RENAMED_OLD_NAME is seen we park
      ## the old path here until FILE_ACTION_RENAMED_NEW_NAME arrives.
      pendingRenameOld: string

elif defined(macosx) or defined(bsd):
  import ioselectors, tables

  type
    WatcherImpl = object
      selector: Selector[string]
      fdMap:    Table[int, string]
      rootPath: string

else: # Linux
  import selectors, tables, posix

  const
    IN_CREATE      = 0x00000100'u32
    IN_DELETE      = 0x00000200'u32
    IN_MODIFY      = 0x00000020'u32
    IN_MOVED_FROM  = 0x00000040'u32
    IN_MOVED_TO    = 0x00000080'u32
    IN_Q_OVERFLOW  = 0xFFFFFFFF'u32
    IN_ISDIR       = 0x40000000'u32
    IN_NONBLOCK    = 0x00004000'u32

  type
    InotifyEvent {.packed.} = object
      wd:     cint
      mask:   uint32
      cookie: uint32
      len:    uint32

    WatcherImpl = object
      inoFd:    cint
      selector: Selector[string]
      wdMap:    Table[cint, string]  ## watch descriptor → absolute directory path
      rootPath: string

  proc inotify_init1(flags: cint): cint {.importc, header: "<sys/inotify.h>".}
  proc inotify_init():              cint {.importc, header: "<sys/inotify.h>".}
  proc inotify_add_watch(fd: cint; path: cstring; mask: uint32): cint {.
      importc, header: "<sys/inotify.h>".}
  proc inotify_rm_watch(fd: cint; wd: cint): cint {.
      importc, header: "<sys/inotify.h>".}

# ---------------------------------------------------------------------------
# Public types
# ---------------------------------------------------------------------------

type
  WatchCallback* = proc(ev: FileEvent) {.closure.}

  Watcher* = ref object
    ## Owns the OS watch resources, the event channel, and the watch thread.
    ##
    ## Lifetime:
    ##   newWatcher  → starts watchThread
    ##   poll()      → drains channel, applies events, fires callbacks
    ##   close()     → signals watchThread to stop, joins it, releases handles
    tree*:      ptr FileTree
    callbacks*: seq[WatchCallback]
    ext*:       string                    ## Optional extension filter (e.g. ".png")
    channel:    Channel[seq[FileEvent]]   ## OS thread pushes batches; poll() drains
    running:    bool                      ## Set to false to stop watchThread
    implData:   WatcherImpl
    watchThread: Thread[pointer]

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc fire(w: Watcher; ev: FileEvent) =
  ## Dispatches a FileEvent to all registered callbacks.
  ## Skips the event when an extension filter is set and the file does not
  ## match.  Directory events always pass through regardless of the filter.
  if w.ext.len > 0 and not ev.isDir and not ev.path.endsWith(w.ext):
    return
  for cb in w.callbacks:
    cb(ev)

# ---------------------------------------------------------------------------
# Windows backend — ReadDirectoryChangesW (OVERLAPPED)
# ---------------------------------------------------------------------------

when defined(windows):

  const
    FILE_LIST_DIRECTORY          = 0x00000001'i32
    FILE_FLAG_BACKUP_SEMANTICS   = 0x02000000'i32
    FILE_FLAG_OVERLAPPED         = 0x40000000'i32
    FILE_NOTIFY_CHANGE_FILE_NAME = 0x00000001'i32
    FILE_NOTIFY_CHANGE_DIR_NAME  = 0x00000002'i32
    FILE_NOTIFY_CHANGE_LAST_WRITE= 0x00000010'i32

    FILE_ACTION_ADDED              = 1'u32
    FILE_ACTION_REMOVED            = 2'u32
    FILE_ACTION_MODIFIED           = 3'u32
    FILE_ACTION_RENAMED_OLD_NAME   = 4'u32
    FILE_ACTION_RENAMED_NEW_NAME   = 5'u32

    ERROR_NOTIFY_ENUM_DIR          = 1022'u32
    INFINITE_TIMEOUT               = 0xFFFFFFFF'u32

  type
    FILE_NOTIFY_INFORMATION {.packed.} = object
      nextEntryOffset: DWORD
      action:          DWORD
      fileNameLength:  DWORD
      ## fileName follows immediately in memory as a variable-length UTF-16LE
      ## string; we read it via pointer arithmetic.

  proc waitForSingleObject(hHandle: Handle; dwMilliseconds: DWORD): DWORD {.
      importc: "WaitForSingleObject", dynlib: "kernel32", stdcall.}

  proc readDirectoryChangesW(
    hDirectory:          Handle,
    lpBuffer:            pointer,
    nBufferLength:       DWORD,
    bWatchSubtree:       WINBOOL,
    dwNotifyFilter:      DWORD,
    lpBytesReturned:     ptr DWORD,
    lpOverlapped:        ptr OVERLAPPED,
    lpCompletionRoutine: pointer
  ): WINBOOL {.importc: "ReadDirectoryChangesW", dynlib: "kernel32", stdcall.}

  proc getOverlappedResult(
    hFile:            Handle,
    lpOverlapped:     ptr OVERLAPPED,
    lpNumberOfBytesTransferred: ptr DWORD,
    bWait:            WINBOOL
  ): WINBOOL {.importc: "GetOverlappedResult", dynlib: "kernel32", stdcall.}

  proc createEventW(
    lpEventAttributes: pointer,
    bManualReset:      WINBOOL,
    bInitialState:     WINBOOL,
    lpName:            WideCString
  ): Handle {.importc: "CreateEventW", dynlib: "kernel32", stdcall.}

  proc cancelIoEx(hFile: Handle, lpOverlapped: ptr OVERLAPPED): WINBOOL {.
    importc: "CancelIoEx", dynlib: "kernel32", stdcall.}

  proc getLastError(): DWORD {.importc: "GetLastError", dynlib: "kernel32", stdcall.}

  const OPEN_EXISTING = 3'u32
 
  proc newWatcherImpl(rootPath: string): WatcherImpl =
    result.rootPath = rootPath
    result.dirHandle = createFileW(
      newWideCString(result.rootPath.cstring).toWideCString,
      DWORD(FILE_LIST_DIRECTORY),
      DWORD(1 or 2 or 4),        # FILE_SHARE_READ | WRITE | DELETE
      nil,
      OPEN_EXISTING.DWORD,
      DWORD(FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED),
      Handle(0))

    if result.dirHandle == Handle(-1):
      raiseOSError(osLastError())
    # Create a manual-reset event for the OVERLAPPED structure.
    result.overlapped = OVERLAPPED()
    result.overlapped.hEvent = createEventW(nil, 1.WINBOOL, 0.WINBOOL, nil)

  proc watchThreadProc(pt: pointer) {.thread, nimcall.} =
    ## Watch thread for Windows.
    ##
    ## Issues async ReadDirectoryChangesW requests in a loop, waits for
    ## completion, decodes FILE_NOTIFY_INFORMATION records, and pushes
    ## a batch of FileEvents into the channel per read cycle.
    let bufSize = 65536
    var buf = cast[ptr UncheckedArray[byte]](alloc0(bufSize))
    var bytesReturned: DWORD
    let filter = DWORD(FILE_NOTIFY_CHANGE_FILE_NAME  or
                       FILE_NOTIFY_CHANGE_DIR_NAME   or
                       FILE_NOTIFY_CHANGE_LAST_WRITE)
    var wPtr = cast[Watcher](pt)
    var pendingEvents: seq[FileEvent]

    defer: dealloc(buf)

    while not wPtr.isNil and wPtr.running:
      let ok = readDirectoryChangesW(
        wPtr.implData.dirHandle,
        addr buf[0], DWORD(bufSize),
        1.WINBOOL,   # watch subtree
        filter,
        nil,         # bytes returned (N/A for overlapped)
        addr wPtr.implData.overlapped,
        nil)

      if ok == 0:
        # If the buffer overflowed, signal a full resync.
        if getLastError() == ERROR_NOTIFY_ENUM_DIR.DWORD:
          pendingEvents.add(FileEvent(kind: fekOverflow, time: getTime()))
        continue

      # Block until the overlapped request completes.
      if getOverlappedResult(wPtr.implData.dirHandle,
                             addr wPtr.implData.overlapped,
                             addr bytesReturned, 1.WINBOOL) == 0:
        if getLastError() == ERROR_NOTIFY_ENUM_DIR.DWORD:
          pendingEvents.add(FileEvent(kind: fekOverflow, time: getTime()))
        continue

      # Decode FILE_NOTIFY_INFORMATION records.
      var offset = 0
      while offset < bytesReturned.int:
        let info = cast[ptr FILE_NOTIFY_INFORMATION](addr buf[offset])
        # The file name is stored as UTF-16LE right after the fixed fields.
        # fileNameLength is in *bytes*, not characters.
        let namePtr  = cast[ptr UncheckedArray[uint16]](
                         cast[int](info) + sizeof(FILE_NOTIFY_INFORMATION))

        let nameLen  = info.fileNameLength.int div 2
        let nameLenBytes = info.fileNameLength.int
        if nameLen <= 0: break

        var relName = newWideCString("", nameLen)
        copyMem(addr relName[0], namePtr, nameLenBytes)

        let absPath  = wPtr.implData.rootPath / $relName

        var res: FileEvent

        case info.action.uint32
        of FILE_ACTION_ADDED:
          res = FileEvent(
            kind:  fekCreated,
            path:  absPath,
            isDir: dirExists(absPath),
            time:  getTime())

        of FILE_ACTION_REMOVED:
          # We can no longer query isDir from disk; infer from the tree.
          let isDir = wPtr.tree[].dirsByPath.hasKey(absPath)
          res = FileEvent(
            kind:  fekDeleted,
            path:  absPath,
            isDir: isDir,
            time:  getTime())

        of FILE_ACTION_MODIFIED:
          res = FileEvent(
            kind:  fekModified,
            path:  absPath,
            isDir: false,
            time:  getTime())

        of FILE_ACTION_RENAMED_OLD_NAME:
          # Park the old name; the next record will be NEW_NAME.
          wPtr.implData.pendingRenameOld = absPath

        of FILE_ACTION_RENAMED_NEW_NAME:
          let oldPath = wPtr.implData.pendingRenameOld
          wPtr.implData.pendingRenameOld = ""
          res = FileEvent(
            kind:    fekRenamed,
            path:    absPath,
            oldPath: oldPath,
            isDir:   dirExists(absPath),
            time:    getTime())

        else: discard

        pendingEvents.add(res)

        if info.nextEntryOffset == 0: break
        offset += info.nextEntryOffset.int

      if pendingEvents.len > 0:
        wPtr.channel.send(pendingEvents)
        pendingEvents.setLen(0)

  proc closeImpl(w: Watcher) =
    discard closeHandle(w.implData.dirHandle)
    discard closeHandle(w.implData.overlapped.hEvent)

# ---------------------------------------------------------------------------
# macOS / BSD backend — kqueue vnode
# ---------------------------------------------------------------------------

elif defined(macosx) or defined(bsd):

  proc watchNodeKqueue(impl: var WatcherImpl; path: string) =
    ## Registers a single file or directory path with kqueue.
    let fd = open(path.cstring, 0x8000)
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

  proc watchThreadProc(pt: pointer) {.thread, nimcall.} =
    ## Watch thread for macOS/BSD.
    ##
    ## Blocks on kqueue select() with a 100 ms timeout, maps vnode events to
    ## FileEvents, and pushes one batch per select() cycle into the channel.
    ##
    ## All events produced by a single select() call are collected into a
    ## seq[FileEvent] and sent together, mirroring the Windows model where one
    ## ReadDirectoryChangesW completion may carry multiple records.
    ##
    ## Rename handling:
    ##   kqueue VnodeRename fires on the *source* vnode but does not supply the
    ##   destination path.  We emit a fekDeleted for the old path and rely on a
    ##   subsequent VnodeWrite on the parent directory (which triggers
    ##   fekOverflow) to surface the new entry via diffTree().
    ##
    ## New subdirectory registration:
    ##   When a VnodeWrite arrives for a directory, we emit fekOverflow so that
    ##   poll() triggers diffTree().  diffTree() calls createDir() for new
    ##   entries, which does not register kqueue watches for the subtree.
    ##   Newly created directories and files therefore need to be registered
    ##   here explicitly once we know their paths.  Because VnodeWrite on a
    ##   directory does not tell us *which* child was added, we walk the
    ##   directory with walkDir and register any fd not yet in fdMap.
    var wPtr = cast[Watcher](pt)

    while not wPtr.isNil and wPtr.running:
      let ready = wPtr[].implData.selector.select(100)
      if ready.len == 0: continue

      # Collect all events from this select() cycle into one batch.
      var pendingEvents: seq[FileEvent]

      for ev in ready:
        let path = wPtr[].implData.fdMap.getOrDefault(ev.fd, "")
        if path.len == 0: continue

        if Event.VnodeDelete in ev.events:
          # The vnode was unlinked.  Infer isDir from the in-memory tree since
          # the path no longer exists on disk.
          let isDir = wPtr[].tree[].dirsByPath.hasKey(path)
          pendingEvents.add(FileEvent(
            kind:  fekDeleted,
            path:  path,
            isDir: isDir,
            time:  getTime()))

        elif Event.VnodeRename in ev.events:
          # kqueue reports the rename on the source vnode only; the destination
          # path is unknown.  Emit a delete and let a subsequent overflow (from
          # the parent directory's VnodeWrite) resync via diffTree().
          let isDir = wPtr[].tree[].dirsByPath.hasKey(path)
          pendingEvents.add(FileEvent(
            kind:  fekDeleted,
            path:  path,
            isDir: isDir,
            time:  getTime()))

        elif Event.VnodeWrite in ev.events or
             Event.VnodeExtend in ev.events:
          if dirExists(path):
            # A write to a directory means a child was created or removed.
            # Emit overflow so poll() can resync via diffTree().
            pendingEvents.add(FileEvent(
              kind: fekOverflow,
              time: getTime()))
            # Eagerly register any new children so future vnode events reach us.
            for kind, entry in walkDir(path):
              let fd = open(entry.cstring, 0)
              if fd >= 0 and fd.int notin wPtr[].implData.fdMap:
                wPtr[].implData.selector.registerVnode(fd,
                  {Event.VnodeWrite, Event.VnodeDelete,
                   Event.VnodeExtend, Event.VnodeRename, Event.VnodeAttrib},
                  entry)
                wPtr[].implData.fdMap[fd.int] = entry
          else:
            pendingEvents.add(FileEvent(
              kind:  fekModified,
              path:  path,
              isDir: false,
              time:  getTime()))

        # VnodeAttrib and other flags — no action needed.

      if pendingEvents.len > 0:
        wPtr[].channel.send(pendingEvents)

  proc closeImpl(w: Watcher) =
    w.implData.selector.close()

# ---------------------------------------------------------------------------
# Linux backend — inotify
# ---------------------------------------------------------------------------

else:

  proc watchDirInotify(impl: var WatcherImpl; path: string) =
    ## Adds a single directory to the inotify watch set.
    let mask = IN_CREATE or IN_DELETE or IN_MODIFY or
               IN_MOVED_FROM or IN_MOVED_TO
    let wd = inotify_add_watch(impl.inoFd, path.cstring, mask)
    if wd >= 0:
      impl.wdMap[wd] = path

  proc newWatcherImpl(rootPath: string; tree: var FileTree): WatcherImpl =
    result.rootPath = rootPath
    result.inoFd = inotify_init1(IN_NONBLOCK.cint)
    if result.inoFd < 0:
      result.inoFd = inotify_init()   # fallback for kernels < 2.6.27
    if result.inoFd < 0:
      raise newException(OSError, "inotify_init failed")
    result.selector = newSelector[string]()
    result.selector.registerHandle(result.inoFd.int, {Event.Read}, rootPath)
    watchDirInotify(result, rootPath)
    for d in tree.allDirs:
      watchDirInotify(result, d.name)

  proc watchThreadProc(pt: pointer) {.thread, nimcall.} =
    ## Watch thread for Linux.
    ##
    ## Blocks on inotify via ioselectors.select(), reads all available
    ## InotifyEvent structs from the fd in one read() call, decodes them into
    ## FileEvents, and pushes the whole batch into the channel in a single
    ## send() — matching the Windows model where one ReadDirectoryChangesW
    ## completion may carry multiple FILE_NOTIFY_INFORMATION records.
    ##
    ## Rename detection:
    ##   IN_MOVED_FROM and IN_MOVED_TO share a cookie.  We park the
    ##   MOVED_FROM path in a table keyed by cookie and pair it when
    ##   MOVED_TO arrives in the same read batch.  Unpaired MOVED_FROM
    ##   events (file moved outside the watched tree) are emitted as
    ##   fekDeleted after the batch is fully decoded.
    ##
    ## New subdirectory registration:
    ##   When IN_CREATE arrives with IN_ISDIR set, or when IN_MOVED_TO
    ##   arrives for a directory, we immediately add an inotify watch for
    ##   the new path so that future events inside it are captured.
    var pendingMoves: Table[uint32, string]   # cookie → old absolute path
    var wPtr = cast[Watcher](pt)

    while not wPtr.isNil and wPtr.running:
      let ready = wPtr.implData.selector.select(100)
      if ready.len == 0: continue

      # Read all available inotify events in one go.
      var buf: array[4096 * (sizeof(InotifyEvent) + 16), byte]
      let n = read(wPtr.implData.inoFd, addr buf[0], buf.len)
      
      if n <= 0: continue

      # Collect every event from this read() call into one batch before
      # sending, so the caller receives a consistent snapshot of one kernel
      # notification burst rather than one channel message per event.
      var pendingEvents: seq[FileEvent]

      var i = 0
      while i < n:
        let ev = cast[ptr InotifyEvent](addr buf[i])
        if ev.len <= 0: break
        let dirPath = wPtr.implData.wdMap.getOrDefault(ev.wd, "")

        # Read the optional name that follows the fixed header.
        let name =
          if ev.len > 0:
            let namePtr = cast[cstring](addr buf[i + sizeof(InotifyEvent)])
            $namePtr
          else:
            ""
        let absPath = if name.len > 0: dirPath / name else: dirPath
        let isDir   = (ev.mask and IN_ISDIR) != 0

        if (ev.mask and IN_Q_OVERFLOW) == IN_Q_OVERFLOW:
          # The kernel dropped events; a full diffTree() pass is required.
          pendingEvents.add(FileEvent(kind: fekOverflow, time: getTime()))

        elif (ev.mask and IN_CREATE) != 0:
          pendingEvents.add(FileEvent(
            kind:  fekCreated,
            path:  absPath,
            isDir: isDir,
            time:  getTime()))
          # Start watching newly created subdirectories immediately so that
          # events for their children are captured without waiting for a
          # subsequent diffTree() pass.
          if isDir:
            watchDirInotify(wPtr[].implData, absPath)

        elif (ev.mask and IN_DELETE) != 0:
          pendingEvents.add(FileEvent(
            kind:  fekDeleted,
            path:  absPath,
            isDir: isDir,
            time:  getTime()))

        elif (ev.mask and IN_MODIFY) != 0:
          pendingEvents.add(FileEvent(
            kind:  fekModified,
            path:  absPath,
            isDir: false,
            time:  getTime()))

        elif (ev.mask and IN_MOVED_FROM) != 0:
          # Park the source path; wait for the matching IN_MOVED_TO in this
          # same batch (inotify guarantees they arrive in the same read() when
          # the destination is inside the watched tree).
          pendingMoves[ev.cookie] = absPath

        elif (ev.mask and IN_MOVED_TO) != 0:
          let oldPath = pendingMoves.getOrDefault(ev.cookie, "")
          if oldPath.len > 0:
            # Paired rename: emit a single fekRenamed event.
            pendingMoves.del(ev.cookie)
            pendingEvents.add(FileEvent(
              kind:    fekRenamed,
              path:    absPath,
              oldPath: oldPath,
              isDir:   isDir,
              time:    getTime()))
            # Keep watching the directory under its new name.
            if isDir:
              watchDirInotify(wPtr[].implData, absPath)
          else:
            # No matching MOVED_FROM in this batch — the source was outside
            # the watched tree.  Treat as a plain creation.
            pendingEvents.add(FileEvent(
              kind:  fekCreated,
              path:  absPath,
              isDir: isDir,
              time:  getTime()))

        i += sizeof(InotifyEvent) + ev.len.int

      # Any MOVED_FROM that had no matching MOVED_TO means the file was moved
      # out of the watched tree entirely.  Emit fekDeleted for each.
      for cookie, oldPath in pendingMoves:
        let isDir = wPtr.tree[].dirsByPath.hasKey(oldPath)
        pendingEvents.add(FileEvent(
          kind:  fekDeleted,
          path:  oldPath,
          isDir: isDir,
          time:  getTime()))
      pendingMoves.clear()

      if pendingEvents.len > 0:
        wPtr.channel.send(pendingEvents)

  proc closeImpl(w: Watcher) =
    w.implData.selector.close()
    discard close(w.implData.inoFd)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc newWatcher*(tree: var FileTree; ext: string = ""): Watcher =
  ## Creates a new Watcher for *tree* and starts the background watch thread.
  ##
  ## *ext* — optional extension filter (e.g. ".png").
  ## Directory events always pass through regardless of the filter.
  ##
  ## The caller drives event delivery by calling poll() from their own thread
  ## or game loop tick.  No callbacks fire until poll() is called.
  result = Watcher(tree: addr tree, ext: ext, running: true)
  result.channel.open()

  when defined(windows):
    result.implData = newWatcherImpl(tree.root.name)
  else:
    result.implData = newWatcherImpl(tree.root.name, tree)

  createThread(result.watchThread, watchThreadProc, addr result[])

proc onEvent*(w: Watcher; cb: WatchCallback) =
  ## Registers *cb* to be called on every dispatched event.
  ## Multiple callbacks are called in registration order.
  w.callbacks.add(cb)

proc removeCallbacks*(w: Watcher) =
  ## Removes all registered callbacks.
  w.callbacks.setLen(0)

proc poll*(w: Watcher; timeout: int = 100) =
  ## Drains the event channel and dispatches all pending events.
  ##
  ## For each FileEvent in each received batch:
  ##   1. applyEvent() updates the in-memory tree surgically (or calls
  ##      diffTree() on fekOverflow).
  ##   2. fire() dispatches the event to all registered callbacks, subject
  ##      to the optional extension filter set on the Watcher.
  ##
  ## *timeout* — controls how long poll() will spin waiting for at least one
  ## batch when the channel is initially empty.  Set to 0 for a fully
  ## non-blocking drain.  Positive values are kept for API compatibility;
  ## the OS thread handles the actual blocking select/wait inside the kernel.
  var cDown    = timeout
  var received = false
  var pending: seq[FileEvent]

  while true:
    (received, pending) = w.channel.tryRecv()
    if received:
      for fileEv in pending:
        discard w.tree[].applyEvent(fileEv)
        w.fire(fileEv)

    cDown -= 1
    if received or cDown <= 0:
      break
    else:
      sleep(1)

proc close*(w: Watcher) =
  ## Signals the watch thread to stop, waits for it to exit, then releases
  ## all OS resources.  The FileTree is not modified.
  w.running = false
  when defined(windows):
    discard cancelIoEx(w.implData.dirHandle, addr w.implData.overlapped)
  joinThread(w.watchThread)
  w.channel.close()
  closeImpl(w)