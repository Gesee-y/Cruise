######################################################################################################################################################################
############################################################################# IR ALLOCATOR ##########################################################################
######################################################################################################################################################################

const MAX_INTERPRETER_MEM = 128

include "hibitset.nim"

type
  CRegisterAllocator = object
    active: Table[(int, int), int]
    allocator: CAHibitset
    tick: int

proc alloc(c: var CRegisterAllocator, size, line: int): int =
  let s = c.getSpace(size)
  c.fillAlloc(s, size)
  c.active[(s, size)] = line
  s

proc free(c: var CRegisterAllocator, s, size: int) =
  c.freeRange(s, size)
  c.active.del((s, size))

proc updateTick(c: var CRegisterAllocator, t: int) =
  if t <= c.tick: return
  c.tick = t
  var toDelete: seq[(int, int)]
  for i, n in c.active.mpairs:
    if n <= c.tick: toDelete.add(i)

  for (i, size) in toDelete:
    c.free(i, size)