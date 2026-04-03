####################################################################################################################################################
################################################################## ECS TYPES #######################################################################
####################################################################################################################################################
##
## Central type definitions for the Cruise ECS.
##
## This module contains **all** type definitions, constants and simple utility
## templates that the remaining ECS sub-modules depend on.  By keeping every
## type in a single, implementation-free module we break the circular-dependency
## chains that the old ``include``-based layout would create when moving to
## proper ``import`` / ``export``.
##
## **Rule of thumb** – if it is a ``type``, a ``const``, or a tiny inline
## template that only operates on the types defined here, it belongs here.
## Anything that contains meaningful logic goes into its own sub-module.
##
## Usage example
## =============
##
## .. code-block:: nim
##   import cruise/ecs/types
##
##   var mask: ArchetypeMask
##   mask.withComponentInPlace(0)
##   assert mask.hasComponent(0)

import std/[tables, hashes, math]

# ─────────────────────────────── Constants ────────────────────────────────── #

const
  MAX_COMPONENT_LAYER* = 4
    ## Number of uint words used to represent a component mask.
    ## Total component limit = MAX_COMPONENT_LAYER * sizeof(uint) * 8.
    ## With 4 layers on a 64-bit platform this gives 256 components.

  PARTITION_ZONE_CAP* = 10
    ## Pre-allocated zone capacity for a new TablePartition.

  UINT_BITS* = sizeof(uint) * 8
    ## Number of bits in a native ``uint`` (32 on JS, 64 on native 64-bit).

  BIT_DIVIDER* = floor(log(UINT_BITS.float, 2.0)).int
    ## ``log2(UINT_BITS)`` – used for fast integer division by UINT_BITS.

  BIT_REMAINDER* = UINT_BITS - 1
    ## Bit mask for ``mod UINT_BITS``.

  BLK_SHIFT* = sizeof(uint) * 4
    ## Bit shift used to extract the block index from a packed entity ID.

  BLK_MASK* = (1 shl BLK_SHIFT) - 1
    ## Bit mask used to extract the local offset from a packed entity ID.

  DEFAULT_BLK_SIZE* = UINT_BITS * UINT_BITS
    ## Default number of elements per dense block (4 096 on 64-bit).

  INITIAL_SPARSE_SIZE* = 10_000
    ## Initial capacity of sparse storage (blocks).

  MAX_COMPONENTS* = MAX_COMPONENT_LAYER * sizeof(uint) * 8
    ## Hard upper bound on the number of distinct component types.

when defined(cruiseEvents):
  const EVENT_ACTIVE* = true
    ## When ``-d:cruiseEvents`` is passed at compile time, ECS lifecycle
    ## events (entity created, destroyed, migrated …) are emitted.
else:
  const EVENT_ACTIVE* = false
    ## By default, ECS lifecycle events are **disabled** for maximum
    ## throughput in hot paths. Pass ``-d:cruiseEvents`` to enable them.

# ────────────────────────────── Check helper ──────────────────────────────── #

template check*(code: untyped, msg: string) =
  ## Debug-only assertion. Compiled out with ``-d:danger``.
  when not defined(danger):
    doAssert code, msg

template onDanger*(code: untyped) =
  ## Executes ``code`` only in non-danger builds (debug/release).
  when not defined(danger):
    code

# ─────────────────────────── Archetype Mask ───────────────────────────────── #

type
  ArchetypeMask* = array[MAX_COMPONENT_LAYER, uint]
    ## Fixed-size bitmask representing a set of component IDs.
    ##
    ## Each of the ``MAX_COMPONENT_LAYER`` words holds ``sizeof(uint)*8``
    ## component bits, giving a total of ``MAX_COMPONENTS`` addressable
    ## component slots.
    ##
    ## Example
    ## -------
    ## .. code-block:: nim
    ##   var m: ArchetypeMask
    ##   m.withComponentInPlace(0)     # set bit 0
    ##   m.withComponentInPlace(64)    # set bit 64 (second word)
    ##   assert m.hasComponent(0)
    ##   assert not m.hasComponent(1)

  ComponentId* = range[0 .. MAX_COMPONENTS - 1]
    ## Integer sub-range type for validated component indices.

  Range* = object
    ## Half-open integer range ``[s, e)``.
    s*, e*: int

# ─────────────────────── HiBitSet type declarations ───────────────────────── #
# The full implementation lives in ``hibitset.nim``; here we only need the type
# shells so that ``QueryFilter`` and ``SoAFragmentArray`` can reference them.

when defined(js):
  const
    L0_BITS*  = 32
    L0_SHIFT* = 5
    L0_MASK*  = 31
  type BitBlock* = uint32
else:
  const
    L0_BITS*  = 64
    L0_SHIFT* = 6
    L0_MASK*  = 63
  type BitBlock* = uint64

type
  HiBitSet* = object
    ## Dense 3-level hierarchical bitset – see ``hibitset.nim`` for docs.
    layer0*: seq[BitBlock]
    layer1*: seq[BitBlock]
    layer2*: seq[BitBlock]

  SparseHiBitSet* = object
    ## Sparse 3-level hierarchical bitset – see ``hibitset.nim`` for docs.
    layer0Dense*:    seq[BitBlock]
    layer0Sparse*:   seq[int]
    layer0DenseIdx*: seq[int]
    layer0Count*:    int
    layer1Dense*:    seq[BitBlock]
    layer1Sparse*:   seq[int]
    layer1DenseIdx*: seq[int]
    layer1Count*:    int
    layer2Dense*:    seq[BitBlock]
    layer2Sparse*:   seq[int]
    layer2DenseIdx*: seq[int]
    layer2Count*:    int

  HiBitSetType* = HiBitSet
    ## Alias selecting the concrete bitset implementation used at runtime.

# ─────────────────────────── Query Filter ─────────────────────────────────── #

type
  QueryFilter* = object
    ## Dual-layer filter used by queries to narrow dense and sparse results.
    dLayer*: HiBitSetType   ## Dense entity filter
    sLayer*: HiBitSetType   ## Sparse entity filter

# ──────────────────── SoA Fragment type declarations ──────────────────────── #
# Full implementations in ``fragment.nim``.

type
  SoAFragment*[N: static int, P: static bool, T, B] = object
    ## A single Structure-of-Arrays (SoA) block storing ``N`` component rows.
    data*: T
    ticks*: array[N, uint64]

  SoAFragmentArray*[N: static int, P: static bool, T, S, B] = ref object
    ## Dynamically-sized array of SoA fragments with optional sparse storage.
    blocks*: seq[ref SoAFragment[N, P, T, B]]
    blkTicks*: seq[uint64]
    sparse*: seq[SoAFragment[sizeof(uint)*8, P, S, B]]
    sparseTicks*: seq[uint64]
    changeFilter*: QueryFilter
    toSparse*: seq[int]
    mask*: seq[uint]
    sparseMask*: HiBitSetType
    freeBlocks*: seq[int]
    tick*: uint64

# ──────────────────────────── Entity types ────────────────────────────────── #

type
  Entity* = object
    ## Internal metadata stored per dense entity.
    id*: uint            ## Packed block-ID + local offset
    archetypeId*: uint16 ## Current archetype
    widx*: int           ## Stable world index (for handle recycling)

  DenseHandle* = object
    ## Safe, generation-checked handle to a dense entity.
    ##
    ## Example
    ## -------
    ## .. code-block:: nim
    ##   let d = world.createEntity(Position, Velocity)
    ##   assert world.isAlive(d)
    ##   world.deleteEntity(d)
    ##   assert not world.isAlive(d)  # stale handle
    obj*: ptr Entity
    gen*: uint32

  SparseHandle* = object
    ## Safe handle to a sparse entity.
    id*: uint
    gen*: uint32
    archID*: uint16

  SomeEntity* = ptr Entity | Entity | var Entity
    ## Type class encompassing Entity pointer/value/var.

# ──────────────────────── Command Buffer types ────────────────────────────── #

const
  MAX_COMMANDS* = 2_000_000
  MAP_CAPACITY* = 16384
  INITIAL_CAPACITY* = 64

type
  Payload* = object
    eid*: uint
    obj*: DenseHandle
    data*: pointer
    size*: uint32

  CommandKey* = uint64

  BatchEntry* = object
    key*: CommandKey
    count*: uint32
    capacity*: uint32
    when defined(js):
      data*: seq[Payload]
    else:
      data*: ptr UncheckedArray[Payload]

  BatchMap* = object
    when defined(js):
      entries*: seq[BatchEntry]
    else:
      entries*: ptr UncheckedArray[BatchEntry]
    currentGeneration*: uint8
    activeSignatures*: seq[uint32]

  CommandBuffer* = object
    ## Deferred-execution command buffer for batching structural ECS changes.
    ##
    ## Allows safe entity deletion / migration during iteration.  Commands
    ## are sorted by (op, archetype) signature and executed in bulk when
    ## ``flush`` is called.
    map*: BatchMap
    cursor*: int

# ───────────────────── Component Registry types ───────────────────────────── #

type
  ComponentEntry* = ref object
    ## Type-erased descriptor for a registered component.
    ## Each field is a function pointer implementing a specific operation on
    ## the underlying ``SoAFragmentArray`` without knowing its concrete type.
    rawPointer*: pointer
    resizeOp*: proc (p: pointer, n: int) {.noSideEffect, nimcall, inline.}
    newBlockAtOp*: proc (p: pointer, i: int) {.noSideEffect, nimcall, inline.}
    newBlockOp*: proc (p: pointer, offset: int) {.noSideEffect, nimcall, inline.}
    newSparseBlockOp*: proc (p: pointer, offset: int, m: uint) {.noSideEffect, nimcall, inline.}
    newSparseBlocksOp*: proc (p: pointer, offset: int, m: seq[uint]) {.noSideEffect, nimcall, inline.}
    overrideValsOp*: proc (p: pointer, i: uint, j: uint) {.noSideEffect, nimcall, inline.}
    overrideDSOp*: proc (p: pointer, d: DenseHandle, s: SparseHandle) {.noSideEffect, nimcall, inline.}
    overrideSDOp*: proc (p: pointer, s: SparseHandle, d: DenseHandle) {.noSideEffect, nimcall, inline.}
    overrideValsBatchOp*: proc (
      p: pointer, archId: uint16, ents: ptr seq[ptr Entity],
      ids: openArray[DenseHandle], sw: seq[uint], ad: seq[uint])
    getChangeMaskop*: proc (p: pointer): ptr QueryFilter {.noSideEffect, nimcall, inline.}
    getSparseChangeMaskop*: proc (p: pointer): ptr HiBitSetType {.noSideEffect, nimcall, inline.}
    getSparseMaskOp*: proc (p: pointer): ptr HiBitSetType {.noSideEffect, nimcall, inline.}
    getSparseChunkMaskOp*: proc (p: pointer, i: int): uint {.noSideEffect, nimcall, inline.}
    setSparseMaskOp*: proc (p: pointer, m: seq[uint]) {.noSideEffect, nimcall, inline.}
    clearDenseChangeOp*: proc (p: pointer) {.noSideEffect, nimcall, inline.}
    clearSparseChangeOp*: proc (p: pointer) {.noSideEffect, nimcall, inline.}
    activateSparseBitOp*: proc (p: pointer, i: uint) {.noSideEffect, nimcall, inline.}
    activateSparseBitBatchOp*: proc (p: pointer, i: seq[uint]) {.noSideEffect, nimcall, inline.}
    deactivateSparseBitOp*: proc (p: pointer, i: uint) {.noSideEffect, nimcall, inline.}
    deactivateSparseBitBatchOp*: proc (p: pointer, i: seq[uint]) {.noSideEffect, nimcall, inline.}
    freeEntry*: proc (p: pointer) {.raises: [].}

  ComponentRegistry* = object
    ## Global registry of all component types.
    entries*: seq[ComponentEntry]
    cmap*: Table[string, int]

# ──────────────────────── Table / Partition types ─────────────────────────── #

type
  TableRange* = object
    ## A dense block range: block index + half-open element range.
    r*: Range
    block_idx*: int

  TablePartition* = ref object
    ## The set of zones (block ranges) belonging to one archetype partition.
    zones*: seq[TableRange]
    components*: seq[int]
    fill_index*: int

# ──────────────────────── Archetype Graph types ──────────────────────────── #

type
  ArchetypeNode* = ref object
    ## A node in the archetype graph, representing a unique component
    ## combination.
    id*: uint16
    mask*: ArchetypeMask
    partition*: TablePartition
    edges*: array[MAX_COMPONENTS, ArchetypeNode]
    removeEdges*: array[MAX_COMPONENTS, ArchetypeNode]
    edgeMask*: ArchetypeMask
    componentIds*: seq[int]
    lastEdge*: int
    lastRemEdge*: int

  ArchetypeGraph* = ref object
    ## Directed graph of archetype transitions.
    root*: ArchetypeNode
    nodes*: seq[ArchetypeNode]
    maskToId*: Table[ArchetypeMask, uint16]
    lru_active*: bool
    lastMask*: ArchetypeMask
    lastNode*: ArchetypeNode

# ────────────────────────── ECS Event types ───────────────────────────────── #

type
  DenseEntityCreatedEvent* = object
    entity*: DenseHandle

  DenseEntityDestroyedEvent* = object
    entity*: DenseHandle
    last*: uint

  DenseComponentAddedEvent* = object
    entity*: DenseHandle
    componentIds*: seq[int]

  DenseComponentRemovedEvent* = object
    entity*: DenseHandle
    componentIds*: seq[int]

  DenseEntityMigratedEvent* = object
    entity*: DenseHandle
    oldId*: uint
    lastId*: uint
    oldArchetype*: uint16
    newArchetype*: uint16

  DenseEntityMigratedBatchEvent* = object
    ids*: seq[uint]
    oldIds*: seq[uint]
    newIds*: seq[uint]
    oldArchetype*: uint16
    newArchetype*: uint16

  SparseEntityCreatedEvent* = object
    entity*: SparseHandle

  SparseEntityDestroyedEvent* = object
    entity*: SparseHandle

  SparseComponentAddedEvent* = object
    entity*: SparseHandle
    componentIds*: seq[int]

  SparseComponentRemovedEvent* = object
    entity*: SparseHandle
    componentIds*: seq[int]

  DensifiedEvent* = object
    oldSparse*: SparseHandle
    newDense*: DenseHandle

  SparsifiedEvent* = object
    oldDense*: DenseHandle
    newSparse*: SparseHandle

  CommandBufferFlushedEvent* = object
    bufferId*: int
    entitiesProcessed*: int
    operationCount*: int

  ArchetypeCreatedEvent* = object
    archetypeId*: int
    mask*: ArchetypeMask
    componentIds*: seq[int]

  EventCallback*[T] = proc(event: T) {.closure.}

  EventPool*[T] = object
    ## Callback pool with free-list recycling.
    callbacks*: seq[EventCallback[T]]
    freeSlots*: seq[int]

  EventManager* = object
    ## Central event dispatcher for the ECS world.
    denseEntityCreated*: EventPool[DenseEntityCreatedEvent]
    denseEntityDestroyed*: EventPool[DenseEntityDestroyedEvent]
    denseComponentAdded*: EventPool[DenseComponentAddedEvent]
    denseComponentRemoved*: EventPool[DenseComponentRemovedEvent]
    denseEntityMigrated*: EventPool[DenseEntityMigratedEvent]
    denseEntityMigratedBatch*: EventPool[DenseEntityMigratedBatchEvent]
    sparseEntityCreated*: EventPool[SparseEntityCreatedEvent]
    sparseEntityDestroyed*: EventPool[SparseEntityDestroyedEvent]
    sparseComponentAdded*: EventPool[SparseComponentAddedEvent]
    sparseComponentRemoved*: EventPool[SparseComponentRemovedEvent]
    densifiedEvent*: EventPool[DensifiedEvent]
    sparsifiedEvent*: EventPool[SparsifiedEvent]
    commandBufferFlushed*: EventPool[CommandBufferFlushedEvent]
    archetypeCreated*: EventPool[ArchetypeCreatedEvent]

# ─────────────────────────── ECS Operation codes ──────────────────────────── #

type
  ECSOpCode* = enum
    ## Operation codes used by the deferred command buffer.
    DeleteOp = 0
    MigrateOp = 1

# ─────────────────────── Query types ──────────────────────────────────────── #

type
  QueryOp* = enum
    qInclude     ## Component must be present
    qExclude     ## Component must be absent
    qModified    ## Component must be present AND modified
    qNotModified ## Component must be present AND NOT modified

  QueryComponent* = object
    id*: int
    op*: QueryOp

  QuerySignature* = object
    ## Compiled query with bitmask representation.
    components*: seq[QueryComponent]
    includeMask*: ArchetypeMask
    excludeMask*: ArchetypeMask
    modified*: seq[int]
    notModified*: seq[int]
    filters*: seq[ptr QueryFilter]

  DenseQueryResult* = object
    part*: seq[TablePartition]

  DenseIterator* = object
    r*: HSlice[int, int]
    m*: ptr seq[BitBlock]
    masked*: bool

  sparseQueryResult* = object
    rmask*: seq[uint]
    chunks*: seq[uint]

  SparseIterator* = object
    m*: uint

  QueryKey* = tuple[incl: ArchetypeMask, excl: ArchetypeMask]

  QueryCacheEntry* = object
    version*: int
    nodes*: seq[ArchetypeNode]

# ──────────────────────────── ECS World ───────────────────────────────────── #

type
  ECSWorld* = ref object
    ## The top-level ECS container.
    ##
    ## Holds the component registry, entity storage, command buffers,
    ## archetype graph and query cache.
    ##
    ## Example
    ## -------
    ## .. code-block:: nim
    ##   var world = newECSWorld()
    ##   discard world.registerComponent(Position)
    ##   discard world.registerComponent(Velocity)
    ##   let e = world.createEntity(Position, Velocity)
    registry*: ComponentRegistry
    entities*: seq[Entity]
    commandBufs*: seq[CommandBuffer]
    events*: EventManager
    handles*: seq[ptr Entity]
    generations*: seq[uint32]
    sparse_gens*: seq[uint32]
    free_entities*: seq[int]
    archGraph*: ArchetypeGraph
    free_list*: seq[uint]
    max_index*: int
    blockCount*: int
    queryCache*: Table[QueryKey, QueryCacheEntry]

# ──────────────────── Inline utilities on Range/Table ─────────────────────── #

template isEmpty*(t: TableRange | ptr TableRange): bool =
  t.r.s == t.r.e

template isFull*(t: TableRange | ptr TableRange): bool =
  t.r.e - t.r.s == DEFAULT_BLK_SIZE

proc hash*(mask: ArchetypeMask | ptr ArchetypeMask): Hash =
  result = !$(hash(mask[0]) !& hash(mask[1]) !& hash(mask[2]) !& hash(mask[3]))
