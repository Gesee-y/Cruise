  # ######################################################################################################################################### #
 # ########################################################### ALLOCATOR HIBITSET ########################################################## #
# ######################################################################################################################################### #

type
  ## A 4-bit Hierarchical bitset for allocation
  ## Allows us to quickly get an available memory chuck when allocating
  BitBlock = uint8
  CAHiBitSet* = object
    layer0: seq[uint8] # Get to know if 4 bits are used
    layer1: seq[uint8] # Get to know if 16 bits are used
    layer2: seq[uint8] # Get to know if 64 bits are used

const
  L0_BITS*  = 4
  L0_SHIFT* = 2
  L0_MASK*  = 3
  L0_FULL* = 0xF

proc firstSetBit(v: BitBlock): int {.inline.} =
  ## Returns the index of the least significant set bit. `v` must be non-zero.
  var bits = v
  result = 0
  while (bits and BitBlock(1)) == 0:
    inc result
    bits = bits shr 1

proc len*(h: CAHiBitSet): int {.inline.} =
  ## Total capacity of the bitset in bits.
  result = h.layer0.len * L0_BITS

# ---------- internal growth helper ----------

proc ensureCapacity(h: var CAHiBitSet, idx: int) =
  let neededL0 = (idx shr L0_SHIFT) + 1
  if neededL0 > h.layer0.len:
    h.layer0.setLen(neededL0)
  let neededL1 = (neededL0 + L0_BITS - 1) shr L0_SHIFT
  if neededL1 > h.layer1.len:
    h.layer1.setLen(neededL1)
  let neededL2 = (neededL1 + L0_BITS - 1) shr L0_SHIFT
  if neededL2 > h.layer2.len:
    h.layer2.setLen(neededL2)

# ---------- bit manipulation ----------

proc unsafeSet*(h: var CAHiBitSet, idx: int) =
  ## Sets the bit at `idx` to 1. Grows automatically.
  let l0Idx  = idx   shr L0_SHIFT
  let bitPos = idx   and L0_MASK
  h.layer0[l0Idx] = h.layer0[l0Idx] or (BitBlock(1) shl bitPos)

  let l1Idx  = l0Idx shr L0_SHIFT
  h.layer1[l1Idx] = h.layer1[l1Idx] or (BitBlock(1) shl (l0Idx and L0_MASK))

  let l2Idx  = l1Idx shr L0_SHIFT
  h.layer2[l2Idx] = h.layer2[l2Idx] or (BitBlock(1) shl (l1Idx and L0_MASK))

proc set*(h: var CAHiBitSet, idx: int) =
  ## Sets the bit at `idx` to 1. Grows automatically.
  h.ensureCapacity(idx)
  h.unsafeSet(idx)
  
template unset*(h: var CAHiBitSet, idx: int) =
  ## Sets the bit at `idx` to 0.
  ## Propagates the clearing up through layer1 / layer2 when a block empties.
  if idx < h.len:
    let l0Idx  = idx   shr L0_SHIFT
    let bitPos = idx   and L0_MASK
    h.layer0[l0Idx] = h.layer0[l0Idx] and not (BitBlock(1) shl bitPos)

    if h.layer0[l0Idx] == 0:
      let l1Idx = l0Idx shr L0_SHIFT
      h.layer1[l1Idx] = h.layer1[l1Idx] and not (BitBlock(1) shl (l0Idx and L0_MASK))

      if h.layer1[l1Idx] == 0:
        let l2Idx = l1Idx shr L0_SHIFT
        h.layer2[l2Idx] = h.layer2[l2Idx] and not (BitBlock(1) shl (l1Idx and L0_MASK))

proc setL0Block*(h: var CAHiBitSet, l0Idx: int, value: BitBlock) {.inline.} =
  ## Sets an entire layer0 block and updates layer1 / layer2 accordingly..
  if (l0Idx + 1) > h.layer0.len:
    h.ensureCapacity(l0Idx shl L0_SHIFT)

  h.layer0[l0Idx] = value

  let l1Idx  = l0Idx shr L0_SHIFT
  let l1Bit  = l0Idx and L0_MASK
  if value != 0:
    h.layer1[l1Idx] = h.layer1[l1Idx] or  (BitBlock(1) shl l1Bit)
  else:
    h.layer1[l1Idx] = h.layer1[l1Idx] and not (BitBlock(1) shl l1Bit)

  let l2Idx  = l1Idx shr L0_SHIFT
  let l2Bit  = l1Idx and L0_MASK
  if h.layer1[l1Idx] != 0:
    h.layer2[l2Idx] = h.layer2[l2Idx] or  (BitBlock(1) shl l2Bit)
  else:
    h.layer2[l2Idx] = h.layer2[l2Idx] and not (BitBlock(1) shl l2Bit)

proc get*(h: CAHiBitSet, idx: int): bool {.inline.} =
  ## Returns true if the bit at `idx` is set. Time complexity: O(1)
  if idx >= h.len: return false
  let l0Idx  = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  let mask = BitBlock(1) shl bitPos
  (h.layer0[l0Idx] and mask) != 0

proc get*(h: ptr CAHiBitSet, idx: int): bool {.inline.} =
  h[].get(idx)

proc getL0*(h: CAHiBitSet, idx: int): BitBlock {.inline.} =
  ## Returns the raw block at layer0 index `idx`.
  if idx >= h.layer0.len: return 0
  h.layer0[idx]

proc getL0*(h: ptr CAHiBitSet, idx: int): BitBlock {.inline.} =
  h[].getL0(idx)

proc clear*(h: var CAHiBitSet) =
  ## Resets all bits to 0. Time complexity: O(n)
  for i in 0..<h.layer0.len: h.layer0[i] = 0
  for i in 0..<h.layer1.len: h.layer1[i] = 0
  for i in 0..<h.layer2.len: h.layer2[i] = 0

proc getSpace*(c: var CAHiBitSet, size: int = 4): int =
  ## Return the starting point of the index with enough space for the request.
  ## `size` in words (needed slots = size * 2)
  if size <= 0: return 0
  let needed = size * 2
  var slot = 0
  var count = 0

  while true:
    if slot >= c.len:
      let start = slot - count
      c.ensureCapacity(start + needed)
      return start

    # Hierarchy acceleration when count == 0:
    if count == 0 and (slot and 63) == 0:
      let l2Idx = slot shr 6
      if l2Idx < c.layer2.len and c.layer2[l2Idx] == 0xF:
        slot += 64
        continue

    if count == 0 and (slot and 15) == 0:
      let l1Idx = slot shr 4
      if l1Idx < c.layer1.len and c.layer1[l1Idx] == 0xF:
        slot += 16
        continue

    if count == 0 and (slot and 3) == 0:
      let l0Idx = slot shr 2
      if l0Idx < c.layer0.len and c.layer0[l0Idx] == 0xF:
        slot += 4
        continue

    # Fast forward full free blocks when aligned and fitting into needed:
    if (slot and 15) == 0 and count + 16 <= needed:
      let l1Idx = slot shr 4
      if l1Idx < c.layer1.len and c.layer1[l1Idx] == 0:
        count += 16
        slot += 16
        if count >= needed:
          return slot - count
        continue

    if (slot and 3) == 0 and count + 4 <= needed:
      let l0Idx = slot shr 2
      if l0Idx < c.layer0.len and c.layer0[l0Idx] == 0:
        count += 4
        slot += 4
        if count >= needed:
          return slot - count
        continue

    # Single-slot check
    let l0Idx = slot shr L0_SHIFT
    let bitPos = slot and L0_MASK
    let isOccupied = (c.layer0[l0Idx] and (BitBlock(1) shl bitPos)) != 0
    inc slot

    if isOccupied:
      count = 0
    else:
      inc count
      if count >= needed:
        return slot - count

# Fills a space in an allocator with one in order to make it unavailave for future allocations
# until freed
proc fillAlloc*(h: var CAHiBitSet, startSlot: int, size: int) =
  if size <= 0: return
  let stop = startSlot+size*2 - 1
  h.set(stop)
  
  for i in startSlot..<stop:
    h.unsafeSet(i)

##########################################################################################################################################################
################################################################## FREE RANGE ############################################################################
##########################################################################################################################################################

proc freeRange*(h: var CAHiBitSet, startSlot: int, size: int) =
  for i in startSlot..<startSlot+size*2:
    h.unset(i)
