include "hibitset.nim"

  # ########################################################################################################################################## #
 # ############################################################### IR ALLOCATOR ############################################################# #
# ########################################################################################################################################## #

#
# This allocator is based on hibitset to efficiently fetch the best chunk of memory for a given allocation
# avoiding fragmentation.
#
# Named allocations (variables) are registered at a compactified birth position key and carry
# a `lastUse` timestamp.  `updateTick` scans the active table and lazily frees any allocation
# whose `lastUse` has already passed.
#
# Anonymous/temporary allocations bypass the active table and must be freed manually via `free`.
#

const
  LINE_BITPOS = 32
  COL_BITMASK = (1'u64 shl LINE_BITPOS) - 1

type
  # Representation of an allocation.
  # `pos`    – start byte address in virtual memory.
  # `size`   – number of virtual-memory bytes owned by this allocation.
  # `isTemp` – true when the allocation is a scratch temporary that must be freed
  #            manually; false when it is a named variable managed by `updateTick`.
  CAllocation* = object
    pos*:    int
    size*:   int
    lastUse: uint
    isTemp*: bool

  # The main allocator for the generated program.
  # Tracks named allocations and releases stale ones on demand.
  CVramAllocator* = object
    active:    Table[uint, CAllocation]
    allocator: CAHiBitSet
    maxMem:    int

# ########################################################################################################################################## #
# ################################################################## UTILITIES ########################################################### #
# ########################################################################################################################################## #

# Pack (line, col) into a single uint so it can be used as a map key or compared
# directly for ordering (a position is "earlier" when its packed value is smaller).
proc compactifyLineInfo(line, col: int): uint =
  (uint(line) shl LINE_BITPOS) or uint(col)

proc decompactLineInfo(info: uint): tuple[line, col: int] =
  let line = int(info shr LINE_BITPOS)
  let col  = int(info and COL_BITMASK)
  (line, col)

# Release a named allocation identified by its packed birth-position key.
proc free(c: var CVramAllocator, id: uint) =
  if not c.active.hasKey(id): return
  let allocation = c.active.getOrDefault(id)
  c.allocator.freeRange(allocation.pos, allocation.size)
  c.active.del(id)

proc free*(c: var CVramAllocator, pos, size: int) =
  c.allocator.freeRange(pos, size)

proc free*(c: var CVramAllocator, allocation: CAllocation) =
  ## Free the memory owned by `allocation`.
  ## For temporary allocations (`isTemp = true`) this releases the range
  ## immediately.  Named allocations should not be freed this way; the
  ## allocator reclaims them automatically via `updateTick`.
  c.allocator.freeRange(allocation.pos, allocation.size)

# Scan the active table and release every allocation whose `lastUse` position
# lies strictly before the current position `(line, col)`.
proc updateTick(c: var CVramAllocator, line, col: int) =
  let id       = compactifyLineInfo(line, col)
  var toDelete: seq[uint] = @[]

  for aid, allocation in c.active.mpairs:
    if allocation.lastUse < id:
      toDelete.add(aid)

  for aid in toDelete:
    c.free(aid)

# ########################################################################################################################################## #
# ################################################################# API FUNCTIONS ####################################################### #
# ########################################################################################################################################## #

proc alloc*(c: var CVramAllocator, size, line, col: int,
            lline = 0, lcol = 0, cleanup = true): CAllocation =
  ## Allocate `size` words at birth position `(line, col)`.
  ## The allocation lives until `(lline, lcol)` (its last use); when a later
  ## `alloc` call triggers `updateTick`, stale allocations are freed
  ## automatically.  Returns a `CAllocation` with `isTemp = false`.
  if cleanup: c.updateTick(line, col)

  let s          = c.allocator.getSpace(size)
  let allocation = CAllocation(pos: s, size: size,
                                lastUse: compactifyLineInfo(lline, lcol),
                                isTemp: false)
  c.allocator.fillAlloc(s, size)
  c.maxMem = max(c.maxMem, s + size)
  c.active[compactifyLineInfo(line, col)] = allocation
  result = allocation

proc alloc*(c: var CVramAllocator, size: int): CAllocation =
  ## Allocate `size` words as an anonymous temporary.
  ## The caller **must** free the returned allocation manually via `free`.
  ## `isTemp` is set to `true` to signal this obligation.
  let s = c.allocator.getSpace(size)
  c.allocator.fillAlloc(s, size)
  c.maxMem = max(c.maxMem, s + size)
  result = CAllocation(pos: s, size: size, isTemp: true)

proc lookup*(c: var CVramAllocator, line, col: int): CAllocation =
  ## Retrieve the named allocation whose birth position is `(line, col)`.
  ## Returns an empty `CAllocation` (size = 0) when no matching entry exists.
  let key = compactifyLineInfo(line, col)
  result  = c.active.getOrDefault(key)

proc newVramAllocator*(): CVramAllocator =
  result = CVramAllocator(active: initTable[uint, CAllocation]())

proc highWaterMark*(c: CVramAllocator): int {.inline.} =
  ## Highest byte address reached, even if that allocation has since been freed.
  c.maxMem
