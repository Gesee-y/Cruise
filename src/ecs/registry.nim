####################################################################################################################################################
############################################################# COMPONENT REGISTRY ###################################################################
####################################################################################################################################################

type
  ComponentEntry = ref object
    rawPointer: pointer
    resizeOp: proc (p:pointer, n:int) {.noSideEffect, nimcall, inline.}
    newBlockAtOp: proc (p:pointer, i:int) {.noSideEffect, nimcall, inline.}
    newBlockOp: proc (p:pointer, offset:int) {.noSideEffect, nimcall, inline.}
    newSparseBlockOp: proc (p:pointer, offset:int, m:uint) {.noSideEffect, nimcall, inline.}
    newSparseBlocksOp: proc (p:pointer, m:seq[uint]) {.noSideEffect, nimcall, inline.}
    overrideValsOp: proc (p:pointer, i:uint, j:uint)  {.noSideEffect, nimcall, inline.}
    overrideDSOp: proc (p:pointer, d:DenseHandle, s:SparseHandle)  {.noSideEffect, nimcall, inline.}
    overrideSDOp: proc (p:pointer, s:SparseHandle, d:DenseHandle)  {.noSideEffect, nimcall, inline.}
    overrideValsBatchOp: proc (p:pointer, archId:uint16, ents: ptr seq[ptr Entity], ids:openArray[DenseHandle], sw:seq[uint], ad:seq[uint])
    getSparseMaskOp: proc (p:pointer):seq[uint] {.noSideEffect, nimcall, inline.}
    getSparseChunkMaskOp: proc(p:pointer, i:int):uint {.noSideEffect, nimcall, inline.}
    setSparseMaskOp: proc (p:pointer, m:seq[uint]) {.noSideEffect, nimcall, inline.}
    activateSparseBitOp: proc (p:pointer, i:uint) {.noSideEffect, nimcall, inline.}
    activateSparseBitBatchOp: proc (p:pointer, i:seq[uint]) {.noSideEffect, nimcall, inline.}
    deactivateSparseBitOp: proc (p:pointer, i:uint) {.noSideEffect, nimcall, inline.}
    deactivateSparseBitBatchOp: proc (p:pointer, i:seq[uint]) {.noSideEffect, nimcall, inline.}

  ComponentRegistry = ref object
    entries:seq[ComponentEntry]
    cmap:Table[string, int]

macro registerComponent(registry:untyped, B:typed, P:static bool=false):untyped =
  let str = B.getType()[1].strVal

  return quote do:
    var frag = newSoAFragArr(`B`, DEFAULT_BLK_SIZE, `P`)

    GC_ref(frag)
    let pt = cast[pointer](frag)

    let res = proc (p:pointer, n:int) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.resize(n)

    let newBlkAt = proc (p:pointer, i:int) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.newBlockAt(i)

    let newBlk = proc (p:pointer, offset:int) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      discard fr.newBlock(offset)

    let newSparseBlk = proc (p:pointer, offset:int, m:uint) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.newSparseBlock(offset, m)

    let newSparseBlks = proc (p:pointer, m:seq[uint]) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.newSparseBlocks(m)

    let actBitB = proc (p:pointer, idxs:seq[uint]) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.activateSparseBit(idxs)

    let deactBitB = proc (p:pointer, idxs:seq[uint]) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.deactivateSparseBit(idxs)

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

    let getsmask = proc (p:pointer):seq[uint] {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      return fr.sparseMask

    let getscmask = proc (p:pointer, i:int):uint {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      return fr.sparse[i].mask

    let setsmask = proc (p:pointer, m:seq[uint]) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.sparseMask = m

    let actSparseBit = proc (p:pointer, i:uint) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.activateSparseBit(i)

    let deactSparseBit = proc (p:pointer, i:uint) {.noSideEffect, nimcall, inline.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE,`P`)
      fr.deactivateSparseBit(i)

    var entry:ComponentEntry
    new(entry)
    entry.rawPointer = pt
    entry.resizeOp = res
    entry.newBlockAtOp = newBlkAt
    entry.newBlockOp = newBlk
    entry.newSparseBlockOp = newSparseBlk
    entry.newSparseBlocksOp = newSparseBlks
    entry.overrideValsOp = overv
    entry.overrideDSOp = overDS
    entry.overrideSDOp = overSD
    entry.overrideValsBatchOp = overvb
    entry.getSparseMaskOp = getsmask
    entry.getSparseChunkMaskOp = getscmask
    entry.setSparseMaskOp = setsmask
    entry.deactivateSparseBitOp = deactSparseBit
    entry.activateSparseBitOp = actSparseBit
    entry.activateSparseBitBatchOp = actBitB
    entry.deactivateSparseBitBatchOp = deactBitB

    let id = `registry`.entries.len
    `registry`.cmap[`str`] = id
    `registry`.entries.add(entry)

    id

proc getEntry(r:ComponentRegistry, i:int):ComponentEntry =
  return r.entries[i]

template getvalue[B](entry:ComponentEntry, P:static bool=false):untyped =
  castTo(entry.rawPointer, B, DEFAULT_BLK_SIZE,P)