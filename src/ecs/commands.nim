import std/monotimes
import std/times
import std/algorithm

# --- Configuration & Types ---

const
  MAX_COMMANDS = 2_000_000
  MAP_CAPACITY = 16384
  INITIAL_CAPACITY = 64

type
  EntityId = uint64
  Payload = object
    eid: EntityId
    obj: DenseHandle
    data: pointer
    size: uint32

  CommandKey = uint64

  BatchEntry = object
    key: CommandKey
    count: uint32
    capacity: uint32
    when defined(js):
      data: seq[Payload]
    else:
      data: ptr UncheckedArray[Payload]
  BatchMap = object
    when defined(js):
      entries: seq[BatchEntry]
    else:
      entries: ptr UncheckedArray[BatchEntry]
    currentGeneration: uint8
    activeSignatures: seq[uint32]

  CommandBuffer* = object
    map: BatchMap
    cursor: int

func makeSignature(op: range[0..15], arch: range[0..65535], flags: range[
    0..1023]): uint32 {.inline.} =
  uint32((op shl 28) or (arch shl 12) or (flags shl 2))

func getOp(s: uint32): uint32 = s shr 28
func getArchetype(s: uint32): uint32 = (s shr 12) and ((1'u32 shl 12) - 1)

proc resize(entry: ptr BatchEntry) =
  let newCap = INITIAL_CAPACITY*(entry.capacity == 0).uint32 + entry.capacity * 2'u32
  when defined(js):
    entry.data.setLen(newCap.int)
  else:
    let size = newCap * sizeof(Payload).uint32
    entry.data = cast[ptr UncheckedArray[Payload]](realloc(entry.data, size))
    check(entry.data != nil, "Failed to reallocate memory for CommandBuffer BatchEntry")
  entry.capacity = newCap

proc initBatchMap(): BatchMap =
  when defined(js):
    result.entries = newSeq[BatchEntry](MAP_CAPACITY)
  else:
    let size = sizeof(BatchEntry) * MAP_CAPACITY
    result.entries = cast[ptr UncheckedArray[BatchEntry]](alloc0(size))
    check(result.entries != nil, "Failed to allocate memory for BatchMap entries")
  result.currentGeneration = 1
  result.activeSignatures = newSeqOfCap[uint32](1024)

proc destroy(map: var BatchMap) =
  when not defined(js):
    for i in 0..<MAP_CAPACITY:
      if map.entries[i].data != nil:
        dealloc(map.entries[i].data)
    dealloc(map.entries)
  else:
    map.entries = @[]

proc initCommandBuffer(): CommandBuffer =
  result.map = initBatchMap()

proc destroy(cb: var CommandBuffer) =
  cb.map.destroy()

proc addCommand(cb: var CommandBuffer, op: range[0..15], arch: uint16,
    flags: uint32, payload: Payload) {.inline.} =
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
