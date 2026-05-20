######################################################################################################################################################################
###################################################################### ALLOCATOR HIBITSET ############################################################################
######################################################################################################################################################################

type
  ## A 4-bit Hierarchical bitset for allocation
  ## Allows us to quickly get an available memory chuck when allocating
  BitBlock = uint8
  CAHiBitSet = type
    layer0: seq[uint8] # Get to know if 4 bits are used
    layer1: seq[uint8] # Get to know if 16 bits are used
    layer2: seq[uint8] # Get to know if 64 bits are used

const
  L0_BITS*  = 4
  L0_SHIFT* = 2
  L0_MASK*  = 3

proc len*(h: CAHiBitSet): int {.inline.} =
  ## Total capacity of the bitset in bits.
  h.layer0.len * L0_BITS

# ---------- internal growth helper ----------

template ensureCapacity(h: var CAHiBitSet, i: untyped) =
  let idx = i.int
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

template set*(h: var CAHiBitSet, i: untyped) =
  ## Sets the bit at `idx` to 1. Grows automatically.
  let idx = i.int
  h.ensureCapacity(idx)
  let l0Idx  = idx   shr L0_SHIFT
  let bitPos = idx   and L0_MASK
  h.layer0[l0Idx] = h.layer0[l0Idx] or (BitBlock(1) shl bitPos)

  let l1Idx  = l0Idx shr L0_SHIFT
  h.layer1[l1Idx] = h.layer1[l1Idx] or (BitBlock(1) shl (l0Idx and L0_MASK))

  let l2Idx  = l1Idx shr L0_SHIFT
  h.layer2[l2Idx] = h.layer2[l2Idx] or (BitBlock(1) shl (l1Idx and L0_MASK))

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

proc get*(h: CAHiBitSet | ptr CAHiBitSet, idx: int): bool {.inline.} =
  ## Returns true if the bit at `idx` is set. Time complexity: O(1)
  if idx >= h.len: return false
  let l0Idx  = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  (h.layer0[l0Idx] and (BitBlock(1) shl bitPos)) != 0

proc getL0*(h: CAHiBitSet | ptr CAHiBitSet, idx: int): BitBlock {.inline.} =
  ## Returns the raw block at layer0 index `idx`.
  if idx >= h.layer0.len: return 0
  h.layer0[idx]

proc clear*(h: var CAHiBitSet) =
  ## Resets all bits to 0. Time complexity: O(n)
  for i in 0..<h.layer0.len: h.layer0[i] = 0
  for i in 0..<h.layer1.len: h.layer1[i] = 0
  for i in 0..<h.layer2.len: h.layer2[i] = 0

proc getSpace(c: var CAHiBitSet, size: int=4): int =
  ## Return the starting point of the index with enough space for the request.
  ## `size` in bytes
  
  # Store our current position in the allocator, tells us if we are still contiguous and where to continue from if not
  var current = 0

  # The positions of the previous run.
  # Those allow the program to continue searching space where it stopped
  var 
    lastL0 = 0
    lastL1 = 0
    lastL2 = 0

  # Our main loop. Run until we find enough space and return it's starting offset
  while true:

    # We initialize result to store the starting point
    result = current

    # This block will be broken if we fail to find contiguous space in this run.
    block searchSpace:

      # `s` = number of bit necessary for this layer
      # `v` = number of remainder of bit necessary, used by the next layer as `size`
      var (s, v) = (size div 8, size mod 8)

      # These let us know if we found the required number of blocks for this layer before continuing
      var
        countL0 = 0
        countL1 = 0
        countL2 = 0

      if s != 0:

        # This block is in case we found the necessary number of block and need to escape the loop
        # BUT if in lower layers we fail to find contiguous space, we continue where we stopped this
        block l2Search:
          while countL2 < s:

            # The current index in the L2 layer
            let currentL2 = current div 64
            if currentL2 >= c.layer2.len: c.layer2.setLen(currentL2+1)
            var currentBits = (not c.layer2[currentL2]) and 0xF

            while currentBits != 0:
              let bit = getTrailingZeroBits(currentBits)
              let pos = currentL2*L0_BITS+bit # Our position relative to this layer, since `currentBits` is 4 bits long

              # if our last position is not consecutive to this one.
              # We reset the counter
              if (pos-lastL2 != 1): 
                countL2 = 0

              # Updating ou last position and counter
              lastL2 = pos
              inc countL2

              # If we found the necessary space, we just escape the block
              if countL2 >= s: break l2Search

              # Else we update `currentBits` for the next iteration
              currentBits = currentBits and (currentBits - 1)

            current += 64
      
      # If countL2 = 0, this means we didn't need the previous layer for this allocation
      # So we should not update next layer based on it
      if countL2 > 0: 
        lastL1 = lastL2*4

      (s, v) = (v div 2, v mod 2)
      if s != 0:
        block l1Search:
          while countL1 < s:
            let currentL1 = lastL1
            if currentL1 >= c.layer1.len: c.layer1.setLen(currentL1+1)
            var currentBits = (not c.layer1[currentL1]) and 0xF

            while currentBits != 0:
              let bit = getTrailingZeroBits(currentBits)
              let pos = currentL1*L0_BITS+bit

              if (pos-lastL1 != 1): 
                countL1 = 0

              lastL1 = pos
              inc countL1
              if countL1 >= s: break l1Search

              currentBits = currentBits and (currentBits - 1)

            current += 16

      if countL1 > 0: 
        lastL0 = lastL1*4

      s = v
      if s != 0:
        block l0Search:
          while countL0 < s:
            let currentL0 = lastL0
            
            if currentL0 >= c.layer0.len: c.layer0.setLen(currentL0+1)
            var currentBits = (not c.layer0[currentL0]) and 0xF

            while currentBits != 0:
              let bit = getTrailingZeroBits(currentBits)
              let pos = currentL0*L0_BITS+bit

              if (pos-lastL0 != 1): 
                countL0 = 0

              lastL0 = pos
              inc countL0
              if countL0 >= s: break l0Search

              currentBits = currentBits and (currentBits - 1)

            current += 4

      break

proc fillL1*(h: var CAHiBitSet, l1Idx: int) {.inline.} =
  ## Mark a full layer1 block (16 slots) as occupied.
  ## Writes L0_FULL into all 4 layer0 children, sets the layer1 byte to L0_FULL,
  ## then sets the corresponding bit in the layer2 byte.
  let l0Base = l1Idx * L0_BITS
  for l0Off in 0..<L0_BITS:
    h.layer0[l0Base + l0Off] = L0_FULL
  h.layer1[l1Idx] = L0_FULL
  # Propagate: set the layer2 bit that tracks this l1 block.
  let l2Idx = l1Idx shr L0_SHIFT
  h.layer2[l2Idx] = h.layer2[l2Idx] or (1'u8 shl (l1Idx and L0_MASK))
 
proc fillL2*(h: var CAHiBitSet, l2Idx: int) {.inline.} =
  ## Mark a full layer2 block (64 slots) as occupied.
  ## Delegates to fillL1 for each of the 4 layer1 children (which in turn fill
  ## their layer0 children), then sets the layer2 byte to L0_FULL.
  let l1Base = l2Idx * L0_BITS
  for l1Off in 0..<L0_BITS:
    h.fillL1(l1Base + l1Off)
  h.layer2[l2Idx] = L0_FULL   ## overwrite after fillL1 to ensure all 4 bits set
 
proc fillAlloc*(h: var CAHiBitSet, startSlot: int, size: int) =
  ## Mark `size` contiguous slots starting at `startSlot` as occupied.
  ##
  ## Processes the range in up to five passes, from finest to coarsest and back:
  ##   1. Unaligned prefix bits  (< layer0 boundary)  -> setBit per slot.
  ##   2. Full layer0 blocks (4  slots each)           -> write L0_FULL + propagate.
  ##   3. Full layer1 blocks (16 slots each)           -> fillL1.
  ##   4. Full layer2 blocks (64 slots each)           -> fillL2.
  ##   5. Unaligned suffix bits                        -> setBit per slot.
  ##
  ## Example costs:
  ##   float  (1  slot) : 1 setBit call.
  ##   vec4   (4  slots, aligned) : 1 layer0 write + 2 propagations.
  ##   mat4   (16 slots, aligned) : 1 fillL1 call  (4 l0 writes + 1 l1 + 1 l2).
  h.ensureCapacity(startSlot + size - 1)
 
  var slot    = startSlot
  let endSlot = startSlot + size
 
  # 1. Unaligned prefix.
  while slot < endSlot and (slot and L0_MASK) != 0:
    h.setBit(slot)
    inc slot
 
  # 4. Full layer2 blocks first to avoid redundant propagations.
  while slot + 64 <= endSlot:
    h.fillL2(slot shr 6)
    slot += 64
 
  # 3. Full layer1 blocks.
  while slot + 16 <= endSlot:
    h.fillL1(slot shr 4)
    slot += 16
 
  # 2. Full layer0 blocks.
  while slot + L0_BITS <= endSlot:
    let l0Idx = slot shr L0_SHIFT
    h.layer0[l0Idx] = L0_FULL
    let l1Idx = l0Idx shr L0_SHIFT
    h.layer1[l1Idx] = h.layer1[l1Idx] or (1'u8 shl (l0Idx and L0_MASK))
    let l2Idx = l1Idx shr L0_SHIFT
    h.layer2[l2Idx] = h.layer2[l2Idx] or (1'u8 shl (l1Idx and L0_MASK))
    slot += L0_BITS
 
  # 5. Unaligned suffix.
  while slot < endSlot:
    h.setBit(slot)
    inc slot
 
##########################################################################################################################################################
################################################################## FREE RANGE ############################################################################
##########################################################################################################################################################
##
## freeL1 and freeL2 are the batch helpers used internally by freeRange.
## They clear the coarse layer bit first (releasing the whole block claim) and
## then zero all children downward.
 
proc freeL1*(h: var CAHiBitSet, l1Idx: int) {.inline.} =
  ## Release a full layer1 block (16 slots).
  ## Zeros all 4 layer0 children, clears the layer1 byte,
  ## then clears the corresponding bit in the layer2 byte.
  let l0Base = l1Idx * L0_BITS
  for l0Off in 0..<L0_BITS:
    h.layer0[l0Base + l0Off] = 0
  h.layer1[l1Idx] = 0
  let l2Idx = l1Idx shr L0_SHIFT
  h.layer2[l2Idx] = h.layer2[l2Idx] and not (1'u8 shl (l1Idx and L0_MASK))
 
proc freeL2*(h: var CAHiBitSet, l2Idx: int) {.inline.} =
  ## Release a full layer2 block (64 slots).
  ## Delegates to freeL1 for each of the 4 layer1 children, then zeros the
  ## layer2 byte itself.
  let l1Base = l2Idx * L0_BITS
  for l1Off in 0..<L0_BITS:
    h.freeL1(l1Base + l1Off)
  h.layer2[l2Idx] = 0
 
proc freeRange*(h: var CAHiBitSet, startSlot: int, size: int) =
  ## Release `size` contiguous slots starting at `startSlot`.
  ##
  ## Mirrors fillAlloc exactly:
  ##   1. Unaligned prefix bits                        -> unsetBit per slot.
  ##   2. Full layer0 blocks (4  slots each)           -> zero block + clear l1/l2 if empty.
  ##   3. Full layer1 blocks (16 slots each)           -> freeL1.
  ##   4. Full layer2 blocks (64 slots each)           -> freeL2.
  ##   5. Unaligned suffix bits                        -> unsetBit per slot.
  ##
  ## Layer1 / layer2 bits are cleared conservatively: a parent bit is cleared
  ## only after confirming the entire child block is now zero, which `freeL1`
  ## and `freeL2` guarantee by construction.
  if startSlot >= h.len: return
 
  var slot    = startSlot
  let endSlot = min(startSlot + size, h.len)
 
  # 1. Unaligned prefix.
  while slot < endSlot and (slot and L0_MASK) != 0:
    h.unsetBit(slot)
    inc slot
 
  # 4. Full layer2 blocks.
  while slot + 64 <= endSlot:
    h.freeL2(slot shr 6)
    slot += 64
 
  # 3. Full layer1 blocks.
  while slot + 16 <= endSlot:
    h.freeL1(slot shr 4)
    slot += 16
 
  # 2. Full layer0 blocks.
  while slot + L0_BITS <= endSlot:
    let l0Idx = slot shr L0_SHIFT
    h.layer0[l0Idx] = 0
    # Clear the layer1 bit for this l0 block.
    let l1Idx = l0Idx shr L0_SHIFT
    h.layer1[l1Idx] = h.layer1[l1Idx] and not (1'u8 shl (l0Idx and L0_MASK))
    # Clear the layer2 bit only if the entire l1 byte is now empty.
    if (h.layer1[l1Idx] and L0_FULL) == 0:
      let l2Idx = l1Idx shr L0_SHIFT
      h.layer2[l2Idx] = h.layer2[l2Idx] and not (1'u8 shl (l1Idx and L0_MASK))
    slot += L0_BITS
 
  # 5. Unaligned suffix.
  while slot < endSlot:
    h.unsetBit(slot)
    inc slot