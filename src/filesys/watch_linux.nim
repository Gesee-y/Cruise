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

      