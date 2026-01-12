####################################################################################################################################################
######################################################################## ECS TABLE #################################################################
####################################################################################################################################################

import tables, bitops, typetraits, hashes

const
  MAX_COMPONENT_LAYER = 4

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

include "fragment.nim"
include "entity.nim"
include "registry.nim"
include "mask.nim"

type
  TableColumn[N:static int,T,B] = ref object
    components:SoAFragmentArray[N,T,B]
    mask:seq[uint]

  TableRange = object
    r:Range
    block_idx:int

  TablePartition = ref object
    zones:seq[TableRange]
    components:seq[int]
    fill_index:int

include "archetypes.nim"

type
  ECSWorld = ref object
    registry:ComponentRegistry
    entities:seq[Entity]
    handles:seq[ptr Entity]
    generations:seq[uint32]
    free_entities:seq[int]
    sparse_entities:seq[Entity]
    archetypes:Table[ArchetypeMask, TablePartition]
    archGraph:ArchetypeGraph
    pooltype:Table[string, int]
    free_list:seq[uint]
    max_index:int
    block_count:int

template newTableColumn[N,T,B](f:SoAFragmentArray[N,T,B]):untyped =
  var m = newSeq[uint]()

  for i in 0..<f.blocks.len:
    let idx = i div sizeof(uint)
    let bitpos = i mod sizeof(uint)
    if idx >= m.len:
      m.add(0.uint)

    if not f.blocks[i].isNil:
      m[idx] = m[idx] or (1 shl bitpos)
  
  var res = TableColumn[N,T,B](components:f, mask:m)
  res

proc newECSWorld(max_entities:int=1000000):ECSWorld =
  var w:ECSWorld
  new(w)
  new(w.registry)
  w.archGraph = initArchetypeGraph()
  w.entities = newSeqofCap[Entity](max_entities)

  return w

####################################################################################################################################################
####################################################################### OPERATIONS #################################################################
####################################################################################################################################################

{.push inline.}

proc isEmpty(t:TableRange):bool = t.r.s == t.r.e
proc isFull(t:TableRange):bool = t.r.e - t.r.s == DEFAULT_BLK_SIZE

proc getComponentId(world:ECSWorld, t:typedesc):int =
  return world.registry.cmap[$t]

proc getArchetype(w:ECSWorld, e:SomeEntity):ArchetypeNode =
  return w.archGraph.nodes[e.archetypeId]
proc getArchetype(w:ECSWorld, d:DenseHandle):ArchetypeNode =
  return w.getArchetype(d.obj)

proc makeId(info:(uint, Range)):uint =
  return ((info[0]).uint shl BLK_SHIFT) or ((info[1].e-1) mod DEFAULT_BLK_SIZE).uint

proc makeId(idx,bid:int|uint):uint =
  return (bid.uint shl BLK_SHIFT) or idx.uint

proc makeId(i:int):uint =
  let bid = i div DEFAULT_BLK_SIZE
  let idx = i mod DEFAULT_BLK_SIZE

  return (bid.uint shl BLK_SHIFT) or idx.uint

{.pop.}

proc getStableEntity(world:ECSWorld):int =
  var entity_idx: int
  if world.free_entities.len > 0:
    entity_idx = world.free_entities.pop()
  else:
    entity_idx = world.entities.len
    world.entities.setLen(entity_idx + 1)
    world.generations.setLen(entity_idx + 1)

  return entity_idx

proc getStableEntities(world:ECSWorld, n:int):seq[int] =
  var entity_idx = newSeq[int](n)
  let free_len = world.free_entities.len
  let start = max(0, free_len-n)

  if free_len > 0:
    copyMem(addr entity_idx[0], addr world.free_entities[start], (free_len-start)*sizeof(int))
    world.free_entities.setLen(start)

  if world.free_entities.len == 0:
    let L = world.entities.len
    world.entities.setLen(L+(n-free_len))
    world.generations.setLen(L+(n-free_len))
    
    for i in L..<world.entities.len:
      entity_idx[free_len] = i

  return entity_idx

proc registerComponent[T](world:var ECSWorld, t:typedesc[T]):int =
  registerComponent(world.registry, T)

template get[T](world:ECSWorld,t:typedesc[T]):untyped =
  let id = world.getComponentId(t)
  getValue[T](world.registry.entries[id])

template get[T](world:ECSWorld, t:typedesc[T], i:untyped):untyped =
  let id = world.getComponentId(t)
  getValue[T](world.registry.entries[id])[i]

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