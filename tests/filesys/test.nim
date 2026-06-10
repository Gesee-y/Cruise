import unittest, os, times, strutils, sequtils
import ../../src/filesys/filesystem

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const TMP = "tmp_fs_test"

proc setup(): string =
  ## Creates a temporary directory tree on disk for testing and returns its path.
  ##
  ## Structure:
  ##   tmp_fs_test/
  ##     a/
  ##       b/
  ##         deep.txt
  ##       hello.txt
  ##       logo.png
  ##     c/
  ##       world.txt
  ##     root.txt
  removeDir(TMP)
  createDir(TMP)
  createDir(TMP / "a")
  createDir(TMP / "a" / "b")
  createDir(TMP / "c")
  writeFile(TMP / "root.txt",        "root")
  writeFile(TMP / "a" / "hello.txt", "hello")
  writeFile(TMP / "a" / "logo.png",  "fakepng")
  writeFile(TMP / "a" / "b" / "deep.txt", "deep")
  writeFile(TMP / "c" / "world.txt", "world")
  result = TMP

proc teardown() =
  removeDir(TMP)

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

suite "FileTree — construction":

  test "root node has correct path":
    let base = setup()
    let tree = newFileTree(base)
    check tree.root.name == absolutePath(base)
    check tree.root.kind == fnDir
    teardown()

  test "allFiles contains every file":
    let base = setup()
    let tree = newFileTree(base)
    # 4 files: root.txt, hello.txt, logo.png, deep.txt, world.txt
    check tree.allFiles.len == 5
    teardown()

  test "allDirs contains every directory (excluding root)":
    let base = setup()
    let tree = newFileTree(base)
    # dirs: a, a/b, c  — root itself is not in allDirs
    check tree.allDirs.len == 3
    teardown()

  test "nodes carry a valid lastModified timestamp":
    let base = setup()
    let tree = newFileTree(base)
    for f in tree.allFiles:
      check f.lastModified != fromUnix(0)
    teardown()


suite "FileTree — lookup":

  test "getDir returns the correct node":
    let base = setup()
    let tree = newFileTree(base)
    let node = tree.getDir("a")
    check node != nil
    check node.kind == fnDir
    teardown()

  test "getDir returns nil for unknown path":
    let base = setup()
    let tree = newFileTree(base)
    check tree.getDir("nonexistent") == nil
    teardown()

  test "getFile returns the correct node":
    let base = setup()
    let tree = newFileTree(base)
    let node = tree.getFile("root.txt")
    check node != nil
    check node.kind == fnFile
    teardown()

  test "getFile returns nil for unknown path":
    let base = setup()
    let tree = newFileTree(base)
    check tree.getFile("ghost.txt") == nil
    teardown()


suite "FileTree — filtering":

  test "filterByExt returns only matching files":
    let base = setup()
    let tree = newFileTree(base)
    let pngs = tree.filterByExt(".png")
    check pngs.len == 1
    check pngs[0].name.endsWith(".png")
    teardown()

  test "filterByExt with unknown extension returns empty":
    let base = setup()
    let tree = newFileTree(base)
    check tree.filterByExt(".xyz").len == 0
    teardown()

  test "filterDirByExt filters within a directory":
    let base = setup()
    let tree = newFileTree(base)
    let dirA = tree.getDir("a")
    check dirA != nil
    let txts = filterDirByExt(dirA, ".txt")
    check txts.len == 1
    check txts[0].name.endsWith("hello.txt")
    teardown()


suite "FileTree — createDir":

  test "creates directory on disk":
    let base = setup()
    var tree = newFileTree(base)
    tree.createDir("newdir")
    check dirExists(absolutePath(base / "newdir"))
    teardown()

  test "registers new node in allDirs":
    let base = setup()
    var tree = newFileTree(base)
    let before = tree.allDirs.len
    tree.createDir("newdir")
    check tree.allDirs.len == before + 1
    teardown()

  test "createDir is idempotent for existing dirs":
    let base = setup()
    var tree = newFileTree(base)
    tree.createDir("a")
    # No duplicate nodes should be added for an already-known directory.
    let countA = tree.allDirs.filterIt(it.name == absolutePath(base / "a")).len
    check countA == 1
    teardown()

  test "creates nested directories":
    let base = setup()
    var tree = newFileTree(base)
    tree.createDir("x/y/z")
    check dirExists(absolutePath(base / "x" / "y" / "z"))
    teardown()


suite "FileTree — createFile":

  test "creates file on disk with content":
    let base = setup()
    var tree = newFileTree(base)
    tree.createFile("new.txt", "hello nim")
    let absPath = absolutePath(base / "new.txt")
    check fileExists(absPath)
    check readFile(absPath) == "hello nim"
    teardown()

  test "registers new node in allFiles":
    let base = setup()
    var tree = newFileTree(base)
    let before = tree.allFiles.len
    tree.createFile("new.txt")
    check tree.allFiles.len == before + 1
    teardown()


suite "FileTree — copyFile":

  test "copy creates a new file on disk":
    let base = setup()
    var tree = newFileTree(base)
    tree.copyFile("root.txt", "root_copy.txt")
    check fileExists(absolutePath(base / "root_copy.txt"))
    teardown()

  test "copy registers new node in allFiles":
    let base = setup()
    var tree = newFileTree(base)
    let before = tree.allFiles.len
    tree.copyFile("root.txt", "root_copy.txt")
    check tree.allFiles.len == before + 1
    teardown()

  test "original file still exists after copy":
    let base = setup()
    var tree = newFileTree(base)
    tree.copyFile("root.txt", "root_copy.txt")
    check fileExists(absolutePath(base / "root.txt"))
    teardown()


suite "FileTree — moveFile":

  test "destination file exists after move":
    let base = setup()
    var tree = newFileTree(base)
    tree.moveFile("root.txt", "moved.txt")
    check fileExists(absolutePath(base / "moved.txt"))
    teardown()

  test "source file is gone after move":
    let base = setup()
    var tree = newFileTree(base)
    tree.moveFile("root.txt", "moved.txt")
    check not fileExists(absolutePath(base / "root.txt"))
    teardown()

  test "allFiles count stays the same after move":
    let base = setup()
    var tree = newFileTree(base)
    let before = tree.allFiles.len
    tree.moveFile("root.txt", "moved.txt")
    check tree.allFiles.len == before
    teardown()

  test "old node is removed from allFiles":
    let base = setup()
    var tree = newFileTree(base)
    let src = absolutePath(base / "root.txt")
    tree.moveFile("root.txt", "moved.txt")
    check tree.allFiles.filterIt(it.name == src).len == 0
    teardown()


suite "FileTree — deleteFile":

  test "file is removed from disk":
    let base = setup()
    var tree = newFileTree(base)
    tree.deleteFile("root.txt")
    check not fileExists(absolutePath(base / "root.txt"))
    teardown()

  test "node is removed from allFiles":
    let base = setup()
    var tree = newFileTree(base)
    let before = tree.allFiles.len
    tree.deleteFile("root.txt")
    check tree.allFiles.len == before - 1
    teardown()


suite "FileTree — deleteDir":

  test "directory is removed from disk":
    let base = setup()
    var tree = newFileTree(base)
    tree.deleteDir("c")
    check not dirExists(absolutePath(base / "c"))
    teardown()

  test "descendant files are removed from allFiles":
    let base = setup()
    var tree = newFileTree(base)
    tree.deleteDir("a")
    let absA = absolutePath(base / "a")
    check tree.allFiles.filterIt(it.name.startsWith(absA)).len == 0
    teardown()

  test "descendant dirs are removed from allDirs":
    let base = setup()
    var tree = newFileTree(base)
    tree.deleteDir("a")
    let absA = absolutePath(base / "a")
    check tree.allDirs.filterIt(it.name.startsWith(absA)).len == 0
    teardown()


suite "FileTree — detectChanges":

  test "no changes returns empty seq":
    let base = setup()
    var tree = newFileTree(base)
    let changes = tree.detectChanges()
    check changes.len == 0
    teardown()

  test "modified file is detected":
    let base = setup()
    var tree = newFileTree(base)
    sleep(10) # ensure mtime will differ
    let target = absolutePath(base / "root.txt")
    writeFile(target, "modified content")
    # Touch the mtime explicitly to guarantee a difference.
    setLastModificationTime(target, getTime())
    let changes = tree.detectChanges()
    check changes.len >= 1
    check changes.filterIt(it.node.name == target).len == 1
    teardown()

  test "detectChanges updates lastModified on changed node":
    let base = setup()
    var tree = newFileTree(base)
    sleep(10)
    let target = absolutePath(base / "root.txt")
    writeFile(target, "v2")
    setLastModificationTime(target, getTime())
    let changes = tree.detectChanges()
    # Second call should see no changes since lastModified was updated.
    let changes2 = tree.detectChanges()
    check changes2.len == 0
    teardown()

  test "detectChanges respects extension filter":
    let base = setup()
    var tree = newFileTree(base)
    sleep(10)
    let txtTarget = absolutePath(base / "root.txt")
    let pngTarget = absolutePath(base / "a" / "logo.png")
    writeFile(txtTarget, "changed")
    writeFile(pngTarget, "changedpng")
    setLastModificationTime(txtTarget, getTime())
    setLastModificationTime(pngTarget, getTime())
    let changes = tree.detectChanges(".png")
    check changes.len == 1
    check changes[0].node.name == pngTarget
    teardown()


suite "FileTree — refresh":

  test "refresh picks up externally added files":
    let base = setup()
    var tree = newFileTree(base)
    writeFile(absolutePath(base / "surprise.txt"), "external")
    tree.refresh()
    check tree.getFile("surprise.txt") != nil
    teardown()

  test "refresh removes externally deleted files":
    let base = setup()
    var tree = newFileTree(base)
    os.removeFile(absolutePath(base / "root.txt"))
    tree.refresh()
    check tree.getFile("root.txt") == nil
    teardown()