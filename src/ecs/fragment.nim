####################################################################################################################################################
############################################################## FRAGMENT ARRAYS #####################################################################
####################################################################################################################################################

import macros

type
  SoAFragment[N:static int, T, B] = ref object
    data:T
    offset:int
    mask:uint

  SoAFragmentArray[N:static int, T, B] = ref object
    blocks:seq[SoAFragment[N,T,B]]
    sparse:seq[SoAFragment[sizeof(uint)*8,T,B]]
    mask:seq[uint]
    sparseMask:seq[uint]

const
  BLK_MASK = (1 shl 32) - 1
  BLK_SHIFT = 32
  DEFAULT_BLK_SIZE = 4096

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

macro castTo(obj:untyped, T:typedesc, N:static int):untyped =
  let ty = toSoATuple(T.getType[1], N)
  return quote("@") do:
    cast[SoAFragmentArray[`@N`,`@ty`,`@T`]](`@obj`) 

macro newSoAFragArr(T:typedesc, N:static int):untyped =
  let ty = toSoATuple(T.getType[1], N)
  return quote("@") do:
    new(SoAFragmentArray[`@N`,`@ty`,`@T`])

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

macro toObject(n:untyped, T:typedesc, c:untyped, idx:untyped):untyped =
  var res = newNimNode(nnkObjConstr)
  let ty = T.getType()[1].getType()[2]
  res.add(ident(T.getType()[1].strVal))

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
    `@n` = `@res`

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

template overrideVals[N,T,B](b: SoAFragmentArray[N,T,B], i, j:int|uint) =
  b[i] = b[j]

template overrideVals[N,T,B](b: SoAFragment[N,T,B], i, j:int|uint) =
  b[i] = b[j]

template overrideVals(f, archId, ents, ids, toSwap, toAdd:untyped) =
  for i in 0..<ids.len:
    let e = ids[i]
    let s = toSwap[i]
    let a = toAdd[i]
    
    f[a] = f[e]
    f[e] = f[s]
    
    ents[a.toIdx] = e
    ents[e.id.toIdx] = ents[s.toIdx]
    ents[s.toIdx].id = e.id

    e.id = a
    e.archetypeId = archId

proc getDataType[N,T,B](f: SoAFragmentArray[N,T,B]):typedesc[B] = B

proc newSparseBlock[N,T,B](f: var SoAFragmentArray[N,T,B], offset:int, m:uint) =
  var blk: SoAFragment[sizeof(uint)*8,T,B]
  new(blk)
  let S = sizeof(uint)*8
  
  var i = offset div S
  var j = i div S
  if i >= f.sparse.len: f.sparse.setLen(i+1)
  if j >= f.sparseMask.len: f.sparseMask.setLen(j+1)
  
  blk.offset = offset
  blk.mask = m
  f.sparse[i] = blk

  if m != 0:
    f.sparseMask[j] = f.sparseMask[j] or (1.uint shl i)

proc freeSparseBlock[N,T,B](f: var SoAFragmentArray[N,T,B], i:int) =
  f.sparse[i] = nil

proc newBlockAt[N,T,B](f: var SoAFragmentArray[N,T,B], i:int) =
 var blk:SoAFragment[N,T,B]
 new(blk)
 blk.offset = N*i
 f.blocks[i] = blk

proc newBlock[N,T,B](f: var SoAFragmentArray[N, T, B], offset:int):bool =
  var blk: SoAFragment[N,T,B]
  new(blk)
  blk.offset = offset
  
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

proc getBlockIdx[N,T,B](f:SoAFragmentArray[N,T,B], i:int):int =
  return i div N

proc getBlock[N,T,B](f:SoAFragmentArray[N,T,B], i:int):SoAFragment[N,T,B] =
  return f.blocks[getBlockIdx(f, i)]

template getBlock[N,T,B](f:SoAFragmentArray[N,T,B], i:uint):SoAFragment[N,T,B] =
  f.blocks[(i shr BLK_SHIFT) and BLK_MASK]

proc `[]`[N,T,B](blk:SoAFragment[N,T,B], i:int|uint):B =
  var res:B
  toObject(res, B, blk.data, i)

  return res

proc activateBit[N,T,B](f: var SoAFragmentArray[N,T,B], i:int|uint) =
  let bid = i div N
  let lid = i mod N
  let mid = bid div sizeof(uint)*8

  if f.mask.len <= mid:
    f.mask.setLen(mid+1)

  f.mask[mid] = f.mask[mid] or (1.uint shl bid)
  f.blocks[bid].mask = f.blocks[bid].mask or (1.uint shl lid)

proc deactivateBit[N,T,B](f: var SoAFragmentArray[N,T,B], i:int|uint) =
  let bid = i div N
  let lid = i mod N
  let mid = bid div sizeof(uint)*8
  f.blocks[bid].mask = f.blocks[bid].mask and not (1.uint shl lid)
  if f.blocks[bid].mask == 0:
    f.mask[mid] = f.mask[mid] and not (1.uint shl bid)
  
proc activateSparseBit[N,T,B](f: var SoAFragmentArray[N,T,B], i:int|uint) =
  let S = (sizeof(uint)*8).uint
  let bid = i div S
  let lid = i mod S
  let mid = bid div S

  if f.sparseMask.len.uint <= mid:
    f.sparseMask.setLen(mid+1)

  f.sparseMask[mid] = f.sparseMask[mid] or (1.uint shl bid)
  f.sparse[bid].mask = f.sparse[bid].mask or (1.uint shl lid)

proc deactivateSparseBit[N,T,B](f: var SoAFragmentArray[N,T,B], i:int|uint) =
  let S = (sizeof(uint)*8).uint
  let bid = i div S
  let lid = i mod S
  let mid = bid div S
  f.sparse[bid].mask = f.sparse[bid].mask and not (1.uint shl lid)
  if f.sparse[bid].mask == 0'u:
    f.sparseMask[mid] = f.sparseMask[mid] and not (1.uint shl bid)


template `[]=`[N,T,B](blk:var SoAFragment[N,T,B], i:int|uint, v:B) =
  toObjectMod(B, blk.data, i, v)

proc `[]`[N,T,B](f:SoAFragmentArray[N,T,B], i:int):B =
  let blk = getBlock(f,i)
  return blk[i-blk.offset]

proc `[]=`[N,T,B](f:var SoAFragmentArray[N,T,B], i:int, v:B) =
  var blk = getBlock(f,i)
  f.blocks[i div N][i mod N] = v

proc `[]`[N,T,B](f:SoAFragmentArray[N,T,B], i:uint):B =
  let blk = (i shr BLK_SHIFT) and BLK_MASK
  let idx = i and BLK_MASK

  return f.blocks[blk][idx]

proc `[]=`[N,T,B](f:var SoAFragmentArray[N,T,B], i:uint, v:B) =
  let blk = (i shr BLK_SHIFT) and BLK_MASK
  let idx = i and BLK_MASK

  f.blocks[blk][idx] = v

proc len[N,T,B](blk:SoAFragment[N,T,B]) = N

iterator iter[N,T,B](blk:SoAFragment[N,T,B]):B =
  for i in 0..<N:
    yield blk[i]

iterator pairs[N,T,B](blk:SoAFragment[N,T,B]):(int, B) =
  for i in 0..<N:
    yield (i, blk[i])

iterator iter[N,T,B](f:SoAFragmentArray[N,T,B]):B =
  for blk in f.blocks:
    for d in blk.iter:
      yield d

iterator pairs[N,T,B](f:SoAFragmentArray[N,T,B]):(int,B) =
  for blk in f.blocks:
    for i in 0..<N:
      yield (i+blk.offset,blk[i])
  
proc resize[N,T,B](f: var SoAFragmentArray[N,T,B], n:int) =
  f.blocks.setLen(n)
  