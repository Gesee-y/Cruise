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
    value: float32

  # OPTIMIZATION: Single 64-bit Key = Generation (High) | Signature (Low)
  # Cela permet une seule comparaison au lieu de deux.
  CommandKey = uint64

  BatchEntry = object
    key: CommandKey      # 8 octets (Gen + Sig)
    count: uint32        # 4 octets
    capacity: uint32     # 4 octets
    data: ptr UncheckedArray[Payload] # 8 octets
    # Total 24 octets. Padding automatique à 32.

  BatchMap = object
    entries: ptr UncheckedArray[BatchEntry] 
    currentGeneration: uint8
    activeSignatures: seq[uint32] # On stocke juste la signature (32 bits)

  CommandBuffer = object
    map: BatchMap
    cursor: int

func makeSignature(op: range[0..15], arch: range[0..65535], flags: range[0..1023]): uint32 {.inline.} =
  uint32((op shl 28) or (arch shl 12) or (flags shl 2))

proc resize(entry: ptr BatchEntry) =
  let newCap = INITIAL_CAPACITY*(entry.capacity==0).uint32 + entry.capacity * 2'u32
  entry.data = cast[ptr UncheckedArray[Payload]](realloc(entry.data, newCap * sizeof(Payload).uint32))
  entry.capacity = newCap

proc initBatchMap(): BatchMap =
  result.entries = cast[ptr UncheckedArray[BatchEntry]](alloc0(sizeof(BatchEntry) * MAP_CAPACITY))
  result.currentGeneration = 1
  result.activeSignatures = newSeqOfCap[uint32](1024)

proc destroy(map: var BatchMap) =
  for i in 0..<MAP_CAPACITY:
    if map.entries[i].data != nil:
      dealloc(map.entries[i].data)
  dealloc(map.entries)

proc initCommandBuffer(): CommandBuffer =
  result.map = initBatchMap()

proc destroy(cb: var CommandBuffer) =
  cb.map.destroy()

proc addCommand(cb: var CommandBuffer, op: range[0..15], arch: uint16, flags: uint32, payload: Payload) {.inline.} =
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
          scanEntry.data = nil
          cb.map.activeSignatures.add(sig)
          if scanEntry.count >= scanEntry.capacity: resize(scanEntry)
          scanEntry.data[scanEntry.count] = payload
          scanEntry.count.inc
          return

#[ --- Benchmark ---

proc runBenchmark() =
  var cb = initCommandBuffer()
  defer: cb.destroy()
  
  const NUM_COMMANDS = 2_000_000
  
  echo "--- Setup Benchmark (Merged Key 64-bit) ---"
  echo "Commandes: ", NUM_COMMANDS
  
  var dataPayloads: array[100, Payload]
  for i in 0..<100:
    dataPayloads[i] = Payload(eid: EntityId(i), value: float32(i))

  let t0 = getMonoTime()
  for i in 0..<NUM_COMMANDS:
    let op = i mod 4
    let arch = (i div 4) mod 10
    let flags = i mod 2
    
    cb.addCommand(cast[range[0..15]](op), cast[uint16](arch), uint32(flags), (dataPayloads[i mod 100]))
  
  let t1 = getMonoTime()
  let addTime = (t1 - t0).inMicroseconds
  echo "Ajout commandes: ", addTime, " us"
  
  let nsPerCmd = (addTime.float * 1000.0) / NUM_COMMANDS.float
  echo "=> ", nsPerCmd, " ns / commande."

  let t2 = getMonoTime()
  cb.process()
  let t3 = getMonoTime()
  echo "Traitement: ", (t3 - t2).inMicroseconds, " us"
  
  echo "Total: ", (t3 - t0).inMicroseconds, " us"

when isMainModule:
  runBenchmark()
]#