####################################################################################################################################################
############################################################## FRAGMENT ARRAYS #####################################################################
####################################################################################################################################################
##
## Structure-of-Arrays (SoA) fragment storage for the Cruise ECS.
##
## This module is the **performance-critical core** of Cruise's component
## storage.  At compile time, macros transform standard AoS component types
## into SoA tuple layouts (``toSoATuple``), enabling cache-friendly iteration
## without developer boilerplate.
##
## Key types
## ---------
## - ``SoAFragment[N,P,T,B]`` — a single fixed-size SoA block
## - ``SoAFragmentArray[N,P,T,S,B]`` — dynamic array of blocks + sparse storage
##
## Usage example
## =============
##
## .. code-block:: nim
##   type Position = object
##     x, y: float32
##
##   # Allocate SoA storage for Position with 4096-element blocks
##   var positions = newSoAFragArr(Position, 4096)
##
##   # Write / read via packed IDs
##   positions[packedId] = Position(x: 1.0, y: 2.0)
##   let p = positions[packedId]
##
##   # Direct SoA field access (cache friendly)
##   let xPtr = positions.getDenseField(blockIdx, x)
##   for i in 0..<count:
##     xPtr[i] += 1.0

import std/[macros, math]
import ./types
import ./hibitset
export types, hibitset

# ──── NOTE ─────────────────────────────────────────────────────────────── #
# The type definitions for SoAFragment and SoAFragmentArray live in        #
# types.nim.  This file contains the compile-time macros and runtime procs #
# that operate on them.                                                    #
# ─────────────────────────────────────────────────────────────────────── #

####################################################################################################################################################
########################################################### COMPILE-TIME MACROS ####################################################################
####################################################################################################################################################

proc toSoATuple*(T: NimNode, N: int): NimNode =
  ## Transform an object type into a tuple-of-arrays (SoA-compatible) type.
  ##
  ## Each field of the original object becomes an ``array[N, FieldType]``
  ## entry in the resulting tuple.
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
      if v[0].strVal == "array":
        v[0] = ident v[0].strVal

        if v[1].kind == nnkBracketExpr:
          var temp = newNimNode(nnkInfix)
          temp.add(ident "..")
          temp.add(v[1][1])
          temp.add(v[1][2])
          v[1] = temp

        v[2] = ident v[2].strVal
        brack.add(v)
    elif v.kind == nnkEnumTy or v.kind == nnkObjectTy:
      brack.add(ident(v.getTypeInst.strVal))
    else:
      brack.add(ident(v.strVal))

    intl.intVal = N

    res.add(identdef)

  return res

macro castTo*(obj: untyped, Ty: typedesc, N: static int,
    P: static bool = false): untyped =
  ## Cast an opaque pointer / value to its concrete ``SoAFragmentArray`` type.
  ##
  ## This is a **low-level** operation used by the type-erased registry.
  let T = Ty.getTypeInst()[1]
  let ty = toSoATuple(Ty.getType[1], N)
  let sy = toSoATuple(Ty.getType[1], sizeof(uint)*8)
  return quote("@") do:
    cast[SoAFragmentArray[`@N`, `@P`, `@ty`, `@sy`, `@T`]](`@obj`)

macro newSoAFragArr*(Ty: typedesc, N: static int,
    P: static bool = false): untyped =
  ## Allocate and initialise a new ``SoAFragmentArray`` for component type ``Ty``.
  ##
  ## Example
  ## -------
  ## .. code-block:: nim
  ##   type Velocity = object
  ##     vx, vy: float32
  ##   var velocities = newSoAFragArr(Velocity, 4096)
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

macro SoAFragArr*(N: static int, stmt: typed) =
  ## Rewrite variable declarations to use ``SoAFragmentArray`` automatically.
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

macro toObject*(Ty: typedesc, c: untyped, idx: untyped): untyped =
  ## Materialise an AoS object from SoA storage at a given index.
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

macro toObjectParam*(T: typedesc, c: untyped, idx: untyped): untyped =
  ## Materialise an AoS object using a constructor call.
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

macro toObjectMod*(T: typedesc, c: untyped, idx: untyped, v: untyped) =
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

macro toObjectCopy*(T: typedesc, cDst: untyped, idxDst: untyped, cSrc: untyped,
    idxSrc: untyped) =
  ## Copy SoA data field-by-field from ``cSrc[idxSrc]`` to ``cDst[idxDst]``.
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

template toIdx*(i: uint): untyped =
  ## Convert a packed (block, index) ID into a linear index.
  let id = i and BLK_MASK
  let bid = (i shr BLK_SHIFT) and BLK_MASK
  id+bid*DEFAULT_BLK_SIZE

template swapVals*(b: untyped, i, j: int|uint) =
  ## Swap two values inside a buffer.
  let tmp = b[i]
  b[i] = b[j]
  b[j] = tmp

template overrideVals*[N, P, T, S, B](b: SoAFragmentArray[N, P, T, S, B], i, j: int|uint) =
  ## Override one value with another inside a fragment array by field-copying.
  when T is tuple[]:
    discard
  else:
    let bidi = (i.uint shr BLK_SHIFT) and BLK_MASK
    let idxi = i.uint and BLK_MASK
    let bidj = (j.uint shr BLK_SHIFT) and BLK_MASK
    let idxj = j.uint and BLK_MASK
    toObjectCopy(B, b.blocks[bidi].data, idxi, b.blocks[bidj].data, idxj)

template overrideVals*[N, P, T, B](b: SoAFragment[N, P, T, B] | ref SoAFragment[
    N, P, T, B], i, j: int|uint) =
  ## Override one value with another inside a single fragment.
  when T is tuple[]:
    discard
  else:
    toObjectCopy(B, b.data, i, b.data, j)

macro overrideValsBatch*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
    ids: untyped, sw: seq[uint], ad: seq[uint]) =
  ## Component-outside, entity-inside batch migration.
  var res = newNimNode(nnkStmtList)
  let types = T.getTypeImpl()

  for i in 0..<types.len:
    let fName = types[i][0]
    var loop = quote do:
      for k in 0..<ids.len:
        let e = ids[k].obj
        let s = sw[k]
        let a = ad[k]

        let bid_a = (a shr BLK_SHIFT) and BLK_MASK
        let idx_a = a and BLK_MASK
        let bid_e = (e.id shr BLK_SHIFT) and BLK_MASK
        let idx_e = e.id and BLK_MASK
        let bid_s = (s shr BLK_SHIFT) and BLK_MASK
        let idx_s = s and BLK_MASK

        f.blocks[bid_a].data.`fName`[idx_a] = f.blocks[bid_e].data.`fName`[idx_e]
        f.blocks[bid_e].data.`fName`[idx_e] = f.blocks[bid_s].data.`fName`[idx_s]
    res.add(loop)
  return res


template overrideVals*(f, archId, ents, ids, toSwap, toAdd: untyped) =
  ## Redirect to the aggressive batch macro.
  f.overrideValsBatch(ids, toSwap, toAdd)


template setChanged*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], id: uint) =
  ## Mark a dense block as modified for change tracking.
  let bid = (id shr BLK_SHIFT) and BLK_MASK
  let i = id and BLK_MASK

  f.tick += 1
  f.blkTicks[bid] = f.tick
  f.blocks[bid].ticks[i] = f.tick
  f.changeFilter.dLayer.set(id.toIdx.int)

template setChangedSparse*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S,
    B], id: uint) =
  ## Mark a sparse entry as modified.
  let sbid = id shr BIT_DIVIDER
  let si = id and BIT_REMAINDER
  let physIdx = f.toSparse[sbid] - 1

  f.tick += 1
  f.sparseTicks[physIdx] = f.tick
  f.sparse[physIdx].ticks[si] = f.tick
  f.changeFilter.sLayer.set(id.int)

# ─── Block accessors ────────────────────────────────────────────────────── #

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

proc getDataType*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B]): typedesc[B] =
  ## Return the AoS component type stored in this array.
  B

# ─── Sparse block management ────────────────────────────────────────────── #

proc newSparseBlock*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
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
      f.sparseTicks.setLen(f.sparse.len+1)

  f.sparseMask.setL0Block(i.int, m.BitBlock)

proc newSparseBlocks*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
    offset: int, masks: openArray[uint]) =
  ## Allocate multiple sparse blocks at once.
  let base = offset shr BIT_DIVIDER

  for c in 0..<masks.len:
    let m = masks[c]
    let i = base + c

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

proc freeSparseBlock*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: int) =
  ## Free a sparse block and recycle its index.
  if i < f.toSparse.len and f.toSparse[i] != 0:
    f.freeBlocks.add(f.toSparse[i])
    f.toSparse[i] = 0
    f.sparseMask.setL0Block(i, 0'u.BitBlock)

# ─── Dense block management ─────────────────────────────────────────────── #

proc newBlockAt*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: int) =
  ## Allocate a new dense block at a specific index with exponential growth.
  if i >= f.blocks.len:
    let newCap = max(i + 1, f.blocks.len * 2)
    f.blocks.setLen(newCap)
    f.blkTicks.setLen(newCap)
  var blk: ref SoAFragment[N, P, T, B]
  new(blk)
  f.blocks[i] = blk

proc getBlockIdx*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B], i: int): int =
  ## Compute the block index for a linear index.
  return i div N

proc getBlock*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B],
    i: int): ref SoAFragment[N, P, T, B] =
  ## Get the dense block containing a given linear index.
  return f.blocks[getBlockIdx(f, i)]

template getBlock*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B],
    i: uint): ref SoAFragment[N, P, T, B] =
  ## Get the dense block from a packed ID.
  f.blocks[(i shr BLK_SHIFT) and BLK_MASK]

# ─── Sparse bit activation ──────────────────────────────────────────────── #

template activateSparseBit*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S,
    B], i: int|uint) =
  ## Mark a sparse index as active.
  let bid = i shr BIT_DIVIDER
  if bid.int >= f.toSparse.len or f.toSparse[bid] == 0:
    f.newSparseBlock(i.int, 0'u)
  f.sparseMask.set(i.int)

template activateSparseBit*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S,
    B], idxs: openArray[uint]) =
  ## Mark multiple sparse indices as active (batch).
  for i in idxs:
    let bid = i shr BIT_DIVIDER
    if bid.int >= f.toSparse.len or f.toSparse[bid] == 0:
      f.newSparseBlock(i.int, 0'u)
  f.sparseMask.setBatch(idxs)

template deactivateSparseBit*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S,
    B], i: int|uint) =
  ## Deactivate a sparse index.
  f.sparseMask.unset(i.int)
  let bid = i.int shr BIT_DIVIDER
  if f.sparseMask.getL0(bid) == 0'u.BitBlock:
    f.freeSparseBlock(bid)


proc deactivateSparseBit*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B],
    idxs: openArray[uint]) =
  ## Deactivate multiple sparse indices.
  f.sparseMask.unsetBatch(idxs)
  for i in idxs:
    let bid = i.int shr BIT_DIVIDER
    if f.sparseMask.hasL0(bid) and f.sparseMask.getL0(bid) == 0'u.BitBlock:
      f.freeSparseBlock(bid)

# ─── Fragment indexing operators ─────────────────────────────────────────── #

template `[]=`*[N, P, T, B](blk: var SoAFragment[N, P, T, B] | ref SoAFragment[
    N, P, T, B], i: int|uint, v: untyped) =
  ## Write a value into a fragment slot.
  when T is tuple[]:
    discard
  else:
    check(i.int < N, "Invalid access. " & $i &
        " is out of bound for block of size " & $N)
    when P:
      setComponent(addr blk, i.uint, v)
    else:
      toObjectMod(B, blk.data, i.uint, v)

template `[]`*[N: static int, P: static bool, T, B](blk: var SoAFragment[N, P,
    T, B] | ref SoAFragment[N, P, T, B], i: int|uint): untyped =
  ## Read a value from a fragment slot.
  when T is tuple[]:
    B()
  else:
    check(i.int < N, "Invalid access. " & $i &
        " is out of bound for block of size " & $N)

    when P == true:
      toObjectParam(B, blk.data, i)
    else:
      toObject(B, blk.data, i)

proc `[]`*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B], i: int): B =
  ## Read a value from the fragment array using a linear index.
  return f.blocks[i div N][i mod N]

template `[]`*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B],
    i: uint): untyped =
  ## Read a value using a packed (block, index) ID.
  let blk = (i shr BLK_SHIFT) and BLK_MASK
  let idx = i and BLK_MASK

  check(blk < f.blocks.len.uint, "Invalid access. " & $blk &
      " is out of bound. The component only has " & $(f.blocks.len) & " blocks")
  f.blocks[blk][idx]

template `[]=`*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: uint, v: untyped) =
  ## Write a value using a packed (block, index) ID.
  let blk: uint = (i shr BLK_SHIFT) and BLK_MASK
  let idx = i and BLK_MASK

  check(blk < f.blocks.len.uint, "Invalid access. " & $blk &
      " is out of bound. The component only has " & $(f.blocks.len) & " blocks")
  check(not f.blocks[blk].isNil, "Invalid access. Trying to access nil block at " & $blk)

  when P: setChanged(f, i)
  f.blocks[blk][idx] = v

template `[]=`*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], i: int, v: untyped) =
  f[i.uint] = v

proc len*[N, P, T, B](blk: SoAFragment[N, P, T, B]): int =
  ## Return the capacity of a fragment.
  N

# ─── Iterators ──────────────────────────────────────────────────────────── #

iterator iter*[N, P, T, B](blk: SoAFragment[N, P, T, B] | ref SoAFragment[N, P,
    T, B]): B =
  ## Iterate over all values in a fragment.
  for i in 0..<N:
    yield blk[i]

iterator pairs*[N, P, T, B](blk: SoAFragment[N, P, T, B] | ref SoAFragment[N, P,
    T, B]): (int, B) =
  ## Iterate over (index, value) pairs in a fragment.
  for i in 0..<N:
    yield (i, blk[i])

iterator iter*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B]): B =
  ## Iterate over all values in the fragment array.
  for blk in f.blocks:
    for d in blk.iter:
      yield d

iterator pairs*[N, P, T, S, B](f: SoAFragmentArray[N, P, T, S, B]): (int, B) =
  ## Iterate over (global index, value) pairs.
  var j = 0
  for blk in f.blocks:
    for i in 0..<N:
      yield (i+j*N, blk[i])

# ─── Resize / Clear ─────────────────────────────────────────────────────── #

proc resize*[N, P, T, S, B](f: var SoAFragmentArray[N, P, T, S, B], n: int) =
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
