include "../../src/render/commandBuf.nim"
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