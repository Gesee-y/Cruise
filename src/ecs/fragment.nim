####################################################################################################################################################
############################################################## FRAGMENT ARRAYS #####################################################################
####################################################################################################################################################

import macros, math

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
  SoAFragment*[N: static int, P: static bool, T, B] = object
    ## SoA storage for all fields.
    data*: T
    ticks*: array[N, uint64]

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
  SoAFragmentArray*[N: static int, P: static bool, T, S, B] = ref object
    ## Dense blocks.
    blocks*: seq[ref SoAFragment[N, P, T, B]]
    blkTicks: seq[uint64]
    ## Sparse blocks (one block represents sizeof(uint)*8 entities).
    sparse*: seq[SoAFragment[sizeof(uint)*8, P, S, B]]
    sparseTicks: seq[uint64]
    changeFilter: QueryFilter
    ## Mapping from dense indices to sparse blocks.
    toSparse: seq[int]
    ## Dense activation mask.
    mask: seq[uint]
    ## Active sparse indices.
    sparseMask: HiBitSetType
    ## Recycled sparse block indices.
    freeBlocks: seq[int]
    ## Change counter tick
    tick: uint64

proc toSoATuple(T: NimNode, N: int): NimNode =
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

    if v.kind == nnkBracketExpr:
      if v[0].strVal == "distinct":
        brack.add ident(v.getTypeInst.strVal)
      elif v[0].strVal == "array":
        v[0] = ident v[0].strVal
        
        if v[1].kind == nnkBracketExpr:
          var temp = newNimNode(nnkInfix)
          temp.add(ident "..")
          temp.add(v[1][1])
          temp.add(v[1][2])
          v[1] = temp
        
        v[2] = ident v[2].strVal
        brack.add(v)
      elif v[0].strVal == "set":
        v[0] = ident(v[0].strVal)
        if v[1].kind == nnkEnumTy:
          v[1] = ident(v[1].getTypeInst.strVal)

        brack.add(v)

    elif v.kind == nnkEnumTy or v.kind == nnkObjectTy:
      brack.add(ident(v.getTypeInst.strVal))
    else:
      brack.add(ident(v.strVal))

    intl.intVal = N

    res.add(identdef)

  return res

macro toFragmentTy*(Ty: typedesc, N: static int = DEFAULT_BLK_SIZE,
    P: static bool = false): untyped = 
  let T = Ty.getTypeInst()[1]
  let ty = toSoATuple(Ty.getType[1], N)
  let sy = toSoATuple(Ty.getType[1], sizeof(uint)*8)
  return quote("@") do:
    SoAFragmentArray[`@N`, `@P`, `@ty`, `@sy`, `@T`]

macro castTo*(obj: untyped, Ty: typedesc, N: static int,
    P: static bool = false): untyped =
  ## Cast an existing value to a `SoAFragmentArray` of the given type.
  ##
  ## This is a low-level operation and assumes the underlying layout
  ## already matches the requested SoAFragmentArray.
  let T = Ty.getTypeInst()[1]
  let ty = toSoATuple(Ty.getType[1], N)
  let sy = toSoATuple(Ty.getType[1], sizeof(uint)*8)

  return quote("@") do:
    cast[SoAFragmentArray[`@N`, `@P`, `@ty`, `@sy`, `@T`]](`@obj`)

macro newSoAFragArr(Ty: typedesc, N: static int,
    P: static bool = false): untyped =
  ## Allocate and initialize a new `SoAFragmentArray`.
  ##
  ## This sets up empty dense storage and pre-allocates sparse structures.
  let T = Ty.getTypeInst()[1]
  let ty = toSoATuple(Ty.getType[1], N)
  let sy = toSoATuple(Ty.getType[1], sizeof(uint)*8)
  let S = sizeof(uint)*8
  return quote("@") do:
    let f = new(SoAFragmentArray[`@N`, `@P`, `@ty`, `@sy`, `@T`])
    f.sparse = newSeqOfCap[SoAFragment[`@S`, `@P`, `@sy`, `@T`]](INITIAL_SPARSE_SIZE)
    f.toSparse = newSeqOfCap[int](INITIAL_SPARSE_SIZE*`@S`)
    f.freeBlocks = newSeq[int]()
    f.sparseMask = newHiBitSet(INITIAL_SPARSE_SIZE)
    f

macro SoAFragArr(N: static int, stmt: typed) =
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

macro toObject(Ty: typedesc, c: untyped, idx: untyped): untyped =
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

macro toObjectParam(T: typedesc, c: untyped, idx: untyped): untyped =
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

macro toObjectMod(T: typedesc, c: untyped, idx: untyped, v: untyped) =
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

macro toObjectCopy(T: typedesc, cDst: untyped, idxDst: untyped, cSrc: untyped,
    idxSrc: untyped) =
  ## Override SoA values using another SoA-backed value directly field-by-field.
  var res = newNimNode(nnkStmtList)
  let ty = T.getType()[1].getType()[2]

  for f in ty:
    var asg = newNimNode(nnkAsgn)
    var brack = newNimNode(nnkBracketExpr)
    var brack2 = newNimNode(nnkBracketExpr)
    var dot1 = newNimNode(nnkDotExpr)
    var dot2 = newNimNode(nnkDotExpr)

    dot1.add(cDst)
    dot1.add(ident(f.strVal))
    brack.add(dot1)
    brack.add(idxDst)
    asg.add(brack)

    dot2.add(cSrc)
    dot2.add(ident(f.strVal))
    brack2.add(dot2)
    brack2.add(idxSrc)
    asg.add(brack2)
    res.add(asg)

  return quote("@") do:
    `@res`

template getDenseMeta(i):untyped =
  (i shr ID_SHIFT, i and ID_MASK)

template toIdx(i: uint): untyped =
  ## Convert a packed (block,index) ID into a linear index.
  let (bid, id) = i.getDenseMeta
  id+bid*DEFAULT_BLK_SIZE

template swapVals(b: untyped, i, j: int|uint) =
  ## Swap two values inside a buffer.
  let tmp = b[i]
  b[i] = b[j]
  b[j] = tmp

template overrideVals[N, P, T, S, B](b: SoAFragmentArray[N, P, T, S, B], i, j: int|uint) =
  ## Override one value with another inside a fragment array by field-copying.
  when T is tuple[]:
    discard
  else:
    let (bidi, idxi) = i.getDenseMeta
    let (bidj, idxj) = j.getDenseMeta
    toObjectCopy(B, b.blocks[bidi].data, idxi, b.blocks[bidj].data, idxj)

template overrideVals[N, P, T, B](b: SoAFragment[N, P, T, B] | ref SoAFragment[
    N, P, T, B], i, j: int|uint) =
  ## Override one value with another inside a fragment.
  when T is tuple[]:
    discard
  else:
    toObjectCopy(B, b.data, i, b.data, j)

macro overrideValsBatch[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
    ids: untyped, sw: seq[uint32], ad: seq[uint32]) =
  
  var res = newNimNode(nnkStmtList)
  let types = T.getTypeImpl() # T is the tuple-of-arrays type

  for i in 0..<types.len:
    let fName = types[i][0] # The name is in the first child of the IdentDefs
    var loop = quote do:
      for k in 0..<ids.len:
        let e = ids[k]
        let s = sw[k]
        let a = ad[k]

        let (bid_a, idx_a) = a.getDenseMeta
        let (bid_e, idx_e) = e.getDenseMeta
        let (bid_s, idx_s) = s.getDenseMeta

        f.blocks[bid_a].data.`fName`[idx_a] = f.blocks[bid_e].data.`fName`[idx_e]
        f.blocks[bid_e].data.`fName`[idx_e] = f.blocks[bid_s].data.`fName`[idx_s]
    res.add(loop)
  return res


template overrideVals(f, archId, ents, ids, toSwap, toAdd: untyped) =
  ## Redirect to the aggressive batch macro.
  f.overrideValsBatch(ids, toSwap, toAdd)


template setChanged[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], id: uint) =
  ## Mark a dense block as modified.
  let (bid, i) = id.getDenseMeta

  f.tick += 1
  f.blkTicks[bid] = f.tick
  f.blocks[bid].ticks[i] = f.tick
  f.changeFilter.dSet(id.toIdx.int)

template setChangedSparse[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], id: uint) =
  ## Mark a sparse entry as modified.
  let sbid = id shr BIT_DIVIDER
  let si = id and BIT_REMAINDER
  let physIdx = f.toSparse[sbid] - 1

  f.tick += 1
  f.sparseTicks[physIdx] = f.tick
  f.sparse[physIdx].ticks[si] = f.tick
  f.changeFilter.sSet(id.int)

template getDenseBlock*(f: SoAFragmentArray, i: int|uint): untyped = f.blocks[i]
template getSparseBlock*(f: SoAFragmentArray, i: int|uint): untyped = f.sparse[
    f.toSparse[i]]
template getDenseField*(f: SoAFragmentArray, i: int|uint,
    f0: untyped): untyped = addr f.getDenseBlock(i).data.f0
template getSparseField*(f: SoAFragmentArray, i: int|uint,
    f0: untyped): untyped = addr f.getSparseBlock(i).data.f0
template getBlockTick*(f: var SoAFragmentArray,
    i: int|uint): untyped = f.blkTicks[i]
template getSparseTick*(f: var SoAFragmentArray,
    i: int|uint): untyped = f.sparseTicks[i]

proc getDataType[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B]): typedesc[B] =
  ## Return the AoS component type stored in this array.
  B

proc newSparseBlock[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
    offset: int, m: uint) =
  ## Allocate or update a sparse block covering a given offset.
  var i = offset shr BIT_DIVIDER

  if i >= f.toSparse.len:
    f.toSparse.setLen(i+1)

  if f.toSparse[i] == 0:
    if f.freeBlocks.len > 0:
      f.toSparse[i] = f.freeBlocks.pop()
    else:
      f.toSparse[i] = f.sparse.len+1
      f.sparse.setLen(f.sparse.len+1)
      f.sparseTicks.setLen(f.sparse.len)

  f.sparseMask.setL0Block(i.int, m.BitBlock)

proc newSparseBlocks[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
    offset: int, masks: openArray[uint]) =
  ## Allocate multiple sparse blocks at once.
  let base = offset shr BIT_DIVIDER

  for c in 0..<masks.len:
    let m = masks[c]
    let i = base + c
    let j = i shr BIT_DIVIDER

    if i >= f.toSparse.len:
      f.toSparse.setLen(i+1)

    if f.toSparse[i] == 0:
      if f.freeBlocks.len > 0:
        f.toSparse[i] = f.freeBlocks.pop()
      else:
        f.toSparse[i] = f.sparse.len+1
        f.sparse.setLen(f.sparse.len+1)
        f.sparseTicks.setLen(f.sparse.len+1)

    f.sparseMask.setL0Block(i.int, m.BitBlock)

proc freeSparseBlock[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: int) =
  ## Free a sparse block and recycle its index for future use.
  if i < f.toSparse.len and f.toSparse[i] != 0:
    f.freeBlocks.add(f.toSparse[i])
    f.toSparse[i] = 0
    f.sparseMask.setL0Block(i, 0'u.BitBlock)

proc newBlockAt[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: int) =
  ## Allocate a new dense block at a specific index with exponential growth.
  check(i >= 0,
    "newBlockAt: block index cannot be negative (got " & $i & ").")
  checkWarn(i < 65535,
    "newBlockAt: block index=" & $i & " is unusually large. " &
    "Verify entity IDs are not corrupted; large indices waste memory.")
  check(i >= f.blocks.len or f.blocks[i].isNil,
    "newBlockAt: block at index=" & $i & " already exists and will be overwritten. " &
    "Double-allocation detected — existing data silently lost. " &
    "Check for duplicate createEntity calls or archetype graph corruption.")
  if i >= f.blocks.len:
    let newCap = i + 1
    f.blocks.setLen(newCap)
    f.blkTicks.setLen(newCap)
  var blk: ref SoAFragment[N, P, T, B]
  new(blk)
  f.blocks[i] = blk

proc getBlockId*[N, P, T, S, B](i: int|uint): uint =
  ## Compute the block index for a linear index.
  return (i.uint shr ID_SHIFT)

proc getIdInBlock*[N, P, T, S, B](i: int|uint): uint =
  return i.uint and ID_MASK

proc getBlock[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B],
    i: int): ref SoAFragment[N, P, T, B] =
  ## Get the dense block containing a given linear index.
  return f.blocks[getBlockId(f, i)]

template getBlock[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B],
    i: uint): ref SoAFragment[N, P, T, B] =
  ## Get the dense block from a packed ID.
  f.blocks[i.getBlockID]

template activateSparseBit[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: int|uint) =
  ## Mark a sparse index as active.
  let bid = i shr BIT_DIVIDER
  if bid.int >= f.toSparse.len or f.toSparse[bid] == 0:
    f.newSparseBlock(i.int, 0'u)
  f.sparseMask.set(i.int)

template activateSparseBit[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
    idxs: openArray[uint]) =
  ## Mark multiple sparse indices as active.
  ## Optimized to allocate blocks first then set bits in batch.
  for i in idxs:
    let bid = i shr BIT_DIVIDER
    if bid.int >= f.toSparse.len or f.toSparse[bid] == 0:
      f.newSparseBlock(i.int, 0'u)
  f.sparseMask.setBatch(idxs)

template deactivateSparseBit[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: int|uint) =
  ## Deactivate a sparse index.
  f.sparseMask.unset(i.int)
  let bid = i.int shr BIT_DIVIDER
  if f.sparseMask.getL0(bid) == 0'u.BitBlock:
    f.freeSparseBlock(bid)


proc deactivateSparseBit[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
    idxs: openArray[uint]) =
  ## Deactivate multiple sparse indices.
  f.sparseMask.unsetBatch(idxs)
  # Check and free blocks that became empty
  for i in idxs:
    let bid = i.int shr BIT_DIVIDER
    if f.sparseMask.hasL0(bid) and f.sparseMask.getL0(bid) == 0'u.BitBlock:
      f.freeSparseBlock(bid)

template `[]=`*[N, P, T, B](blk: var SoAFragment[N, P, T, B] | ref SoAFragment[N,
    P, T, B], i: int|uint, v: untyped) =
  ## Write a value into a fragment slot.
  when T is tuple[]:
    discard
  else:
    check(i.int < N, "Invalid access. " & $i &
        "is out of bound for block of size " & $N)
    when P:
      setComponent(addr blk, i.uint, v)
    else:
      toObjectMod(B, blk.data, i.uint, v)

template `[]`*[N: static int, P: static bool, T, B](blk: SoAFragment[N, P, T,
    B] | ref SoAFragment[N, P, T, B], i: int|uint): untyped =
  ## Read a value from a fragment slot.
  when T is tuple[]:
    B()
  else:
    check(i.int < N, "Invalid access. " & $i &
        "is out of bound for block of size " & $N)

    when P == true:
      toObjectParam(B, blk.data, i)
    else:
      toObject(B, blk.data, i)

template `[]`*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B],
    i: uint): untyped =
  ## Read a value using a packed (block,index) ID.
  let (blk, idx) = i.getDenseMeta

  check(blk.int < f.blocks.len, "Invalid access. " & $blk &
      "is out of bound. The component only has " & $(f.blocks.len) & "blocks")
  f.blocks[blk][idx]

template `[]=`*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: uint, v: untyped) =
  ## Write a value using a packed (block,index) ID.
  let (blk, idx) = i.getDenseMeta

  check(blk.int < f.blocks.len, "Invalid access. " & $blk &
      " is out of bound. The component only has " & $(f.blocks.len) & "blocks")
  check(not f.blocks[blk].isNil, "Invalid access. Trying to access nil block at " & $blk)

  when P: setChanged(f, i)
  f.blocks[blk][idx] = v

template `[]=`*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: int, v: untyped) =
  f[i.uint] = v

proc len[N, P, T, B](blk: SoAFragment[N, P, T, B]): int =
  ## Return the capacity of a fragment.
  N

iterator iter[N, P, T, B](blk: SoAFragment[N, P, T, B] | ref SoAFragment[N, P,
    T, B]): B =
  ## Iterate over all values in a fragment.
  for i in 0..<N:
    yield blk[i]

iterator pairs[N, P, T, B](blk: SoAFragment[N, P, T, B] | ref SoAFragment[N, P,
    T, B]): (int, B) =
  ## Iterate over (index, value) pairs in a fragment.
  for i in 0..<N:
    yield (i, blk[i])

iterator iter[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B]): B =
  ## Iterate over all values in the fragment array.
  for blk in f.blocks:
    for d in blk.iter:
      yield d

iterator pairs[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B]): (int, B) =
  ## Iterate over (global index, value) pairs.
  var j = 0
  for blk in f.blocks:
    for i in 0..<N:
      yield (i+j*N, blk[i])

proc resize[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], n: int) =
  ## Resize the number of dense blocks.
  check(n >= 0, "Can't resize to negative size. Got " & $n)
  f.blocks.setLen(n)
  f.blkTicks.setLen(n)

proc clearDenseChanges*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B]) =
  ## Clear all dense change tracking state.
  f.changeFilter.dLayer.clear()

proc clearSparseChanges*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B]) =
  ## Clear all sparse change tracking state.
  f.changeFilter.sLayer.clear()
