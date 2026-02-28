###########################################################################################################################
##################################################### COMMAND BUFFER ######################################################
###########################################################################################################################

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

