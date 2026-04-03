####################################################################################################################################################
############################################################# COMPONENT REGISTRY ###################################################################
####################################################################################################################################################

## The component registry provides a type-erased interface over SoA-backed
## component storage.
##
## Each registered component is stored as a `SoAFragmentArray`, but is exposed
## through a table of function pointers so higher-level systems (ECS, archetypes,
## schedulers) can manipulate components without knowing their concrete type.

var NEXT_COMPONENT_ID {.compileTime.} = 0
var NEXT_ARCHETYPE_ID {.compileTime.} = 0
var COMPONENT_ID_REGISTRY {.compileTime.} = initTable[int, int]()
var ID_TO_COMPONENT {.compileTime.} = initTable[int, NimNode]()
var ARCHETYPE_ID_REGISTRY {.compileTime.} = initTable[ArchetypeMask, int]()
var ARCHETYPE_ID_TO_MASK {.compileTime.} = initTable[int, ArchetypeMask]()
var REQUIRED_COMPS {.compileTime.} = initTable[int, seq[int]]()

static:
  var r:ArchetypeMask
  ARCHETYPE_ID_REGISTRY[r] = NEXT_ARCHETYPE_ID
  ARCHETYPE_ID_TO_MASK[NEXT_ARCHETYPE_ID] = r
  inc NEXT_ARCHETYPE_ID

proc getComponentIdFromRegistry(T:NimNode): int =
  let str = T.getTypeInst.repr
  let hash = T.getTypeInst.repr.hash.int
  let maxComp = MAX_COMPONENT_LAYER*UINT_BITS

  if hash notin COMPONENT_ID_REGISTRY:
    if NEXT_COMPONENT_ID < maxComp:
      COMPONENT_ID_REGISTRY[hash] = NEXT_COMPONENT_ID
      inc NEXT_COMPONENT_ID
    else:
      error "Failed to add " & str & ". Can't have more than " & $maxComp & " component."

  return COMPONENT_ID_REGISTRY[hash]

proc addRequired(m: var ArchetypeMask, comps: seq[int], registry: Table[int, seq[int]]) {.compileTime.} =
  for c in comps:
    if not m.hasComponent(c):
      m.withComponentInPlace(c)
      m.addRequired(registry[c], registry)

proc getRequiredComps(id:int): seq[int] {.compileTime.} =
  if id notin REQUIRED_COMPS:
    return @[]

  return REQUIRED_COMPS[id]

proc getRequiredCompsNode(id:int): seq[NimNode] {.compileTime.} =
  var res = newSeq[NimNode]()
  if id notin REQUIRED_COMPS:
    return res

  for i in REQUIRED_COMPS[id]:
    res.add(ID_TO_COMPONENT[i])

  return res

macro toComponentId(T:typedesc): int =
  let id = getComponentIdFromRegistry(T)
  ID_TO_COMPONENT[id] = T

  return quote do: `id`

proc toArchetypeIDC(comps: openArray[int]): (ArchetypeMask, int) {.compileTime.} =
  var m:ArchetypeMask
  for c in comps:
    let req = getRequiredComps(c)
    m.withComponentInPlace(c)

    for r in req:
      m.withComponentInPlace(r)

  if m notin ARCHETYPE_ID_REGISTRY:
    ARCHETYPE_ID_REGISTRY[m] = NEXT_ARCHETYPE_ID
    ARCHETYPE_ID_TO_MASK[NEXT_ARCHETYPE_ID] = m
    inc NEXT_ARCHETYPE_ID

  return (m, ARCHETYPE_ID_REGISTRY[m])

macro toArchetypeID(comps: static openArray[int]): int =
  let (_, id) = toArchetypeIDC(comps)
  return quote do: `id`

macro typesToArchetypeID(comps:varargs[typed]): int =
  var compIds = newNimNode(nnkBracket)
  for c in comps:
    echo c
    compIds.add quote("@") do: 
      toComponentId(`@c`)

  return quote do: toArchetypeID(`compIds`)

proc getComponentsMetadata(comps:NimNode): tuple[ids: NimNode, components:seq[NimNode]] =
  var compIds = newNimNode(nnkBracket)
  var components: seq[NimNode]
  for comp in comps:
    components.add(comp)
    let id = getComponentIdFromRegistry(comp)
    let required = getRequiredCompsNode(id)
    for c in required:
      components.add(c)
      compIds.add quote("@") do:
        toComponentId(`@c`)
    
    compIds.add quote("@") do:
      toComponentId(`@comp`)
  if compIds.len == 0:
    compIds = quote("@") do: array[0, int](`@compIds`)

  return (compIds, components)

type
  ComponentEntry = ref object
    ## Raw pointer to the underlying SoAFragmentArray.
    ## This is type-erased and must be cast back using `castTo`.
    rawPointer: pointer

    ## Resize the number of dense blocks.
    resizeOp: proc (p:pointer, n:int) {.noSideEffect, nimcall, inline.}

    ## Allocate a dense block at a specific index.
    newBlockAtOp: proc (p:pointer, i:int) {.noSideEffect, nimcall, inline.}

    ## Allocate a dense block at a given offset.
    newBlockOp: proc (p:pointer, offset:int) {.noSideEffect, nimcall, inline.}

    ## Allocate or update a sparse block.
    newSparseBlockOp: proc (p:pointer, offset:int, m:uint) {.noSideEffect, nimcall, inline.}

    ## Allocate multiple sparse blocks at once.
    newSparseBlocksOp: proc (p:pointer, offset:int, m:seq[uint]) {.noSideEffect, nimcall, inline.}

    ## Override one value with another (dense/dense or sparse/sparse via packed IDs).
    overrideValsOp: proc (p:pointer, i:uint, j:uint)  {.noSideEffect, nimcall, inline.}

    ## Override a dense value with a sparse value.
    overrideDSOp: proc (p:pointer, d:DenseHandle, s:SparseHandle)  {.noSideEffect, nimcall, inline.}

    ## Override a sparse value with a dense value.
    overrideSDOp: proc (p:pointer, s:SparseHandle, d:DenseHandle)  {.noSideEffect, nimcall, inline.}

    ## Batch override used during archetype transitions.
    overrideValsBatchOp: proc (
      p:pointer,
      archId:uint16,
      ents: ptr seq[ptr Entity],
      ids:openArray[DenseHandle],
      sw:seq[uint],
      ad:seq[uint]
    )

    ## Get the per-slot change mask for a dense block.
    getChangeMaskop: proc (p:pointer):ptr QueryFilter {.noSideEffect, nimcall, inline.}

    ## Get the global sparse change bitset.
    getSparseChangeMaskop: proc (p:pointer):ptr HibitsetType {.noSideEffect, nimcall, inline.}

    ## Get the sparse activation mask.
    getSparseMaskOp: proc (p:pointer):ptr HibitsetType {.noSideEffect, nimcall, inline.}

    ## Get the mask of a specific sparse chunk.
    getSparseChunkMaskOp: proc(p:pointer, i:int):uint {.noSideEffect, nimcall, inline.}

    ## Set the sparse mask (currently unused / placeholder).
    setSparseMaskOp: proc (p:pointer, m:seq[uint]) {.noSideEffect, nimcall, inline.}

    ## Clear all dense change tracking.
    clearDenseChangeOp: proc(p:pointer) {.noSideEffect, nimcall, inline.}

    ## Clear all sparse change tracking.
    clearSparseChangeOp: proc(p:pointer) {.noSideEffect, nimcall, inline.}

    ## Activate a single sparse bit.
    activateSparseBitOp: proc (p:pointer, i:uint) {.noSideEffect, nimcall, inline.}

    ## Activate multiple sparse bits.
    activateSparseBitBatchOp: proc (p:pointer, i:seq[uint]) {.noSideEffect, nimcall, inline.}

    ## Deactivate a single sparse bit.
    deactivateSparseBitOp: proc (p:pointer, i:uint) {.noSideEffect, nimcall, inline.}

    ## Deactivate multiple sparse bits.
    deactivateSparseBitBatchOp: proc (p:pointer, i:seq[uint]) {.noSideEffect, nimcall, inline.}

    freeEntry: proc (p:pointer) {.raises: [].}

  ## Global registry holding all component types.
  ##
  ## Components are indexed by an integer ID and also mapped by name.
  ComponentRegistry = object
    entries:seq[ComponentEntry]
    cmap:Table[string, int]

macro registerComponent(registry:untyped, B:typed, P:static bool=false):untyped =
  ## Register a component type `B` into the given registry.
  ##
  ## This macro:
  ## - Allocates a new `SoAFragmentArray` for the component
  ## - Creates a `ComponentEntry` with type-erased function pointers
  ## - Stores the entry in the registry and returns its component ID
  ##
  ## Parameters:
  ## - registry: the ComponentRegistry instance
  ## - B: component type (AoS)
  ## - P: enable/disable change tracking
  let str = B.getType()[1].strVal

  return quote do:
    let id = toComponentId(`B`)

    if id >= `registry`.entries.len or `registry`.entries[id].isNil:
      `registry`.cmap[`str`] = id
      if id >= `registry`.entries.len: 
        `registry`.entries.setLen(id+1)
      
      # Allocate SoA storage for the component
      var frag = newSoAFragArr(`B`, DEFAULT_BLK_SIZE, `P`)

      # Prevent GC from collecting the fragment array
      GC_ref(frag)
      let pt = cast[pointer](frag)

      # --- Dense operations ---

      let res = proc (p:pointer, n:int) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.resize(n)

      let newBlkAt = proc (p:pointer, i:int) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.newBlockAt(i)

      # --- Sparse operations ---

      let newSparseBlk = proc (p:pointer, offset:int, m:uint) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.newSparseBlock(offset, m)

      let newSparseBlks = proc (p:pointer, offset:int, m:seq[uint]) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.newSparseBlocks(offset, m)

      let actBitB = proc (p:pointer, idxs:seq[uint]) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.activateSparseBit(idxs)

      let deactBitB = proc (p:pointer, idxs:seq[uint]) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.deactivateSparseBit(idxs)

      # --- Override operations ---

      let overv = proc (p:pointer, i,j:uint) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,false)
        fr.overrideVals(i, j)

      let overDS = proc (p:pointer, d:DenseHandle,s:SparseHandle) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,false)
        let bidi = (d.obj.id shr BLK_SHIFT) and BLK_MASK
        let idxi = d.obj.id and BLK_MASK
        let sbid = s.id shr 6
        let si = s.id and 63
        let physIdx = fr.toSparse[sbid] - 1
        toObjectCopy(`B`, fr.blocks[bidi].data, idxi, fr.sparse[physIdx].data, si)

      let overSD = proc (p:pointer,s:SparseHandle, d:DenseHandle) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,false)
        let bidi = (d.obj.id shr BLK_SHIFT) and BLK_MASK
        let idxi = d.obj.id and BLK_MASK
        let sbid = s.id shr 6
        let si = s.id and 63
        let physIdx = fr.toSparse[sbid] - 1
        toObjectCopy(`B`, fr.sparse[physIdx].data, si, fr.blocks[bidi].data, idxi)

      let overvb = proc (p:pointer, archId:uint16, ents: ptr seq[ptr Entity], ids:openArray[DenseHandle], sw:seq[uint], ad:seq[uint]) =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,false)
        fr.overrideVals(archId, ents, ids, sw, ad)

      # --- Change tracking accessors ---

      let getchangeMask = proc (p:pointer):ptr QueryFilter {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        return addr fr.changeFilter

      let getsmask = proc (p:pointer):ptr HibitsetType {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        return addr fr.sparseMask

      let clearDCh = proc (p:pointer) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.clearDenseChanges()

      let clearSCh = proc (p:pointer) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.clearSparseChanges()

      let actSparseBit = proc (p:pointer, i:uint) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.activateSparseBit(i)

      let deactSparseBit = proc (p:pointer, i:uint) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        fr.deactivateSparseBit(i)

      # --- Build registry entry ---

      var entry:ComponentEntry
      new(entry)
      entry.rawPointer = pt
      entry.resizeOp = res
      entry.newBlockAtOp = newBlkAt
      entry.newSparseBlockOp = newSparseBlk
      entry.newSparseBlocksOp = newSparseBlks
      entry.overrideValsOp = overv
      entry.overrideDSOp = overDS
      entry.overrideSDOp = overSD
      entry.overrideValsBatchOp = overvb
      entry.getChangeMaskop = getchangeMask
      entry.getSparseMaskOp = getsmask
      entry.clearDenseChangeOp = clearDCh
      entry.clearSparseChangeOp = clearSCh
      entry.deactivateSparseBitOp = deactSparseBit
      entry.activateSparseBitOp = actSparseBit
      entry.activateSparseBitBatchOp = actBitB
      entry.deactivateSparseBitBatchOp = deactBitB
      entry.freeEntry = proc (p:pointer) {.raises: [].} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
        GC_unref(fr)

      # Register entry and return its component ID
      `registry`.entries[id] = entry

    id

proc getEntry(r:ComponentRegistry, i:int):ComponentEntry =
  ## Retrieve a component entry by its ID.
  return r.entries[i]

template getvalue[B](entry:ComponentEntry, P:static bool=false):untyped =
  ## Cast the raw pointer of a component entry back to its typed
  ## `SoAFragmentArray`.
  castTo(entry.rawPointer, B, DEFAULT_BLK_SIZE,P)

proc `=destroy`(rg:var ComponentRegistry) {.raises: [].} = 
  for entry in rg.entries:
    if not entry.isNil: entry.freeEntry(entry.rawPointer)

  rg.entries = @[]