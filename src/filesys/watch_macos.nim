import selectors, tables

type
  WatcherImpl = object
    selector: Selector[string]
    fdMap:    Table[int, string]
    rootPath: string

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

  