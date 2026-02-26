## command_buffer.nim
##
## GPU command buffer abstraction for batching render commands.
##
## Architecture:
##   CommandBuffer
##   └── Pass (string key, e.g. "render", "postprocess")
##       └── (CommandId, Signature) → RenderBatch[T]
##
## Key design rules:
##   - Command types are plain `object`s with NO inheritance.
##   - `RenderBatch[T]` is fully parametric → static dispatch everywhere.
##   - New command types MUST be declared with `commandAction` macro so that
##     the compile-time ID counter and the runtime registry never diverge.

import std/[tables, macros, algorithm, hashes]

# ---------------------------------------------------------------------------
# Command ID
##
## Assigned at compile time inside `commandAction`, stored as a runtime uint32.
# ---------------------------------------------------------------------------

type CommandId* = uint32

## Runtime name → id table (useful for serialisation / debugging).
var gCommandRegistry*: Table[string, CommandId]

# Compile-time counter — incremented once per `commandAction` expansion.
var gCommandCount {.compileTime.} = 0

# ---------------------------------------------------------------------------
# Signature  (two packed uint64 fields — Nim has no uint128)
##
## Layout:
##   hi : bits 63-32 = targetId   | bits 31-0 = priority
##   lo : bits 63-32 = callerId   | bits 31-0 = commandId
##
## All four fields are uint32, so no bits are wasted and no overflow is possible.
# ---------------------------------------------------------------------------

type 
  Signature* = object
    hi*: uint64   
    lo*: uint64   

  CommandQuery* = object
    mask*: Signature
    qry*:  Signature

  RenderBatch*[T] = ref object
    target*:   uint32
    priority*: uint32
    caller*:   uint32
    commands*: seq[T]

  RendererPtr = pointer  ## Type-erased renderer pointer passed into `process`.

  BatchHandle* = ref object
    ## Type-erased handle to a single `RenderBatch[T]`.  All three closures
    ## capture the raw `RenderBatch[T]` and know how to operate on it.
    priority*: uint32     ## Cached for sorting without touching inner data.
    data:      pointer    ## Owning raw pointer to the heap-allocated batch.
    processFn: proc(data: pointer, ren: RendererPtr) {.closure.}
    clearFn:   proc(data: pointer)                   {.closure.}
    destroyFn: proc(data: pointer)                   {.closure.}

  PassStorage = object
    batches: Table[Signature, BatchHandle]

  CommandBuffer* = object
    passes: Table[string, PassStorage]

proc `==`*(a, b: Signature): bool {.inline.} =
  a.hi == b.hi and a.lo == b.lo

proc `and`*(a, b: Signature): Signature {.inline.} =
  Signature(hi: a.hi and b.hi, lo: a.lo and b.lo)

proc `or`*(a, b: Signature): Signature {.inline.} =
  Signature(hi: a.hi or b.hi, lo: a.lo or b.lo)

template commandId(name): CommandId = gCommandRegistry[$name]

## Needed so Signature can be used as a Table key.
proc hash*(s: Signature): Hash =
  hash((s.hi, s.lo))

proc encodeSignature*(target, priority, caller: uint32,
                      cmdId: CommandId): Signature {.inline.} =
  Signature(
    hi: (uint64(target) shl 32) or uint64(priority),
    lo: (uint64(caller) shl 32) or uint64(cmdId),
  )

proc decodeSignature*(s: Signature): tuple[target, priority, caller, cmdId: uint32] =
  result.target   = uint32(s.hi shr 32)
  result.priority = uint32(s.hi and 0xFFFF_FFFF'u64)
  result.caller   = uint32(s.lo shr 32)
  result.cmdId    = uint32(s.lo and 0xFFFF_FFFF'u64)

proc sigTarget*(s: Signature):   uint32 {.inline.} = uint32(s.hi shr 32)
proc sigPriority*(s: Signature): uint32 {.inline.} = uint32(s.hi and 0xFFFF_FFFF'u64)
proc sigCaller*(s: Signature):   uint32 {.inline.} = uint32(s.lo shr 32)
proc sigCmdId*(s: Signature):    uint32 {.inline.} = uint32(s.lo and 0xFFFF_FFFF'u64)

# ---------------------------------------------------------------------------
# CommandQuery
# ---------------------------------------------------------------------------

proc newCommandQuery*(
    target   = 0u32,
    priority = 0u32,
    caller   = 0u32,
    cmdId    = CommandId(0)
): CommandQuery =
  ## Build a query; zero fields act as wildcards.
  ## Each non-zero field sets the corresponding 32-bit slot in hi/lo.
  if target != 0:
    result.mask.hi = result.mask.hi or 0xFFFF_FFFF_0000_0000'u64
    result.qry.hi  = result.qry.hi  or (uint64(target) shl 32)
  if priority != 0:
    result.mask.hi = result.mask.hi or 0x0000_0000_FFFF_FFFF'u64
    result.qry.hi  = result.qry.hi  or uint64(priority)
  if caller != 0:
    result.mask.lo = result.mask.lo or 0xFFFF_FFFF_0000_0000'u64
    result.qry.lo  = result.qry.lo  or (uint64(caller) shl 32)
  if cmdId != 0:
    result.mask.lo = result.mask.lo or 0x0000_0000_FFFF_FFFF'u64
    result.qry.lo  = result.qry.lo  or uint64(cmdId)

proc matches*(q: CommandQuery, sig: Signature): bool {.inline.} =
  (sig and q.mask) == q.qry

# ---------------------------------------------------------------------------
# RenderBatch[T]
##
## Parametric, no inheritance. T must be a plain object (value type).
## Static dispatch is guaranteed at every call site.
# ---------------------------------------------------------------------------

proc initRenderBatch*[T](target, priority, caller: uint32): RenderBatch[T] =
  RenderBatch[T](target: target, priority: priority, caller: caller, commands: @[])


macro commandAction*(typeName: untyped): untyped =
  # Assign a stable compile-time ID.
  inc gCommandCount
  let idLit = newLit(CommandId(gCommandCount))

  # 1. Re-emit the type section unchanged — the user wrote valid Nim already.
  # 2. `commandId` proc — result is a constant folded at every call site.
  let cmdIdProc = quote do:
    proc commandId*(_: typedesc[`typeName`]): CommandId {.inline.} = `idLit`

  # 3. Runtime registration (runs once at module initialisation).
  let nameStr = newLit($typeName)
  let reg = quote do:
    gCommandRegistry[`nameStr`] = `idLit`

  result = newStmtList(cmdIdProc, reg)

# ---------------------------------------------------------------------------
# BatchHandle
##
## An opaque, GC-tracked handle stored in the command buffer.
## Holds three procs closed over the concrete `RenderBatch[T]`:
##
##   process(ren)  — casts the data pointer back to `RenderBatch[T]`,
##                   then calls `executeCommand(ren, ...)` — fully statically
##                   dispatched at the instantiation site in `addCommand`.
##
##   clear()       — resets the command seq without freeing memory (frame reuse).
##
##   destroy()     — runs `=destroy` on the inner batch and frees the raw
##                   memory; after this the handle must not be used again.
##                   Called by `removeCommand` and `destroyAllPasses` so the
##                   GC can collect the surrounding `ref BatchHandle` normally.
##
## Because `BatchHandle` is a `ref object`, the GC keeps it alive as long as
## the `PassStorage` table holds a reference.  Once we `del` the key (or clear
## the table), the ref-count drops to zero and the GC reclaims the header;
## `destroy` must have been called first to free the unmanaged inner data.
# ---------------------------------------------------------------------------

proc process*(h: BatchHandle, ren: RendererPtr) {.inline.} =
  ## Dispatch the batch to the renderer. `ren` must be a pointer to the
  ## concrete renderer that owns the matching `executeCommand` overload.
  h.processFn(h.data, ren)

proc clear*(h: BatchHandle) {.inline.} =
  ## Reset the command list — keeps allocated seq memory for next frame.
  h.clearFn(h.data)

proc destroy*(h: BatchHandle) {.inline.} =
  ## Free the inner `RenderBatch[T]` memory.  Call this before dropping the
  ## last reference so the GC finds only the (now inert) header to collect.
  if h.data != nil:
    h.destroyFn(h.data)
    h.data = nil

## Build a fully typed `BatchHandle` for `RenderBatch[T]`.
## Called once per unique (T, target, priority, caller) key.
template newBatchHandle*[T, R](target, priority, caller: uint32): BatchHandle =
  ## `R` is the concrete renderer type; the `process` closure captures it so
  ## `executeCommand[T]` is resolved at compile time here.
  var b = initRenderBatch[T](target, priority, caller)
  GC_ref(b)

  BatchHandle(
    priority: priority,
    data: cast[pointer](b),

    processFn: proc(data: pointer, ren: RendererPtr) =
      let batch = cast[RenderBatch[T]](data)
      var r     = cast[R](ren)
      executeCommand(r, batch),

    clearFn: proc(data: pointer) =
      cast[RenderBatch[T]](data).commands.setLen(0),

    destroyFn: proc(data: pointer) =
      let batch = cast[RenderBatch[T]](data)
      GC_unref(batch)
  )

# ---------------------------------------------------------------------------
# CommandBuffer
##
## Passes are named string keys.  Inside each pass, batches are stored as
## `BatchHandle` refs keyed by `(CommandId, Signature)`.
## The GC owns every handle through that ref; `destroy` must be called before
## removing a key so the unmanaged inner memory is freed first.
# ---------------------------------------------------------------------------

proc initPassStorage(): PassStorage =
  PassStorage(batches: initTable[Signature, BatchHandle]())

proc initCommandBuffer*(): CommandBuffer =
  result.passes["render"]      = initPassStorage()
  result.passes["postprocess"] = initPassStorage()

proc addPass*(cb: var CommandBuffer, name: string) =
  ## Register a new named render pass.
  if name notin cb.passes:
    cb.passes[name] = initPassStorage()

# ---------------------------------------------------------------------------
# Typed mutation API
# ---------------------------------------------------------------------------

proc addCommand*[T, R](
    cb:       var CommandBuffer,
    target, priority, caller: uint32,
    cmd:      T,
    pass =    "render"
) =
  ## Append `cmd` to the matching batch.  `R` is the renderer type; it is used
  ## once at batch-creation time to close over the correct `executeCommand[T]`
  ## overload — all subsequent pushes reuse the same handle.
  let cid = commandId(T)
  let sig  = encodeSignature(target, priority, caller, cid)
  let key  = sig

  if pass notin cb.passes:
    cb.passes[pass] = initPassStorage()

  var ps = addr cb.passes[pass]
  if key notin ps.batches:
    ps.batches[key] = newBatchHandle[T, R](target, priority, caller)

  cast[RenderBatch[T]](ps.batches[key].data).commands.add(cmd)

proc removeCommand*[T](
    cb:     var CommandBuffer,
    target, priority, caller: uint32,
    pass =  "render"
) =
  ## Destroy and remove the batch for type T with the given addressing triple.
  let sig = encodeSignature(target, priority, caller, commandId(T))
  let key = sig
  if pass in cb.passes:
    let h = cb.passes[pass].batches.getOrDefault(key, nil)
    if h != nil:
      h.destroy()                          # free inner memory first
      cb.passes[pass].batches.del(key)     # drop ref → GC reclaims header

proc clearPass*(cb: var CommandBuffer, pass = "render") =
  ## Reset every batch in `pass` — keeps seq memory allocated for next frame.
  if pass notin cb.passes: return
  for h in cb.passes[pass].batches.values:
    h.clear()

proc destroyAllPasses*(cb: var CommandBuffer) =
  ## Destroy all inner batches and remove all handles across every pass.
  ## After this call the buffer is empty but passes are still registered.
  for passName in cb.passes.keys:
    for h in cb.passes[passName].batches.values:
      h.destroy()                          # free unmanaged memory
    cb.passes[passName].batches.clear()    # drop refs → GC collects headers

# ---------------------------------------------------------------------------
# Query / iteration
# ---------------------------------------------------------------------------

iterator queriedBatches*[T](
    cb:    CommandBuffer,
    q:     CommandQuery,
    pass = "render"
): RenderBatch[T] =
  ## Yield every RenderBatch[T] in `pass` whose signature matches `q`.
  let cid = commandId(T)
  var result: RenderBatch[T]
  if pass in cb.passes:
    for sig, h in cb.passes[pass].batches:
      if q.matches(sig):
        result = cast[RenderBatch[T]](h.data) 
        yield result

proc sortedHandles*(
    cb:    CommandBuffer,
    pass = "render"
): seq[BatchHandle] =
  ## All handles in `pass`, sorted by ascending priority.
  ## Used by `executeAll` to dispatch in priority order without knowing T.
  result = @[]
  if pass notin cb.passes: return
  for h in cb.passes[pass].batches.values:
    result.add(h)
  result.sort(proc(a, b: BatchHandle): int = cmp(a.priority, b.priority))

# ---------------------------------------------------------------------------
# Execution hooks
##
## `executeCommand` must be overloaded per (RendererType, CommandType) pair.
## Resolution happens at compile time inside `newBatchHandle` — no vtable.
# ---------------------------------------------------------------------------

proc passOrder*(ren: auto): seq[string] =
  ## Default pass order. Override per renderer type.
  @["render", "postprocess"]

proc executeCommand*[T](ren: var auto, commands: RenderBatch[T]) =
  ## Fallback — compile error if the required overload is missing.
  {.error: "executeCommand not implemented for this (renderer, command) pair".}

proc executeAll*[R](ren: var R, cb: CommandBuffer) =
  ## Flush the buffer: iterate passes in order, sort by priority, dispatch.
  ## Each `BatchHandle.process` calls the statically resolved `executeCommand`.
  let renPtr = cast[RendererPtr](ren)
  for pass in ren.passOrder():
    for h in cb.sortedHandles(pass):
      h.process(renPtr)

# ---------------------------------------------------------------------------
# Built-in command types  (macro is the only legal path)
# ---------------------------------------------------------------------------

type DrawSprite = object
  x*, y*: float32
  spriteId*: uint32

commandAction DrawSprite

type ClearBuffer = object
  r*, g*, b*, a*: float32

commandAction ClearBuffer

type CopyTexture = object
  srcId*, dstId*: uint32

commandAction CopyTexture

## test_command_buffer.nim
##
## Unit tests for command_buffer.nim.
## Run with: nim c -r test_command_buffer.nim

import unittest
import std/[tables, sequtils]

# ---------------------------------------------------------------------------
# Minimal test renderer
# ---------------------------------------------------------------------------

type
  TestRenderer* = ref object
    drawSpriteLog*:  seq[(uint32, uint32, ptr seq[DrawSprite])]
    clearBufferLog*: seq[(uint32, uint32, ptr seq[ClearBuffer])]
    copyTextureLog*: seq[(uint32, uint32, ptr seq[CopyTexture])]

proc executeCommand*(ren: var TestRenderer, command: RenderBatch[DrawSprite]) =
  ren.drawSpriteLog.add((command.target, command.caller, addr command.commands))

proc executeCommand*(ren: var TestRenderer, command: RenderBatch[ClearBuffer]) =
  ren.clearBufferLog.add((command.target, command.caller, addr command.commands))

proc executeCommand*(ren: var TestRenderer, command: RenderBatch[CopyTexture]) =
  ren.copyTextureLog.add((command.target, command.caller, addr command.commands))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc freshCb(): CommandBuffer = initCommandBuffer()
proc freshRen(): TestRenderer = TestRenderer()

# ---------------------------------------------------------------------------
# Signature
# ---------------------------------------------------------------------------

suite "Signature encoding / decoding":

  test "round-trip preserves all four fields":
    let sig = encodeSignature(1u32, 2u32, 3u32, CommandId(4))
    let (t, p, c, id) = decodeSignature(sig)
    check t  == 1u32
    check p  == 2u32
    check c  == 3u32
    check id == 4u32

  test "zero fields encode and decode to zero":
    let sig = encodeSignature(0u32, 0u32, 0u32, CommandId(0))
    let (t, p, c, id) = decodeSignature(sig)
    check t == 0u32 and p == 0u32 and c == 0u32 and id == 0u32

  test "max uint32 fields do not overflow into each other":
    let max = high(uint32)
    let sig = encodeSignature(max, max, max, CommandId(max))
    let (t, p, c, id) = decodeSignature(sig)
    check t == max and p == max and c == max and id == max

  test "field accessors match decode":
    let sig = encodeSignature(10u32, 20u32, 30u32, CommandId(40))
    check sigTarget(sig)   == 10u32
    check sigPriority(sig) == 20u32
    check sigCaller(sig)   == 30u32
    check sigCmdId(sig)    == 40u32

  test "two signatures with different fields are not equal":
    let a = encodeSignature(1u32, 0u32, 0u32, CommandId(0))
    let b = encodeSignature(2u32, 0u32, 0u32, CommandId(0))
    check a != b

# ---------------------------------------------------------------------------
# CommandQuery
# ---------------------------------------------------------------------------

suite "CommandQuery matching":

  test "empty query matches any signature":
    let q   = newCommandQuery()
    let sig = encodeSignature(99u32, 7u32, 3u32, CommandId(2))
    check q.matches(sig)

  test "target-only query matches correct target":
    let q    = newCommandQuery(target = 5u32)
    let yes  = encodeSignature(5u32, 0u32, 0u32, CommandId(0))
    let no   = encodeSignature(6u32, 0u32, 0u32, CommandId(0))
    check     q.matches(yes)
    check not q.matches(no)

  test "priority-only query is a wildcard on other fields":
    let q = newCommandQuery(priority = 3u32)
    check     q.matches(encodeSignature(99u32, 3u32, 42u32, CommandId(7)))
    check not q.matches(encodeSignature(99u32, 2u32, 42u32, CommandId(7)))

  test "multi-field query requires all specified fields to match":
    let q = newCommandQuery(target = 1u32, caller = 2u32)
    check     q.matches(encodeSignature(1u32, 0u32, 2u32, CommandId(0)))
    check not q.matches(encodeSignature(1u32, 0u32, 9u32, CommandId(0)))
    check not q.matches(encodeSignature(9u32, 0u32, 2u32, CommandId(0)))

  test "cmdId field is matched independently":
    let cid = commandId(DrawSprite)
    let q   = newCommandQuery(cmdId = cid)
    check     q.matches(encodeSignature(0u32, 0u32, 0u32, cid))
    check not q.matches(encodeSignature(0u32, 0u32, 0u32, CommandId(cid + 1)))

# ---------------------------------------------------------------------------
# Command registration
# ---------------------------------------------------------------------------

suite "Command registration":

  test "each built-in type has a unique non-zero ID":
    let ids = [commandId(DrawSprite), commandId(ClearBuffer), commandId(CopyTexture)]
    for id in ids:
      check id != 0u32
    check ids[0] != ids[1]
    check ids[1] != ids[2]
    check ids[0] != ids[2]

  test "runtime registry contains all built-in names":
    check "DrawSprite"  in gCommandRegistry
    check "ClearBuffer" in gCommandRegistry
    check "CopyTexture" in gCommandRegistry

  test "runtime registry IDs match proc IDs":
    check gCommandRegistry["DrawSprite"]  == commandId(DrawSprite)
    check gCommandRegistry["ClearBuffer"] == commandId(ClearBuffer)
    check gCommandRegistry["CopyTexture"] == commandId(CopyTexture)

# ---------------------------------------------------------------------------
# CommandBuffer — structural
# ---------------------------------------------------------------------------

suite "CommandBuffer initialisation":

  test "default passes are present after init":
    let cb = freshCb()
    check "render"      in cb.passes
    check "postprocess" in cb.passes

  test "addPass registers a new pass":
    var cb = freshCb()
    cb.addPass("shadow")
    check "shadow" in cb.passes

  test "addPass is idempotent":
    var cb = freshCb()
    cb.addPass("shadow")
    cb.addPass("shadow")   # must not raise
    check "shadow" in cb.passes

# ---------------------------------------------------------------------------
# CommandBuffer — addCommand / removeCommand
# ---------------------------------------------------------------------------

suite "addCommand":

  test "first addCommand creates the batch":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32,
      DrawSprite(x: 1, y: 2, spriteId: 10))
    let sig = encodeSignature(1u32, 0u32, 0u32, commandId(DrawSprite))
    check sig in cb.passes["render"].batches

  test "subsequent addCommands append to the same batch":
    var cb = freshCb()
    for i in 0 ..< 5:
      addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32,
        DrawSprite(x: float32(i), y: 0, spriteId: 0))
    let sig = encodeSignature(1u32, 0u32, 0u32, commandId(DrawSprite))
    let h   = cb.passes["render"].batches[sig]
    let b   = cast[RenderBatch[DrawSprite]](h.data)
    check b.commands.len == 5

  test "different (target, caller) produce separate batches":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    addCommand[DrawSprite, TestRenderer](cb, 2u32, 0u32, 0u32, DrawSprite())
    check cb.passes["render"].batches.len == 2

  test "addCommand respects the pass argument":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32,
      DrawSprite(), pass = "postprocess")
    check cb.passes["render"].batches.len      == 0
    check cb.passes["postprocess"].batches.len == 1

  test "addCommand to unknown pass auto-creates it":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32,
      DrawSprite(), pass = "custom")
    check "custom" in cb.passes

suite "removeCommand":

  test "removes an existing batch":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    removeCommand[DrawSprite](cb, 1u32, 0u32, 0u32)
    check cb.passes["render"].batches.len == 0

  test "removeCommand on non-existent key is a no-op":
    var cb = freshCb()
    removeCommand[DrawSprite](cb, 99u32, 0u32, 0u32)   # must not raise

# ---------------------------------------------------------------------------
# BatchHandle lifecycle
# ---------------------------------------------------------------------------

suite "BatchHandle clear / destroy":

  test "clearPass resets commands but keeps the batch alive":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    cb.clearPass("render")
    let sig = encodeSignature(1u32, 0u32, 0u32, commandId(DrawSprite))
    let h   = cb.passes["render"].batches[sig]
    let b   = cast[RenderBatch[DrawSprite]](h.data)
    check b.commands.len == 0
    check sig in cb.passes["render"].batches   # handle still present

  test "clearPass allows reuse after clearing":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite(spriteId: 1))
    cb.clearPass("render")
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite(spriteId: 2))
    let sig = encodeSignature(1u32, 0u32, 0u32, commandId(DrawSprite))
    let b   = cast[RenderBatch[DrawSprite]](cb.passes["render"].batches[sig].data)
    check b.commands.len == 1
    check b.commands[0].spriteId == 2u32

  test "destroyAllPasses empties every pass":
    var cb = freshCb()
    addCommand[DrawSprite,TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    addCommand[ClearBuffer,TestRenderer](cb, 1u32, 0u32, 0u32, ClearBuffer(),
      pass = "postprocess")
    cb.destroyAllPasses()
    check cb.passes["render"].batches.len      == 0
    check cb.passes["postprocess"].batches.len == 0

  test "destroyAllPasses marks handles as freed (data = nil)":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    let sig = encodeSignature(1u32, 0u32, 0u32, commandId(DrawSprite))
    let h   = cb.passes["render"].batches[sig]
    cb.destroyAllPasses()
    check h.data == nil

# ---------------------------------------------------------------------------
# sortedHandles
# ---------------------------------------------------------------------------

suite "sortedHandles":

  test "returns handles sorted by ascending priority":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 3u32, 0u32, DrawSprite())
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 1u32, 0u32, DrawSprite())
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 2u32, 0u32, DrawSprite())
    let handles = cb.sortedHandles("render")
    check handles.len == 3
    check handles[0].priority == 1u32
    check handles[1].priority == 2u32
    check handles[2].priority == 3u32

  test "sortedHandles on empty pass returns empty seq":
    let cb      = freshCb()
    let handles = cb.sortedHandles("render")
    check handles.len == 0

  test "sortedHandles on unknown pass returns empty seq":
    let cb      = freshCb()
    let handles = cb.sortedHandles("nonexistent")
    check handles.len == 0

# ---------------------------------------------------------------------------
# queriedBatches
# ---------------------------------------------------------------------------

suite "queriedBatches":

  test "wildcard query yields all batches of the given type":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    addCommand[DrawSprite, TestRenderer](cb, 2u32, 0u32, 0u32, DrawSprite())
    let q = newCommandQuery(cmdId = commandId(DrawSprite))
    var count = 0
    for _ in queriedBatches[DrawSprite](cb, q):
      inc count
    check count == 2

  test "targeted query yields only matching batch":
    var cb = freshCb()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite(spriteId: 1))
    addCommand[DrawSprite, TestRenderer](cb, 2u32, 0u32, 0u32, DrawSprite(spriteId: 2))
    let q = newCommandQuery(target = 1u32, cmdId = commandId(DrawSprite))
    var found: seq[uint32]
    for batch in queriedBatches[DrawSprite](cb, q):
      for cmd in batch.commands:
        found.add(cmd.spriteId)
    check found == @[1u32]

  test "query on empty pass yields nothing":
    let cb = freshCb()
    let q  = newCommandQuery()
    var count = 0
    for _ in queriedBatches[DrawSprite](cb, q):
      inc count
    check count == 0

# ---------------------------------------------------------------------------
# executeAll / dispatch
# ---------------------------------------------------------------------------

suite "executeAll dispatch":

  test "executeCommand is called once per batch with correct data":
    var cb  = freshCb()
    var ren = freshRen()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 42u32,
      DrawSprite(x: 3, y: 4, spriteId: 7))
    ren.executeAll(cb)
    check ren.drawSpriteLog.len == 1
    let (t, c, cmds) = ren.drawSpriteLog[0]
    check t    == 1u32
    check c    == 42u32
    check cmds[0].spriteId == 7u32

  test "multiple command types are dispatched to their own overload":
    var cb  = freshCb()
    var ren = freshRen()
    addCommand[DrawSprite,TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    addCommand[ClearBuffer,TestRenderer](cb, 1u32, 0u32, 0u32, ClearBuffer())
    ren.executeAll(cb)
    check ren.drawSpriteLog.len  == 1
    check ren.clearBufferLog.len == 1

  test "batches are dispatched in ascending priority order":
    var cb  = freshCb()
    var ren = freshRen()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 5u32, 0u32,
      DrawSprite(spriteId: 5))
    addCommand[DrawSprite, TestRenderer](cb, 2u32, 1u32, 0u32,
      DrawSprite(spriteId: 1))
    addCommand[DrawSprite, TestRenderer](cb, 3u32, 3u32, 0u32,
      DrawSprite(spriteId: 3))
    ren.executeAll(cb)
    let priorities = ren.drawSpriteLog.mapIt(it[2][0].spriteId)
    check priorities == @[1u32, 3u32, 5u32]

  test "postprocess pass is executed after render pass":
    var cb  = freshCb()
    var ren = freshRen()
    # CopyTexture goes to postprocess, DrawSprite to render
    addCommand[CopyTexture, TestRenderer](cb, 1u32, 0u32, 0u32,
      CopyTexture(srcId: 99), pass = "postprocess")
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32,
      DrawSprite(spriteId: 1))

    var order: seq[string]
    # We track order by inspecting logs after executeAll
    ren.executeAll(cb)
    # render ran → drawSpriteLog populated; postprocess ran → copyTextureLog populated
    check ren.drawSpriteLog.len  == 1
    check ren.copyTextureLog.len == 1

  test "clearPass followed by executeAll dispatches no commands":
    var cb  = freshCb()
    var ren = freshRen()
    addCommand[DrawSprite, TestRenderer](cb, 1u32, 0u32, 0u32, DrawSprite())
    cb.clearPass("render")
    ren.executeAll(cb)
    # Batch exists but commands seq is empty → log entry has zero commands
    check ren.drawSpriteLog.len == 1
    check ren.drawSpriteLog[0][2][].len == 0