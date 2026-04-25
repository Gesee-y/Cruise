##########################################################################################################################################################
##################################################################### FILE SYSTEM ########################################################################
##########################################################################################################################################################

## filesystem.nim
##
## Virtual file tree with integrated event queue for hot-reload and file watching.
##
## Key concepts
## ============
##
##   FileEvent
##     A typed, timestamped description of a single file-system change.
##     OS backends (inotify, kqueue, ReadDirectoryChangesW) push FileEvents into
##     a shared Channel[FileEvent].  The watcher thread drains that channel in
##     poll() and applies each event surgically via applyEvent(), avoiding a full
##     disk walk on every change.
##
##   fekOverflow
##     Signals that the OS event queue overflowed (inotify IN_Q_OVERFLOW,
##     ReadDirectoryChangesW ERROR_NOTIFY_ENUM_DIR).  applyEvent() responds with
##     a full diffTree() pass as a reliable fallback.
##
##   applyEvent vs diffTree
##     applyEvent  – O(1) tree update driven by a single typed event.  No disk walk.
##     diffTree    – Full disk walk producing a TreeDiff.  Used at startup and on
##                   overflow.  Internally calls updateTree to keep the tree in sync.

import os, strutils, times, sequtils, tables, sets

type
  FileNodeKind* = enum
    fnFile
    fnDir

  FileNode* = ref object
    ## A single node in the file tree, either a file or a directory.
    id*:           int
    name*:         string       ## Absolute path on disk
    gen*:          int          ## Generation counter when this node was last seen
    lastGen*:      int          ## Previous generation (used for stale-node detection)
    lastModified*: Time         ## Last modification time, used for hot-reload detection
    dontWatch*:    bool         ## When true, this node (and its subtree if dir) is excluded
                                ## from diffTree, detectChanges, and all watch callbacks.
    case kind*: FileNodeKind
    of fnDir:
      dirs*:  seq[FileNode]
      files*: seq[FileNode]
    of fnFile:
      discard

  FileTree* = object
    ## The full virtual file tree rooted at a given path.
    ##
    ## Files are indexed by extension for O(1) filtered iteration.
    ## Directories are indexed by absolute path for O(1) lookup.
    root*:        FileNode
    filesByExt:   Table[string, seq[FileNode]] ## extension (e.g. ".png") → file nodes
                                               ## "" = files with no extension
    dirsByPath:   Table[string, FileNode]      ## absolute path → directory node
    ignoredExts*: HashSet[string]              ## extensions whose nodes are auto-marked dontWatch
    generation:   int                          ## bumped on each diffTree call

  ChangedFile* = object
    ## Describes a file whose on-disk modification time has changed since
    ## the last call to `detectChanges`.
    node*:       FileNode
    oldModTime*: Time
    newModTime*: Time

  TreeDiff* = object
    ## Summary of what changed between the in-memory tree and disk after diffTree.
    createdFiles*:  seq[string]
    createdDirs*:   seq[string]
    deletedFiles*:  seq[string]
    deletedDirs*:   seq[string]
    modifiedFiles*: seq[string]
    modifiedDirs*:  seq[string]

  # ---------------------------------------------------------------------------
  # File event queue types
  # ---------------------------------------------------------------------------

  FileEventKind* = enum
    fekCreated   ## A new file or directory appeared on disk
    fekModified  ## An existing file's content changed
    fekDeleted   ## A file or directory was removed from disk
    fekRenamed   ## A file or directory was renamed
                 ## path    = new absolute path
                 ## oldPath = previous absolute path
    fekOverflow  ## OS event queue overflowed; a full diffTree() pass is needed.
                 ## path and isDir are meaningless for this kind.

  FileEvent* = object
    ## A typed, timestamped description of a single file-system change.
    ## Produced by OS backends and consumed by the Watcher via a Channel.
    kind*:    FileEventKind
    path*:    string  ## Absolute path affected (new path for fekRenamed)
    oldPath*: string  ## Previous path; non-empty only for fekRenamed
    isDir*:   bool    ## True when the path refers to a directory
    time*:    Time    ## Wall-clock time when the event was recorded

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc `$`*(node: FileNode): string =
  ## Returns the display name (last path component) of a node.
  lastPathPart(node.name)

proc isStale(node: FileNode; currentGen: int): bool =
  ## True when the node was not visited during the last diffTree pass.
  node.gen < currentGen

proc extOf(path: string): string =
  ## Returns the lowercase extension of *path*, including the dot.
  ## Returns "" when the file has no extension.
  let e = splitFile(path).ext
  e.toLowerAscii()

proc registerFile(tree: var FileTree; node: FileNode) =
  ## Inserts *node* into the filesByExt index.
  let ext = extOf(node.name)
  if ext notin tree.filesByExt:
    tree.filesByExt[ext] = @[]
  tree.filesByExt[ext].add(node)

proc unregisterFile(tree: var FileTree; node: FileNode) =
  ## Removes *node* from the filesByExt index.
  let ext = extOf(node.name)
  if ext in tree.filesByExt:
    tree.filesByExt[ext].keepItIf(it != node)
    if tree.filesByExt[ext].len == 0:
      tree.filesByExt.del(ext)

proc registerDir(tree: var FileTree; node: FileNode) =
  ## Inserts *node* into the dirsByPath index.
  tree.dirsByPath[node.name] = node

proc unregisterDir(tree: var FileTree; node: FileNode) =
  ## Removes *node* from the dirsByPath index.
  tree.dirsByPath.del(node.name)

proc applyIgnore(tree: FileTree; node: FileNode) =
  ## Marks *node* as dontWatch when its extension is in the ignored set.
  if node.kind == fnFile and extOf(node.name) in tree.ignoredExts:
    node.dontWatch = true

# ---------------------------------------------------------------------------
# Iterators
# ---------------------------------------------------------------------------

iterator allFiles*(tree: FileTree): FileNode =
  ## Iterates over every file node in the tree, across all extensions.
  for nodes in tree.filesByExt.values:
    for n in nodes:
      yield n

iterator allDirs*(tree: FileTree): FileNode =
  ## Iterates over every directory node in the tree.
  for n in tree.dirsByPath.values:
    yield n

iterator watchableFiles*(tree: FileTree): FileNode =
  ## Iterates over file nodes that are not marked dontWatch.
  for nodes in tree.filesByExt.values:
    for n in nodes:
      if not n.dontWatch:
        yield n

iterator watchableDirs*(tree: FileTree): FileNode =
  ## Iterates over directory nodes that are not marked dontWatch.
  for n in tree.dirsByPath.values:
    if not n.dontWatch:
      yield n

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

proc newFileTree*(path: string; ignoredExts: openArray[string] = []): FileTree =
  ## Builds a new FileTree rooted at *path*, walking the whole tree eagerly.
  ##
  ## *ignoredExts* — extensions (e.g. `[".zip", ".tmp"]`) whose file nodes are
  ## automatically marked `dontWatch = true` on creation.
  var idCounter = 1
  result.generation = 1

  for ext in ignoredExts:
    result.ignoredExts.incl(ext.toLowerAscii())

  let absRoot = absolutePath(path)
  result.root = FileNode(kind: fnDir, id: 0, name: absRoot,
                         gen: 1, lastGen: 1,
                         lastModified: getLastModificationTime(absRoot))
  result.registerDir(result.root)

  # Iterative DFS via an explicit stack — avoids stack-overflow on deep trees.
  var stack: seq[(FileNode, string)]
  stack.add((result.root, absRoot))

  while stack.len > 0:
    let (current, currentPath) = stack.pop()

    for kind, entry in walkDir(currentPath):
      let modTime =
        try: getLastModificationTime(entry)
        except OSError: fromUnix(0)

      case kind
      of pcFile:
        let node = FileNode(kind: fnFile, id: idCounter, name: entry,
                            gen: 1, lastGen: 1, lastModified: modTime)
        inc idCounter
        result.applyIgnore(node)
        current.files.add(node)
        result.registerFile(node)

      of pcDir:
        let node = FileNode(kind: fnDir, id: idCounter, name: entry,
                            gen: 1, lastGen: 1, lastModified: modTime)
        inc idCounter
        current.dirs.add(node)
        result.registerDir(node)
        stack.add((node, entry))

      else: discard

# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

proc getDir*(tree: FileTree; path: string): FileNode =
  ## Returns the directory node for *path* (relative to the tree root) in O(1),
  ## or nil if no such directory exists in the tree.
  let target = absolutePath(tree.root.name / path)
  result = tree.dirsByPath.getOrDefault(target, nil)

proc getFile*(tree: FileTree; path: string): FileNode =
  ## Returns the file node for *path* (relative to the tree root),
  ## or nil if no such file exists in the tree.
  let target = absolutePath(tree.root.name / path)
  let ext    = extOf(target)
  if ext in tree.filesByExt:
    for n in tree.filesByExt[ext]:
      if n.name == target:
        return n
  return nil

# ---------------------------------------------------------------------------
# Filtering
# ---------------------------------------------------------------------------

proc filterByExt*(tree: FileTree; ext: string): seq[FileNode] =
  ## Returns all file nodes whose extension matches *ext* (e.g. ".png") in O(1).
  ## The dot must be included in *ext*.
  tree.filesByExt.getOrDefault(ext.toLowerAscii(), @[])

proc filterDirByExt*(dir: FileNode; ext: string): seq[FileNode] =
  ## Like filterByExt but restricted to the direct children of *dir*.
  if dir.kind != fnDir: return @[]
  dir.files.filterIt(it.name.endsWith(ext))

# ---------------------------------------------------------------------------
# Watch control
# ---------------------------------------------------------------------------

proc ignoreExt*(tree: var FileTree; ext: string) =
  ## Adds *ext* to the ignored-extension set and marks all existing file nodes
  ## with that extension as dontWatch = true.
  let e = ext.toLowerAscii()
  tree.ignoredExts.incl(e)
  if e in tree.filesByExt:
    for node in tree.filesByExt[e]:
      node.dontWatch = true

proc unignoreExt*(tree: var FileTree; ext: string) =
  ## Removes *ext* from the ignored-extension set.
  ## Existing nodes are NOT automatically re-enabled — call setWatchable explicitly
  ## on any node you want to resume watching.
  tree.ignoredExts.excl(ext.toLowerAscii())

proc setWatchable*(tree: var FileTree; node: FileNode; watchable: bool) =
  ## Overrides the dontWatch flag on *node* directly.
  ## For directory nodes, also propagates the flag to all descendants.
  node.dontWatch = not watchable
  if node.kind == fnDir:
    for f in node.files:
      f.dontWatch = not watchable
    for d in node.dirs:
      tree.setWatchable(d, watchable)  # recurse into subtree

proc setWatchable*(tree: var FileTree; path: string; watchable: bool) =
  ## Overrides the dontWatch flag for the node at *path* (relative to tree root).
  ## Works for both files and directories.
  let node = tree.getFile(path)
  if node != nil:
    tree.setWatchable(node, watchable)
    return
  let dir = tree.getDir(path)
  if dir != nil:
    tree.setWatchable(dir, watchable)

# ---------------------------------------------------------------------------
# Mutation — create
# ---------------------------------------------------------------------------

proc createDir*(tree: var FileTree; relPath: string) =
  ## Creates a directory at *relPath* (relative to the tree root) on disk
  ## and inserts the corresponding nodes into the tree.
  ## Intermediate directories are created as needed (like `mkdir -p`).
  let absPath = absolutePath(tree.root.name / relPath)
  createDir(absPath)

  var current  = tree.root
  var cumPath  = tree.root.name

  for part in relPath.replace("\\", "/").split("/"):
    if part.len == 0: continue
    cumPath = cumPath / part

    var found: FileNode = nil
    for d in current.dirs:
      if lastPathPart(d.name) == part:
        found = d
        break

    if found == nil:
      let modTime =
        try: getLastModificationTime(cumPath)
        except OSError: getTime()
      let node = FileNode(kind: fnDir,
                          id: tree.dirsByPath.len + 1,
                          name: cumPath, gen: tree.generation,
                          lastGen: tree.generation, lastModified: modTime)
      current.dirs.add(node)
      tree.registerDir(node)
      found = node

    current = found

proc createFile*(tree: var FileTree; relPath: string; content: string = "") =
  ## Creates a file at *relPath* (relative to the tree root) with optional
  ## initial *content*, then inserts the node into the tree.
  let absPath   = absolutePath(tree.root.name / relPath)
  let parentAbs = parentDir(absPath)

  discard existsOrCreateDir(parentAbs)
  writeFile(absPath, content)

  let modTime = getLastModificationTime(absPath)
  let node = FileNode(kind: fnFile,
                      id: tree.dirsByPath.len + 1,
                      name: absPath, gen: tree.generation,
                      lastGen: tree.generation, lastModified: modTime)
  tree.applyIgnore(node)

  let parentNode = tree.getDir(relativePath(parentAbs, tree.root.name))
  if parentNode != nil:
    parentNode.files.add(node)
  tree.registerFile(node)

# ---------------------------------------------------------------------------
# Mutation — copy & move
# ---------------------------------------------------------------------------

proc copyFile*(tree: var FileTree; srcRel, dstRel: string) =
  ## Copies a file from *srcRel* to *dstRel* (both relative to the tree root)
  ## on disk and registers the new node in the tree.
  let src = absolutePath(tree.root.name / srcRel)
  let dst = absolutePath(tree.root.name / dstRel)
  os.copyFile(src, dst)

  let modTime = getLastModificationTime(dst)
  let node = FileNode(kind: fnFile,
                      id: tree.dirsByPath.len + 1,
                      name: dst, gen: tree.generation,
                      lastGen: tree.generation, lastModified: modTime)
  tree.applyIgnore(node)

  let parentNode = tree.getDir(relativePath(parentDir(dst), tree.root.name))
  if parentNode != nil:
    parentNode.files.add(node)
  tree.registerFile(node)

proc moveFile*(tree: var FileTree; srcRel, dstRel: string) =
  ## Moves a file from *srcRel* to *dstRel* (both relative to the tree root).
  ## Updates the tree to reflect the new location and removes the old node.
  let src = absolutePath(tree.root.name / srcRel)
  let dst = absolutePath(tree.root.name / dstRel)
  os.moveFile(src, dst)

  # Remove old node.
  let oldNode = tree.getFile(relativePath(src, tree.root.name))
  if oldNode != nil:
    tree.unregisterFile(oldNode)
  for d in tree.dirsByPath.values:
    d.files.keepItIf(it.name != src)

  # Register new node.
  let modTime = getLastModificationTime(dst)
  let node = FileNode(kind: fnFile,
                      id: tree.dirsByPath.len + 1,
                      name: dst, gen: tree.generation,
                      lastGen: tree.generation, lastModified: modTime)
  tree.applyIgnore(node)

  let parentNode = tree.getDir(relativePath(parentDir(dst), tree.root.name))
  if parentNode != nil:
    parentNode.files.add(node)
  tree.registerFile(node)

proc moveDir*(tree: var FileTree; srcRel, dstRel: string) =
  ## Moves a directory from *srcRel* to *dstRel* (both relative to the tree root).
  ## Rebuilds the affected subtrees in the in-memory tree.
  let src = absolutePath(tree.root.name / srcRel)
  let dst = absolutePath(tree.root.name / dstRel)
  os.moveDir(src, dst)

  # Remove all nodes under src from both indexes.
  for node in toSeq(tree.allFiles):
    if node.name.startsWith(src):
      tree.unregisterFile(node)
  for key in toSeq(tree.dirsByPath.keys):
    if key.startsWith(src):
      tree.dirsByPath.del(key)
  for d in tree.dirsByPath.values:
    d.dirs.keepItIf(not it.name.startsWith(src))
    d.files.keepItIf(not it.name.startsWith(src))

  # Re-insert the moved subtree.
  tree.createDir(relativePath(dst, tree.root.name))

# ---------------------------------------------------------------------------
# Mutation — delete
# ---------------------------------------------------------------------------

proc deleteFile*(tree: var FileTree; relPath: string) =
  ## Deletes a file at *relPath* from disk and removes its node from the tree.
  let absPath = absolutePath(tree.root.name / relPath)
  if fileExists(absPath):
    os.removeFile(absPath)
  let node = tree.getFile(relPath)
  if node != nil:
    tree.unregisterFile(node)
  for d in tree.dirsByPath.values:
    d.files.keepItIf(it.name != absPath)

proc deleteFile*(tree: var FileTree; node: FileNode) =
  ## Deletes a file by node reference.
  if node.kind != fnFile: return
  let relStart = tree.root.name.len
  tree.deleteFile(node.name[relStart..^1])

proc deleteDir*(tree: var FileTree; relPath: string) =
  ## Recursively deletes a directory at *relPath* from disk and removes all
  ## descendant nodes from the tree.
  let absPath = absolutePath(tree.root.name / relPath)
  if dirExists(absPath):
    os.removeDir(absPath)

  # Remove all descendant files from index.
  for node in toSeq(tree.allFiles):
    if node.name.startsWith(absPath):
      tree.unregisterFile(node)

  # Remove all descendant dirs from index.
  for key in toSeq(tree.dirsByPath.keys):
    if key.startsWith(absPath):
      tree.dirsByPath.del(key)

  # Clean up parent's child lists.
  for d in tree.dirsByPath.values:
    d.dirs.keepItIf(not it.name.startsWith(absPath))
    d.files.keepItIf(not it.name.startsWith(absPath))

proc deleteDir*(tree: var FileTree; node: FileNode) =
  ## Deletes a directory by node reference.
  if node.kind != fnDir: return
  let relStart = tree.root.name.len
  tree.deleteDir(node.name[relStart..^1])

# ---------------------------------------------------------------------------
# Hot-reload / change detection
# ---------------------------------------------------------------------------

proc detectChanges*(tree: var FileTree; ext: string = ""): seq[ChangedFile] =
  ## Scans file nodes for on-disk modification time changes.
  ##
  ## Nodes marked `dontWatch` are skipped entirely.
  ## If *ext* is non-empty, only files with that extension are checked.
  ## Each changed node's `lastModified` is updated so the next call uses
  ## the new baseline.
  let candidates =
    if ext.len > 0: tree.filterByExt(ext)
    else: toSeq(tree.watchableFiles)

  for node in candidates:
    if node.dontWatch: continue
    let current =
      try: getLastModificationTime(node.name)
      except OSError: continue
    if current != node.lastModified:
      result.add(ChangedFile(node: node,
                             oldModTime: node.lastModified,
                             newModTime: current))
      node.lastModified = current

proc updateTree*(tree: var FileTree; diff: TreeDiff) =
  ## Applies a TreeDiff to the in-memory tree — called internally after diffTree.
  let relStart = tree.root.name.len
  for p in diff.deletedDirs:   tree.deleteDir(p[relStart..^1])
  for p in diff.createdDirs:   tree.createDir(p[relStart..^1])
  for p in diff.deletedFiles:  tree.deleteFile(p[relStart..^1])
  for p in diff.createdFiles:  tree.createFile(p[relStart..^1])

proc diffTree*(tree: var FileTree): TreeDiff =
  ## Diffs the in-memory tree against the real disk state and returns a TreeDiff.
  ##
  ## - New entries on disk   → reported in created*, added to the tree
  ## - Missing entries       → reported in deleted*, removed from the tree
  ## - Files with new mtime  → reported in modified*, node updated in place
  ##
  ## Directories marked `dontWatch` are skipped entirely — their subtrees are
  ## neither walked nor reported.
  ##
  ## Used at startup and as a fallback on fekOverflow.
  ## For normal operation, prefer applyEvent which avoids the disk walk entirely.
  inc tree.generation
  let gen = tree.generation

  var stack: seq[string]
  tree.root.gen = gen
  stack.add(tree.root.name)

  while stack.len > 0:
    let currentPath = stack.pop()

    for kind, entry in walkDir(currentPath):
      let modTime =
        try: getLastModificationTime(entry)
        except OSError: fromUnix(0)

      case kind
      of pcFile:
        let found = tree.getFile(relativePath(entry, tree.root.name))
        if found == nil:
          result.createdFiles.add(entry)
        else:
          found.gen = gen
          if not found.dontWatch and found.lastModified != modTime:
            result.modifiedFiles.add(entry)
            found.lastModified = modTime

      of pcDir:
        let found = tree.dirsByPath.getOrDefault(entry, nil)
        if found == nil:
          result.createdDirs.add(entry)
        else:
          found.gen = gen
          # Skip the entire subtree if dontWatch is set on this directory.
          if not found.dontWatch:
            stack.add(entry)

      else: discard

  # Nodes not visited this generation have disappeared from disk.
  for node in tree.allFiles:
    if node.gen < gen or not fileExists(node.name):
      result.deletedFiles.add(node.name)
  for node in tree.allDirs:
    if node.gen < gen or not dirExists(node.name):
      result.deletedDirs.add(node.name)

# ---------------------------------------------------------------------------
# Event queue — surgical tree update
# ---------------------------------------------------------------------------

proc applyEvent*(tree: var FileTree; ev: FileEvent): TreeDiff =
  ## Applies a single FileEvent to the in-memory tree without walking disk.
  ##
  ## Returns a TreeDiff describing what changed so the Watcher can fire
  ## the appropriate callbacks.  The diff contains at most one entry.
  ##
  ## fekOverflow triggers a full diffTree() pass and returns its result,
  ## since the exact set of changes is unknown after an overflow.
  ##
  ## Notes
  ## -----
  ##   - For fekCreated dirs, the new directory is registered but its contents
  ##     are NOT walked here.  The OS backend will emit individual fekCreated
  ##     events for each new child, or the caller can call diffTree() to catch
  ##     everything at once if preferred.
  ##   - For fekRenamed, oldPath must be the previous absolute path; path is the
  ##     new absolute path.  Both the index and the parent's child list are updated.
  ##   - dontWatch nodes are updated in the index (to stay consistent) but their
  ##     paths are NOT included in the returned TreeDiff, so no callback fires.

  case ev.kind

  of fekOverflow:
    # Full resync — we can't trust individual events after an overflow.
    result = tree.diffTree()

  of fekCreated:
    let relPath = relativePath(ev.path, tree.root.name)
    if ev.isDir:
      # Only register if not already known (duplicate events are possible).
      if tree.dirsByPath.getOrDefault(ev.path, nil) == nil:
        tree.createDir(relPath)
        let node = tree.dirsByPath.getOrDefault(ev.path, nil)
        if node != nil and not node.dontWatch:
          result.createdDirs.add(ev.path)
    else:
      if tree.getFile(relPath) == nil:
        tree.createFile(relPath)
        let node = tree.getFile(relPath)
        if node != nil and not node.dontWatch:
          result.createdFiles.add(ev.path)

  of fekDeleted:
    let relPath = relativePath(ev.path, tree.root.name)
    if ev.isDir:
      let node = tree.dirsByPath.getOrDefault(ev.path, nil)
      let shouldReport = node != nil and not node.dontWatch
      tree.deleteDir(relPath)
      if shouldReport:
        result.deletedDirs.add(ev.path)
    else:
      let node = tree.getFile(relPath)
      let shouldReport = node != nil and not node.dontWatch
      tree.deleteFile(relPath)
      if shouldReport:
        result.deletedFiles.add(ev.path)

  of fekModified:
    # Directories don't have meaningful mtime tracking here; skip them.
    if ev.isDir: return
    let relPath = relativePath(ev.path, tree.root.name)
    let node = tree.getFile(relPath)
    if node == nil or node.dontWatch: return
    let newMtime =
      try: getLastModificationTime(ev.path)
      except OSError: return
    if newMtime != node.lastModified:
      node.lastModified = newMtime
      result.modifiedFiles.add(ev.path)

  of fekRenamed:
    # Treat as delete-old + create-new.  The OS already completed the rename.
    let oldRel = relativePath(ev.oldPath, tree.root.name)
    let newRel = relativePath(ev.path,    tree.root.name)

    if ev.isDir:
      let oldNode = tree.dirsByPath.getOrDefault(ev.oldPath, nil)
      let wasWatched = oldNode != nil and not oldNode.dontWatch
      # Remove the old subtree from both indexes.
      
      if not oldNode.isNil: oldNode.name = newRel
    else:
      let oldNode = tree.getFile(oldRel)
      let wasWatched = oldNode != nil and not oldNode.dontWatch
      tree.deleteFile(oldRel)
      tree.createFile(newRel)
      if wasWatched:
        result.deletedFiles.add(ev.oldPath)
        result.createdFiles.add(ev.path)

# ---------------------------------------------------------------------------
# Debug / pretty-print
# ---------------------------------------------------------------------------

proc printTree*(node: FileNode; indent: int = 0) =
  ## Recursively prints the tree to stdout for debugging.
  let prefix = "  ".repeat(indent)
  let watch  = if node.dontWatch: " [ignored]" else: ""
  case node.kind
  of fnDir:
    echo prefix & "[" & lastPathPart(node.name) & "]" & watch
    for d in node.dirs:  printTree(d, indent + 1)
    for f in node.files: printTree(f, indent + 1)
  of fnFile:
    echo prefix & lastPathPart(node.name) & watch

include "hotreload.nim"