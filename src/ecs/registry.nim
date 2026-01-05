####################################################################################################################################################
############################################################# COMPONENT REGISTRY ###################################################################
####################################################################################################################################################

type
  ComponentEntry = object
    rawPointer: pointer
    resizeOp: proc (p:pointer, n:int)
    newBlockAtOp: proc (p:pointer, i:int)
    newBlockOp: proc (p:pointer, offset:int)
    activateBitOp: proc (p:pointer, i:int)
    deactivateBitOp: proc (p:pointer, i:int)
    overrideValsOp: proc (p:pointer, i:int, j:int)

  ComponentRegistry = ref object
    entries:seq[ComponentEntry]
    cmap:Table[string, int]

template registerComponent[B](registry:ComponentRegistry) =
  var frag = newSoAFragArr(B, DEFAULT_BLK_SIZE)
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

  let actBit = proc (p:pointer, i:int) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.activateBit(i)

  let deactBit = proc (p:pointer, i:int) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.deactivateBit(i)

  let overv = proc (p:pointer, i,j:int) =
    var fr = castTo(p, B, DEFAULT_BLK_SIZE)
    fr.overrideVals(i, j)

  var entry:ComponentEntry
  entry.rawPointer = pt
  entry.resizeOp = res
  entry.newBlockAtOp = newBlkAt
  entry.newBlockOp = newBlk
  entry.activateBitOp = actBit
  entry.deactivateBitOp = deactBit
  entry.overrideValsOp = overv

  registry.cmap[$B] = registry.entries.len
  registry.entries.add(entry)

proc getEntry(r:ComponentRegistry, i:int):ComponentEntry =
  return r.entries[i]

template getvalue[B](entry:ComponentEntry):untyped =
  castTo(entry.rawPointer, B, DEFAULT_BLK_SIZE)