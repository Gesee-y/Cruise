## sdl3/texture_pool.nim
##
## Texture pool: allocates, recycles, and manages SDL_Texture lifetimes.
##
## Design:
##   - All SDL_Texture* are stored here, indexed by a TextureKey.
##   - Keys are assigned at allocation; stable across the pool's lifetime.
##   - Frame-transient textures (render targets used by the graph) are
##     tagged and recycled into a free-list keyed by (w, h, format, access).
##   - Persistent textures (loaded assets) are never recycled automatically.
##
## The pool does NOT call SDL — that indirection is the backend's job.
## Instead it stores the raw pointer and calls user-supplied alloc/free procs
## so the module stays testable without a live SDL context.

import std/[tables, hashes]
import ./types


# ---------------------------------------------------------------------------
# PoolEntry — one slot in the pool
# ---------------------------------------------------------------------------

type
  PoolEntryKind* = enum
    entryPersistent   ## Asset textures — never auto-recycled
    entryTransient    ## Render-target textures — recycled per frame
    entryFree         ## Slot available for reuse

  PoolEntry* = object
    kind*:      PoolEntryKind
    rawPtr*:    pointer          ## SDL_Texture* (opaque here)
    desc*:      SDLTextureDesc
    label*:     string           ## debug name
    refCount*:  int              ## for shared textures

# ---------------------------------------------------------------------------
# Recycle bin key — textures are compatible if (w, h, format, access) match
# ---------------------------------------------------------------------------

type RecycleKey = tuple[w, h: int, fmt: SDLPixelFormat, acc: SDLTextureAccess]

proc recycleKey(desc: SDLTextureDesc): RecycleKey {.inline.} =
  (desc.width, desc.height, desc.format, desc.access)

# ---------------------------------------------------------------------------
# TexturePool
# ---------------------------------------------------------------------------

type
  AllocTextureFn* = proc(desc: SDLTextureDesc): pointer {.closure.}
  FreeTextureFn*  = proc(raw: pointer) {.closure.}

  TexturePool* = object
    entries:    seq[PoolEntry]
    freeSlots:  seq[uint32]         ## recycled PoolEntry indices
    nextKey:    uint32

    ## Recycle bin: map from descriptor signature → list of free raw ptrs
    recycleBin: Table[RecycleKey, seq[pointer]]

    allocFn*:   AllocTextureFn
    freeFn*:    FreeTextureFn

proc initTexturePool*(allocFn: AllocTextureFn,
                      freeFn:  FreeTextureFn): TexturePool =
  result.entries  = @[]
  result.freeSlots = @[]
  result.nextKey  = 1   # 0 = InvalidTextureKey
  result.recycleBin = initTable[RecycleKey, seq[pointer]]()
  result.allocFn  = allocFn
  result.freeFn   = freeFn

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc allocSlot(pool: var TexturePool): uint32 =
  if pool.freeSlots.len > 0:
    result = pool.freeSlots.pop()
  else:
    result = uint32(pool.entries.len)
    pool.entries.add(PoolEntry())

proc keyFor(pool: var TexturePool): TextureKey =
  result = TextureKey(pool.nextKey)
  inc pool.nextKey

# ---------------------------------------------------------------------------
# Allocation
# ---------------------------------------------------------------------------

proc allocPersistent*(pool:  var TexturePool,
                      desc:  SDLTextureDesc,
                      label: string = ""): TextureKey =
  ## Allocate a texture that lives until explicitly freed.
  let raw  = pool.allocFn(desc)
  let slot = pool.allocSlot()
  pool.entries[slot] = PoolEntry(kind: entryPersistent, rawPtr: raw,
                                  desc: desc, label: label, refCount: 1)
  result = pool.keyFor()
  # store key → slot mapping: we re-use the slot index as the key value
  # so key == slot+1 (key 0 is invalid, key n maps to slot n-1)
  # Actually simpler: key == slot so we offset nextKey by 1 already.
  # Re-derive: we want key.uint32 == slot, but nextKey started at 1.
  # Fix: assign key directly.
  result = TextureKey(slot + 1)   # canonical mapping: slot = key-1
  pool.nextKey = max(pool.nextKey, uint32(result) + 1)

proc allocTransient*(pool:  var TexturePool,
                     desc:  SDLTextureDesc,
                     label: string = ""): TextureKey =
  ## Allocate a transient render-target texture.
  ## Tries the recycle bin first to avoid unnecessary GPU allocations.
  let rk  = recycleKey(desc)
  var raw: pointer

  if rk in pool.recycleBin and pool.recycleBin[rk].len > 0:
    raw = pool.recycleBin[rk].pop()
  else:
    raw = pool.allocFn(desc)

  let slot = pool.allocSlot()
  pool.entries[slot] = PoolEntry(kind: entryTransient, rawPtr: raw,
                                  desc: desc, label: label, refCount: 1)
  result = TextureKey(slot + 1)
  pool.nextKey = max(pool.nextKey, uint32(result) + 1)

proc registerExternalPersistent*(pool: var TexturePool,
    raw: pointer, desc: SDLTextureDesc, label: string): TextureKey =
  ## Take ownership of an already-created `SDL_Texture*` (e.g. from `SDL_CreateTextureFromSurface`).
  let slot = pool.allocSlot()
  pool.entries[slot] = PoolEntry(kind: entryPersistent, rawPtr: raw,
                                  desc: desc, label: label, refCount: 1)
  result = TextureKey(slot + 1)
  pool.nextKey = max(pool.nextKey, uint32(result) + 1)

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------

proc isValid*(pool: TexturePool, key: TextureKey): bool {.inline.} =
  let slot = uint32(key) - 1
  slot < uint32(pool.entries.len) and pool.entries[slot].kind != entryFree

proc entry*(pool: var TexturePool, key: TextureKey): ptr PoolEntry {.inline.} =
  assert pool.isValid(key), "TexturePool: invalid key " & $key
  addr pool.entries[uint32(key) - 1]

proc rawPtr*(pool: var TexturePool, key: TextureKey): pointer {.inline.} =
  pool.entry(key).rawPtr

proc desc*(pool: var TexturePool, key: TextureKey): SDLTextureDesc {.inline.} =
  pool.entry(key).desc

# ---------------------------------------------------------------------------
# Reference counting (for shared persistent textures)
# ---------------------------------------------------------------------------

proc addRef*(pool: var TexturePool, key: TextureKey) =
  inc pool.entries[uint32(key) - 1].refCount

proc release*(pool: var TexturePool, key: TextureKey) =
  ## Decrement refcount. If it hits zero, destroy (persistent) or recycle
  ## (transient) the texture.
  let slot = uint32(key) - 1
  dec pool.entries[slot].refCount
  if pool.entries[slot].refCount > 0: return

  let e = pool.entries[slot]
  case e.kind
  of entryPersistent:
    pool.freeFn(e.rawPtr)
    pool.entries[slot] = PoolEntry(kind: entryFree)
    pool.freeSlots.add(slot)

  of entryTransient:
    let rk = recycleKey(e.desc)
    if rk notin pool.recycleBin:
      pool.recycleBin[rk] = @[]
    pool.recycleBin[rk].add(e.rawPtr)
    pool.entries[slot] = PoolEntry(kind: entryFree)
    pool.freeSlots.add(slot)

  of entryFree:
    discard   # already freed — no-op

# ---------------------------------------------------------------------------
# Frame lifecycle
# ---------------------------------------------------------------------------

proc flushRecycleBin*(pool: var TexturePool) =
  ## Call once per N frames to actually destroy recycled transient textures
  ## that haven't been claimed. Prevents unbounded growth of the recycle bin.
  for rk, ptrs in pool.recycleBin.mpairs:
    for raw in ptrs:
      pool.freeFn(raw)
    ptrs.setLen(0)

# ---------------------------------------------------------------------------
# Full teardown
# ---------------------------------------------------------------------------

proc teardown*(pool: var TexturePool) =
  ## Destroy every live texture — call when the SDL renderer shuts down.
  for e in pool.entries:
    if e.kind != entryFree and e.rawPtr != nil:
      pool.freeFn(e.rawPtr)
  for rk, ptrs in pool.recycleBin.pairs:
    for raw in ptrs:
      pool.freeFn(raw)
  pool.entries.setLen(0)
  pool.freeSlots.setLen(0)
  pool.recycleBin.clear()
