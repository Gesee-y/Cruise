####################################################################################################################################################
############################################################# COMPONENT REGISTRY ###################################################################
####################################################################################################################################################

type
  ComponentEntry = object
    rawPointer: pointer
    resizeOp: proc (p:pointer, n:int) {.noSideEffect, nimcall.}
    newBlockAtOp: proc (p:pointer, i:int) {.noSideEffect, nimcall.}
    newBlockOp: proc (p:pointer, offset:int) {.noSideEffect, nimcall.}
    newSparseBlockOp: proc (p:pointer, offset:int, m:uint) {.noSideEffect, nimcall.}
    activateBitOp: proc (p:pointer, i:int) {.noSideEffect, nimcall.}
    deactivateBitOp: proc (p:pointer, i:int) {.noSideEffect, nimcall.}
    overrideValsOp: proc (p:pointer, i:uint, j:uint)  {.noSideEffect, nimcall.}
    overrideValsBatchOp: proc (p:pointer, archId:uint16, ents: ptr seq[ptr Entity], ids:openArray[DenseHandle], sw:seq[uint], ad:seq[uint])
    getSparseMaskOp: proc (p:pointer):seq[uint] {.noSideEffect, nimcall.}
    getSparseChunkMaskOp: proc(p:pointer, i:int):uint {.noSideEffect, nimcall.}
    setSparseMaskOp: proc (p:pointer, m:seq[uint]) {.noSideEffect, nimcall.}
    activateSparseBitOp: proc (p:pointer, i:uint) {.noSideEffect, nimcall.}
    activateSparseBitBatchOp: proc (p:pointer, i:seq[uint]) {.noSideEffect, nimcall.}
    deactivateSparseBitOp: proc (p:pointer, i:uint) {.noSideEffect, nimcall.}
    activateSparseBitBatchOp: proc (p:pointer, i:seq[uint]) {.noSideEffect, nimcall.}

  ComponentRegistry = ref object
    entries:seq[ComponentEntry]
    cmap:Table[string, int]

macro registerComponent(registry:untyped, B:typed):untyped =
  let str = B.getType()[1].strVal

  return quote do:
    var frag = newSoAFragArr(`B`, DEFAULT_BLK_SIZE)

    GC_ref(frag)
    let pt = cast[pointer](frag)

    let res = proc (p:pointer, n:int) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.resize(n)

    let newBlkAt = proc (p:pointer, i:int) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.newBlockAt(i)

    let newBlk = proc (p:pointer, offset:int) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      discard fr.newBlock(offset)

    let newSparseBlk = proc (p:pointer, offset:int, m:uint) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.newSparseBlock(offset, m)

    let actBit = proc (p:pointer, i:int) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.activateBit(i)

    let deactBit = proc (p:pointer, i:int) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.deactivateBit(i)

    let actBitB = proc (p:pointer, idxs:seq[uint]) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.activateSparseBit(idxs)

    let deactBitB = proc (p:pointer, idxs:seq[uint]) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.deactivateSparseBit(idxs)

    let overv = proc (p:pointer, i,j:uint) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.overrideVals(i, j)

    let overvb = proc (p:pointer, archId:uint16, ents: ptr seq[ptr Entity], ids:openArray[DenseHandle], sw:seq[uint], ad:seq[uint]) =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.overrideVals(archId, ents, ids, sw, ad)

    let getsmask = proc (p:pointer):seq[uint] {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      return fr.sparseMask

    let getscmask = proc (p:pointer, i:int):uint {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      return fr.sparse[i].mask

    let setsmask = proc (p:pointer, m:seq[uint]) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.sparseMask = m

    let actSparseBit = proc (p:pointer, i:uint) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.activateSparseBit(i)

    let deactSparseBit = proc (p:pointer, i:uint) {.noSideEffect, nimcall.} =
      var fr = castTo(p, `B`, DEFAULT_BLK_SIZE)
      fr.deactivateSparseBit(i)

    var entry:ComponentEntry
    entry.rawPointer = pt
    entry.resizeOp = res
    entry.newBlockAtOp = newBlkAt
    entry.newBlockOp = newBlk
    entry.newSparseBlockOp = newSparseBlk
    entry.activateBitOp = actBit
    entry.deactivateBitOp = deactBit
    entry.overrideValsOp = overv
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

template getvalue[B](entry:ComponentEntry):untyped =
  castTo(entry.rawPointer, B, DEFAULT_BLK_SIZE)