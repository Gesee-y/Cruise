# ################################################################################################################################################## #
# ####################################################################### ECS TABLE ################################################################ #
# ################################################################################################################################################## #

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

# Three severity levels for different build configurations:
#
#  checkWarn      — Debug builds only (no -d:release, no -d:danger).
#                   Emits a non-fatal warning via debugEcho.
#                   Use for near-limit situations, suspicious-but-safe state.
#
#  check          — Debug + Release (disabled by -d:danger).
#                   Raises AssertionDefect on violation.
#                   Use for errors that would silently corrupt ECS state.
#
#  checkCritical  — Always active, even under -d:danger.
#                   Raises Defect. Use for invariant violations that are
#                   *always* programming errors regardless of build mode
#                   (null dereference, OOB access, infinite loops, etc.)
template checkWarn(code: untyped, msg: string) =
  # Non-fatal warning emitted only in debug (un-optimised) builds.
  when not defined(release) and not defined(danger):
    if not (code):
      debugEcho "[ECS WARN] " & msg

template check(code: untyped, msg: string) =
  # Hard assertion active in debug + release, suppressed by -d:danger.
  when not defined(danger):
    doAssert code, "[ECS ERROR] " & msg

template checkCritical(code: untyped, msg: string) =
  # Always-active guard — fires even under -d:danger.
  # Use for invariants whose violation is always a programming error.
  if unlikely(not (code)):
    raise newException(Defect, "[ECS CRITICAL] " & msg)

template onDanger(code: untyped) =
  # Code that executes only when NOT in -d:danger mode.
  when not defined(danger):
    code

include "sparseset.nim"
include "hibitset.nim"

type
  QueryFilter* = ref object
    ## Represent an independent filter that can be used to narrow queries.
    # Dense Query
    dLayer*:HibitsetType

    # Sparse Query
    sLayer*:HibitsetType

include "fragment.nim"
include "entity.nim"
include "mask.nim"
include "registry.nim"

registerLayout(SoAFragment, newSoAFragArr, soaCastTo)
registerLayout(VecFragment, newVecFragArr, vecCastTo)

type
  TableRange* = object
    ## Represent a range of entities for the dense storage, used for patitions
    r:Range
    block_idx:int

  TablePartition* = ref object
    ## Conceptually represent an archetype but in a contiguous storage.
    zones:seq[TableRange]
    components:seq[int]
    fill_index:int

proc clear(t: var TableRange) =
  t.r.reset

proc clear(t: var TablePartition) =
  for z in t.zones.mitems:
    z.clear()
  t.fill_index = 0
  
include "archetypes.nim"

type
  QueryKey* = tuple[incl: ArchetypeMask, excl: ArchetypeMask]
  QueryCacheEntry* = object
    version*: int
    archs: seq[uint16]

  ECSWorld* = ref object
    ## The main object representing the ECSWorld.
    ## Avoid using more than one ECS world at the same time
    ## Since Cruise ECS use static optimization, world shoudl not overlap (in their components layout and stuffs)
    registry:ComponentRegistry
    entities*:seq[Entity]
    evmanager: pointer
    handles*:seq[uint32]
    generations:seq[uint16]
    sparse_gens:seq[uint16]
    sparse_arch:seq[uint16]
    free_entities:seq[uint32]
    archGraph*:ArchetypeGraph
    free_list:seq[uint32]
    max_index:int
    blockCount:int
    queryCache*: Table[QueryKey, QueryCacheEntry]
    resources*: Table[string, pointer]

include "handles.nim"
include "entity_wrappers.nim"
include "commands.nim"
include "events.nim"

template newECSWorld*(max_entities:int=1000000):ECSWorld =
  ## Build a new world with `max_entities` reserved
  ## Only one world shoud exist at the same time
  var w:ECSWorld
  new(w)
  checkWarn(max_entities > 0,
    "newECSWorld: max_entities must be > 0 (got " & $max_entities &
    "). The world will be created but cannot hold any entities.")
  checkWarn(max_entities <= 1_000_000_000,
    "newECSWorld: max_entities=" & $max_entities &
    " exceeds 1 billion. Initial capacities may cause OOM at startup.")
  
  w.archGraph = initArchetypeGraph()
  w.entities = newSeqofCap[Entity](max_entities)
  w.handles = newSeqofCap[uint32](max_entities)
  w.free_list = newSeqofCap[uint32](max_entities div 2)
  w.free_entities = newSeqofCap[uint32](max_entities div 2)
  w.generations = newSeqofCap[uint16](max_entities)
  w.sparse_gens = newSeqofCap[uint16](max_entities)
  w.sparse_arch = newSeqofCap[uint16](max_entities)
  
  var ev = initEventManager()
  GC_ref(ev)
  w.evmanager = cast[pointer](ev)
  w

proc clearEntities*(w: var ECSWorld, max_entities:int=1000000) =
  for node in w.archGraph.nodes.mitems:
    if not node.partition.isNil:
      node.partition.clear()

  for entry in w.registry.entries:
    if not entry.isNil:
      entry.clearEntityOp(entry.rawPointer)

  w.entities = newSeqofCap[Entity](max_entities)
  w.free_list = newSeqofCap[uint32](max_entities div 2)
  w.free_entities = newSeqofCap[uint32](max_entities div 2)
  w.generations = newSeqofCap[uint16](max_entities)
  w.sparse_gens = newSeqofCap[uint16](max_entities)

# ################################################################################################################################################## #
# ###################################################################### OPERATIONS ################################################################ #
# ################################################################################################################################################## #

template events*(w: ECSWorld): EventManager = 
  ## Return the event manager of the ECS manager
  cast[EventManager](w.evmanager)

{.push inline.}

proc addResource*[T](w: var ECSWorld, r:T) =
  ## Add the new resource in the ECS world
  ## You can later fetch it with `getResource`
  ## Resorces are registered per types
  w.resources[$T] = cast[pointer](r)

proc getResource*[T](w: ECSWorld): T =
  ## Return a resource of type `T`
  ## Error if not found.
  let t = $T
  check(t in w.resources, "Error: Resource of type " & t & " not found.")
  cast[T](w.resources[$T])

proc unsafeGetResource*[T](w: ECSWorld): T =
  ## Returns a resource but without checking if it actually exist
  cast[T](w.resources[$T])

proc isEmpty(t:TableRange | ptr TableRange):bool = t.r.s == t.r.e
proc isFull(t:TableRange | ptr TableRange):bool = t.r.e - t.r.s == DEFAULT_BLK_SIZE

template getDHandle*(w: ECSWorld, i:untyped): DenseHandle = 
  ## Return an handle for entity id `i`
  ## `i` is the global ID of the entity, not the id in the storage
  DenseHandle(widx: i.uint32, gen: w.generations[i], world: w)

template getDHandleFromID*(w: ECSWorld, i:untyped): DenseHandle = 
  ## Return a dense handle for the storage id `i` if it exist.
  ## Else it will error.
  var e = w.handles[i.toIdx]
  w.getDHandle(e)

proc getArchetype*(w:ECSWorld, e:SomeEntity):ArchetypeNode =
  ## Return the archetype node of an entity
  return w.archGraph.nodes[e.archetypeId]
proc getArchetype*(w:ECSWorld, d:DenseHandle):ArchetypeNode =
  return w.getArchetype(d.obj)

template makeId*(bid,idx:untyped):uint32 =
  ## Bild an entity storage ID from a block id `bid` and intra id `idx`
  (bid.uint32 shl ID_SHIFT) or idx.uint32

template makeId(i:untyped):uint32 =
  let bid = i.uint32 div DEFAULT_BLK_SIZE.uint32
  let idx = i.uint32 mod DEFAULT_BLK_SIZE.uint32

  (bid shl ID_SHIFT) or idx

proc isAlive*(w:ECSWorld, d:DenseHandle):bool =
  return d.gen == w.generations[d.wid]

{.pop.}

# Return an entity id
# This is used to allocate new entities
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

# Same as above but allocate multiple entities
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

template registerComponent*(world:var ECSWorld, t:typed, P:static bool=false, layout: untyped=SoAFragment):int =
  ## Register a components `t` in the world context (module), `P` is to activate change tracking and `layout is the orrganization of the chunks
  ## This is mostly automated so no need to use it most of the time.
  ## But you can do it to have deterministic component ID (that you can get with `toComponentID(componentType)`)
  registerComponent(world.registry, t, P, layout)

macro requireComponent*(w: var ECSWorld, base: typedesc, comps:typedesc, layout: untyped=SoAFragment) =
  ## Allows you to bind to component so `base` require `comps`
  ## This means that if `base` is added then `comps` will be added
  if base.repr == comps.repr: return
  else:
    let bid = getComponentIdFromRegistry(base)
    let cid = getComponentIdFromRegistry(comps)

    if bid notin REQUIRED_COMPS:
      REQUIRED_COMPS[bid] = newSeq[int]()

    REQUIRED_COMPS[bid].add(cid)

  return quote("@") do:    
    discard `@w`.registerComponent(`@comps`, layout=`@layout`)
    `@w`.archGraph.requiredComps[toComponentId(`@base`)].add(toComponentId(`@comps`))

template get*[T](world:ECSWorld,t:typedesc[T], P:static bool= false):untyped =
  ## Let you get the components pool for the component `T`
  ## `P` is to enable change tracking on that specific instance.
  let id = toComponentId(T)
  getValue[T](world.registry.entries[id], P)

template get*[T](world:ECSWorld, t:typedesc[T], i:untyped):untyped =
  ## Let you get the components an index `i` for the component `T`
  ## `i` is whethever that can index a `FragmentArray`
  let id = toComponentId(T)
  let f = getValue[T](world.registry.entries[id], false)
  f[i]

template get*[T](ent:DWEntity | SWEntity, t:typedesc[T]):untyped =
  ## For handles that possess a reference to the world
  ## You can use this to get one of ther components
  get[T](ent.w, t, ent.handle, false)

template set*[T](world:var ECSWorld, i:untyped, v: T, P:static bool= false):untyped =
  ## For handles that possess a reference to the world
  ## You can use this to set one of ther components
  ## `P` enable change tracking if true
  let id = toComponentId(T)
  var f = getValue[T](world.registry.entries[id], P)
  f[i] = v

template set*[T](ent:var DWEntity | var SWEntity, v: T, P:static bool= false):untyped =
  set(ent.w, ent.handle, v, P)

include "dense.nim"
include "sparse.nim"
include "query.nim"
include "typed_handles.nim"
include "operations.nim"
include "typed_dense.nim"
include "typed_operations.nim"

proc process(world: var ECSWorld, cb: var ECommandBuffer) =
  for cmd in cb.denseEntityRemoved:
    case cmd.entityKind:
      of ecekDense:
        for e in cmd.dEntities:
          world.deleteEntity(e)
      of ecekSparse:
        for e in cmd.sEntities:
          world.deleteEntity(e)
  
  for i, cmds in cb.denseEntityMigrate.pairs:
    for j, cmd in cmds.pairs:    
      world.migrateEntity(cmd.dEntities, j.uint16)

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
