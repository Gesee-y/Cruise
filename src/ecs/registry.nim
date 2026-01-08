####################################################################################################################################################
############################################################# COMPONENT REGISTRY ###################################################################
####################################################################################################################################################

type
  ComponentEntry = object
    rawPointer: pointer
    resizeOp: proc (p:pointer, n:int)
    newBlockAtOp: proc (p:pointer, i:int)
    newBlockOp: proc (p:pointer, offset:int)
    newSparseBlockOp: proc(p:pointer, offset:int, m:uint)
    activateBitOp: proc (p:pointer, i:int)
    deactivateBitOp: proc (p:pointer, i:int)
    overrideValsOp: proc (p:pointer, i:uint, j:uint)
    getSparseMaskOp: proc (p:pointer):seq[uint]
    getSparseChunkMaskOp: proc(p:pointer, i:int):uint
    setSparseMaskOp: proc (p:pointer, m:seq[uint])
    activateSparseBitOp: proc (p:pointer, i:uint)
    deactivateSparseBitOp: proc (p:pointer, i:uint)

  ComponentRegistry = ref object
    entries:seq[ComponentEntry]
    cmap:Table[string, int]

template registerComponent[B](registry:ComponentRegistry):int =
  var frag = newSoAFragArr(B, DEFAULT_BLK_SIZE)

  GC_ref(frag)
  let pt = cast[pointer](frag)

  let res = proc (p:pointer, n:int) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.resize(n)

  let newBlkAt = proc (p:pointer, i:int) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.newBlockAt(i)

  let newBlk = proc (p:pointer, offset:int) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    discard fr.newBlock(offset)

  let newSparseBlk = proc (p:pointer, offset:int, m:uint) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.newSparseBlock(offset, m)

  let actBit = proc (p:pointer, i:int) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.activateBit(i)

  let deactBit = proc (p:pointer, i:int) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.deactivateBit(i)

  let overv = proc (p:pointer, i,j:uint) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.overrideVals(i, j)

  let getsmask = proc (p:pointer):seq[uint] =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    return fr.sparseMask

  let getscmask = proc (p:pointer, i:int):uint =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    return fr.sparse[i].mask

  let setsmask = proc (p:pointer, m:seq[uint]) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.sparseMask = m

  let actSparseBit = proc (p:pointer, i:uint) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.activateSparseBit(i)

  let deactSparseBit = proc (p:pointer, i:uint) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
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
  entry.getSparseMaskOp = getsmask
  entry.getSparseChunkMaskOp = getscmask
  entry.setSparseMaskOp = setsmask
  entry.deactivateSparseBitOp = deactSparseBit
  entry.activateSparseBitOp = actSparseBit

  let id = registry.entries.len
  registry.cmap[$B] = id
  registry.entries.add(entry)

  id

proc getEntry(r:ComponentRegistry, i:int):ComponentEntry =
  return r.entries[i]

template getvalue[B](entry:ComponentEntry):untyped =
  castTo(entry.rawPointer, B, DEFAULT_BLK_SIZE)