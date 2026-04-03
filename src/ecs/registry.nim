####################################################################################################################################################
############################################################# COMPONENT REGISTRY ###################################################################
####################################################################################################################################################
##
## Type-erased component registry for the Cruise ECS.
##
## Each registered component type (``Position``, ``Velocity``, etc.) gets a
## unique compile-time ID and a ``ComponentEntry`` that stores function pointers
## to operate on the underlying ``SoAFragmentArray`` without knowing its
## concrete type.
##
## The registry also manages archetype ID assignment at compile time.
##
## Usage example
## =============
##
## .. code-block:: nim
##   import cruise/ecs/registry
##
##   type
##     Position = object
##       x, y: float32
##     Velocity = object
##       vx, vy: float32
##
##   var reg: ComponentRegistry
##   let posId = reg.registerComponent(Position)
##   let velId = reg.registerComponent(Velocity)
##
##   # posId and velId are stable compile-time integers
##   echo "Position ID: ", posId   # → 0
##   echo "Velocity ID: ", velId   # → 1

import std/[tables, hashes, macros, typetraits]
import ./types
import ./fragment
import ./hibitset
import ./mask
export types, fragment, hibitset, mask

# ──── NOTE ─────────────────────────────────────────────────────────────── #
# Type definitions for ComponentEntry and ComponentRegistry live in        #
# types.nim.  This file contains the compile-time registration macros and  #
# the runtime accessor procs.                                             #
# ─────────────────────────────────────────────────────────────────────── #

# ─── Compile-time ID counters ────────────────────────────────────────── #

var NEXT_COMPONENT_ID* {.compileTime.} = 0
  ## Next available component ID (monotonically increasing).

var NEXT_ARCHETYPE_ID* {.compileTime.} = 0
  ## Next available archetype ID.

var COMPONENT_ID_REGISTRY* {.compileTime.} = initTable[int, int]()
  ## Maps ``hash(typeName)`` → component ID.

var ARCHETYPE_ID_REGISTRY* {.compileTime.} = initTable[ArchetypeMask, int]()
  ## Maps component mask → archetype ID.

var ARCHETYPE_ID_TO_MASK* {.compileTime.} = initTable[int, ArchetypeMask]()
  ## Reverse mapping: archetype ID → mask.

static:
  # Register the empty archetype (root node) at compile time.
  var r: ArchetypeMask
  ARCHETYPE_ID_REGISTRY[r] = NEXT_ARCHETYPE_ID
  ARCHETYPE_ID_TO_MASK[NEXT_ARCHETYPE_ID] = r
  inc NEXT_ARCHETYPE_ID

# ─── Compile-time ID macros ─────────────────────────────────────────────── #

macro toComponentId*(T: typedesc): int =
  ## Returns the unique component ID for type ``T``.
  ## Allocates a new ID on first call.
  ##
  ## Example
  ## -------
  ## .. code-block:: nim
  ##   let id = toComponentId(Position)  # compile-time constant
  let str = T.getTypeInst.repr
  let hash = T.getTypeInst.repr.hash.int
  let maxComp = MAX_COMPONENT_LAYER*UINT_BITS

  if hash notin COMPONENT_ID_REGISTRY:
    if NEXT_COMPONENT_ID < maxComp:
      COMPONENT_ID_REGISTRY[hash] = NEXT_COMPONENT_ID
      inc NEXT_COMPONENT_ID
    else:
      error "Failed to add " & str & ". Can't have more than " & $maxComp & " components."

  let id = COMPONENT_ID_REGISTRY[hash]
  return quote do: `id`

macro toArchetypeID*(comps: static openArray[int]): int =
  ## Returns the unique archetype ID for a set of component IDs.
  var m: ArchetypeMask
  for c in comps:
    m.withComponentInPlace(c)

  if m notin ARCHETYPE_ID_REGISTRY:
    ARCHETYPE_ID_REGISTRY[m] = NEXT_ARCHETYPE_ID
    ARCHETYPE_ID_TO_MASK[NEXT_ARCHETYPE_ID] = m
    inc NEXT_ARCHETYPE_ID

  let id = ARCHETYPE_ID_REGISTRY[m]
  return quote do: `id`

macro typesToArchetypeID*(comps: varargs[typed]): int =
  ## Converts a list of component **types** to an archetype ID.
  var compIds = newNimNode(nnkBracket)
  for c in comps:
    compIds.add quote("@") do:
      toComponentId(`@c`)

  return quote do: toArchetypeID(`compIds`)

# ─── Registration macro ─────────────────────────────────────────────────── #

macro registerComponent*(registry: untyped, B: typed,
    P: static bool = false): untyped =
  ## Register component type ``B`` into the given registry.
  ##
  ## This macro:
  ## - Allocates a ``SoAFragmentArray`` for the component
  ## - Creates a ``ComponentEntry`` with type-erased function pointers
  ## - Stores the entry in the registry and returns its component ID
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

      let res = proc (p: pointer, n: int) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.resize(n)

      let newBlkAt = proc (p: pointer, i: int) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.newBlockAt(i)

      # --- Sparse operations ---

      let newSparseBlk = proc (p: pointer, offset: int, m: uint) {.noSideEffect,
          nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.newSparseBlock(offset, m)

      let newSparseBlks = proc (p: pointer, offset: int, m: seq[
          uint]) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.newSparseBlocks(offset, m)

      let actBitB = proc (p: pointer, idxs: seq[uint]) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.activateSparseBit(idxs)

      let deactBitB = proc (p: pointer, idxs: seq[uint]) {.noSideEffect,
          nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.deactivateSparseBit(idxs)

      # --- Override operations ---

      let overv = proc (p: pointer, i, j: uint) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, false)
        fr.overrideVals(i, j)

      let overDS = proc (p: pointer, d: DenseHandle,
          s: SparseHandle) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, false)
        let bidi = (d.obj.id shr BLK_SHIFT) and BLK_MASK
        let idxi = d.obj.id and BLK_MASK
        let sbid = s.id shr 6
        let si = s.id and 63
        let physIdx = fr.toSparse[sbid] - 1
        toObjectCopy(`B`, fr.blocks[bidi].data, idxi, fr.sparse[physIdx].data, si)

      let overSD = proc (p: pointer, s: SparseHandle,
          d: DenseHandle) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, false)
        let bidi = (d.obj.id shr BLK_SHIFT) and BLK_MASK
        let idxi = d.obj.id and BLK_MASK
        let sbid = s.id shr 6
        let si = s.id and 63
        let physIdx = fr.toSparse[sbid] - 1
        toObjectCopy(`B`, fr.sparse[physIdx].data, si, fr.blocks[bidi].data, idxi)

      let overvb = proc (p: pointer, archId: uint16, ents: ptr seq[ptr Entity],
          ids: openArray[DenseHandle], sw: seq[uint], ad: seq[uint]) =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, false)
        fr.overrideVals(archId, ents, ids, sw, ad)

      # --- Change tracking accessors ---

      let getchangeMask = proc (p: pointer): ptr QueryFilter {.noSideEffect,
          nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        return addr fr.changeFilter

      let getsmask = proc (p: pointer): ptr HiBitSetType {.noSideEffect,
          nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        return addr fr.sparseMask

      let clearDCh = proc (p: pointer) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.clearDenseChanges()

      let clearSCh = proc (p: pointer) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.clearSparseChanges()

      let actSparseBit = proc (p: pointer, i: uint) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.activateSparseBit(i)

      let deactSparseBit = proc (p: pointer, i: uint) {.noSideEffect, nimcall, inline.} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        fr.deactivateSparseBit(i)

      # --- Build registry entry ---

      var entry: ComponentEntry
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
      entry.freeEntry = proc (p: pointer) {.raises: [].} =
        var fr = castTo(p, `B`, DEFAULT_BLK_SIZE, `P`)
        GC_unref(fr)

      `registry`.entries[id] = entry

    id

# ─── Runtime accessors ──────────────────────────────────────────────────── #

proc getEntry*(r: ComponentRegistry, i: int): ComponentEntry =
  ## Retrieve a component entry by its ID.
  return r.entries[i]

template getvalue*[B](entry: ComponentEntry, P: static bool = false): untyped =
  ## Cast the raw pointer of a component entry back to its typed
  ## ``SoAFragmentArray``.
  castTo(entry.rawPointer, B, DEFAULT_BLK_SIZE, P)

proc destroy*(rg: var ComponentRegistry) {.raises: [].} =
  ## Clean up all component storage on registry destruction.
  for entry in rg.entries:
    if not entry.isNil: entry.freeEntry(entry.rawPointer)
  rg.entries = @[]
