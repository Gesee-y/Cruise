####################################################################################################################################################
######################################################################## ECS TABLE #################################################################
####################################################################################################################################################

import tables, bitops, typetraits, hashes, sequtils, math

const
  MAX_COMPONENT_LAYER = 4
  PARTITION_ZONE_CAP = 10
  EVENT_ACTIVE = false
  UINT_BITS = sizeof(uint)*8
  BIT_DIVIDER = floor(log(UINT_BITS.float, 2.0)).int
  BIT_REMAINDER = UINT_BITS-1
  ## Bit shift used to extract block indices from packed IDs.
  BLK_SHIFT = 20
  ID_SHIFT = 32 - BLK_SHIFT
  ## Mask used to extract local indices from packed IDs.
  BLK_MASK = (1 shl BLK_SHIFT) - 1
  ID_MASK = (1 shl ID_SHIFT) - 1
  ## Default size (in elements) of a dense block.
  DEFAULT_BLK_SIZE = UINT_BITS*UINT_BITS
  ## Initial capacity of the sparse storage.
  INITIAL_SPARSE_SIZE = 10000

type 
  Range = object
    s,e:int

  ArchetypeMask = array[MAX_COMPONENT_LAYER, uint]

## ── Graduated safety checks ─────────────────────────────────────────────────
## Three severity levels for different build configurations:
##
##  checkWarn      — Debug builds only (no -d:release, no -d:danger).
##                   Emits a non-fatal warning via debugEcho.
##                   Use for near-limit situations, suspicious-but-safe state.
##
##  check          — Debug + Release (disabled by -d:danger).
##                   Raises AssertionDefect on violation.
##                   Use for errors that would silently corrupt ECS state.
##
##  checkCritical  — Always active, even under -d:danger.
##                   Raises Defect. Use for invariant violations that are
##                   *always* programming errors regardless of build mode
##                   (null dereference, OOB access, infinite loops, etc.)

template checkWarn*(code: untyped, msg: string) =
  ## Non-fatal warning emitted only in debug (un-optimised) builds.
  when not defined(release) and not defined(danger):
    if not (code):
      debugEcho "[ECS WARN] " & msg

template check*(code: untyped, msg: string) =
  ## Hard assertion active in debug + release, suppressed by -d:danger.
  when not defined(danger):
    doAssert code, "[ECS ERROR] " & msg

template checkCritical*(code: untyped, msg: string) =
  ## Always-active guard — fires even under -d:danger.
  ## Use for invariants whose violation is always a programming error.
  if unlikely(not (code)):
    raise newException(Defect, "[ECS CRITICAL] " & msg)

template onDanger*(code: untyped) =
  ## Code that executes only when NOT in -d:danger mode.
  when not defined(danger):
    code

include "hibitset.nim"

type
  ## Represent an independent filter that can be used narrow queries
  QueryFilter* = object

    # Dense Query
    dLayer*:HibitsetType

    # Sparse Query
    sLayer*:HibitsetType

include "fragment.nim"
include "entity.nim"
include "commands.nim"
include "mask.nim"
include "registry.nim"


type
  TableRange* = object
    r:Range
    block_idx:int

  TablePartition* = ref object
    zones:seq[TableRange]
    components:seq[int]
    fill_index:int

include "archetypes.nim"

type
  QueryKey* = tuple[incl: ArchetypeMask, excl: ArchetypeMask]
  QueryCacheEntry* = object
    version*: int
    nodes*: seq[ArchetypeNode]
    archs: set[uint16]

  ECSWorld* = ref object
    registry:ComponentRegistry
    entities*:seq[Entity]
    commandBufs:seq[CommandBuffer]
    evmanager: pointer
    handles*:seq[uint32]
    generations:seq[uint16]
    sparse_gens:seq[uint16]
    free_entities:seq[uint32]
    archGraph*:ArchetypeGraph
    free_list:seq[uint32]
    max_index:int
    blockCount:int
    queryCache*: Table[QueryKey, QueryCacheEntry]
    resources*: Table[string, pointer]

include "handles.nim"
include "entity_wrappers.nim"
include "events.nim"

template newECSWorld*(max_entities:int=1000000):ECSWorld =
  var w:ECSWorld
  new(w)
  checkWarn(max_entities > 0,
    "newECSWorld: max_entities must be > 0 (got " & $max_entities &
    "). The world will be created but cannot hold any entities.")
  checkWarn(max_entities <= 1_000_000_000,
    "newECSWorld: max_entities=" & $max_entities &
    " exceeds 1 billion. Initial capacities may cause OOM at startup.")
  #new(w.registry)
  w.archGraph = initArchetypeGraph()
  w.entities = newSeqofCap[Entity](max_entities)
  w.handles = newSeqofCap[uint32](max_entities)
  w.free_list = newSeqofCap[uint32](max_entities div 2)
  w.free_entities = newSeqofCap[uint32](max_entities div 2)
  w.generations = newSeqofCap[uint16](max_entities)
  w.sparse_gens = newSeqofCap[uint16](max_entities)
  
  var ev = initEventManager()
  GC_ref(ev)
  w.evmanager = cast[pointer](ev)

  w

####################################################################################################################################################
####################################################################### OPERATIONS #################################################################
####################################################################################################################################################

template events*(w: ECSWorld): EventManager = cast[EventManager](w.evmanager)

{.push inline.}

proc addResource*[T](w: var ECSWorld, r:T) =
  w.resources[$T] = cast[pointer](r)

proc getResource*[T](w: ECSWorld): T =
  let t = $T

  check(t in w.resources, "Error: Resource of type " & t & " not found.")
  cast[T](w.resources[$T])

proc unsafeGetResource*[T](w: ECSWorld): T =
  cast[T](w.resources[$T])

proc isEmpty(t:TableRange | ptr TableRange):bool = t.r.s == t.r.e
proc isFull(t:TableRange | ptr TableRange):bool = t.r.e - t.r.s == DEFAULT_BLK_SIZE

template getDHandle*(w: ECSWorld, i:untyped): DenseHandle = DenseHandle(widx: i.uint32, gen: w.generations[i], world: w)
template getDHandleFromID*(w: ECSWorld, i:untyped): DenseHandle = 
  var e = w.handles[i.toIdx]
  w.getDHandle(e)

proc getComponentId*(world:ECSWorld, t:typedesc):int =
  check($t in world.registry.cmap, "Component type '" & $t & "' is not registered. Call registerComponent first.")
  return world.registry.cmap[$t]

proc getArchetype*(w:ECSWorld, e:SomeEntity):ArchetypeNode =
  return w.archGraph.nodes[e.archetypeId]
proc getArchetype*(w:ECSWorld, d:DenseHandle):ArchetypeNode =
  return w.getArchetype(d.obj)

template makeId*(bid,idx:untyped):uint32 =
  (bid.uint32 shl ID_SHIFT) or idx.uint32

template makeId(i:int):uint32 =
  let bid = i.uint32 div DEFAULT_BLK_SIZE
  let idx = i.uint32 mod DEFAULT_BLK_SIZE

  (bid shl ID_SHIFT) or idx

template makeId(i:untyped):uint32 =
  let bid = i.uint32 div DEFAULT_BLK_SIZE.uint32
  let idx = i.uint32 mod DEFAULT_BLK_SIZE.uint32

  (bid shl ID_SHIFT) or idx

proc newCommandBuffer*(w: var ECSWorld):int =
  let c = initCommandBuffer()
  w.commandBufs.add(c)
  return w.commandBufs.len-1

proc getCommandBuffer*(w: var ECSWorld, id:int):CommandBuffer =
  return w.commandBufs[id]

proc isAlive*(w:ECSWorld, d:DenseHandle):bool =
  return d.gen == w.generations[d.wid]


{.pop.}

template getStableEntity(world:ECSWorld):uint32 =
  if world.free_entities.len > 0:
    world.free_entities.pop()
  else:
    let id = world.entities.len.uint32
    checkWarn(id < high(uint32) - 65535u32,
      "getStableEntity: entity pool nearing uint32 limit (" & $id &
      " / " & $high(uint32) & "). Recycle entities to avoid exhaustion.")
    world.entities.setLen(id + 1)
    world.generations.setLen(id + 1)
    id

proc getStableEntities(world:ECSWorld, n:int):seq[uint32] =
  result.setLen(n)
  let free_len = world.free_entities.len
  let start = max(0, free_len-n)

  if free_len > 0:
    let count = free_len - start
    when defined(js):
      for i in 0..<count:
        result[i] = world.free_entities[start + i]
    else:
      copyMem(addr result[0], addr world.free_entities[start], count * sizeof(uint32))
    world.free_entities.setLen(start)

  if world.free_entities.len == 0:
    let L = world.entities.len
    world.entities.setLen(L+(n-free_len))
    world.generations.setLen(L+(n-free_len))
    
    var c = 0
    for i in L..<world.entities.len:
      result[free_len+c] = i.uint32
      inc c

template registerComponent*(world:var ECSWorld, t:typed, P:static bool=false):int =
  registerComponent(world.registry, t, P)

macro requireComponent*(w: var ECSWorld, base: typedesc, comps:typedesc) =
  if base.repr == comps.repr: return
  else:
    let bid = getComponentIdFromRegistry(base)
    let cid = getComponentIdFromRegistry(comps)

    if bid notin REQUIRED_COMPS:
      REQUIRED_COMPS[bid] = newSeq[int]()

    REQUIRED_COMPS[bid].add(cid)

  return quote("@") do:    
    discard `@w`.registerComponent(`@comps`)
    `@w`.archGraph.requiredComps[toComponentId(`@base`)].add(toComponentId(`@comps`))

template get*[T](world:ECSWorld,t:typedesc[T], P:static bool= false):untyped =
  let id = toComponentId(t)
  getValue[T](world.registry.entries[id], P)

template get*[T](world:ECSWorld, t:typedesc[T], i:untyped, P:static bool= false):untyped =
  let id = toComponentId(t)
  let f = getValue[T](world.registry.entries[id], P)
  f[i]

template get*[T](ent:DWEntity | SWEntity, t:typedesc[T], P:static bool= false):untyped =
  get[T](ent.w, t, ent.handle, P)

template set*[T](world:var ECSWorld, i:untyped, v: T, P:static bool= false):untyped =
  let id = toComponentId(T)
  var f = getValue[T](world.registry.entries[id], P)
  f[i] = v

template set*[T](ent:var DWEntity | var SWEntity, v: T, P:static bool= false):untyped =
  set(ent.w, ent.handle, v, P)

include "dense.nim"
include "sparse.nim"
include "query.nim"
include "operations.nim"

proc process(world: var ECSWorld, cb: var CommandBuffer) =
  if cb.map.activeSignatures.len == 0: return

  cb.map.activeSignatures.sort()

  let genKey = CommandKey(cb.map.currentGeneration) shl 32

  for sig in cb.map.activeSignatures:
    let targetKey = genKey or CommandKey(sig)
    
    var idx = int(sig) and (MAP_CAPACITY - 1)
    var next_idx = (idx + 1) and (MAP_CAPACITY - 1)
    var probeCount = 0
    while cb.map.entries[idx].key != targetKey and next_idx != 0:
      idx = (idx + 1) and (MAP_CAPACITY - 1)
      next_idx = (idx + 1) and (MAP_CAPACITY - 1)
      probeCount += 1
      check(probeCount < MAP_CAPACITY,
        "CommandBuffer process: linear probe exhausted all " & $MAP_CAPACITY &
        " slots for signature=" & $sig &
        ". BatchMap is full or corrupted. Increase MAP_CAPACITY.")
    
    let batch = addr(cb.map.entries[idx])
    
    let dataPtr = batch.data
    var ents = newSeqofCap[DenseHandle](batch.count)

    for i in 0..<batch.count:
      ents.add(DenseHandle(widx:dataPtr[i].eid, gen:dataPtr[i].gen))

    case sig.getOp():
      of 0:
        for i in 0..<ents.len:
          var e = ents[i]
          world.deleteEntity(e)
      of 1:
        world.migrateEntity(ents, world.archGraph.nodes[sig.getArchetype()])
      else: discard

  for sig in cb.map.activeSignatures:
    let targetKey = genKey or CommandKey(sig)
    var idx = int(sig) and (MAP_CAPACITY - 1)
    var probeCount2 = 0
    while cb.map.entries[idx].key != targetKey:
      idx = (idx + 1) and (MAP_CAPACITY - 1)
      probeCount2 += 1
      check(probeCount2 < MAP_CAPACITY,
        "CommandBuffer flush/cleanup: linear probe exhausted all " & $MAP_CAPACITY &
        " slots. BatchMap state is corrupted.")
    cb.map.entries[idx].count = 0
  
  cb.map.activeSignatures.setLen(0)
  
  if cb.map.currentGeneration == 255: 
    # Rare case : total reset
    for i in 0..<MAP_CAPACITY:
      if cb.map.entries[i].key != 0:
        cb.map.entries[i].key = 0
    cb.map.currentGeneration = 1
  else:
    inc cb.map.currentGeneration

proc flush*(w:var ECSWorld) =
  for i in 0..<w.commandBufs.len:
    w.process(w.commandBufs[i])

proc clearDenseChanges*(w: var ECSWorld) =
  for entry in w.registry.entries:
    entry.clearDenseChangeOp(entry.rawPointer)

proc clearSparseChanges*(w: var ECSWorld) =
  for entry in w.registry.entries:
    entry.clearSparseChangeOp(entry.rawPointer)

proc clearChanges*(w: var ECSWorld) =
  w.clearDenseChanges()
  w.clearSparseChanges()

proc destroy*(w: var ECSWorld) =
  var ev = w.events
  GC_unref(ev)
  for cb in mitems(w.commandBufs):
    cb.destroy()
