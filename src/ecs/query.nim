# ################################################################################################################################################## #
# ################################################################ QUERIES ######################################################################### #
# ################################################################################################################################################## #

type
  QueryOp = enum
    qInclude
    qExclude
    qModified
    qNotModified

  QueryComponent = object
    ## Represents a single component constraint within a query.
    ## It binds a Component ID to an operation (Include, Exclude, Modified, etc.).
    id: int
    op: QueryOp

  QuerySignature*[T: tuple] = object
    ## The compiled representation of a query.
    ## It translates a list of component constraints into efficient bitmasks
    ## that can be rapidly compared against archetype masks.
    ## It's agnostic to the iteration strategy
    components: seq[QueryComponent]
    includeMask: ArchetypeMask
    excludeMask: ArchetypeMask
    modified: seq[int]
    notModified: seq[int]
    filters:seq[QueryFilter]

  DenseQueryResult* = object
    ## A cached result object for Dense queries.
    ## Stores the partitions (memory blocks) that matched the query signature,
    ## allowing for efficient re-iteration without re-checking archetype masks.
    part*: seq[TablePartition]

  DenseIterator* = object
    ## Iterator for dense queries.
    r*:HSlice[int, int]
    case masked: bool
    of true: m:seq[BitBlock]
    else: discard

  sparseQueryResult* = object
    ## A cached result object for Sparse queries.
    ## Stores the calculated bitmasks representing the matching entities.
    rmask*: seq[uint]
    chunks*: seq[uint]

  SparseIterator* = object
    ## Iterator obtained from sparse queries.
    m:uint

# ################################################################################################################################################## #
# ################################################################## MASK ITERATOR ################################################################# #
# ################################################################################################################################################## #

proc newQueryFilter*(size=4096): QueryFilter =
  ## Build a new query filter, useful to add constraints to a query
  var q: QueryFilter
  new(q)
  when HibitsetType is HiBitSet:
    q.dLayer = newHiBitSet(size)
    q.sLayer = newHiBitSet(size)
  else:
    q.dLayer = newSparseHiBitSet(size)
    q.sLayer = newSparseHiBitSet(size)
  return q

proc `and`*(a, b: var QueryFilter): QueryFilter =
  result = newQueryFilter()
  result.dLayer = a.dLayer and b.dLayer
  result.sLayer = a.sLayer and b.sLayer

proc `or`*(a, b: var QueryFilter): QueryFilter =
  result = newQueryFilter()
  result.dLayer = a.dLayer or b.dLayer
  result.sLayer = a.sLayer or b.sLayer

proc `xor`*(a, b: var QueryFilter): QueryFilter =
  result = newQueryFilter()
  result.dLayer = a.dLayer xor b.dLayer
  result.sLayer = a.sLayer xor b.sLayer

proc `not`*(a: var QueryFilter): QueryFilter =
  result.dLayer = not a.dLayer
  result.sLayer = not a.sLayer

proc dGet*(qf: QueryFilter, id: uint|int): bool =
  ## Returns 1 if the ID is present in the dense filter, 0 otherwise
  qf.dLayer.get(id.int)

proc dSet*(qf: var QueryFilter, id: uint|int) =
  ## Sets an ID in the dense filter
  qf.dLayer.set(id.int)

proc dUnset*(qf: var QueryFilter, id: uint) =
  ## Unsets an ID from the dense filter
  qf.dLayer.unset(id.int)

proc sGet*(qf: QueryFilter, id: int | uint): bool =
  ## Sparse membership check
  qf.sLayer.get(id.int)

proc sSet*(qf: var QueryFilter, id: int | uint) =
  ## Insert into sparse filter
  qf.sLayer.set(id.int)

proc sUnset*(qf: var QueryFilter, id: int | uint) =
  ## Remove from sparse filter
  qf.sLayer.unset(id.int)

iterator maskIter(it: uint): int =
  ## Low-level iterator to traverse set bits in an unsigned integer bitmask.
  ##
  ## This uses the "Brian Kernighan's algorithm" approach (`m & (m-1)`), which efficiently
  ## jumps to the next set bit.
  ##
  ## param: it: The bitmask (uint) to iterate over.
  ## return: The index (int) of each set bit found.

  var m = it
  while m != 0:
    yield countTrailingZeroBits(m)
    m = m and (m-1)

iterator maskIter(it: (HSlice[int,int],seq[uint|BitBlock])): int =
  var current = 0
  var i = 0
  let S = sizeof(uint)*8

  while i < it[1].len and current <= it[0].b:
    var m = it[1][i]

    while m != 0:
      current = i*S + countTrailingZeroBits(m)
      m = m and (m-1)
      if current > it[0].b: break
      yield current

    i += 1

proc count*(it:DenseIterator|SparseIterator):int =
  var res = 0
  for i in it:
    res += 1

  return res

iterator items*(it: DenseIterator): int =
  ## Iterate a `DenseIterator` obtained from a query
  ##
  ## It return the index of the matching entity in a given block.

  if it.masked:
    for i in (it.r, it.m).maskIter:
      yield i
  else:
    for i in it.r:
      yield i

iterator items*(it: SparseIterator): int =
  ## Iterate a `SparseIterator` obtained from a sparse query.
  ##
  ## It return the index of the matching entities in a given block.

  for i in it.m.maskIter:
    yield i

# ################################################################################################################################################## #
# ################################################################## QUERY BUILDER ################################################################# #
# ################################################################################################################################################## #

proc buildQuerySignature[T: tuple](world: ECSWorld, components: seq[QueryComponent]): QuerySignature[T] =
  ## Constructs a `QuerySignature` from a list of component constraints.
  ##
  ## This function calculates the aggregate `includeMask` and `excludeMask` from the
  ## individual `QueryComponent` objects.
  ## Note: Processing logic for qModified/qNotModified is not implemented here per request,
  ## only the ID is cached in the components sequence.
  ##
  ## param: world: The `ECSWorld` (used for context or future expansion).
  ## param: components: A sequence of `QueryComponent` objects defining the filter.
  ## return: A fully constructed `QuerySignature`.

  result.components = components

  for comp in components:
    # Calculate which layer (word) in the mask array and which bit within that word.
    let layer = comp.id div (sizeof(uint) * 8)
    let bitPos = comp.id mod (sizeof(uint) * 8)

    if layer < MAX_COMPONENT_LAYER:
      case comp.op
      of qInclude:
        # Set the bit in the include mask.
        result.includeMask[layer] = result.includeMask[layer] or (1.uint shl bitPos)
      of qExclude:
        # Set the bit in the exclude mask.
        result.excludeMask[layer] = result.excludeMask[layer] or (1.uint shl bitPos)
      of qModified, qNotModified:
        if comp.op == qModified:
          result.modified.add(comp.id)
        else:
          result.notModified.add(comp.id)
        # For archetype matching, a Modified component implies the component must exist (Include).
        # However, we only cache the info here as requested.
        # If you need the entity to exist to be checked for modification:
        result.includeMask[layer] = result.includeMask[layer] or (1.uint shl bitPos)

template addFilter*(qs: var QuerySignature, qf:QueryFilter) =
  ## Adds a new filter to the query
  qs.filters.add(qf)

template clear*(qf: QueryFilter) =
  qf.dLayer.clear()
  qf.sLayer.clear()

proc matchesArchetype[T](sig: QuerySignature[T], arch: ArchetypeMask): bool {.inline.} =
  arch.matches(sig.includeMask, sig.excludeMask)

# ################################################################################################################################################## #
# ################################################################## DENSE QUERIES ################################################################# #
# ################################################################################################################################################## #

iterator denseQuery*[T](world: ECSWorld, sig: QuerySignature[T]): (int, DenseIterator) =
  ## Iterate through all partitions that match the query signature
  ## Returns block index and range for each matching zone

  let mlen = sig.modified.len
  let nmlen = sig.notModified.len
  let maskCount = ((DEFAULT_BLK_SIZE-1) shr L0_SHIFT) + 1
  var res = newSeq[BitBlock](maskCount)

  let key: QueryKey = (sig.includeMask, sig.excludeMask)
  if not world.queryCache.hasKey(key):
    world.queryCache[key] = QueryCacheEntry(version: 0)

  var cacheEntry = addr world.queryCache[key]

  if cacheEntry.version < world.archGraph.version:
    for archNode in world.archGraph.archetypes:
      let i = archNode.id
      if matchesArchetype(sig, archNode.mask) and not (i in cacheEntry.archs):
        cacheEntry.archs.add(i)
    cacheEntry.version = world.archGraph.nodes.len

  for archID in cacheEntry.archs:
    if not world.archGraph.nodes[archID].partition.isNil:
      for zone in world.archGraph.nodes[archID].partition.zones:
        var masked = false

        # Reset mask to all-1s for each zone
        for k in 0..<maskCount:
          res[k] = 0'u - 1

        for i in 0..<max(mlen, nmlen):
          masked = true
          if i < mlen:
            let entry = world.registry.entries[sig.modified[i]]
            let incl = entry.getChangeMaskOp(entry.rawPointer).dLayer
            for j in 0..<maskCount:
              res[j] = res[j] and incl.getL0(zone.block_idx*sizeof(uint)*8 + j)

          if i < nmlen:
            let entry = world.registry.entries[sig.notModified[i]]
            let excl = entry.getChangeMaskOp(entry.rawPointer).dLayer
            for j in 0..<maskCount:
              res[j] = res[j] and not excl.getL0(zone.block_idx*sizeof(uint)*8 + j)

        for qf in sig.filters:
          masked = true
          for i in 0..<maskCount:
            res[i] = res[i] and qf.dLayer.getL0(zone.block_idx*sizeof(uint)*8 + i)

        if masked:
          yield (zone.block_idx, DenseIterator(masked:true, r:zone.r.s..<zone.r.e, m: res))
        else:
          yield (zone.block_idx, DenseIterator(masked:false, r:zone.r.s..<zone.r.e))


proc denseQueryCache*[T](world: ECSWorld, sig: QuerySignature[T]): DenseQueryResult =
  ## Computes and caches the result of a Dense query.
  ##
  ## Useful if you need to iterate over the results multiple times, as it avoids
  ## re-scanning the archetype graph on subsequent iterations.
  ##
  ## param: world: The `ECSWorld` to query.
  ## param: sig: The `QuerySignature` defining the filter.
  ## return: A `DenseQueryResult` containing the matching partitions.

  let key: QueryKey = (sig.includeMask, sig.excludeMask)
  if not world.queryCache.hasKey(key):
    world.queryCache[key] = QueryCacheEntry(version: 0)

  template cacheEntry: untyped = world.queryCache[key]

  if cacheEntry.version < world.archGraph.version:
    for archNode in world.archGraph.archetypes:
      let i = archNode.id
      if matchesArchetype(sig, archNode.mask) and not (i in cacheEntry.archs):
        cacheEntry.archs.add(i)
    cacheEntry.version = world.archGraph.nodes.len

  for id in cacheEntry.archs:
    if not world.archGraph.nodes[id].partition.isNil:
      result.part.add(world.archGraph.nodes[id].partition)

iterator items*(qr:DenseQueryResult):(int, HSlice[int, int]) =
  ## Iterator for the cached `DenseQueryResult`.
  ##
  ## param: qr: The `DenseQueryResult` to iterate over.
  ## yield: A tuple containing:
  ##         - `int`: The Block Index.
  ##         - `HSlice[int, int]`: The range of entity indices.

  for partition in qr.part:
    for zone in partition.zones:
      yield (zone.block_idx, zone.r.s..<zone.r.e)

proc denseQueryCount*[T](world: ECSWorld, sig: QuerySignature[T]): int =
  ## Count total entities matching the dense query
  result = 0

  for bid, r in world.denseQuery(sig):
    result += r.count

template fastExecute*(world: ECSWorld, sig: QuerySignature, bid, startIdx, endIdx, body: untyped) =
  ## Template for raw, SIMD-friendly SoA iteration.
  ## Exposes `bid` (block index), `startIdx`, and `endIdx`.
  ## Use this to iterate directly over native arrays like:
  ## `let pos = world.get(Position); pos.blocks[bid].data.x[i] = ...`
  for bid, dIt in world.denseQuery(sig):
    if not dIt.masked:
      let startIdx = dIt.r.a
      let endIdx = dIt.r.b + 1
      body
    else:
      # Slow path for masked queries
      for i in dIt:
        let startIdx = i
        let endIdx = i + 1
        body

# ################################################################################################################################################## #
# ################################################################## SPARSE QUERIES ################################################################ #
# ################################################################################################################################################## #

iterator sparseQuery*[T](world: ECSWorld, sig: QuerySignature[T]): (int, SparseIterator) =
  ## Iterate through sparse entities matching the query
  ## Returns chunk index and mask iterator for each matching chunk

  var includeIds: seq[int]
  var excludeIds: seq[int]

  for comp in sig.components:
    case comp.op
    of qInclude, qModified, qNotModified: includeIds.add(comp.id)
    of qExclude: excludeIds.add(comp.id)

  if includeIds.len > 0:
    # Iterate through chunks with entities
    let S = sizeof(uint)*8
    let entry = world.registry.entries[includeIds[0]]
    var res = entry.getSparseMaskOp(entry.rawPointer)

    for compId in includeIds[1..^1]:
      let entry = world.registry.entries[compId]
      res.andi entry.getSparseMaskOp(entry.rawPointer)

    for compId in excludeIds:
      let entry = world.registry.entries[compId]
      res.andNoti(entry.getSparseMaskOp(entry.rawPointer))

    for compId in sig.modified:
      let entry = world.registry.entries[compId]
      res.andi entry.getChangeMaskop(entry.rawPointer).sLayer

    for compId in sig.notModified:
      let entry = world.registry.entries[compId]
      res.andNoti(entry.getChangeMaskOp(entry.rawPointer).sLayer)

    for qf in sig.filters:
      res.andi qf.sLayer

    for chunkIdx in res.blkIter:
      yield (chunkIdx, SparseIterator(m:res.getL0(chunkIdx)))

iterator items*(sr:sparseQueryResult):(int, uint) =
  ## Iterator for the cached `sparseQueryResult`.
  ##
  ## param: sr: The `sparseQueryResult` to iterate over.
  ## yield: A tuple containing:
  ##         - `int`: The Chunk Index.
  ##         - `uint`: The bitmask of valid entities within the chunk.

  var c = 0
  let S = sizeof(uint)*8
  for i in 0..<sr.rmask.len:
    var m = sr.rmask[i]

    while m != 0:
      let chunkIdx = i*S + countTrailingZeroBits(m)
      var chunkMask = sr.chunks[c]
      m = m and (m-1)

      yield (chunkIdx, chunkMask)
      c += 1

proc sparseQueryCount*[T](world: ECSWorld, sig: QuerySignature[T]): int =
  ## Count total entities matching the sparse query
  result = 0

  for _,mask in sparseQuery(world, sig):
    for _ in mask:
      result += 1

# ################################################################################################################################################## #
# ################################################################## QUERY SYNTAX ################################################################## #
# ################################################################################################################################################## #

# Helper procs for building queries

proc includeComp*(componentId: int): QueryComponent =
  ## Creates a `QueryComponent` that requires a specific component.
  QueryComponent(id: componentId, op: qInclude)

proc excludeComp*(componentId: int): QueryComponent =
  ## Creates a `QueryComponent` that forbids a specific component.
  QueryComponent(id: componentId, op: qExclude)

proc modifiedComp*(componentId: int): QueryComponent =
  ## Creates a `QueryComponent` that requires a component to be modified.
  QueryComponent(id: componentId, op: qModified)

proc notModifiedComp*(componentId: int): QueryComponent =
  ## Creates a `QueryComponent` that requires a component to be not modified.
  QueryComponent(id: componentId, op: qNotModified)

proc processQueryExpr*(world, expr: NimNode): (NimNode, NimNode) =
  var components = newNimNode(nnkBracket)
  var componentTypes = newNimNode(nnkTupleConstr)

  proc processExpr(world: NimNode, node: NimNode) =
    case node.kind
      of nnkInfix:
        if (node[0].kind == nnkOpenSymChoice and node[0][1].strVal == "and") or node[0].strVal == "and":
          # Recursively process left and right operands of 'and'
          processExpr(world, node[1])
          processExpr(world, node[2])
        else:
          error("Unsupported operator in query: " & node[0].strVal)

      of nnkPrefix:
        if (node[0].kind == nnkOpenSymChoice and node[0][1].strVal == "and") or node[0].strVal == "not":
          let operand = node[1]

          # Check if the operand is Modified[Type]
          if operand.kind == nnkBracketExpr and operand[0].eqIdent("Modified"):
            # not Modified[Type]
            let compNode = operand[1] # The Type inside []
            components.add(quote("@") do:
              notModifiedComp(toComponentId(`@compNode`))
            )
          elif operand.kind in {nnkIdent, nnkSym}:
            # not Type
            components.add(quote("@") do:
              excludeComp(toComponentId(`@operand`))
            )
          else:
            error("Unsupported operand for 'not': " & $operand.kind)
        else:
          error("Unsupported prefix operator in query: " & node[0].strVal)

      of nnkCall:
        # Check for Modified[Type]
        if node[1].eqIdent("Modified"):
          let compNode = node[2].getTypeInst()
          componentTypes.add(compNode)
          components.add(quote("@") do:
            modifiedComp(toComponentId(`@compNode`))
          )
        else:
          var t = newNimNode(nnkBracketExpr)
          t.add(node[1])
          t.add(node[2])
          componentTypes.add(t)
          components.add(quote("@") do:
            includeComp(toComponentId(`@t`))
          )

      of nnkBracketExpr:
        # Check for Modified[Type]
        if node[0].eqIdent("Modified"):
          let compNode = node[1] # The Type inside []
          components.add(quote("@") do:
            modifiedComp(toComponentId(`@compNode`))
          )
        else:
          componentTypes.add(node)
          components.add(quote("@") do:
            includeComp(toComponentId(`@node`))
          )

      of nnkIdent, nnkSym:
        # Process a raw type identifier (Implies 'include')
        componentTypes.add(node)
        components.add(quote("@") do:
          includeComp(toComponentId(`@node`))
        )

      else:
        error("Unsupported node kind in query: " & $node.kind)

  processExpr(world, expr)

  (componentTypes, components)

macro query*(world: untyped, expr: untyped): untyped =
  ## Macro for Domain Specific Language (DSL) query syntax.
  ##
  ## Allows writing queries using `and`, `not`, and `Modified[]` operators, e.g.:
  ## `query(world, Position and Modified[Velocity] and not Dead)`
  ##
  ## The macro parses the Abstract Syntax Tree (AST) of the expression and converts
  ## the identifiers (types) into their Component IDs using the world's registry.
  ##
  ## param: world: The `ECSWorld` instance.
  ## param: expr: The query expression (e.g., `Pos and Modified[Vel]`).
  ## return: A `QuerySignature` ready for use in query functions.
  ##
  ## Example:
  ## ```nim
  ## let sig = world.query(Position and Velocity and not Tag)
  let (componentTypes, componentsSeq) = processQueryExpr(world, expr)

  # Return the call to buildQuerySignature
  result = quote do:
    buildQuerySignature[`componentTypes`](`world`, @`componentsSeq`)

var ITERATOR_REGISTRY {.compileTime.} = initTable[int, NimNode]()
var ITERATOR_SREGISTRY {.compileTime.} = initTable[int, NimNode]()

macro executeDQuery(w: ECSWorld, q: QuerySignature): untyped =
  let qtype = q.getTypeInst()
  let Ty = qtype[1]
  let id = Ty.repr.hash().int
  var iter = newNimNode(nnkEmpty)

  if id in ITERATOR_REGISTRY:
    iter = ITERATOR_REGISTRY[id]
    return quote do:
      `w`.`iter`(`q`)
  else:
    let iterName = ident("queryIter_" & $id)
    let bid = ident("bid")
    let eid = ident("eid")
    let r = ident("r")
    let wsymb = ident("wsymb")
    let qsymb = ident("qsymb")
    var returnType = newNimNode(nnkTupleConstr)
    var returnData = newNimNode(nnkTupleConstr)
    var getComp = newStmtList()
    var symbs: seq[NimNode]
    var blks = newStmtList()
    var sparses: seq[NimNode]

    returnType.add(ident"int")
    returnType.add(ident"DenseIterator")

    returnData.add(bid)
    returnData.add(r)

    var cnt = 0
    for c in Ty:
      let comp = ident(c.strVal)
      let sym = ident("f" & $cnt)
      let bsym = ident("blk" & $cnt)
      let cid = getComponentIdFromRegistry(comp)
      let layId = COMPONENT_TO_LAYOUT[cid].repr.hash.int
      let layoutProc = ID_TO_LAYOUT[layId].getTypeProc
      symbs.add(sym)
      returnType.add(quote do:
        ref `layoutProc`(`comp`)
      )

      getComp.add(quote do:
        var `sym` = `wsymb`.get(`comp`)
      )
      blks.add(quote do:
        var `bsym` = `sym`.blocks[`bid`]
      )
      returnData.add(bsym)
      cnt += 1

    var iterBody = quote do:
      iterator `iterName`(`wsymb`: ECSWorld, `qsymb`: `qtype`): `returnType` =
        `getComp`

        for (`bid`, `r`) in `wsymb`.denseQuery(`qsymb`):
          `blks`
          yield `returnData`

    ITERATOR_REGISTRY[id] = iterName

    return quote do:
      `iterBody`
      `w`.`iterName`(`q`)

macro executeSQuery(w: ECSWorld, q: QuerySignature): untyped =
  let qtype = q.getTypeInst()
  let Ty = qtype[1]
  let id = Ty.repr.hash().int
  var iter = newNimNode(nnkEmpty)

  if id in ITERATOR_SREGISTRY:
    iter = ITERATOR_SREGISTRY[id]
    return quote do:
      `w`.`iter`(`q`)
  else:
    let iterName = ident("querySIter_" & $id)
    let bid = ident("bid")
    let eid = ident("eid")
    let r = ident("r")
    let wsymb = ident("wsymb")
    let qsymb = ident("qsymb")
    var returnType = newNimNode(nnkTupleConstr)
    var returnData = newNimNode(nnkTupleConstr)
    var getComp = newStmtList()
    var symbs: seq[NimNode]
    var sparses = newStmtList()

    returnType.add(ident"int")
    returnType.add(ident"SparseIterator")

    returnData.add(bid)
    returnData.add(r)

    var cnt = 0
    for c in Ty:
      let comp = ident(c.strVal)
      let sym = ident("f" & $cnt)
      let bsym = ident("blk" & $cnt)
      let sid = ident("sid" & $cnt)
      let cid = getComponentIdFromRegistry(comp)
      let layId = COMPONENT_TO_LAYOUT[cid].repr.hash.int
      let layoutProc = ID_TO_LAYOUT[layId].getTypeProc
      symbs.add(sym)
      returnType.add(quote do:
        ptr `layoutProc`(`comp`, sizeof(uint)*8)
      )

      getComp.add(quote do:
        var `sym` = `wsymb`.get(`comp`)
      )
      sparses.add(quote do:
          let `sid` = `sym`.toSparse[`bid`]-1
          var `bsym` = `sym`.sparse[`sid`]
        )

      var addrSym = newNimNode(nnkCommand)
      addrSym.add(ident"addr")
      addrSym.add(bsym)
      returnData.add(addrSym)

      cnt += 1

    var iterBody = quote do:
      iterator `iterName`(`wsymb`: ECSWorld, `qsymb`: `qtype`): `returnType` =
        `getComp`

        for (`bid`, `r`) in `wsymb`.sparseQuery(`qsymb`):
          `sparses`
          yield `returnData`

    ITERATOR_SREGISTRY[id] = iterName

    return quote do:
      `iterBody`
      `w`.`iterName`(`q`)

# ################################################################################################################################### #
# ###################################################### Query and Entity ########################################################### #
# ################################################################################################################################### #

proc get*(qf: QueryFilter, d: DenseHandle): bool =
  ## Dense handle membership check
  qf.dGet(d.obj.id.toIdx)

proc get*(qf: QueryFilter, s: SparseHandle): bool =
  ## Sparse handle membership check
  qf.sGet(s.id)

proc set*(qf: var QueryFilter, d: DenseHandle) =
  ## Insert dense handle into query filter
  qf.dSet(d.obj.id.toIdx)

proc set*(qf: var QueryFilter, s: SparseHandle) =
  ## Insert sparse handle into query filter
  qf.sSet(s.id)

proc unset*(qf: var QueryFilter, d: DenseHandle) =
  ## Remove dense handle from query filter
  qf.dUnset(d.obj.id)

proc unset*(qf: var QueryFilter, s: SparseHandle) =
  ## Remove sparse handle from query filter
  qf.sUnset(s.id)
