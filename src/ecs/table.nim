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
  BLK_SHIFT = sizeof(uint)*4
  ## Mask used to extract local indices from packed IDs.
  BLK_MASK = (1 shl BLK_SHIFT) - 1
  ## Default size (in elements) of a dense block.
  DEFAULT_BLK_SIZE = UINT_BITS*UINT_BITS
  ## Initial capacity of the sparse storage.
  INITIAL_SPARSE_SIZE = 10000

type 
  Range = object
    s,e:int

  ArchetypeMask = array[MAX_COMPONENT_LAYER, uint]

template check(code:untyped, msg:string) =
  when not defined(danger):
    doAssert code, msg

template onDanger(code) =
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
include "events.nim"

type
  QueryKey* = tuple[incl: ArchetypeMask, excl: ArchetypeMask]
  QueryCacheEntry* = object
    version*: int
    nodes*: seq[ArchetypeNode]
    archs: set[uint16]

  ECSWorld* = ref object
    registry:ComponentRegistry
    entities:seq[Entity]
    commandBufs*:seq[CommandBuffer]
    events*: EventManager
    handles*:seq[ptr Entity]
    generations:seq[uint32]
    sparse_gens:seq[uint32]
    free_entities:seq[int]
    archGraph*:ArchetypeGraph
    free_list:seq[uint]
    max_index:int
    blockCount:int
    queryCache*: Table[QueryKey, QueryCacheEntry]
    resources*: Table[string, pointer]

include "entity_wrappers.nim"

proc newECSWorld*(max_entities:int=1000000):ECSWorld =
  var w:ECSWorld
  new(w)
  #new(w.registry)
  w.archGraph = initArchetypeGraph()
  w.entities = newSeqofCap[Entity](max_entities)
  w.handles = newSeqofCap[ptr Entity](max_entities)
  w.free_list = newSeqofCap[uint](max_entities div 2)
  w.generations = newSeqofCap[uint32](max_entities)
  w.sparse_gens = newSeqofCap[uint32](max_entities)
  w.events = initEventManager()

  return w

####################################################################################################################################################
####################################################################### OPERATIONS #################################################################
####################################################################################################################################################

{.push inline.}

proc addResource*[T](w: var ECSWorld, r:T) =
  w.resources[$T] = cast[pointer](r)

proc getResource*[T](w: ECSWorld): T =
  cast[T](w.resources[$T])

proc isEmpty(t:TableRange | ptr TableRange):bool = t.r.s == t.r.e
proc isFull(t:TableRange | ptr TableRange):bool = t.r.e - t.r.s == DEFAULT_BLK_SIZE

proc getDHandle*(w: ECSWorld, i:int | uint): DenseHandle = DenseHandle(obj: addr w.entities[i], gen: w.generations[i])
proc getDHandleFromID*(w: ECSWorld, i:int | uint): DenseHandle = 
  var e = w.handles[i.toIdx].widx
  w.getDHandle(e)

proc getComponentId*(world:ECSWorld, t:typedesc):int =
  check($t in world.registry.cmap, "Component type '" & $t & "' is not registered. Call registerComponent first.")
  return world.registry.cmap[$t]

proc getArchetype*(w:ECSWorld, e:SomeEntity):ArchetypeNode =
  return w.archGraph.nodes[e.archetypeId]
proc getArchetype*(w:ECSWorld, d:DenseHandle):ArchetypeNode =
  return w.getArchetype(d.obj)

proc makeId*(idx,bid:int|uint):uint =
  return (bid.uint shl BLK_SHIFT) or idx.uint

proc makeId(i:int):uint =
  let bid = i.uint div DEFAULT_BLK_SIZE
  let idx = i.uint mod DEFAULT_BLK_SIZE

  return (bid shl BLK_SHIFT) or idx

proc makeId(i:uint):uint =
  let bid = i div DEFAULT_BLK_SIZE.uint
  let idx = i mod DEFAULT_BLK_SIZE.uint

  return (bid shl BLK_SHIFT) or idx

proc newCommandBuffer*(w: var ECSWorld):int =
  let c = initCommandBuffer()
  w.commandBufs.add(c)
  return w.commandBufs.len-1

proc getCommandBuffer*(w: var ECSWorld, id:int):CommandBuffer =
  return w.commandBufs[id]

proc isAlive*(w:ECSWorld, d:DenseHandle):bool =
  return d.gen == w.generations[d.obj.widx]


{.pop.}

template getStableEntity(world:ECSWorld):int =
  if world.free_entities.len > 0:
    world.free_entities.pop()
  else:
    let id = world.entities.len
    world.entities.setLen(id + 1)
    world.generations.setLen(id + 1)
    id

proc getStableEntities(world:ECSWorld, n:int):seq[int] =
  result.setLen(n)
  let free_len = world.free_entities.len
  let start = max(0, free_len-n)

  if free_len > 0:
    let count = free_len - start
    when defined(js):
      for i in 0..<count:
        result[i] = world.free_entities[start + i]
    else:
      copyMem(addr result[0], addr world.free_entities[start], count * sizeof(int))
    world.free_entities.setLen(start)

  if world.free_entities.len == 0:
    let L = world.entities.len
    world.entities.setLen(L+(n-free_len))
    world.generations.setLen(L+(n-free_len))
    
    var c = 0
    for i in L..<world.entities.len:
      result[free_len+c] = i
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

proc resize(world: var ECSWorld, n:int) =
  for entry in world.registry.entries:
    entry.resizeOp(entry.rawPointer, n)

proc upsize(world: var ECSWorld, n:int) =
  for entry in world.registry.entries:
    entry.resizeOp(entry.rawPointer, world.blockCount + n)

proc getComponentsFromSig(sig:ArchetypeMask):seq[int] =
  var res:seq[int]
  for i in 0..<sig.len:
    var s = sig[i]
    while s != 0:
      res.add(countTrailingZeroBits(s))
      s = s and (s-1)

  return res

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
    while cb.map.entries[idx].key != targetKey:
      idx = (idx + 1) and (MAP_CAPACITY - 1)
    
    let batch = addr(cb.map.entries[idx])
    
    let dataPtr = batch.data
    var ents = newSeqofCap[DenseHandle](batch.count)

    for i in 0..<batch.count:
      ents.add(dataPtr[i].obj)

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
    while cb.map.entries[idx].key != targetKey:
      idx = (idx + 1) and (MAP_CAPACITY - 1)
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

proc destroy*(w: ECSWorld) =
  for cb in mitems(w.commandBufs):
    cb.destroy()