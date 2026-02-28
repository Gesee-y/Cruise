## resource_manager.nim
##
## Generic resource management system for renderer backends.
##
## Architecture:
##   CResource[T]      — typed handle (distinct uint64); what user code holds
##   ResourceHandle    — opaque uint64; what travels in command buffers / ECS
##   ResourceRegistry  — one per window/backend; owns all ResourceStore[T]s
##   ResourceStore[T]  — dense slot-map with generation tracking
##
## Handle layout (64 bits):
##   bits 63-54 : typeId     (10 bits → up to 1024 resource types)
##   bits 53-32 : generation (22 bits → ~4M reuses before wrap-around)
##   bits 31- 0 : index      (32 bits → up to 4G resources per type)
##
## Design rules:
##   - CResource[T] is the only thing user code should name explicitly.
##   - ResourceHandle is the stripped, opaque form used in data structures
##     that must not depend on T (command buffers, scene graphs, etc.).
##   - Resource types MUST be registered via `registerType` before use.
##   - Generation counters detect use-after-destroy (dangling handle check).

import std/[tables, macros]

# ---------------------------------------------------------------------------
# Constants — bit layout
# ---------------------------------------------------------------------------

const
  TypeIdBits*    = 10
  GenerationBits = 22
  IndexBits      = 32

  TypeIdShift*    = GenerationBits + IndexBits        # 54
  GenerationShift = IndexBits                         # 32

  TypeIdMask*    = uint64((1 shl TypeIdBits)    - 1)
  GenerationMask = uint64((1 shl GenerationBits) - 1)
  IndexMask      = uint64(0xFFFF_FFFF'u64)

  MaxTypes*     = 1 shl TypeIdBits      ## Hard cap on distinct resource types.
  InvalidHandle = 0u64                  ## Sentinel — never a valid handle.

# ---------------------------------------------------------------------------
# TypeId
# ---------------------------------------------------------------------------

type TypeId* = distinct uint32

proc `==`*(a, b: TypeId): bool {.borrow.}
proc `$`*(t: TypeId): string = "TypeId(" & $uint32(t) & ")"

# ---------------------------------------------------------------------------
# ResourceHandle  — opaque, type-erased, safe to store anywhere
# ---------------------------------------------------------------------------

type ResourceHandle* = distinct uint64

proc isNullHandle*(h: ResourceHandle): bool {.inline.} =
  uint64(h) == InvalidHandle

proc `==`*(a, b: ResourceHandle): bool {.borrow.}
proc `$`*(h: ResourceHandle): string = "ResourceHandle(" & $uint64(h) & ")"

# Internal handle field accessors.
proc handleTypeId*(h: ResourceHandle): TypeId {.inline.} =
  TypeId(uint32((uint64(h) shr TypeIdShift) and TypeIdMask))

proc handleGeneration*(h: ResourceHandle): uint32 {.inline.} =
  uint32((uint64(h) shr GenerationShift) and GenerationMask)

proc handleIndex*(h: ResourceHandle): uint32 {.inline.} =
  uint32(uint64(h) and IndexMask)

proc buildHandle(typeId: TypeId, generation, index: uint32): ResourceHandle {.inline.} =
  let packed =
    (uint64(typeId)    shl TypeIdShift)    or
    (uint64(generation) shl GenerationShift) or
    uint64(index)
  ResourceHandle(packed)

# ---------------------------------------------------------------------------
# CResource[T]  — typed handle; the primary user-facing type
##
## `CResource[T]` is a `distinct uint64` wrapping the same bit layout as
## `ResourceHandle`.  The type parameter T is purely compile-time — it
## carries zero runtime overhead but prevents mixing handles of different
## resource types.
##
## Conversion:
##   toHandle(h)        CResource[T] → ResourceHandle   (strip type, for commands)
##   toResource[T](h)   ResourceHandle → CResource[T]   (restore type, in backend)
# ---------------------------------------------------------------------------

type CResource*[T] = distinct uint64

proc isNull*[T](h: CResource[T]): bool {.inline.} =
  uint64(h) == InvalidHandle

proc toHandle*[T](h: CResource[T]): ResourceHandle {.inline.} =
  ## Strip the type parameter — use when storing the handle in a command,
  ## scene graph, or any structure that must be independent of T.
  ResourceHandle(uint64(h))

proc toResource*[T](h: ResourceHandle): CResource[T] {.inline.} =
  ## Restore the type parameter — use inside backend execution code where
  ## the concrete resource type is statically known.
  CResource[T](uint64(h))

proc `==`*[T](a, b: CResource[T]): bool {.inline.} =
  uint64(a) == uint64(b)

proc `$`*[T](h: CResource[T]): string =
  "CResource[" & $typeof(T) & "](0x" & $uint64(h) & ")"

# Expose the same field accessors on CResource for convenience.
proc resourceTypeId*[T](h: CResource[T]): TypeId {.inline.} =
  h.toHandle.handleTypeId

proc resourceGeneration*[T](h: CResource[T]): uint32 {.inline.} =
  h.toHandle.handleGeneration

proc resourceIndex*[T](h: CResource[T]): uint32 {.inline.} =
  h.toHandle.handleIndex

# ---------------------------------------------------------------------------
# ResourceStore[T]  — dense slot-map with generation tracking
##
## Resources are stored in a contiguous `seq[T]` for cache-friendliness.
## Freed slots are recycled through a free-list; the generation counter on
## each slot is incremented at every recycle so stale handles are detectable.
##
## Slot layout:
##   data[i]        — the actual resource value
##   generations[i] — current generation of slot i
##   freeList       — stack of slot indices available for reuse
# ---------------------------------------------------------------------------

type ResourceStore[T] = object
  data:        seq[T]
  generations: seq[uint32]
  freeList:    seq[uint32]

proc initResourceStore[T](): ResourceStore[T] =
  ResourceStore[T](data: @[], generations: @[], freeList: @[])

proc allocSlot[T](store: var ResourceStore[T]): tuple[index, generation: uint32] =
  ## Claim a slot, either from the free-list or by growing the store.
  if store.freeList.len > 0:
    let idx = store.freeList.pop()
    result = (idx, store.generations[idx])
  else:
    let idx = uint32(store.data.len)
    store.data.add(default(T))
    store.generations.add(1u32)   # generation starts at 1; 0 is reserved for null
    result = (idx, 1u32)

proc freeSlot[T](store: var ResourceStore[T], index: uint32) =
  ## Return slot `index` to the free-list and bump its generation so
  ## any existing handle pointing to it becomes stale.
  store.generations[index] =
    if store.generations[index] >= uint32(GenerationMask):
      1u32   # wrap-around back to 1, never 0
    else:
      store.generations[index] + 1
  store.freeList.add(index)

proc isValidSlot[T](store: ResourceStore[T], index, generation: uint32): bool {.inline.} =
  index < uint32(store.data.len) and store.generations[index] == generation

proc getPtr[T](store: var ResourceStore[T], index: uint32): ptr T {.inline.} =
  addr store.data[index]

# ---------------------------------------------------------------------------
# StoreEntry  — type-erased wrapper around ResourceStore[T]
##
## Mirrors the BatchHandle pattern: closures capture T at registration time
## so the registry itself stays non-generic.
##
## Procs exposed through closures:
##   alloc()                → (index, generation) — reserve a slot
##   write(index, src)      → copy `src` into slot `index`
##   free(index)            → release slot, bump generation
##   valid(index, gen)      → generation check
##   getPtr(index)          → raw pointer to the resource data
##   destroy()              → free all internal memory (registry teardown)
# ---------------------------------------------------------------------------

type
  AllocResult  = tuple[index, generation: uint32]
  RawPtr       = pointer

  StoreEntry* = ref object
    ## Opaque handle to a `ResourceStore[T]`.  All operations go through
    ## closures so the registry table needs no type parameter.
    allocFn:   proc(): AllocResult                           {.closure.}
    writeFn:   proc(index: uint32, src: RawPtr)              {.closure.}
    freeFn:    proc(index: uint32)                           {.closure.}
    validFn:   proc(index, generation: uint32): bool         {.closure.}
    getPtrFn:  proc(index: uint32): RawPtr                   {.closure.}
    destroyFn: proc()                                        {.closure.}

proc newStoreEntry[T](): StoreEntry =
  ## Build a fully typed `StoreEntry` for resource type `T`.
  ## The store is heap-allocated and kept alive by the closures.
  var store = initResourceStore[T]()
  GC_ref(store)

  StoreEntry(
    allocFn: proc(): AllocResult =
      store.allocSlot(),

    writeFn: proc(index: uint32, src: RawPtr) =
      store.data[index] = cast[T](src),

    freeFn: proc(index: uint32) =
      store.freeSlot(index),

    validFn: proc(index, generation: uint32): bool =
      store.isValidSlot(index, generation),

    getPtrFn: proc(index: uint32): RawPtr =
      cast[RawPtr](store.getPtr(index)),

    destroyFn: proc() =
      GC_unref(store)
  )

# ---------------------------------------------------------------------------
# ResourceRegistry
##
## One registry per window / backend.  Holds one StoreEntry per registered
## resource type, indexed by TypeId for O(1) lookup.
##
## TypeIds are assigned sequentially at `registerType` call time.
## The registry is intentionally non-generic — user code passes CResource[T]
## and the compiler resolves T; the registry only sees uint64 indices.
# ---------------------------------------------------------------------------

type ResourceRegistry* = object
  stores:      array[MaxTypes, StoreEntry]   ## nil = type not registered yet
  nextTypeId:  uint32

proc initResourceRegistry*(): ResourceRegistry =
  ResourceRegistry(nextTypeId: 1u32)   # 0 is reserved for "no type"

proc registerType*[T](reg: var ResourceRegistry): TypeId =
  ## Register resource type `T` and return its stable `TypeId`.
  ## Must be called once per type before any create/get/destroy call.
  ## Calling twice for the same T is a logic error (not checked — keep it fast).
  assert reg.nextTypeId < uint32(MaxTypes),
    "ResourceRegistry: exceeded maximum number of resource types (" & $MaxTypes & ")"
  let tid = TypeId(reg.nextTypeId)
  reg.stores[reg.nextTypeId] = newStoreEntry[T]()
  inc reg.nextTypeId
  tid

proc create*[T](reg: var ResourceRegistry, typeId: TypeId, value: T): CResource[T] =
  ## Allocate a new resource slot, write `value` into it, and return a
  ## typed handle.  The returned `CResource[T]` is valid until `destroy` is
  ## called on it.
  let entry = reg.stores[uint32(typeId)]
  assert entry != nil, "ResourceRegistry.create: type not registered"

  let (index, generation) = entry.allocFn()
  var v = value
  entry.writeFn(index, addr v)

  CResource[T](uint64(buildHandle(typeId, generation, index)))

proc isValid*[T](reg: ResourceRegistry, h: CResource[T]): bool =
  ## Return `true` if `h` refers to a live resource.
  ## Returns `false` for null handles and destroyed (stale) handles.
  if h.isNull: return false
  let entry = reg.stores[uint32(h.resourceTypeId)]
  if entry == nil: return false
  entry.validFn(h.resourceIndex, h.resourceGeneration)

proc isValid*(reg: ResourceRegistry, h: ResourceHandle): bool =
  ## Opaque-handle overload — useful in backend execution code.
  if h.isNullHandle: return false
  let entry = reg.stores[uint32(h.handleTypeId)]
  if entry == nil: return false
  entry.validFn(h.handleIndex, h.handleGeneration)

proc get*[T](reg: var ResourceRegistry, h: CResource[T]): ptr T =
  ## Return a pointer to the resource data.
  ## Asserts that the handle is valid — call `isValid` first if unsure.
  assert reg.isValid(h), "ResourceRegistry.get: invalid or stale handle"
  let entry = reg.stores[uint32(h.resourceTypeId)]
  cast[ptr T](entry.getPtrFn(h.resourceIndex))

proc get*[T](reg: var ResourceRegistry, h: ResourceHandle): ptr T =
  ## Opaque-handle overload.  `T` must match the type the handle was created
  ## with — the registry cannot verify this at runtime.
  assert reg.isValid(h), "ResourceRegistry.get: invalid or stale handle"
  let entry = reg.stores[uint32(h.handleTypeId)]
  cast[ptr T](entry.getPtrFn(h.handleIndex))

proc destroy*[T](reg: var ResourceRegistry, h: CResource[T]) =
  ## Release the resource at `h`.  Any existing copies of `h` become stale;
  ## `isValid` will return `false` for them after this call.
  assert reg.isValid(h), "ResourceRegistry.destroy: invalid or stale handle"
  let entry = reg.stores[uint32(h.resourceTypeId)]
  entry.freeFn(h.resourceIndex)

proc destroy*(reg: var ResourceRegistry, h: ResourceHandle) =
  ## Opaque-handle overload.
  assert reg.isValid(h), "ResourceRegistry.destroy: invalid or stale handle"
  let entry = reg.stores[uint32(h.handleTypeId)]
  entry.freeFn(h.handleIndex)

proc teardown*(reg: var ResourceRegistry) =
  ## Release all stores and their resources.  Call when the window/backend
  ## is shut down.  The registry must not be used after this.
  for i in 0 ..< MaxTypes:
    if reg.stores[i] != nil:
      reg.stores[i].destroyFn()
      reg.stores[i] = nil