## sdl3/texture_pool.nim
##
## [FIX-8] allocPersistent / allocTransient: removed dead `pool.keyFor()` call.
##
## Original code:
##   result = pool.keyFor()       -- allocated a key, incremented nextKey
##   result = TextureKey(slot+1)  -- immediately overwrote result, so keyFor
##                                   was called only for the nextKey side-effect
##                                   but the generated key was discarded.
##
## This caused nextKey to drift: after N allocations nextKey was 2N+1 instead
## of N+1, so any code using keyFor directly for other purposes would assign
## non-contiguous keys. In practice allocPersistent and allocTransient are the
## only callers, so the only symptom was wasted key space; but it's still wrong.
##
## Fix: assign the key directly from slot+1 and update nextKey in one place.

import std/[tables, hashes]

type
  PoolEntryKind* = enum
    entryPersistent
    entryTransient
    entryFree

  PoolEntry* = object
    kind*:      PoolEntryKind
    rawPtr*:    pointer
    desc*:      SDLTextureDesc
    label*:     string
    refCount*:  int

type RecycleKey = tuple[w, h: int, fmt: SDLPixelFormat, acc: SDLTextureAccess]

proc recycleKey(desc: SDLTextureDesc): RecycleKey {.inline.} =
  (desc.width, desc.height, desc.format, desc.access)

type
  AllocTextureFn* = proc(desc: SDLTextureDesc): pointer {.closure.}
  FreeTextureFn*  = proc(raw: pointer) {.closure.}

  TexturePool* = object
    entries:    seq[PoolEntry]
    freeSlots:  seq[uint32]
    nextKey:    uint32
    recycleBin: Table[RecycleKey, seq[pointer]]
    allocFn*:   AllocTextureFn
    freeFn*:    FreeTextureFn

proc initTexturePool*(allocFn: AllocTextureFn;
                      freeFn:  FreeTextureFn): TexturePool =
  result.entries   = @[]
  result.freeSlots = @[]
  result.nextKey   = 1   ## 0 = InvalidTextureKey
  result.recycleBin = initTable[RecycleKey, seq[pointer]]()
  result.allocFn   = allocFn
  result.freeFn    = freeFn

proc allocSlot(pool: var TexturePool): uint32 =
  if pool.freeSlots.len > 0:
    result = pool.freeSlots.pop()
  else:
    result = uint32(pool.entries.len)
    pool.entries.add(PoolEntry())

## [FIX-8] Single helper that assigns key = slot+1 and keeps nextKey in sync.
proc assignKey(pool: var TexturePool; slot: uint32): TextureKey {.inline.} =
  let k = TextureKey(slot + 1)
  if uint32(k) >= pool.nextKey:
    pool.nextKey = uint32(k) + 1
  k

proc allocPersistent*(pool:  var TexturePool;
                      desc:  SDLTextureDesc;
                      label: string = ""): TextureKey =
  ## [FIX-8] No longer calls the now-removed keyFor().
  let raw  = pool.allocFn(desc)
  let slot = pool.allocSlot()
  pool.entries[slot] = PoolEntry(kind: entryPersistent, rawPtr: raw,
                                  desc: desc, label: label, refCount: 1)
  pool.assignKey(slot)

proc allocTransient*(pool:  var TexturePool;
                     desc:  SDLTextureDesc;
                     label: string = ""): TextureKey =
  ## [FIX-8] Same fix: single assignKey call.
  let rk  = recycleKey(desc)
  var raw: pointer
  if rk in pool.recycleBin and pool.recycleBin[rk].len > 0:
    raw = pool.recycleBin[rk].pop()
  else:
    raw = pool.allocFn(desc)
  let slot = pool.allocSlot()
  pool.entries[slot] = PoolEntry(kind: entryTransient, rawPtr: raw,
                                  desc: desc, label: label, refCount: 1)
  pool.assignKey(slot)

proc registerExternalPersistent*(pool:  var TexturePool;
                                  raw:   pointer;
                                  desc:  SDLTextureDesc;
                                  label: string): TextureKey =
  let slot = pool.allocSlot()
  pool.entries[slot] = PoolEntry(kind: entryPersistent, rawPtr: raw,
                                  desc: desc, label: label, refCount: 1)
  pool.assignKey(slot)

proc isValid*(pool: TexturePool; key: TextureKey): bool {.inline.} =
  let slot = uint32(key) - 1
  slot < uint32(pool.entries.len) and pool.entries[slot].kind != entryFree

proc entry*(pool: var TexturePool; key: TextureKey): ptr PoolEntry {.inline.} =
  assert pool.isValid(key), "TexturePool: invalid key " & $key
  addr pool.entries[uint32(key) - 1]

proc rawPtr*(pool: var TexturePool; key: TextureKey): pointer {.inline.} =
  if not pool.isValid(key): return nil   ## guard: return nil instead of assert
  pool.entry(key).rawPtr

proc desc*(pool: var TexturePool; key: TextureKey): SDLTextureDesc {.inline.} =
  pool.entry(key).desc

proc addRef*(pool: var TexturePool; key: TextureKey) =
  if not pool.isValid(key): return
  inc pool.entries[uint32(key) - 1].refCount

proc release*(pool: var TexturePool; key: TextureKey) =
  if not pool.isValid(key): return
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
    discard

proc flushRecycleBin*(pool: var TexturePool) =
  for rk, ptrs in pool.recycleBin.mpairs:
    for raw in ptrs:
      pool.freeFn(raw)
    ptrs.setLen(0)

proc teardown*(pool: var TexturePool) =
  for e in pool.entries:
    if e.kind != entryFree and e.rawPtr != nil:
      pool.freeFn(e.rawPtr)
  for rk, ptrs in pool.recycleBin.pairs:
    for raw in ptrs:
      pool.freeFn(raw)
  pool.entries.setLen(0)
  pool.freeSlots.setLen(0)
  pool.recycleBin.clear()