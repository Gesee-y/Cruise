######################################################################################################################################################################
############################################################################# IR ALLOCATOR ##########################################################################
######################################################################################################################################################################

const MAX_INTERPRETER_MEM = 128

type
  CAllocation = object
    pos, size: int
  CRegisterAllocator = object
    active: Table[(int, int), int]
    allocator: CAHibitset
    tick: int

proc alloc(c: var CRegisterAllocator, size, line: int): int =
  let s = c.allocator.getSpace(size)
  c.allocator.fillAlloc(s, size)
  c.active[(s, size)] = line
  s

proc free(c: var CRegisterAllocator, s, size: int) =
  c.allocator.freeRange(s, size)
  c.active.del((s, size))

proc updateTick(c: var CRegisterAllocator, t: int) =
  if t <= c.tick: return
  c.tick = t
  var toDelete: seq[(int, int)]
  for i, n in c.active.mpairs:
    if n <= c.tick: toDelete.add(i)

  for (i, size) in toDelete:
    c.free(i, size)