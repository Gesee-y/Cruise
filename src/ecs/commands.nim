####################################################################################################################################################
############################################################# COMMAND BUFFER #######################################################################
####################################################################################################################################################
##
## Deferred command buffer for the Cruise ECS.
##
## Allows systems to queue structural changes (entity deletion, archetype
## migration) while iterating entities.  Changes are sorted by
## ``(op, archetype)`` signature and executed in bulk when ``flush()`` is
## called.
##
## The buffer uses a flat hash-map with open addressing and a signature-based
## key:
##
## .. code-block:: text
##   signature = op(4 bits) | archetype(16 bits) | flags(10 bits)
##
## Usage example
## =============
##
## .. code-block:: nim
##   import cruise/ecs/commands
##
##   var cb = initCommandBuffer()
##   cb.addCommand(DeleteOp.ord, archId, 0'u32, Payload(eid: entity.id))
##   # … later:
##   # flush(cb, world)

import ./types
export types

# ─── Signature helpers ──────────────────────────────────────────────────── #

func makeSignature*(op: range[0..15], arch: range[0..65535], flags: range[
    0..1023]): uint32 {.inline.} =
  ## Packs ``op``, ``arch`` and ``flags`` into a compact 32-bit key.
  uint32((op shl 28) or (arch shl 12) or (flags shl 2))

func getOp*(s: uint32): uint32 = s shr 28
func getArchetype*(s: uint32): uint32 = (s shr 12) and ((1'u32 shl 12) - 1)

# ─── BatchEntry operations ──────────────────────────────────────────────── #

proc resize*(entry: ptr BatchEntry) =
  ## Doubles the entry's payload capacity (initial INITIAL_CAPACITY).
  let newCap = INITIAL_CAPACITY.uint32 * (entry.capacity == 0).uint32 +
      entry.capacity * 2'u32
  when defined(js):
    entry.data.setLen(newCap.int)
  else:
    let size = newCap * sizeof(Payload).uint32
    entry.data = cast[ptr UncheckedArray[Payload]](realloc(entry.data, size))
    check(entry.data != nil, "Failed to reallocate memory for CommandBuffer BatchEntry")
  entry.capacity = newCap

proc initBatchMap*(): BatchMap =
  ## Allocate the flat hash-map used to group commands by signature.
  when defined(js):
    result.entries = newSeq[BatchEntry](MAP_CAPACITY)
  else:
    let size = sizeof(BatchEntry) * MAP_CAPACITY
    result.entries = cast[ptr UncheckedArray[BatchEntry]](alloc0(size))
    check(result.entries != nil, "Failed to allocate memory for BatchMap entries")
  result.currentGeneration = 1
  result.activeSignatures = newSeqOfCap[uint32](1024)

proc destroy*(map: var BatchMap) =
  ## Release all memory owned by the batch-map.
  when not defined(js):
    for i in 0..<MAP_CAPACITY:
      if map.entries[i].data != nil:
        dealloc(map.entries[i].data)
    dealloc(map.entries)
  else:
    map.entries = @[]

proc initCommandBuffer*(): CommandBuffer =
  ## Create a fresh command buffer.
  result.map = initBatchMap()

proc destroy*(cb: var CommandBuffer) =
  ## Release all resources held by the command buffer.
  cb.map.destroy()

proc addCommand*(cb: var CommandBuffer, op: range[0..15], arch: uint16,
    flags: uint32, payload: Payload) {.inline.} =
  ## Insert a command into the buffer. Commands with the same signature are
  ## batched together for efficient bulk processing.
  let sig = makeSignature(op, arch, flags)
  let targetKey = (CommandKey(cb.map.currentGeneration) shl 32) or CommandKey(sig)
  let mask = MAP_CAPACITY - 1
  let idx = int(sig) and mask
  let entryPtr = addr(cb.map.entries[idx])

  if entryPtr.key == targetKey:
    if entryPtr.count >= entryPtr.capacity:
      resize(entryPtr)
    entryPtr.data[entryPtr.count] = payload
    entryPtr.count.inc
  else:
    if entryPtr.key == 0:
      entryPtr.key = targetKey
      entryPtr.count = 0
      entryPtr.capacity = 0
      when not defined(js):
        entryPtr.data = nil
      cb.map.activeSignatures.add(sig)

      if entryPtr.count >= entryPtr.capacity: resize(entryPtr)
      entryPtr.data[entryPtr.count] = payload
      entryPtr.count.inc
    else:
      var scanIdx = idx
      while true:
        scanIdx = (scanIdx + 1) and mask
        let scanEntry = addr(cb.map.entries[scanIdx])

        if scanEntry.key == targetKey:
          if scanEntry.count >= scanEntry.capacity: resize(scanEntry)
          scanEntry.data[scanEntry.count] = payload
          scanEntry.count.inc
          return
        elif scanEntry.key == 0:
          scanEntry.key = targetKey
          scanEntry.count = 0
          scanEntry.capacity = 0
          when not defined(js):
            scanEntry.data = nil
          cb.map.activeSignatures.add(sig)
          if scanEntry.count >= scanEntry.capacity: resize(scanEntry)
          scanEntry.data[scanEntry.count] = payload
          scanEntry.count.inc
          return
