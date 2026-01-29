####################################################################################################################################################
############################################################## FRAGMENT ARRAYS #####################################################################
####################################################################################################################################################

import macros

## A single Structure-of-Arrays (SoA) fragment.
##
## A fragment represents a fixed-size block (`N`) of component data stored
## in SoA form. Each field of the original component type is stored as a
## separate array inside `data`.
##
## Type parameters:
## - N: Static size of the fragment (number of elements).
## - P: Enable/disable change tracking.
## - T: Tuple type holding the SoA arrays.
## - B: Original component (AoS) type.
type
  SoAFragment*[N:static int,P:static bool,T,B] = object
    ## SoA storage for all fields.
    data*:T

  ## A dynamically-sized array of SoA fragments.
  ##
  ## This is the main container used to store a component in SoA layout.
  ## It supports dense blocks and optional sparse blocks for partial
  ## materialization.
  ##
  ## Type parameters:
  ## - N: Block size.
  ## - P: Enable/disable change tracking.
  ## - T: Tuple type for dense SoA storage.
  ## - S: Tuple type for sparse SoA storage.
  ## - B: Original component (AoS) type.
  SoAFragmentArray*[N:static int,P:static bool,T,S,B] = ref object
    ## Dense blocks.
    blocks*:seq[ref SoAFragment[N,P,T,B]]
    ## Sparse blocks (one block represents sizeof(uint)*8 entities).
    sparse*:seq[SoAFragment[sizeof(uint)*8,P,S,B]]
    changeFilter:QueryFilter
    ## Mapping from dense indices to sparse blocks.
    toSparse:seq[int]
    ## Dense activation mask.
    mask:seq[uint]
    ## Active sparse indices.
    sparseMask:HiBitSetType


const
  ## Mask used to extract local indices from packed IDs.
  BLK_MASK = (1 shl 32) - 1
  ## Bit shift used to extract block indices from packed IDs.
  BLK_SHIFT = 32
  ## Default size (in elements) of a dense block.
  DEFAULT_BLK_SIZE = 4096
  ## Initial capacity of the sparse storage.
  INITIAL_SPARSE_SIZE = 1000

proc toSoATuple(T:NimNode, N:int):NimNode  =
  ## Transform an object type into a tuple-of-arrays (SoA-compatible) type.
  ##
  ## Each field of the original object becomes an `array[N, FieldType]`
  ## entry in the resulting tuple.
  ##
  ## This is used at compile time by macros to derive SoA storage layouts.
  var res = newNimNode(nnkTupleTy)
  let o = T.getType()[2]
  
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
  ## Cast an existing value to a `SoAFragmentArray` of the given type.
  ##
  ## This is a low-level operation and assumes the underlying layout
  ## already matches the requested SoAFragmentArray.
  let T = Ty.getTypeInst()[1]
  let ty = toSoATuple(Ty.getType[1], N)
  let sy = toSoATuple(Ty.getType[1], sizeof(uint)*8)
  return quote("@") do:
    cast[SoAFragmentArray[`@N`,`@P`,`@ty`,`@sy`,`@T`]](`@obj`) 

macro newSoAFragArr(Ty:typedesc, N:static int, P:static bool=false):untyped =
  ## Allocate and initialize a new `SoAFragmentArray`.
  ##
  ## This sets up empty dense storage and pre-allocates sparse structures.
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
  ## Rewrite variable declarations to use `SoAFragmentArray` automatically.
  ##
  ## This macro allows declaring SoA-backed components using a more
  ## ergonomic syntax.
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
  ## Materialize an AoS object from SoA storage at a given index.
  ##
  ## This version builds an object literal directly.
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
  ## Materialize an AoS object using a constructor call.
  ##
  ## This version respects Nim hygiene and avoids redeclarations in C backends.
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
  ## Assign all fields of an AoS value into SoA storage at a given index.
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
  ## Override SoA values using another SoA-backed value.
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
  ## Convert a packed (block,index) ID into a linear index.
  let id = i and BLK_MASK
  let bid = (i shr BLK_SHIFT) and BLK_MASK
  id+bid*DEFAULT_BLK_SIZE

template swapVals(b: untyped, i, j:int|uint) =
  ## Swap two values inside a buffer.
  let tmp = b[i]
  b[i] = b[j]
  b[j] = tmp

template overrideVals[N,P,T,S,B](b: SoAFragmentArray[N,P,T,S,B], i, j:int|uint) =
  ## Override one value with another inside a fragment array.
  b[i] = b[j]

template overrideVals[N,P,T,B](b: SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B], i, j:int|uint) =
  ## Override one value with another inside a fragment.
  b[i] = b[j]

template overrideVals(f, archId, ents, ids, toSwap, toAdd:untyped) =
  ## Specialized override logic used during archetype transitions.
  for i in 0..<ids.len:
    var e = ids[i].obj
    let s = toSwap[i]
    let a = toAdd[i]
    
    f[a] = f[e]
    f[e] = f[s]


template setChanged[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], id:uint) =
  ## Mark a dense block as modified.
  f.changeFilter.dSet(id.toIdx.int)

template setChangedSparse[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], id:uint) =
  ## Mark a sparse entry as modified.
  f.changeFilter.sSet(id.int)

proc getDataType[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B]):typedesc[B] =
  ## Return the AoS component type stored in this array.
  B

proc newSparseBlock[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], offset:int, m:uint) =
  ## Allocate or update a sparse block covering a given offset.
  let S = sizeof(uint)*8
  var i = offset div S
  var j = i div S

  if i >= f.toSparse.len: 
    f.toSparse.setLen(i+1)
  
  if f.toSparse[i] == 0:
    f.toSparse[i] = f.sparse.len+1
    f.sparse.setLen(f.sparse.len+1)
  
  let id = f.toSparse[i]-1

  var msk = m
  while msk != 0:
    f.sparseMask.set(offset + countTrailingZeroBits(msk))
    msk = msk and (msk-1)

proc newSparseBlocks[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], offset:int, masks:openArray[uint]) =
  ## Allocate multiple sparse blocks at once.
  let S = sizeof(uint)*8
  let base = f.toSparse.len

  for c in 0..<masks.len:
    let m = masks[c]
    let i = base + c
    let j = i div S

    if i >= f.toSparse.len: 
      f.toSparse.setLen(i+1)
      f.toSparse[i] = f.sparse.len+1
      f.sparse.setLen(f.sparse.len+1)
    
    let id = f.toSparse[i]-1
    let offset = i*S
    var msk = m
    
    while msk != 0:
      f.sparseMask.set(offset+c*S + countTrailingZeroBits(msk))
      msk = msk and (msk-1)

proc freeSparseBlock[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], i:int) =
  ## Free a sparse block (currently a no-op placeholder).
  discard

proc newBlockAt[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], i:int) =
  ## Allocate a new dense block at a specific index.
  var blk:ref SoAFragment[N,P,T,B]
  new(blk)
  f.blocks[i] = blk

proc getBlockIdx[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:int):int =
  ## Compute the block index for a linear index.
  return i div N

proc getBlock[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:int):ref SoAFragment[N,P,T,B] =
  ## Get the dense block containing a given linear index.
  return f.blocks[getBlockIdx(f, i)]

template getBlock[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:uint):ref SoAFragment[N,P,T,B] =
  ## Get the dense block from a packed ID.
  f.blocks[(i shr BLK_SHIFT) and BLK_MASK]

proc activateSparseBit[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], i:int|uint) =
  ## Mark a sparse index as active.
  let bid = i shr 6
  if bid.int >= f.toSparse.len or f.toSparse[bid] == 0:
    f.newSparseBlock(i.int, 0'u)
  f.sparseMask.set(i.int)

proc activateSparseBit[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], idxs:openArray[uint]) =
  ## Mark multiple sparse indices as active.
  for i in idxs:
    f.activateSparseBit(i)

proc deactivateSparseBit[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], i:int|uint) =
  ## Deactivate a sparse index.
  f.sparseMask.unset(i.int)

proc deactivateSparseBit[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], idxs:openArray[uint]) =
  ## Deactivate multiple sparse indices.
  for i in idxs:
    f.sparseMask.unset(i.int)

template `[]=`[N,P,T,B](blk:var SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B], i:int|uint, v:untyped) =
  ## Write a value into a fragment slot.
  when T is tuple[]:
    discard
  else:
    check(i.int < N, "Invalid access. " & $i & "is out of bound for block of size " & $N)
    when P:
      setComponent(addr blk, i, v)
    else:
      toObjectMod(B, blk.data, i, v)

template `[]`[N:static int,P:static bool,T,B](blk:var SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B], i:int|uint):untyped =
  ## Read a value from a fragment slot.
  when T is tuple[]:
    B()
  else:
    check(i.int < N, "Invalid access. " & $i & "is out of bound for block of size " & $N)

    when P == true:
      toObjectParam(B, blk.data, i)
    else:
      toObject(B, blk.data, i)

proc `[]`[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:int):B =
  ## Read a value from the fragment array using a linear index.
  let blk = getBlock(f,i)
  return blk[i-blk.offset]

proc `[]=`[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], i:int, v:B) =
  ## Write a value into the fragment array using a linear index.
  var blk = getBlock(f,i)
  check((i div N) < f.blocks.len, "Invalid access. " & $(i div N) & "is out of bound. The component only has " & $(f.blocks.len) & "blocks")
  f.blocks[i div N][i.uint mod N.uint] = v

template `[]`[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B], i:uint):untyped =
  ## Read a value using a packed (block,index) ID.
  let blk = (i shr BLK_SHIFT) and BLK_MASK
  let idx = i and BLK_MASK

  check(blk < f.blocks.len.uint, "Invalid access. " & $blk & "is out of bound. The component only has " & $(f.blocks.len) & "blocks")
  f.blocks[blk][idx]

template `[]=`[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], i:uint, v:untyped) =
  ## Write a value using a packed (block,index) ID.
  let blk = (i shr BLK_SHIFT) and BLK_MASK
  let idx = i and BLK_MASK

  check(blk < f.blocks.len.uint, "Invalid access. " & $blk & "is out of bound. The component only has " & $(f.blocks.len) & "blocks")
  check(not f.blocks[blk].isNil, "Invalid access. Trying to access nil block at " & $blk)
  
  when P: setChanged(f, i)
  f.blocks[blk][idx] = v

proc len[N,P,T,B](blk:SoAFragment[N,P,T,B]) =
  ## Return the capacity of a fragment.
  N

iterator iter[N,P,T,B](blk:SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B]):B =
  ## Iterate over all values in a fragment.
  for i in 0..<N:
    yield blk[i]

iterator pairs[N,P,T,B](blk:SoAFragment[N,P,T,B] | ref SoAFragment[N,P,T,B]):(int, B) =
  ## Iterate over (index, value) pairs in a fragment.
  for i in 0..<N:
    yield (i, blk[i])

iterator iter[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B]):B =
  ## Iterate over all values in the fragment array.
  for blk in f.blocks:
    for d in blk.iter:
      yield d

iterator pairs[N,P,T,S,B](f:SoAFragmentArray[N,P,T,S,B]):(int,B) =
  ## Iterate over (global index, value) pairs.
  var j = 0
  for blk in f.blocks:
    for i in 0..<N:
      yield (i+j*N,blk[i])
  
proc resize[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], n:int) =
  ## Resize the number of dense blocks.
  check(n >= 0, "Can't resize to negative size. Got " & $n)
  f.blocks.setLen(n)
  
proc clearDenseChanges[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B]) =
  ## Clear all dense change tracking state.
  f.changeFilter.dLayer.clear()

proc clearSparseChanges[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B]) =
  ## Clear all sparse change tracking state.
  f.changeFilter.sLayer.clear()
