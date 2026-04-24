# Cruise Filesystem

A virtual file tree with OS-native change detection, built for game engines and editors.

## Why care?

With great games comes great compiles time, that's why it's almost a must to be able to reload resource without recompiling during game develeopment.
This module gives you a **persistent in-memory mirror** of a directory tree that stays in sync with disk automatically, and fires typed events when something changes, without sleeping, without busy-looping, and without missing rapid bursts of writes.

## Features

- **Virtual File system**: An in-memory mirror of a directory.

- **Repertory diffing**: Allowing to get the difference between you virtual file system and the actual files on disk.

- **OS-agnostic file watching**: The OS signal is used as a wake-up trigger to diff the repertory. 

- **Burst grouping**  
When multiple files change in rapid succession (e.g. a shader compiler writing several
outputs at once), the watcher drains all pending OS signals before diffing. The result
is a single batched event set instead of a flood of individual callbacks.

- **Extension filter**  
`newWatcher(tree, ext = ".png")` limits file callbacks to a specific extension.
Directory events always pass through regardless of the filter.

- **Game-loop friendly**  
`poll(timeout = 0)` is non-blocking and safe to call every frame. No threads are spawned.
The caller owns the loop.

## Quick start

```nim
import Cruise/src/filesys/filesystem

var tree = newFileTree("assets")
var w    = newWatcher(tree)

w.onEvent(proc(ev: FileEvent) =
  case ev.kind
  of fekCreated:  echo "created  ", ev.path
  of fekModified: echo "modified ", ev.path
  of fekDeleted:  echo "deleted  ", ev.path)

# In your game loop:
while true:
  w.poll(timeout = 100)
```
