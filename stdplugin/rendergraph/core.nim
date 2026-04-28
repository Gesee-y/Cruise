## render_graph.nim
##
## A render graph implemented as a Cruise plugin.
##
## Architecture:
##   - RenderResource     — GPU texture/buffer descriptor stored in PResourceManager
##   - RenderPassNode     — PluginNode subtype; declares reads/writes via attachSystem
##   - RenderGraph        — thin wrapper around Plugin that adds:
##                            * resource lifetime tracking  (first/last pass)
##                            * transition inference        (state changes between passes)
##                            * backbuffer culling          (prune unused subgraphs)
##   - TransitionCallback — backend-agnostic hook for barriers / layout changes
##
## What Cruise already provides (nothing reimplemented here):
##   - Topological sort + parallel level computation  (computeParallelLevel / pmap)
##   - Read/write conflict resolution                 (buildGlobalAccessGraph)
##   - DAG merging (dependency DAG ∪ resource DAG)   (mergeEdgeInto)
##   - System lifecycle (awake / update / shutdown)   (PluginNode)
##   - Typed resource storage                         (ResourceRegistry / CResource)
##   - Command batching + dispatch                    (CommandBuffer / executeAll)

# ---------------------------------------------------------------------------
# Dependencies (adjust import paths to your project layout)
# ---------------------------------------------------------------------------

import ../../src/plugins/plugins          # Plugin, PluginNode, attachSystem, addDependency …
import ../../src/render/render
import algorithm, tables

# ---------------------------------------------------------------------------
# RenderResourceState
#
# Agnostic to any backend. The TransitionCallback maps these to whatever
# the backend needs (VkImageLayout, GL memory barriers, Metal resource states…).
# ---------------------------------------------------------------------------

type
  RenderResourceState* = enum
    rsUndefined     ## Initial state — resource not yet written
    rsColorWrite    ## Being written as a color attachment
    rsDepthWrite    ## Being written as a depth attachment
    rsShaderRead    ## Being sampled inside a shader
    rsPresent       ## Ready for presentation (swap-chain output)

# ---------------------------------------------------------------------------
# TextureDesc / RenderResource
#
# Stored in PResourceManager exactly like any Cruise resource.
# `backingPtr` is nil until the graph is compiled; the backend fills it in
# inside its own `onAllocate` callback.
# ---------------------------------------------------------------------------

type
  TextureFormat* = enum
    fmtRGBA8, fmtRGBA16F, fmtRGBA32F,
    fmtDepth32, fmtDepth24Stencil8

  TextureDesc* = object
    width*, height*: uint32
    format*:         TextureFormat
    mips*:           uint32       ## 0 = full mip chain, 1 = no mips
    access*:int

  RenderResource* = ref object
    name*:       string
    desc*:       TextureDesc
    state*:      RenderResourceState
    transient*:  bool             ## true = owned + managed by the render graph
    backingPtr*: pointer          ## filled by AllocateCallback; nil if transient

proc byteSize*(desc: TextureDesc): uint64 =
  let pixelBytes = case desc.format
    of fmtRGBA8:            4u64
    of fmtRGBA16F:          8u64
    of fmtRGBA32F:         16u64
    of fmtDepth32:          4u64
    of fmtDepth24Stencil8:  4u64
  uint64(desc.width) * uint64(desc.height) * uint64(max(desc.mips, 1u32)) * pixelBytes

# ---------------------------------------------------------------------------
# AliasGroup
#
# Computed by computeAliasGroups during compile().
# canonicalId — the resource whose onAllocate was called (largest in the group).
# aliasIds    — resources that reuse canonicalId's backing via onAlias.
# ---------------------------------------------------------------------------

type
  AliasGroup* = object
    canonicalId*: int        ## PResourceManager id of the "master" resource
    aliasIds*:    seq[int]   ## ids that piggyback on canonicalId's backingPtr

# ---------------------------------------------------------------------------
# Callbacks
#
# All three are optional; the render graph calls them at the right moment.
# The backend casts `backingPtr` to its own texture/buffer type.
# ---------------------------------------------------------------------------

type
  ## Called once per transient resource when the graph determines it is live.
  AllocateCallback* = proc(res: var RenderResource) {.closure.}

  ## Called once per transient resource after the last pass that uses it.
  ReleaseCallback*  = proc(res: var RenderResource) {.closure.}

  ## Called between two passes whenever a resource changes state.
  TransitionCallback* = proc(
    res:       var RenderResource,
    fromState: RenderResourceState,
    toState:   RenderResourceState
  ) {.closure.}

  ## Called instead of onAllocate when the graph determines that `alias` can
  ## reuse `canonical`'s backing memory.
  ## Contract: the backend must set alias.backingPtr from canonical.backingPtr,
  ## using whatever sub-allocation / aliased view mechanism it supports.
  ## canonical.backingPtr is guaranteed to be non-nil (onAllocate already ran).
  AliasCallback* = proc(
    canonical: var RenderResource,   # already allocated, larger or equal size
    alias:     var RenderResource    # must receive a view of canonical's memory
  ) {.closure.}

# ---------------------------------------------------------------------------
# RenderPassNode
#
# Each render pass IS a Cruise PluginNode. It holds:
#   - the ids of resources it reads / writes (for transition inference)
#   - a user-supplied execute proc that records GPU commands into CommandBuffer
#
# The Cruise macro `attachSystem` is responsible for wiring read/write
# requests into PResourceManager; we only store the ids here for the
# transition pass that runs after computeParallelLevel.
# ---------------------------------------------------------------------------

type
  ExecuteFn* = proc(pass: RenderPassNode, cb: var CommandBuffer) {.closure.}

  RenderPassNode* = ref object of PluginNode
    name: string
    ## Explicit resource lists — filled by addRenderPass, used by
    ## inferTransitions. Cruise's PResourceManager already holds the same
    ## information but we cache it here to avoid re-scanning at runtime.
    readIds*:  seq[int]   ## PResourceManager indices this pass reads
    writeIds*: seq[int]   ## PResourceManager indices this pass writes
    execute*:  ExecuteFn  ## Records commands into the CommandBuffer

method update(pass: RenderPassNode) =
  ## Cruise calls this in topo+parallel order.
  ## The CommandBuffer is provided via the RenderGraph wrapper (see executeFrame).
  discard  # execution is driven by RenderGraph.executeFrame, not pmap directly

method asKey(pass: RenderPassNode): string = $pass.id  # unique per node

# ---------------------------------------------------------------------------
# ResourceLifetime
#
# Computed during graph compilation: which parallel level first writes a
# resource and which level last reads it.  Used to drive allocate/release.
# ---------------------------------------------------------------------------

type
  ResourceLifetime* = object
    resourceId*: int
    firstLevel*: int   ## level at which the resource must be allocated
    lastLevel*:  int   ## level after which the resource can be released

# ---------------------------------------------------------------------------
# Transition
#
# One transition = one (resource, fromState, toState) triple that must be
# applied between two consecutive parallel levels.
# After level `afterLevel` the resource moves from `fromState` to `toState`.
# ---------------------------------------------------------------------------

type
  Transition* = object
    resourceId*: int
    afterLevel*: int
    fromState*:  RenderResourceState
    toState*:    RenderResourceState

# ---------------------------------------------------------------------------
# RenderGraph
#
# Thin wrapper around a Cruise Plugin. Adds:
#   - a dedicated PResourceManager slot for RenderResources
#   - lifetime + transition tables (computed once, reused every frame)
#   - backend callbacks
#   - executeFrame: the single entry point per frame
# ---------------------------------------------------------------------------

type
  PoolSlot = object
    canonicalId: int
    lastLevel:   int
    size:        uint64

  RenderGraph* = object
    plugin*:      Plugin
    registry*:    ResourceRegistry                ## typed GPU resource storage
    resTypeId*:   TypeId                          ## TypeId for RenderResource
    cb*:          CommandBuffer
    backbufferId*: int                            ## resource id of the final output

    # Computed by compile(), invalidated when plugin.dirty = true
    lifetimes*:   seq[ResourceLifetime]
    transitions*: seq[Transition]
    aliasGroups*: seq[AliasGroup]   ## which resources share backing memory

    # Backend hooks
    onAllocate*:   AllocateCallback
    onRelease*:    ReleaseCallback
    onTransition*: TransitionCallback
    onAlias*:      AliasCallback    ## nil = aliasing disabled

# ---------------------------------------------------------------------------
# initRenderGraph
# ---------------------------------------------------------------------------

proc initRenderGraph*(
    onAllocate:   AllocateCallback   = nil,
    onRelease:    ReleaseCallback    = nil,
    onTransition: TransitionCallback = nil,
    onAlias:      AliasCallback      = nil
): RenderGraph =
  result.plugin = Plugin()
  result.registry     = initResourceRegistry()
  result.resTypeId    = result.registry.registerType(RenderResource)
  result.cb           = initCommandBuffer()
  result.backbufferId = -1
  result.onAllocate   = onAllocate
  result.onRelease    = onRelease
  result.onTransition = onTransition
  result.onAlias      = onAlias
# ---------------------------------------------------------------------------
# addRenderResource
#
# Register a RenderResource in both the ResourceRegistry (typed, for the
# backend) and the Plugin's PResourceManager (for DAG conflict resolution).
# Returns the PResourceManager index so it can be passed to addRenderPass.
# ---------------------------------------------------------------------------

proc addRenderResource*(
    rg:        var RenderGraph,
    res:       RenderResource
): int =
  ## Returns the PResourceManager id (used in addRenderPass read/write lists).
  let handle = rg.registry.create(rg.resTypeId, res)
  # Store the opaque handle as the resource so the access DAG can track it.
  result = rg.plugin.res_manager.addResource(cast[ResourceHandle](handle))

proc setBackbuffer*(rg: var RenderGraph, resourceId: int) =
  rg.backbufferId = resourceId

# ---------------------------------------------------------------------------
# addRenderPass
#
# Register a pass node in the Cruise Plugin, declare its resource accesses,
# and optionally declare explicit ordering dependencies (start → dep).
# ---------------------------------------------------------------------------

proc addRenderPass*(
    rg:       var RenderGraph,
    pass:     RenderPassNode,
    reads:    seq[int],
    writes:   seq[int],
    deps:     seq[int] = @[]   # ids of passes this one depends on
): int =
  ## Returns the Cruise system id of the new pass.
  pass.readIds  = reads
  pass.writeIds = writes

  # Register node in the Cruise dependency DAG
  let id = addSystem(rg.plugin, pass)

  # Wire resource accesses into PResourceManager → feeds buildGlobalAccessGraph
  for r in reads:
    rg.plugin.res_manager.addReadRequest(id, r)
  for w in writes:
    rg.plugin.res_manager.addWriteRequest(id, w)

  # Explicit ordering edges (over and above what the resource DAG infers)
  for dep in deps:
    discard rg.plugin.addDependency(dep, id)

  result = id

# ---------------------------------------------------------------------------
# compile
#
# Called automatically by executeFrame when plugin.dirty = true.
# Steps:
#   1. Let Cruise compute parallel levels (topo sort + resource DAG merge)
#   2. Backbuffer culling — mark every pass that contributes to backbuffer
#   3. Compute resource lifetimes
#   4. Infer transitions
# ---------------------------------------------------------------------------

proc reachesBackbuffer(
    plugin:      Plugin,
    nodeId:      int,
    backbufferId: int,
    memo:        var seq[int]   # -1 = unknown, 0 = no, 1 = yes
): bool =
  if memo[nodeId] >= 0: return memo[nodeId] == 1

  let pass = RenderPassNode(plugin.idtonode[nodeId])
  if pass == nil:
    memo[nodeId] = 0
    return false

  # Does this pass write the backbuffer directly?
  if backbufferId in pass.writeIds:
    memo[nodeId] = 1
    return true

  # Does any successor reach the backbuffer?
  for edge in plugin.getGraph.outedges[nodeId]:
    if reachesBackbuffer(plugin, edge.idx, backbufferId, memo):
      memo[nodeId] = 1
      return true

  memo[nodeId] = 0
  return false

proc compile*(rg: var RenderGraph) =
  ## (Re-)compute lifetimes and transitions. Called when dirty.

  # 1. Cruise computes parallel levels: topo sort + resource DAG
  computeParallelLevel(rg.plugin)
  let levels = rg.plugin.getParallelCache()   # seq[array[2, seq[int]]]

  # 2. Backbuffer culling
  if rg.backbufferId >= 0:
    var memo = newSeq[int](rg.plugin.idtonode.len)
    for i in 0 ..< memo.len: memo[i] = -1

    for levelIdx, level in levels:
      for threadBucket in level:
        for nodeId in threadBucket:
          if not reachesBackbuffer(rg.plugin, nodeId, rg.backbufferId, memo):
            rg.plugin.idtonode[nodeId].enabled = false

  # 3. Compute resource lifetimes
  rg.lifetimes = @[]
  let nRes = rg.plugin.res_manager.resources.len

  var firstWrite = newSeq[int](nRes)
  var lastRead   = newSeq[int](nRes)
  for i in 0 ..< nRes:
    firstWrite[i] = high(int)
    lastRead[i]   = -1

  for levelIdx, level in levels:
    for threadBucket in level:
      for nodeId in threadBucket:
        let pass = RenderPassNode(rg.plugin.idtonode[nodeId])
        if pass == nil or not pass.enabled: continue

        for w in pass.writeIds:
          if levelIdx < firstWrite[w]: firstWrite[w] = levelIdx
        for r in pass.readIds:
          if levelIdx > lastRead[r]:   lastRead[r]   = levelIdx

  for i in 0 ..< nRes:
    if firstWrite[i] == high(int): continue   # resource never written
    rg.lifetimes.add ResourceLifetime(
      resourceId: i,
      firstLevel: firstWrite[i],
      lastLevel:  max(firstWrite[i], lastRead[i])
    )

  # 4. Compute alias groups (interval scheduling / register allocation)
  #
  # Only runs when onAlias is provided — if the backend doesn't support
  # aliasing there is no point computing the groups.
  #
  # Algorithm:
  #   - Sort lifetimes by firstLevel (ascending).
  #   - Maintain a free pool: slots that have been fully released and whose
  #     backing could be reused.  Each slot carries the resourceId of the
  #     canonical allocation and the byte size of that allocation.
  #   - For each resource R (in firstLevel order):
  #       Search the pool for a slot S where
  #         S.lastLevel < R.firstLevel          — strictly disjoint
  #         byteSize(S.desc) >= byteSize(R.desc) — large enough
  #       Pick the smallest qualifying S (best-fit) to minimise waste.
  #       If found  → record (S.canonicalId, R) alias, remove S from pool.
  #       If not    → R becomes a new canonical; enters pool when freed.
  #   - After all resources are processed, build AliasGroup objects.
  rg.aliasGroups = @[]

  if rg.onAlias != nil:

    # Sort a copy of lifetimes by firstLevel so the greedy scan is O(n log n)
    var sorted = rg.lifetimes
    sorted.sort(proc(a, b: ResourceLifetime): int = cmp(a.firstLevel, b.firstLevel))

    var pool:    seq[PoolSlot]                   ## free slots available for reuse
    var aliasOf: Table[int, int]                 ## resourceId → canonicalId

    for lt in sorted:
      let res = get[RenderResource](rg.registry,
        getResource[ResourceHandle](rg.plugin.res_manager, lt.resourceId)
      )
      if not res.transient: continue             ## non-transient = swap-chain etc.

      let needed = byteSize(res.desc)

      # Best-fit search: find the smallest slot that is (a) free and (b) big enough
      var bestIdx = -1
      var bestSize = high(uint64)
      for i, slot in pool:
        if slot.lastLevel < lt.firstLevel and slot.size >= needed:
          if slot.size < bestSize:
            bestSize = slot.size
            bestIdx  = i

      if bestIdx >= 0:
        # Alias R onto the canonical slot
        aliasOf[lt.resourceId] = pool[bestIdx].canonicalId
        # The alias inherits the slot's lastLevel so it stays in the pool
        # with the *larger* of the two lastLevels (the slot may be reused again
        # only after both the canonical and the alias are done).
        pool[bestIdx].lastLevel = max(pool[bestIdx].lastLevel, lt.lastLevel)
      else:
        # R is a new canonical — it enters the pool when its lifetime ends
        pool.add PoolSlot(
          canonicalId: lt.resourceId,
          lastLevel:   lt.lastLevel,
          size:        needed
        )

    # Build AliasGroup objects from the aliasOf table
    var groups: Table[int, AliasGroup]
    for aliasId, canonId in aliasOf:
      if canonId notin groups:
        groups[canonId] = AliasGroup(canonicalId: canonId, aliasIds: @[])
      groups[canonId].aliasIds.add(aliasId)

    for g in groups.values:
      rg.aliasGroups.add(g)

  # 5. Infer transitions
  #
  # For each resource, whenever a pass writes it and a later pass reads it,
  # insert a transition at the boundary.  We use the simplified heuristic:
  #   write → the end of firstLevel    (rsColorWrite / rsDepthWrite)
  #   read  → the start of lastLevel   (rsShaderRead)
  # A more precise implementation would track per-pass states; this is
  # sufficient for a first-pass agnostic implementation.
  rg.transitions = @[]

  for lt in rg.lifetimes:
    if lt.lastLevel <= lt.firstLevel: continue   # write-only resource

    # Determine write state from the texture format
    let res = get[RenderResource](rg.registry,
      getResource[ResourceHandle](rg.plugin.res_manager, lt.resourceId)
    )
    let writeState =
      if res.desc.format in {fmtDepth32, fmtDepth24Stencil8}: rsDepthWrite
      else: rsColorWrite

    rg.transitions.add Transition(
      resourceId: lt.resourceId,
      afterLevel: lt.firstLevel,
      fromState:  writeState,
      toState:    rsShaderRead
    )

    # Final transition to Present for the backbuffer
    if lt.resourceId == rg.backbufferId:
      rg.transitions.add Transition(
        resourceId: lt.resourceId,
        afterLevel: lt.lastLevel,
        fromState:  rsShaderRead,
        toState:    rsPresent
      )

# ---------------------------------------------------------------------------
# executeFrame
#
# The single entry point called once per frame.
#
# Flow:
#   1. Recompile if dirty
#   2. For each parallel level:
#        a. Allocate resources whose firstLevel == this level
#        b. Execute passes in the level (both thread buckets)
#        c. Apply transitions that fire after this level
#        d. Release resources whose lastLevel == this level
#   3. Flush CommandBuffer through executeAll
# ---------------------------------------------------------------------------

proc executeFrame*[R](rg: var RenderGraph, renderer: var CRenderer[R]) =
  if rg.plugin.isDirty:
    compile(rg)

  let levels = rg.plugin.getParallelCache

  # Helper: get the mutable RenderResource by PResourceManager id
  template getMutRes(resId: int): ptr RenderResource =
    let handle = getResource[ResourceHandle](rg.plugin.res_manager, resId)
    let res = get[RenderResource](rg.registry, handle)
    res

  # Build alias lookup once per frame (O(aliases), not O(levels × aliases))
  var aliasToCanon:  Table[int, int]
  var canonHasAlias: Table[int, bool]
  for g in rg.aliasGroups:
    canonHasAlias[g.canonicalId] = true
    for a in g.aliasIds:
      aliasToCanon[a] = g.canonicalId

  for levelIdx, level in levels:

    for lt in rg.lifetimes:
      if lt.firstLevel != levelIdx: continue
      var res = getMutRes(lt.resourceId)
      if not res.transient: continue

      if lt.resourceId in aliasToCanon:
        # Alias path — onAlias instead of onAllocate
        let canonId = aliasToCanon[lt.resourceId]
        var canon   = getMutRes(canonId)
        if rg.onAlias != nil:
          rg.onAlias(canon[], res[])
      else:
        # Normal allocation
        if rg.onAllocate != nil:
          rg.onAllocate(res[])

    # --- Execute passes (main-thread bucket [1] last, matching Cruise pmap)
    for threadBucket in level:
      for nodeId in threadBucket:
        let pass = RenderPassNode(rg.plugin.idtonode[nodeId])
        if pass == nil #[or not pass.enabled]#: continue
        if pass.execute != nil:
          pass.execute(pass, rg.cb)

    renderer.executeAll(renderer, rg.cb)
    for pass in passOrder(renderer):
      clearPass(rg.cb, pass)

    # --- Apply transitions that fire after this level
    for t in rg.transitions:
      if t.afterLevel == levelIdx:
        var res = getMutRes(t.resourceId)
        if rg.onTransition != nil:
          rg.onTransition(res[], t.fromState, t.toState)
        res.state = t.toState

    # --- Release transient resources whose lifetime ends at this level
    #     Only canonical resources call onRelease — aliases don't own memory.
    for lt in rg.lifetimes:
      if lt.lastLevel != levelIdx: continue
      var res = getMutRes(lt.resourceId)
      if not res.transient: continue
      if lt.resourceId in aliasToCanon: continue   ## alias — no memory to free
      if rg.onRelease != nil:
        rg.onRelease(res[])

  # --- Flush all recorded commands through the Cruise CommandBuffer
  

# ---------------------------------------------------------------------------
# teardown
# ---------------------------------------------------------------------------

proc teardown*(rg: var RenderGraph) =
  destroyAllPasses(rg.cb)
  rg.registry.teardown()
