##########################################################################################################################################################
##################################################################### FILE SYSTEM ########################################################################
##########################################################################################################################################################

import os, strutils, times, sequtils

type
  FileNodeKind* = enum
    fnFile
    fnDir

  FileNode* = ref object
    ## A single node in the file tree, either a file or a directory.
    id*: int
    name*: string       ## Absolute path on disk
    gen*: int           ## Generation counter when this node was last seen
    lastGen*: int       ## Previous generation (used for stale-node detection)
    lastModified*: Time ## Last modification time, used for hot-reload detection
    case kind*: FileNodeKind
    of fnDir:
      dirs*:  seq[FileNode]
      files*: seq[FileNode]
    of fnFile:
      discard

  FileTree* = object
    ## The full virtual file tree rooted at a given path.
    root*:     FileNode
    allFiles*: seq[FileNode] ## Flat list of every file node
    allDirs*:  seq[FileNode] ## Flat list of every directory node
    generation: int          ## Current generation, bumped on each refresh

  ChangedFile* = object
    ## Describes a file whose on-disk modification time has changed since
    ## the last call to `detectChanges`.
    node*:       FileNode
    oldModTime*: Time
    newModTime*: Time

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc `$`*(node: FileNode): string =
  ## Returns the display name (last path component) of a node.
  lastPathPart(node.name)

proc isStale(node: FileNode, currentGen: int): bool =
  ## Returns true when a node was not visited during the last refresh pass.
  node.lastGen < currentGen

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

proc newFileTree*(path: string): FileTree =
  ## Builds a new FileTree rooted at *path*.
  ## The whole directory tree is walked eagerly and stored in memory.
  var idCounter = 1
  result.generation = 1

  let absRoot = absolutePath(path)
  result.root = FileNode(kind: fnDir, id: 0, name: absRoot,
                         gen: 1, lastGen: 1,
                         lastModified: getLastModificationTime(absRoot))

  # Iterative BFS/DFS via an explicit stack — avoids stack-overflow on deep trees.
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
        current.files.add(node)
        result.allFiles.add(node)

      of pcDir:
        let node = FileNode(kind: fnDir, id: idCounter, name: entry,
                            gen: 1, lastGen: 1, lastModified: modTime)
        inc idCounter
        current.dirs.add(node)
        result.allDirs.add(node)
        stack.add((node, entry))

      else:
        discard

# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

proc getDir*(tree: FileTree, path: string): FileNode =
  ## Returns the directory node for *path* (relative to the tree root),
  ## or nil if no such directory exists in the tree.
  let target = absolutePath(tree.root.name / path)
  result = nil
  for d in tree.allDirs:
    if d.name == target:
      return d

proc getFile*(tree: FileTree, path: string): FileNode =
  ## Returns the file node for *path* (relative to the tree root),
  ## or nil if no such file exists in the tree.
  let target = absolutePath(tree.root.name / path)
  result = nil
  for f in tree.allFiles:
    if f.name == target:
      return f

# ---------------------------------------------------------------------------
# Filtering
# ---------------------------------------------------------------------------

proc filterByExt*(tree: FileTree, ext: string): seq[FileNode] =
  ## Returns all file nodes whose name ends with *ext* (e.g. ".png").
  ## The dot must be included in *ext*.
  tree.allFiles.filterIt(it.name.endsWith(ext))

proc filterDirByExt*(dir: FileNode, ext: string): seq[FileNode] =
  ## Like filterByExt but restricted to the direct children of *dir*.
  if dir.kind != fnDir: return @[]
  dir.files.filterIt(it.name.endsWith(ext))

# ---------------------------------------------------------------------------
# Mutation — create
# ---------------------------------------------------------------------------

proc createDir*(tree: var FileTree, relPath: string) =
  ## Creates a directory at *relPath* (relative to the tree root) on disk
  ## and inserts the corresponding nodes into the tree.
  ##
  ## Intermediate directories are created as needed (like `mkdir -p`).
  let absPath = absolutePath(tree.root.name / relPath)
  createDir(absPath)

  var current = tree.root
  var cumPath = tree.root.name

  for part in relPath.replace("\\", "/").split("/"):
    if part.len == 0: continue
    cumPath = cumPath / part

    # Check whether this segment already exists in the tree.
    var found: FileNode = nil
    for d in current.dirs:
      if lastPathPart(d.name) == part:
        found = d
        break

    if found == nil:
      # Node missing from the tree — create it.
      let modTime =
        try: getLastModificationTime(cumPath)
        except OSError: getTime()
      let node = FileNode(kind: fnDir, id: tree.allDirs.len + tree.allFiles.len + 1,
                          name: cumPath, gen: tree.generation,
                          lastGen: tree.generation, lastModified: modTime)
      current.dirs.add(node)
      tree.allDirs.add(node)
      found = node

    current = found

proc createFile*(tree: var FileTree, relPath: string, content: string = "") =
  ## Creates a file at *relPath* (relative to the tree root) with optional
  ## initial *content*, then inserts the node into the tree.
  let absPath = absolutePath(tree.root.name / relPath)
  let parentAbs = parentDir(absPath)

  # Ensure parent directory exists.
  discard existsOrCreateDir(parentAbs)
  writeFile(absPath, content)

  let modTime = getLastModificationTime(absPath)
  let node = FileNode(kind: fnFile,
                      id: tree.allDirs.len + tree.allFiles.len + 1,
                      name: absPath, gen: tree.generation,
                      lastGen: tree.generation, lastModified: modTime)

  # Attach to the correct parent node.
  let parentNode = getDir(tree, relativePath(parentAbs, tree.root.name))
  if parentNode != nil:
    parentNode.files.add(node)
  tree.allFiles.add(node)

# ---------------------------------------------------------------------------
# Mutation — copy & move
# ---------------------------------------------------------------------------

proc copyFile*(tree: var FileTree, srcRel, dstRel: string) =
  ## Copies a file from *srcRel* to *dstRel* (both relative to the tree root)
  ## on disk and registers the new node in the tree.
  let src = absolutePath(tree.root.name / srcRel)
  let dst = absolutePath(tree.root.name / dstRel)
  os.copyFile(src, dst)
  # Re-use createFile to register the new node (content already on disk).
  let modTime = getLastModificationTime(dst)
  let node = FileNode(kind: fnFile,
                      id: tree.allDirs.len + tree.allFiles.len + 1,
                      name: dst, gen: tree.generation,
                      lastGen: tree.generation, lastModified: modTime)
  let parentNode = getDir(tree, relativePath(parentDir(dst), tree.root.name))
  if parentNode != nil:
    parentNode.files.add(node)
  tree.allFiles.add(node)

proc moveFile*(tree: var FileTree, srcRel, dstRel: string) =
  ## Moves a file from *srcRel* to *dstRel* (both relative to the tree root).
  ## Updates the tree to reflect the new location and removes the old node.
  let src = absolutePath(tree.root.name / srcRel)
  let dst = absolutePath(tree.root.name / dstRel)
  os.moveFile(src, dst)

  # Remove old node from flat list and its parent.
  tree.allFiles.keepItIf(it.name != src)
  for d in tree.allDirs:
    d.files.keepItIf(it.name != src)

  # Register new node.
  let modTime = getLastModificationTime(dst)
  let node = FileNode(kind: fnFile,
                      id: tree.allDirs.len + tree.allFiles.len + 1,
                      name: dst, gen: tree.generation,
                      lastGen: tree.generation, lastModified: modTime)
  let parentNode = getDir(tree, relativePath(parentDir(dst), tree.root.name))
  if parentNode != nil:
    parentNode.files.add(node)
  tree.allFiles.add(node)

proc moveDir*(tree: var FileTree, srcRel, dstRel: string) =
  ## Moves a directory from *srcRel* to *dstRel* (both relative to the tree root).
  ## Rebuilds the affected subtrees in the in-memory tree.
  let src = absolutePath(tree.root.name / srcRel)
  let dst = absolutePath(tree.root.name / dstRel)
  os.moveDir(src, dst)

  # Simplest correct strategy: remove stale nodes and rebuild from the new path.
  tree.allFiles.keepItIf(not it.name.startsWith(src))
  tree.allDirs.keepItIf(not it.name.startsWith(src))
  for d in tree.allDirs:
    d.dirs.keepItIf(not it.name.startsWith(src))
    d.files.keepItIf(not it.name.startsWith(src))

  # Re-insert the moved subtree by treating it as a new directory creation.
  tree.createDir(relativePath(dst, tree.root.name))

# ---------------------------------------------------------------------------
# Mutation — delete
# ---------------------------------------------------------------------------

proc deleteFile*(tree: var FileTree, relPath: string) =
  ## Deletes a file at *relPath* from disk and removes its node from the tree.
  let absPath = absolutePath(tree.root.name / relPath)
  if fileExists(absPath):
    os.removeFile(absPath)
  tree.allFiles.keepItIf(it.name != absPath)
  for d in tree.allDirs:
    d.files.keepItIf(it.name != absPath)

proc deleteDir*(tree: var FileTree, relPath: string) =
  ## Recursively deletes a directory at *relPath* from disk and removes all
  ## descendant nodes from the tree.
  let absPath = absolutePath(tree.root.name / relPath)
  if dirExists(absPath):
    os.removeDir(absPath)
  tree.allFiles.keepItIf(not it.name.startsWith(absPath))
  tree.allDirs.keepItIf(not it.name.startsWith(absPath))
  for d in tree.allDirs:
    d.dirs.keepItIf(not it.name.startsWith(absPath))
    d.files.keepItIf(not it.name.startsWith(absPath))

# ---------------------------------------------------------------------------
# Hot-reload / change detection
# ---------------------------------------------------------------------------

proc detectChanges*(tree: var FileTree,
                    ext: string = ""): seq[ChangedFile] =
  ## Scans every file in the tree for on-disk modification time changes.
  ##
  ## If *ext* is non-empty (e.g. ".png"), only files with that extension are
  ## checked.  For each changed file the node's `lastModified` field is updated
  ## in place so the next call to `detectChanges` uses the new baseline.
  ##
  ## Returns a seq of ChangedFile descriptors for every file that changed.
  let candidates =
    if ext.len > 0: tree.filterByExt(ext)
    else: tree.allFiles

  for node in candidates:
    let current =
      try: getLastModificationTime(node.name)
      except OSError: continue

    if current != node.lastModified:
      result.add(ChangedFile(node: node,
                             oldModTime: node.lastModified,
                             newModTime: current))
      node.lastModified = current

proc refresh*(tree: var FileTree) =
  ## Fully rebuilds the tree from disk.
  ## Useful when external processes may have added or removed files that
  ## `detectChanges` cannot see (it only tracks already-known nodes).
  tree = newFileTree(tree.root.name)

# ---------------------------------------------------------------------------
# Debug / pretty-print
# ---------------------------------------------------------------------------

proc printTree*(node: FileNode, indent: int = 0) =
  ## Recursively prints the tree to stdout for debugging purposes.
  let prefix = "  ".repeat(indent)
  case node.kind
  of fnDir:
    echo prefix & "[" & lastPathPart(node.name) & "]"
    for d in node.dirs:  printTree(d, indent + 1)
    for f in node.files: printTree(f, indent + 1)
  of fnFile:
    echo prefix & lastPathPart(node.name)

