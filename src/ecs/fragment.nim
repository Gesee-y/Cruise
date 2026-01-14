####################################################################################################################################################
############################################################## FRAGMENT ARRAYS #####################################################################
####################################################################################################################################################

import macros

type
  SoAFragment*[N:static int,P:static bool,T,B] = object
    data*:T
    offset:int
    mask:uint
    valMask:seq[uint]

  SoAFragmentArray*[N:static int,P:static bool,T,S,B] = ref object
    blocks*:seq[ref SoAFragment[N,P,T,B]]
    blkChangeMask:seq[uint]
    sparse*:seq[SoAFragment[sizeof(uint)*8,P,S,B]]
    sparseChangeMask:seq[uint]
    toSparse:seq[int]
    mask:seq[uint]
    sparseMask:seq[uint]


const
  BLK_MASK = (1 shl 32) - 1
  BLK_SHIFT = 32
  DEFAULT_BLK_SIZE = 4096
  INITIAL_SPARSE_SIZE = 1000

proc toSoATuple(T:NimNode, N:int):NimNode  =
  ## This macro transform a type into a tuple compatible for the SoA fragmebt
  ## It decompose the type into fields that becomes indepedent array.

  var res = newNimNode(nnkTupleTy) # We initialize the tuple type
  let o = T.getType()[2] # Here we get the list of fields of our type
  
  # Then for each field we build the identifer definition 
  for f in o:
    let v = f.getType()
    var identdef = newNimNode(nnkIdentDefs)
    var brack = newNimNode(nnkBracketExpr)
    var intl = newNimNode(nnkIntLit)
    
    identdef.add(ident(f.strVal))
    identdef.add(brack)
    identdef.add(newNimNode(nnkEmpty))
    
    brack.add(ident"array")
    brack.add(intl)
    brack.add(ident(v.strVal))
    
    intl.intVal = N
    
    res.add(identdef)

  return res

macro castTo(obj:untyped, Ty:typedesc, N:static int, P:static bool=false):untyped =
  let T = Ty.getTypeInst()[1]
  let ty = toSoATuple(Ty.getType[1], N)
  let sy = toSoATuple(Ty.getType[1], sizeof(uint)*8)
  return quote("@") do:
    cast[SoAFragmentArray[`@N`,`@P`,`@ty`,`@sy`,`@T`]](`@obj`) 

macro newSoAFragArr(Ty:typedesc, N:static int, P:static bool=false):untyped =
  let T = Ty.getTypeInst()[1]
  let ty = toSoATuple(Ty.getType[1], N)
  let sy = toSoATuple(Ty.getType[1], sizeof(uint)*8)
  let S = sizeof(uint)*8
  return quote("@") do:
    let f = new(SoAFragmentArray[`@N`,`@P`,`@ty`,`@sy`,`@T`])
    f.sparse = newSeqOfCap[SoAFragment[`@S`,`@P`,`@sy`,`@T`]](INITIAL_SPARSE_SIZE)
    f.toSparse = newSeqOfCap[int](INITIAL_SPARSE_SIZE*`@S`)
    f

macro SoAFragArr(N:static int,stmt:typed) =
  for section in stmt:
    case section.kind:
      of nnkVarSection, nnkLetSection, nnkConstSection:
        for identdef in section:
          var ridentdef = newNimNode(nnkIdentDefs)
          var brack = newNimNode(nnkBracketExpr)
          var intl = newNimNode(nnkIntLit)
          let ty = toSoATuple(identdef[1], N)

          intl.intVal = N

          brack.add(ident"SoAFragmentArray")
          brack.add(intl)
          brack.add(ty)
          brack.add(ident(identdef[1].strVal))

          identdef[0] = (ident(identdef[0].strVal))
          identdef[1] = brack
      else: continue

  return quote("@") do:
    `@stmt`

####################################################################################################################################################
############################################################### OPERATIONS #########################################################################
####################################################################################################################################################

macro toObject(Ty:typedesc, c:untyped, idx:untyped):untyped =
  let T = Ty.getTypeInst()[1]
  var res = newNimNode(nnkObjConstr)
  let ty = Ty.getType()[1].getType()[2]
  res.add(T)

  for f in ty:
    var ex = newNimNode(nnkExprColonExpr)
    var brack = newNimNode(nnkBracketExpr)
    var brack2 = newNimNode(nnkDotExpr)

    ex.add(ident(f.strVal))
    brack2.add(c)
    brack2.add(ident(f.strVal))
    brack.add(brack2)
    brack.add(idx)
    ex.add(brack)
    res.add(ex)

  return quote("@") do:
    `@res`

macro toObjectParam(T:typedesc, c:untyped, idx:untyped): untyped =
  ## Cette version respecte l'hygiène de Nim et évite les redéclarations en C.
  let typeNode = T.getType()
  
  let typeName = typeNode[1].strVal
  let constructorName = ident("new" & typeName)

  let fields = typeNode[1].getType()[2]

  var res = newNimNode(nnkCall)
  res.add(constructorName)

  for f in fields:
    let fieldAccess = newDotExpr(c, ident(f.strVal))
    let bracketAccess = newNimNode(nnkBracketExpr).add(fieldAccess, idx)
    res.add(bracketAccess)

  return res

macro toObjectMod(T:typedesc, c:untyped, idx:untyped, v:untyped) =
  var res = newNimNode(nnkStmtList)
  let ty = T.getType()[1].getType()[2]

  for f in ty:
    var asg = newNimNode(nnkAsgn)
    var brack = newNimNode(nnkBracketExpr)
    var dot1 = newNimNode(nnkDotExpr)
    var dot2 = newNimNode(nnkDotExpr)

    dot1.add(c)
    dot1.add(ident(f.strVal))
    brack.add(dot1)
    brack.add(idx)
    asg.add(brack)

    dot2.add(v)
    dot2.add(ident(f.strVal))
    asg.add(dot2)
    res.add(asg)

  return quote("@") do:
    `@res`

macro toObjectOverride(T:typedesc, c:untyped, idx:untyped, v:untyped) =
  var res = newNimNode(nnkStmtList)
  let ty = T.getType()[1].getType()[2]

  for f in ty:
    var asg = newNimNode(nnkAsgn)
    var brack = newNimNode(nnkBracketExpr)
    var brack2 = newNimNode(nnkBracketExpr)
    var dot1 = newNimNode(nnkDotExpr)
    var dot2 = newNimNode(nnkDotExpr)

    dot1.add(c)
    dot1.add(ident(f.strVal))
    brack.add(dot1)
    brack.add(idx)
    asg.add(brack)

    dot2.add(v)
    dot2.add(ident(f.strVal))
    brack2.add(dot2)
    brack2.add(idx)
    asg.add(brack2)
    res.add(asg)

  return quote("@") do:
    `@res`

template toIdx(i:uint):untyped =
  let id = i and BLK_MASK
  let bid = (i shr BLK_SHIFT) and BLK_MASK
  id+bid*DEFAULT_BLK_SIZE

template swapVals(b: untyped, i, j:int|uint) =
  let tmp = b[i]
  b[i] = b[j]
  b[j] = tmp

template overrideVals[N,P,T,S,B](b: SoAFragmentArray[N,P,T,S,B], i, j:int|uint) =
  b[i] = b[j]

template overrideVals[N,P,T,B](b: SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B], i, j:int|uint) =
  b[i] = b[j]

template overrideVals(f, archId, ents, ids, toSwap, toAdd:untyped) =
  for i in 0..<ids.len:
    let e = ids[i].obj
    let s = toSwap[i]
    let a = toAdd[i]
    
    f[a] = f[e]
    f[e] = f[s]
    
    ents[a.toIdx] = e
    ents[e.id.toIdx] = ents[s.toIdx]
    ents[s.toIdx].id = e.id

    e.id = a
    e.archetypeId = archId


template setChanged[N,P,T,B](f: var SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B], id:uint|int) =
  var blk = id shr 6
  var bitp = id and 63
  f.valMask[blk] = f.valMask[blk] or (1'u shl bitp)

template setChanged[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], id:uint) =
  var bid = id shr BLK_SHIFT
  var blk = bid shr 6
  var bitp = bid and 63

  if blk.int >= f.blkChangeMask.len:
    f.blkChangeMask.setLen(blk+1)
  
  f.blkChangeMask[blk] = f.blkChangeMask[blk] or (1'u shl bitp)

template setChangedSparse[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], id:uint) =
  var bid = id shr 6
  var blk = bid shr 6
  var bitp = bid and 63

  if blk.int >= f.blkChangeMask.len:
    f.blkChangeMask.setLen(blk+1)
  
  f.blkChangeMask[blk] = f.blkChangeMask[blk] or 1'u shl bitp
  
proc getDataType[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B]):typedesc[B] = B

proc newSparseBlock[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], offset:int, m:uint) =
  let S = sizeof(uint)*8
  var i = offset div S
  var j = i div S

  if i >= f.toSparse.len: 
    f.toSparse.setLen(i+1)
    f.toSparse[i] = f.sparse.len+1
  
  let id = f.toSparse[i]-1

  if id >= f.sparse.len:
    f.sparse.setLen(id+1)
  
  if j >= f.sparseMask.len: f.sparseMask.setLen(j+1)
  
  var blk = addr f.sparse[id]
  blk.offset = offset
  blk.mask = blk.mask or m
  blk.valMask = @[0'u]

  if m != 0:
    f.sparseMask[j] = f.sparseMask[j] or (1.uint shl i)

proc newSparseBlocks[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], masks:openArray[uint]) =
  let S = sizeof(uint)*8
  let base = f.sparse.len

  for c in 0..<masks.len:
    let m = masks[c]
    let i = base + c
    let j = i div S

    if i >= f.toSparse.len: 
      f.toSparse.setLen(i+1)
      f.toSparse[i] = f.sparse.len+1
    
    let id = f.toSparse[i]-1

    if id >= f.sparse.len:
      f.sparse.setLen(id+1)
    
    if j >= f.sparseMask.len: f.sparseMask.setLen(j+1)
    var blk = addr f.sparse[id]
    
    blk.mask = blk.mask or m

    if m != 0:
      f.sparseMask[j] = f.sparseMask[j] or (1.uint shl i)

proc freeSparseBlock[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], i:int) =
  discard#f.sparse[i] = nil

proc newBlockAt[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], i:int) =
 var blk:ref SoAFragment[N,P,T,B]
 new(blk)
 blk.offset = N*i
 blk.valMask.setLen(((N-1) shr 6) + 1)
 f.blocks[i] = blk

proc newBlock[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], offset:int):bool =
  var blk: ref SoAFragment[N,P,T,B]
  new(blk)
  blk.offset = offset
  blk.valMask.setLen(((N-1) shr 6) + 1)
  
  if f.blocks.len == 0 or offset >= N+f.blocks[^1].offset:
    f.blocks.add(blk)
    return true

  var right = f.blocks.len-1
  var left = 0

  while left < right:
    let center = (left + right) div 2
    if f.blocks[center].offset > offset:
      right = center - 1
    elif f.blocks[center].offset < offset:
      left = center + 1
    else: return false

  if offset - f.blocks[left].offset < N and offset - f.blocks[left].offset >= 0:
    return false

  f.blocks.insert(blk, left)
  return true

proc getBlockIdx[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:int):int =
  return i div N

proc getBlock[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:int):ref SoAFragment[N,P,T,B] =
  return f.blocks[getBlockIdx(f, i)]

template getBlock[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:uint):ref SoAFragment[N,P,T,B] =
  f.blocks[(i shr BLK_SHIFT) and BLK_MASK]

proc activateSparseBit[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], i:int|uint) =
  let S = (sizeof(uint)*8).uint
  let bid = i.uint shr 6
  let lid = i.uint and 63
  let mid = bid shr 6

  if bid.int >= f.toSparse.len:
    f.toSparse.setLen(bid+1)
    f.toSparse[bid] = f.sparse.len+1

  let id = f.toSparse[bid]-1

  if id >= f.sparse.len:
    f.sparse.setLen(id+1)

  if f.sparseMask.len.uint <= mid:
    f.sparseMask.setLen(mid+1)

  f.sparseMask[mid] = f.sparseMask[mid] or (1.uint shl bid)
  f.sparse[id].mask = f.sparse[id].mask or (1.uint shl lid)

proc activateSparseBit[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], idxs:openArray[uint]) =
  let S = (sizeof(uint)*8).uint

  for i in idxs:
    let bid = i div S
    let lid = i mod S
    let mid = bid div S

    if bid.int >= f.toSparse.len:
      f.toSparse.setLen(bid+1)
      f.toSparse[bid] = f.sparse.len+1

    let id = f.toSparse[bid]-1

    if id >= f.sparse.len:
      f.sparse.setLen(id+1)

    if f.sparseMask.len.uint <= mid:
      f.sparseMask.setLen(mid+1)

    f.sparseMask[mid] = f.sparseMask[mid] or (1.uint shl bid)
    f.sparse[id].mask = f.sparse[id].mask or (1.uint shl lid)


proc deactivateSparseBit[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], i:int|uint) =
  let S = (sizeof(uint)*8).uint
  let bid = i.uint div S
  let lid = i.uint mod S
  let mid = bid div S
  let id = f.toSparse[bid]-1
  
  f.sparse[id].mask = f.sparse[id].mask and not (1.uint shl lid)
  if f.sparse[id].mask == 0'u:
    f.sparseMask[mid] = f.sparseMask[mid] and not (1.uint shl bid)

proc deactivateSparseBit[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], idxs:openArray[uint]) =
  let S = (sizeof(uint)*8).uint

  for i in idxs:
    let bid = i div S
    let lid = i mod S
    let mid = bid div S
    let id = f.toSparse[bid]-1    

    f.sparse[id].mask = f.sparse[id].mask and not (1.uint shl lid)
    if f.sparse[id].mask == 0'u:
      f.sparseMask[mid] = f.sparseMask[mid] and not (1.uint shl bid)

template `[]=`[N,P,T,B](blk:var SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B], i:int|uint, v:untyped) =
  when T is tuple[]:
    discard
  else:
    check(i.int < N, "Invalid access. " & $i & "is out of bound for block of size " & $N)
    when P:
      setChanged(blk, i)
      setComponent(addr blk, i, v)
    else:
      toObjectMod(B, blk.data, i, v)

template `[]`[N:static int,P:static bool,T,B](blk:var SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B], i:int|uint):untyped =
  when T is tuple[]:
    B()
  else:
    check(i.int < N, "Invalid access. " & $i & "is out of bound for block of size " & $N)

    when P == true:
      toObjectParam(B, blk.data, i)
    else:
      toObject(B, blk.data, i)

proc `[]`[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:int):B =
  let blk = getBlock(f,i)
  return blk[i-blk.offset]

proc `[]=`[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], i:int, v:B) =
  var blk = getBlock(f,i)
  check((i div N) < f.blocks.len, "Invalid access. " & $(i div N) & "is out of bound. The component only has " & $(f.blocks.len) & "blocks")
  f.blocks[i div N][i.uint mod N.uint] = v

template `[]`[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:uint):untyped =
  let blk = (i shr BLK_SHIFT) and BLK_MASK
  let idx = i and BLK_MASK

  check(blk < f.blocks.len.uint, "Invalid access. " & $blk & "is out of bound. The component only has " & $(f.blocks.len) & "blocks")
  f.blocks[blk][idx]

template `[]=`[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], i:uint, v:untyped) =
  let blk = (i shr BLK_SHIFT) and BLK_MASK
  let idx = i and BLK_MASK

  check(blk < f.blocks.len.uint, "Invalid access. " & $blk & "is out of bound. The component only has " & $(f.blocks.len) & "blocks")
  check(not f.blocks[blk].isNil, "Invalid access. Trying to access nil block at " & $blk)
  
  when P: setChanged(f, i)
  f.blocks[blk][idx] = v

proc len[N,P,T,B](blk:SoAFragment[N,P,T,B]) = N

iterator iter[N,P,T,B](blk:SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B]):B =
  for i in 0..<N:
    yield blk[i]

iterator pairs[N,P,T,B](blk:SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B]):(int, B) =
  for i in 0..<N:
    yield (i, blk[i])

iterator iter[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B]):B =
  for blk in f.blocks:
    for d in blk.iter:
      yield d

iterator pairs[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B]):(int,B) =
  for blk in f.blocks:
    for i in 0..<N:
      yield (i+blk.offset,blk[i])
  
proc resize[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], n:int) =
  check(n >= 0, "Can't resize to negative size. Got " & $n)
  f.blocks.setLen(n)
  
proc clearDenseChanges[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B]) =
  for i in 0..<f.blkChangeMask.len:
    f.blkChangeMask[i] = 0'u
    if not f.blocks[i].isNil:
      for j in 0..<f.blocks[i].valMask.len:
        f.blocks[i].valMask[j] = 0'u

proc clearSparseChanges[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B]) =
  for i in 0..<f.sparseChangeMask.len:
    f.sparseChangeMask[i] = 0'u
    if f.toSparse[i] > 0:
      let j = f.toSparse[i]-1
      f.sparse[j].valMask[0] = 0'u