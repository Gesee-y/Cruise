####################################################################################################################################################
############################################################## FRAGMENT ARRAYS #####################################################################
####################################################################################################################################################

import macros

type
  SoAFragment[N:static int, T, B] = ref object
    data:T
    offset:int

  SoAFragmentArray[N:static int, T, B] = object
    blocks:seq[SoAFragment[N,T,B]]

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
    brack.add(v)
    
    intl.intVal = N
    
    res.add(identdef)

  return res

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

template swapVals(b: untyped, i, j:int|uint) =
  let tmp = b[i]
  b[i] = b[j]
  b[j] = tmp

proc overrideVals[N,T,B](b: var SoAFragment[N,T,B], i, j:int|uint) =
  b[i] = b[j]

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

  if offset - f.blocks[left].offset < N:
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
  
