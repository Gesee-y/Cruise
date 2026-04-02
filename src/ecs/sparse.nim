#######################################################################################################################################
######################################################## SPARSE ECS LOGICS ############################################################
#######################################################################################################################################

## Activates a set of components for a single sparse entity index.
## This marks the entity as owning those components without allocating dense storage.
template activateComponentsSparse(table: var ECSWorld, i:int|uint, components:untyped) =
  for id in components:
    let entry = addr table.registry.entries[id]
    entry.activateSparseBitOp(entry.rawPointer, i.uint)

## Batch version of sparse activation.
## Efficiently activates the same set of components for multiple entity indices.
template activateComponentsSparse(table: var ECSWorld, idxs:openArray, components:untyped) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.activateSparseBitBatchOp(entry.rawPointer, idxs)

## Deactivates a set of components for a single sparse entity index.
## This does NOT reclaim entity IDs, only clears component ownership.
template deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:untyped) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.deactivateSparseBitOp(entry.rawPointer, i.uint)

## Deactivates components described by an archetype mask.
## Uses bit iteration for fast traversal of active component IDs.
template deactivateComponentsSparse(table: var ECSWorld, i:int|uint, components:ArchetypeMask) =
  for m in components:
    var mask = m
    while mask != 0:
      let id = countTrailingZeroBits(mask)
      let entry = table.registry.entries[id]
      entry.deactivateSparseBitOp(entry.rawPointer, i.uint)
      mask = mask and (mask - 1)

## Typed single sparse entity allocation.
##
## Replaces allocateSparseEntity which calls per component:
##   entry.newSparseBlockOp    → vtable
##   entry.activateSparseBitOp → vtable
##
## Here each component is known at compile time → castTo + direct call.
## Returns the allocated entity id (uint), same contract as the template.
macro allocateSparseEntity*(
  table: ECSWorld,
  comps: varargs[typed]
): uint =

  ## newSparseBlock call per component type — runs only on fresh block path.
  var newBlockCode = newNimNode(nnkStmtList)
  for c in comps[0]:
    newBlockCode.add quote("@") do:
      block:
        let rawp = `@table`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.newSparseBlock(`@table`.max_index, 1'u)

  ## activateSparseBit per component — runs on both paths.
  var activateCode = newNimNode(nnkStmtList)
  for c in comps[0]:
    activateCode.add quote("@") do:
      block:
        let toAct = `@table`.free_list[^1]
        let rawp = `@table`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(toAct)

  return quote("@") do:
    block:
      var id: uint

      if `@table`.free_list.len > 0:
        ## Reuse a recycled slot — just activate, block already exists.
        `@activateCode`
        id = `@table`.free_list.pop()
      else:
        ## No free slot — allocate a new sparse block for every component.
        `@newBlockCode`

        ## Push remaining slots of the new block into the free list.
        let count  = UINT_BITS - 1
        let curLen = `@table`.free_list.len
        `@table`.free_list.setLen(curLen + count)
        for i in 0..<count:
          `@table`.free_list[curLen + i] = (`@table`.max_index + 1 + i).uint

        id = `@table`.max_index.uint
        `@table`.max_index += UINT_BITS
        `@table`.sparse_gens.setLen(`@table`.max_index)

        ## Activate only the first slot of the fresh block.
        `@activateCode`

      id


## Typed batch sparse entity allocation.
##
## Replaces allocateSparseEntities which loops over components and calls:
##   entry.newSparseBlocksOp          → vtable
##   entry.activateSparseBitBatchOp   → vtable
##
## The macro unrolls both loops at compile time per component type.
## Returns seq[Range] of allocated indices — same contract as template.
macro allocateSparseEntities*(
  table: ECSWorld,
  count: typed,
  comps: varargs[typed]
): seq[Range] =
  let toActivateId = genSym(nskVar, "toActivate")
  let masksId      = genSym(nskVar, "masks")
  let baseOffsetId = genSym(nskLet, "baseOffset")

  ## activateSparseBit(seq[uint]) — batch typed activation, no vtable.
  ## Receives `toActivate` which is built at runtime in the emitted code.
  var activateBatchCode = newNimNode(nnkStmtList)
  for c in comps[0]:
    activateBatchCode.add quote("@") do:
      block:
        let rawp = `@table`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(`@toActivateId`)

  ## newSparseBlocks(offset, masks) — typed bulk block allocation.
  var newBlocksCode = newNimNode(nnkStmtList)
  for c in comps[0]:
    newBlocksCode.add quote("@") do:
      block:
        let rawp = `@table`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.newSparseBlocks(`@baseOffsetId`, `@masksId`)

  return quote("@") do:
    block:
      var res          = newSeqOfCap[Range](`@count` shr BIT_DIVIDER + 1)
      var free_cursor  = `@table`.free_list.len - 1
      var `@toActivateId`   = newSeqOfCap[uint](`@count`)
      var n            = `@count`

      ## --- reuse recycled slots first --------------------------------------
      while n > 0 and free_cursor >= 0:
        let i = `@table`.free_list[free_cursor].toIdx
        res.add(Range(s: i.int, e: i.int + 1))
        `@toActivateId`.add(i.uint)
        dec free_cursor
        dec n

      ## Typed batch activation for all recycled ids — one pass per component.
      if `@toActivateId`.len > 0:
        `@activateBatchCode`

      `@table`.free_list.setLen(free_cursor + 1)

      ## --- allocate fresh sparse blocks for remaining count ----------------
      var `@masksId`: seq[uint]
      let `@baseOffsetId` = `@table`.max_index

      while n > 0:
        let toAdd = min(n, UINT_BITS)
        let m     = `@table`.max_index
        res.add(Range(s: m, e: m + toAdd))

        let mask = if toAdd == UINT_BITS: high(uint)
                   else: (1'u shl toAdd) - 1'u
        `@masksId`.add(mask)

        n -= toAdd
        `@table`.max_index += UINT_BITS

        ## Remaining slots in the last block go to the free list.
        if n <= 0:
          let start = m + toAdd
          let spare = UINT_BITS - toAdd
          if spare > 0:
            let curLen = `@table`.free_list.len
            `@table`.free_list.setLen(curLen + spare)
            for i in 0..<spare:
              `@table`.free_list[curLen + i] = (start + i).uint

      ## Typed newSparseBlocks — one call per component, no vtable.
      if `@masksId`.len > 0:
        `@newBlocksCode`

      `@table`.sparse_gens.setLen(`@table`.max_index)
      res

## Overrides component values from entity j into entity i
## for all components present in the archetype mask.
## Used during entity migration or structural transformations.
template overrideComponents(table: var ECSWorld, i,j:int|uint, components:ArchetypeMask) =
  for m in components:
    var mask = m
    while mask != 0:
      let id = countTrailingZeroBits(mask)
      let entry = table.registry.entries[id]
      entry.overrideValsOp(entry.rawPointer, i.uint, j.makeID)
      mask = mask and (mask - 1)

## Batch deactivation of sparse components for multiple entity indices.
template deactivateComponentsSparse(table: var ECSWorld, idxs:openArray, components:untyped) =
  for id in components:
    let entry = table.registry.entries[id]
    entry.deactivateSparseBitBatchOp(entry.rawPointer, idxs)


## Deletes a sparse entity row.
## The entity ID is recycled and all components are deactivated.
template deleteSparseRow(table: var ECSWorld, i:uint, components:untyped) =
  table.free_list.add(i)
  deactivateComponentsSparse(table, i, components)


## Typed single-component activation for one entity.
## Zero vtable — direct castTo per type.
macro activateSparseTyped*(
  table: ECSWorld,
  i:     uint,
  comps: varargs[typed]
): untyped =

  var code = newNimNode(nnkStmtList)
  for c in comps[0]:
    code.add quote("@") do:
      block:
        let rawp = `@table`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(`@i`)

  return quote("@") do:
    `@code`


## Typed batch activation for multiple entity ids.
## One castTo + activateSparseBit(openArray) per component — no vtable.
macro activateSparseTypedBatch*(
  table: ECSWorld,
  ids:   seq[uint],
  comps: varargs[typed]
): untyped =

  var code = newNimNode(nnkStmtList)
  for c in comps[0]:
    code.add quote("@") do:
      block:
        let rawp = `@table`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.activateSparseBit(`@ids`)

  return quote("@") do:
    `@code`


## Typed single deactivation.
macro deactivateSparseTyped*(
  table: ECSWorld,
  i:     uint,
  comps: varargs[typed]
): untyped =

  var code = newNimNode(nnkStmtList)
  for c in comps[0]:
    code.add quote("@") do:
      block:
        let rawp = `@table`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.deactivateSparseBit(`@i`)

  return quote("@") do:
    `@code`


## Typed batch deactivation.
macro deactivateSparseTypedBatch*(
  table: ECSWorld,
  ids:   seq[uint],
  comps: varargs[typed]
): untyped =

  var code = newNimNode(nnkStmtList)
  for c in comps[0]:
    code.add quote("@") do:
      block:
        let rawp = `@table`.registry.entries[toComponentId(`@c`)].rawPointer
        var fr = castTo(rawp, `@c`, DEFAULT_BLK_SIZE)
        fr.deactivateSparseBit(`@ids`)

  return quote("@") do:
    `@code`

