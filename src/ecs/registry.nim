####################################################################################################################################################
############################################################# COMPONENT REGISTRY ###################################################################
####################################################################################################################################################

## The component registry provides a type-erased interface over SoA-backed
## component storage.
##
## Each registered component is stored as a `SoAFragmentArray`, but is exposed
## through a table of function pointers so higher-level systems (ECS, archetypes,
## schedulers) can manipulate components without knowing their concrete type.

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
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.overrideVals(i, j)

    let overDS = proc (p:pointer, d:DenseHandle,s:SparseHandle) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      let r = fr[s]
      fr[d] = r

    let overSD = proc (p:pointer,s:SparseHandle, d:DenseHandle) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      let r = fr[d]
      fr[s] = r

    let overvb = proc (p:pointer, archId:uint16, ents: ptr seq[ptr Entity], ids:openArray[DenseHandle], sw:seq[uint], ad:seq[uint]) =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
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
    let id = `registry`.entries.len
    `registry`.cmap[`str`] = id
    `registry`.entries.add(entry)

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
    entry.freeEntry(entry.rawPointer)

  rg.entries = @[]