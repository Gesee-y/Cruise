## hotreload.nim
##
## Event-driven file system watcher built on top of FileTree.
##
## Each OS backend is isolated in its own `when` branch:
##   - Linux   : inotify via a raw file descriptor registered into ioselectors
##   - macOS   : kqueue/vnode via ioselectors registerVnode
##   - Windows : ReadDirectoryChangesW imported directly from kernel32
##               (winlean does not expose this proc)
##
## The watcher is intentionally *not* async by itself.
## Calling `poll` returns a seq of `WatchEvent` — the caller decides how and
## when to drive the loop (plain thread, async dispatcher, game loop, etc.).
##
## Basic usage:
##
##   var tree = newFileTree("assets")
##   var w    = newWatcher(tree)
##   w.onEvent(proc(ev: WatchEvent) = echo ev.path, " -> ", ev.kind)
##   while true:
##     w.poll(timeout = 100)   # drive from your own loop / thread

import os, strutils, tables

# ---------------------------------------------------------------------------
# OS-specific implementation types
# ---------------------------------------------------------------------------

when defined(windows):
  import winlean

  type
    WatcherImpl = object
      dirHandle:    Handle  ## opened for synchronous ReadDirectoryChangesW
      notifyHandle: Handle  ## FindFirstChangeNotification handle for timeout
      buffer:       array[65536, byte]
      rootPath:     string

elif defined(macosx) or defined(bsd):
  import ioselectors

  type
    WatcherImpl = object
      selector: Selector[string]  ## maps fd -> absolute path
      fdMap:    Table[int, string]
      rootPath: string

else: # Linux
  import ioselectors

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
      inoFd:    cint                 ## inotify instance fd
      selector: Selector[string]     ## used to block efficiently on the fd
      wdMap:    Table[cint, string]  ## watch descriptor -> directory path
      rootPath: string

  proc inotify_init(): cint {.importc, header: "<sys/inotify.h>".}
  proc inotify_add_watch(fd: cint; path: cstring; mask: uint32): cint {.
      importc, header: "<sys/inotify.h>".}
  proc inotify_rm_watch(fd: cint; wd: cint): cint {.
      importc, header: "<sys/inotify.h>".}

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
    ## Opaque watcher handle. Internals differ per OS.
    tree*:     ptr FileTree    ## The FileTree kept in sync with events
    callbacks: seq[WatchCallback]
    ext*:      string          ## Optional extension filter ("" = all)
    implData:  WatcherImpl     ## OS-specific state (see below)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc fire(w: Watcher; ev: WatchEvent) =
  ## Dispatches *ev* to every registered callback.
  ## The extension filter is applied here so backends stay simple.
  if w.ext.len > 0 and not ev.isDir and not ev.path.endsWith(w.ext):
    return
  for cb in w.callbacks:
    cb(ev)

# ---------------------------------------------------------------------------
# Linux backend (inotify)
# ---------------------------------------------------------------------------

when not defined(windows) and not defined(macosx) and not defined(bsd):

  proc watchDirInotify(impl: var WatcherImpl; path: string) =
    ## Adds an inotify watch for *path* and records the watch descriptor.
    let mask = IN_CREATE or IN_DELETE or IN_MODIFY or IN_MOVED_TO or IN_ONLYDIR
    let wd = inotify_add_watch(impl.inoFd, path.cstring, mask)
    if wd >= 0:
      impl.wdMap[wd] = path

  proc newWatcherImpl(rootPath: string; tree: var FileTree): WatcherImpl =
    result.rootPath = rootPath
    result.inoFd    = inotify_init()
    if result.inoFd < 0:
      raise newException(OSError, "inotify_init failed")
    result.selector = newSelector[string]()
    result.selector.registerHandle(result.inoFd.int, {Event.Read}, rootPath)
    watchDirInotify(result, rootPath)
    for d in tree.allDirs:
      watchDirInotify(result, d.name)

  proc pollImpl(w: Watcher; timeout: int): seq[WatchEvent] =
    let ready = w.implData.selector.select(timeout)
    for key in ready:
      if Event.Read notin key.events: continue
      var buf: array[4096, byte]
      let n = read(w.implData.inoFd, addr buf[0], buf.len)
      var i = 0
      while i < n:
        let ev      = cast[ptr InotifyEvent](addr buf[i])
        let nameLen = ev.len.int
        var name    = ""
        if nameLen > 0:
          name = $cast[cstring](addr buf[i + sizeof(InotifyEvent)])
        let dirPath  = w.implData.wdMap.getOrDefault(ev.wd, "")
        let fullPath = if name.len > 0: dirPath / name else: dirPath
        let isDir    = (ev.mask and IN_ISDIR) != 0

        var kind: WatchEventKind
        if (ev.mask and IN_CREATE) != 0 or (ev.mask and IN_MOVED_TO) != 0:
          kind = wekCreated
          if isDir:
            watchDirInotify(w.implData, fullPath)
            w.tree[].createDir(relativePath(fullPath, w.implData.rootPath))
        elif (ev.mask and IN_DELETE) != 0:
          kind = wekDeleted
          if isDir: w.tree[].deleteDir(relativePath(fullPath, w.implData.rootPath))
          else:     w.tree[].deleteFile(relativePath(fullPath, w.implData.rootPath))
        elif (ev.mask and IN_MODIFY) != 0:
          kind = wekModified
          let node = w.tree[].getFile(relativePath(fullPath, w.implData.rootPath))
          if node != nil:
            node.lastModified = getLastModificationTime(fullPath)
        else:
          i += sizeof(InotifyEvent) + nameLen
          continue

        result.add(WatchEvent(kind: kind, path: fullPath, isDir: isDir))
        i += sizeof(InotifyEvent) + nameLen

  proc closeImpl(w: Watcher) =
    w.implData.selector.close()
    discard close(w.implData.inoFd)

# ---------------------------------------------------------------------------
# macOS / BSD backend (kqueue vnode)
# ---------------------------------------------------------------------------

elif defined(macosx) or defined(bsd):

  proc watchNodeKqueue(impl: var WatcherImpl; path: string) =
    ## Opens *path* and registers it as a vnode event source in the selector.
    let fd = open(path.cstring, 0)  # O_RDONLY
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
    for key in ready:
      let path  = w.implData.fdMap.getOrDefault(key.fd, "")
      if path.len == 0: continue
      let isDir = dirExists(path)

      if Event.VnodeDelete in key.events or Event.VnodeRevoke in key.events:
        result.add(WatchEvent(kind: wekDeleted, path: path, isDir: isDir))
        w.implData.selector.unregister(key.fd)
        w.implData.fdMap.del(key.fd)
        if isDir: w.tree[].deleteDir(relativePath(path, w.implData.rootPath))
        else:     w.tree[].deleteFile(relativePath(path, w.implData.rootPath))

      elif Event.VnodeRename in key.events:
        result.add(WatchEvent(kind: wekRenamed, path: path, isDir: isDir))

      elif Event.VnodeWrite  in key.events or
           Event.VnodeExtend in key.events or
           Event.VnodeAttrib in key.events:
        result.add(WatchEvent(kind: wekModified, path: path, isDir: isDir))
        let node = w.tree[].getFile(relativePath(path, w.implData.rootPath))
        if node != nil:
          node.lastModified = getLastModificationTime(path)

  proc closeImpl(w: Watcher) =
    w.implData.selector.close()

# ---------------------------------------------------------------------------
# Windows backend (ReadDirectoryChangesW — synchronous + WaitForSingleObject)
# ---------------------------------------------------------------------------
# Strategy:
#   - Open the directory WITHOUT FILE_FLAG_OVERLAPPED (synchronous mode).
#   - Use FindFirstChangeNotification + WaitForSingleObject to implement the
#     poll timeout without blocking forever.
#   - Once a change is signalled, call ReadDirectoryChangesW synchronously to
#     read the actual change records.
# ---------------------------------------------------------------------------

else:

  const
    FILE_LIST_DIRECTORY           = 0x00000001'i32
    FILE_FLAG_BACKUP_SEMANTICS    = 0x02000000'i32
    FILE_NOTIFY_CHANGE_FILE_NAME  = 0x00000001'i32
    FILE_NOTIFY_CHANGE_DIR_NAME   = 0x00000002'i32
    FILE_NOTIFY_CHANGE_LAST_WRITE = 0x00000010'i32
    FILE_ACTION_ADDED             = 0x00000001'u32
    FILE_ACTION_REMOVED           = 0x00000002'u32
    FILE_ACTION_MODIFIED          = 0x00000003'u32
    FILE_ACTION_RENAMED_NEW_NAME  = 0x00000005'u32
    WAIT_TIMEOUT_VAL              = 0x00000102'u32

  type
    FileNotifyInformation {.packed.} = object
      nextEntryOffset: DWORD
      action:          DWORD
      fileNameLength:  DWORD
      fileName:        array[1, WinChar]  ## variable-length UTF-16LE

  # Synchronous variant — no OVERLAPPED argument.
  proc readDirectoryChangesWSync(
    hDirectory:      Handle,
    lpBuffer:        pointer,
    nBufferLength:   DWORD,
    bWatchSubtree:   WINBOOL,
    dwNotifyFilter:  DWORD,
    lpBytesReturned: ptr DWORD
  ): WINBOOL {.importc: "ReadDirectoryChangesW", dynlib: "kernel32", stdcall.}

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
    result.rootPath = rootPath
    let wPath = newWideCString(rootPath)

    # Directory handle for ReadDirectoryChangesW (synchronous — no OVERLAPPED).
    result.dirHandle = createFileW(
      wPath,
      FILE_LIST_DIRECTORY,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil,
      OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS,
      0)
    if result.dirHandle == Handle(-1):
      raiseOSError(osLastError())

    # Separate notification handle used only for timeout-aware waiting.
    let notifyFilter = DWORD(FILE_NOTIFY_CHANGE_FILE_NAME or
                             FILE_NOTIFY_CHANGE_DIR_NAME  or
                             FILE_NOTIFY_CHANGE_LAST_WRITE)
    result.notifyHandle = findFirstChangeNotificationW(wPath, true.WINBOOL, notifyFilter)
    if result.notifyHandle == Handle(-1):
      raiseOSError(osLastError())

  proc pollImpl(w: Watcher; timeout: int): seq[WatchEvent] =
    # Step 1 — wait up to *timeout* ms for a change signal.
    let inf = 0xFFFFFFFF'u32
    let ms = if timeout < 0: DWORD(inf)   # INFINITE
             else:           DWORD(timeout)
    let waitResult = waitForSingleObject(w.implData.notifyHandle, ms)
    if waitResult == WAIT_TIMEOUT_VAL.DWORD: return

    # Re-arm for the next poll() call before reading, so we don't miss events.
    discard findNextChangeNotification(w.implData.notifyHandle)

    # Step 2 — read change records synchronously.
    var bytesReturned: DWORD = 0
    let notifyFilter = DWORD(FILE_NOTIFY_CHANGE_FILE_NAME or
                             FILE_NOTIFY_CHANGE_DIR_NAME  or
                             FILE_NOTIFY_CHANGE_LAST_WRITE)
    let ok = readDirectoryChangesWSync(
      w.implData.dirHandle,
      addr w.implData.buffer[0],
      DWORD(w.implData.buffer.len),
      true.WINBOOL,
      notifyFilter,
      addr bytesReturned)

    if not ok.bool or bytesReturned == 0: return

    var offset = 0
    while offset < bytesReturned.int:
      let info     = cast[ptr FileNotifyInformation](addr w.implData.buffer[offset])
      let nameWide = cast[ptr UncheckedArray[WinChar]](addr info.fileName)
      let nameUtf8 = $newWideCString(($nameWide.WideCString).cstring, info.fileNameLength.int div 2)
      let fullPath = w.implData.rootPath / nameUtf8
      let isDir    = dirExists(fullPath)

      var kind: WatchEventKind
      case info.action.uint32
      of FILE_ACTION_ADDED:
        kind = wekCreated
        if isDir: w.tree[].createDir(relativePath(fullPath, w.implData.rootPath))
      of FILE_ACTION_REMOVED:
        kind = wekDeleted
        if isDir: w.tree[].deleteDir(relativePath(fullPath, w.implData.rootPath))
        else:     w.tree[].deleteFile(relativePath(fullPath, w.implData.rootPath))
      of FILE_ACTION_MODIFIED:
        kind = wekModified
        let node = w.tree[].getFile(relativePath(fullPath, w.implData.rootPath))
        if node != nil:
          node.lastModified = getLastModificationTime(fullPath)
      of FILE_ACTION_RENAMED_NEW_NAME:
        kind = wekRenamed
      else:
        if info.nextEntryOffset == 0: break
        offset += info.nextEntryOffset.int
        continue

      result.add(WatchEvent(kind: kind, path: fullPath, isDir: isDir))
      if info.nextEntryOffset == 0: break
      offset += info.nextEntryOffset.int

  proc closeImpl(w: Watcher) =
    discard findCloseChangeNotification(w.implData.notifyHandle)
    #discard closeHandle(w.implData.dirHandle)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc newWatcher*(tree: var FileTree; ext: string = ""): Watcher =
  ## Creates a new Watcher for *tree*.
  ##
  ## *ext* is an optional extension filter (e.g. ".png").
  ## When set, only events for files matching that extension are dispatched
  ## to callbacks.  Directory events are always forwarded regardless of *ext*.
  ##
  ## The caller is responsible for driving the event loop by calling `poll`
  ## from their own thread, async dispatcher, or game loop.
  result = Watcher(tree: addr tree, ext: ext)
  result.implData = newWatcherImpl(tree.root.name, tree)

proc onEvent*(w: Watcher; cb: WatchCallback) =
  ## Registers *cb* to be called whenever a watch event is dispatched.
  ## Multiple callbacks can be registered and are called in registration order.
  w.callbacks.add(cb)

proc removeCallbacks*(w: Watcher) =
  ## Removes all registered callbacks from *w*.
  w.callbacks.setLen(0)

proc poll*(w: Watcher; timeout: int = 100) =
  ## Polls for file system events and dispatches them to registered callbacks.
  ##
  ## *timeout* — maximum milliseconds to block waiting for events.
  ## Pass 0 for a non-blocking check, -1 to block indefinitely.
  ##
  ## This proc does **not** spawn any thread.  Call it from wherever suits
  ## your architecture: a dedicated thread, an async loop, a game update
  ## tick, etc.
  let events = pollImpl(w, timeout)
  for ev in events:
    w.fire(ev)

proc close*(w: Watcher) =
  ## Releases all OS resources held by the watcher.
  ## The associated FileTree is not modified.
  closeImpl(w)