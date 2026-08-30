import std/tables
import ./hibitset

  # ########################################################################################################################################## #
 # ############################################################### IR ALLOCATOR ############################################################# #
# ########################################################################################################################################## #

#
# This allocator is based on hibitset to efficiently fetch the best chunk of memory for a given allocation
# Thus avoiding fragmentation.
# 
# Allocation are lazily free only when a new allocation is requested.
# Old ones are removed at that instant.


const 
  LINE_BITPOS = 32
  COL_BITMASK = (1'u64 shl LINE_BITPOS) - 1

type
  # Representation of an allocation.
  # `pos` is the start of the allocation
  # For the others, I think it's straightforward
  CAllocation = object
    pos, size: int
    lastUse: uint
  
  # The main allocator for our program.
  # Tracks allocation and release them on demand of a new allocation
  CVramAllocator* = object
    active: Table[uint, CAllocation]
    allocator: CAHiBitSet
    maxMem: int

# ########################################################################################################################################## #
# ################################################################## UTILITIES ############################################################# #
# ########################################################################################################################################## #

# Transfrom line information into a single unsigned integer
# So it can be used for direct comparison (ie. get stale allocation and free them)
proc compactifyLineInfo(line, col: int): uint =
  (uint(line) shl LINE_BITPOS) or uint(col) 

# From a compactified line information, return the elements that compose it
proc decompactLineInfo(info: uint): tuple[line, col: int] =
  let line = int(info shr LINE_BITPOS)
  let col = int(info and COL_BITMASK)
  (line, col)

# Remove a given allocation from the list of active allocation
# So his memory can be reused
proc free(c: var CVramAllocator, id: uint) =
  if not c.active.hasKey(id): return
  let allocation = c.active.getOrDefault(id)
  c.allocator.freeRange(allocation.pos, allocation.size)
  c.active.del(id)

proc free*(c: var CVramAllocator, pos, size: int) =
  c.allocator.freeRange(pos, size)

proc free*(c: var CVramAllocator, allocation: CAllocation) =
  c.allocator.freeRange(allocation.pos, allocation.size)

# Update tick of the static memory allocator
proc updateTick(c: var CVramAllocator, line, col: int) =
  let id = compactifyLineInfo(line, col)
  var toDelete: seq[uint] = @[]

  # Since the id is compactified, a simple comparison with the last use tell us if it's stale
  for aid, allocation in c.active.mpairs:
    if allocation.lastUse < id: toDelete.add(aid)

  for aid in toDelete:
    c.free(aid)

# ########################################################################################################################################## #
# ################################################################# API Functions ########################################################## #
# ########################################################################################################################################## #

proc alloc*(c: var CVramAllocator, size, line, col: int, lline = 0, lcol = 0, cleanup=true): int =
  if cleanup: c.updateTick(line, col) # Updating the tick to lazily free unused memory

  let s = c.allocator.getSpace(size)
  let allocation = CAllocation(pos: s, size: size, lastUse: compactifyLineInfo(lline, lcol))
  
  # Setting the allocator with new infor
  c.allocator.fillAlloc(s, size) # Making the memory unavailable for future allocations
  c.active[compactifyLineInfo(line, col)] = allocation # adding the allocation to the active set 
  return allocation

# Anonymous alloc for temporary values
proc alloc*(c: var CVramAllocator, size: int): CAllocation =
  let s = c.allocator.getSpace(size)
  c.allocator.fillAlloc(s, size) # Making the memory unavailable for future allocations
  return CAllocation(pos: s, size: size)

proc newVramAllocator*(): CVramAllocator =
  result = CVramAllocator(active: initTable[uint, CAllocation]())


