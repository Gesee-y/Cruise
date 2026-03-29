########################################################################################################################################
######################################################### CRUISE HIBITSETS #############################################################
########################################################################################################################################

import std/[bitops, times, strformat]
## Hierarchical BitSets (HiBitSet) for Nim
## 
## This module provides two implementations of hierarchical bitsets:
## - HiBitSet: Dense implementation with fixed memory allocation
## - SparseHiBitSet: Sparse implementation using sparse sets, only allocates non-zero blocks
##
## Both use a 2-level hierarchy where layer1 summarizes 64 blocks of layer0,
## enabling fast iteration over set bits using trailing zero counts.

when defined(js):
  const
    L0_BITS* = 32      ## Bits per layer0 block (optimized for JS bitwise)
    L0_SHIFT* = 5      ## log2(32)
    L0_MASK* = 31      ## Mask for 32 bits
  type BitBlock* = uint32
else:
  const
    L0_BITS* = 64      ## Bits per layer0 block
    L0_SHIFT* = 6      ## log2(64)
    L0_MASK* = 63      ## Mask for 64 bits
  type BitBlock* = uint64

type
  HiBitSet* = object
    ## Dense hierarchical bitset
    ## Memory usage: O(capacity/8) bytes, allocated upfront
    layer0: seq[BitBlock]  ## Bottom level - actual bits
    layer1: seq[BitBlock]  ## Top level - summary of layer0 blocks

  SparseHiBitSet* = object
    ## Sparse hierarchical bitset using sparse sets
    ## Memory usage: O(set_bits * 3 * sizeof(uint64)), only allocates non-zero blocks
    ## Uses sparse set technique for O(1) insert/delete/lookup without hashing
    layer0Dense: seq[BitBlock]      ## Dense array: contains only non-zero block values
    layer0Sparse: seq[int]        ## Sparse array: maps block index -> dense position
    layer0DenseIdx: seq[int]      ## Inverse map: dense position -> block index
    layer0Count: int              ## Number of valid entries in dense arrays
    
    layer1Dense: seq[BitBlock]      ## Same structure for layer1
    layer1Sparse: seq[int]
    layer1DenseIdx: seq[int]
    layer1Count: int

  HiBitSetType = HiBitSet

# ============================================================================
# Dense HiBitSet Implementation
# ============================================================================

proc newHiBitSet*(capacity: int = 4096): HiBitSet =
  ## Creates a new dense HiBitSet with specified capacity.
  ## Memory is allocated upfront based on capacity.
  ## 
  ## Example:
  ##   var bs = newHiBitSet(10000)
  let l0Size = (capacity + L0_BITS - 1) shr L0_SHIFT
  let l1Size = (l0Size + L0_BITS - 1) shr L0_SHIFT
  result.layer0 = newSeq[BitBlock](l0Size)
  result.layer1 = newSeq[BitBlock](l1Size)

proc len*(h: HiBitSet): int {.inline.} =
  ## Returns the total capacity of the bitset in bits
  h.layer0.len * L0_BITS

template ensureCapacity(h: var HiBitSet, idx: int) =
  ## Ensures the bitset can hold the given index, growing if necessary
  let neededL0 = (idx shr L0_SHIFT) + 1
  if neededL0 > h.layer0.len:
    h.layer0.setLen(neededL0)
    let neededL1 = (neededL0 + L0_BITS - 1) shr L0_SHIFT
    if neededL1 > h.layer1.len:
      h.layer1.setLen(neededL1)

template set*(h: var HiBitSet, idx: int) =
  ## Sets the bit at the specified index to 1.
  ## Automatically grows the bitset if needed.
  ## 
  ## Time complexity: O(1)
  h.ensureCapacity(idx)
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  h.layer0[l0Idx] = h.layer0[l0Idx] or (BitBlock(1) shl bitPos)
  h.layer1[l0Idx shr L0_SHIFT] = h.layer1[l0Idx shr L0_SHIFT] or (BitBlock(1) shl (l0Idx and L0_MASK))

proc setL0Block*(h: var HiBitSet, l0Idx: int, value: BitBlock) {.inline.} =
  ## Sets an entire block at l0Idx.
  ## Updates layer1 correctly. O(1).
  let neededL0 = l0Idx + 1
  if neededL0 > h.layer0.len:
    h.ensureCapacity(l0Idx shl L0_SHIFT)
  
  h.layer0[l0Idx] = value
  let l1Idx = l0Idx shr L0_SHIFT
  let l1Bit = l0Idx and L0_MASK
  if value != 0:
    h.layer1[l1Idx] = h.layer1[l1Idx] or (BitBlock(1) shl l1Bit)
  else:
    h.layer1[l1Idx] = h.layer1[l1Idx] and not (BitBlock(1) shl l1Bit)

template setBatch*(h: var HiBitSet, idxs: openArray[uint|int]) =
  ## Sets multiple bits at once. 
  ## Optimizes layer1 updates by grouping indices into blocks.
  if idxs.len == 0: return
  
  var lastL0Idx = -1
  
  for idx in idxs:
    let i = idx.int
    h.ensureCapacity(i)
    let l0Idx = i shr L0_SHIFT
    let bitPos = i and L0_MASK
    h.layer0[l0Idx] = h.layer0[l0Idx] or (BitBlock(1) shl bitPos)
    
    if l0Idx != lastL0Idx:
      h.layer1[l0Idx shr L0_SHIFT] = h.layer1[l0Idx shr L0_SHIFT] or (BitBlock(1) shl (l0Idx and L0_MASK))
      lastL0Idx = l0Idx

proc unsetBatch*(h: var HiBitSet, idxs: openArray[uint|int]) =
  ## Unsets multiple bits at once.
  if idxs.len == 0: return
  for idx in idxs:
    h.unset(idx.int)


template unset*(h: var HiBitSet, idx: int) =
  ## Sets the bit at the specified index to 0.
  ## Updates layer1 if the entire block becomes empty.
  ## 
  ## Time complexity: O(1)
  if idx >= h.len: return
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  h.layer0[l0Idx] = h.layer0[l0Idx] and not (BitBlock(1) shl bitPos)
  
  if h.layer0[l0Idx] == 0:
    let l1Idx = l0Idx shr L0_SHIFT
    let l1Bit = l0Idx and L0_MASK
    h.layer1[l1Idx] = h.layer1[l1Idx] and not (BitBlock(1) shl l1Bit)

proc get*(h: HiBitSet, idx: int): bool {.inline.} =
  ## Returns true if the bit at index is set, false otherwise.
  ## 
  ## Time complexity: O(1)
  if idx >= h.len: return false
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  (h.layer0[l0Idx] and (BitBlock(1) shl bitPos)) != 0

proc getL0*(h: HiBitSet, idx: int): BitBlock =
  ## Returns the raw uint64 block at layer0 index.
  ## Useful for direct block manipulation.
  if idx >= h.layer0.len: return 0
  h.layer0[idx]

proc hasL0*(h: HiBitSet, l0Idx: int): bool {.inline.} =
  ## Returns true if the block index is within the allocated capacity.
  l0Idx < h.layer0.len

proc `[]`*(h: HiBitSet, idx: int): bool {.inline.} =
  ## Array access syntax: returns true if bit is set.
  ## Example: if bitset[42]: echo "bit 42 is set"
  h.get(idx)

proc `[]=`*(h: var HiBitSet, idx: int, value: bool) {.inline.} =
  ## Array assignment syntax: sets or unsets bit based on value.
  ## Example: bitset[42] = true
  if value: h.set(idx) else: h.unset(idx)

proc clear*(h: var HiBitSet) =
  ## Resets all bits to 0.
  ## 
  ## Time complexity: O(n) where n is allocated capacity
  for i in 0..<h.layer0.len: h.layer0[i] = 0
  for i in 0..<h.layer1.len: h.layer1[i] = 0

proc `and`*(a, b: HiBitSet): HiBitSet =
  ## Bitwise AND operation: returns bits set in both a AND b.
  ## Result capacity is min(a.len, b.len)
  result = newHiBitSet()
  let minL0 = min(a.layer0.len, b.layer0.len)
  result.layer0.setLen(minL0)
  result.layer1.setLen((minL0 + L0_BITS - 1) shr L0_SHIFT)
  
  for i in 0..<minL0:
    result.layer0[i] = a.layer0[i] and b.layer0[i]
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (BitBlock(1) shl (i and L0_MASK))

proc `or`*(a, b: HiBitSet): HiBitSet =
  ## Bitwise OR operation: returns bits set in a OR b or both.
  ## Result capacity is max(a.len, b.len)
  result = newHiBitSet()
  let maxL0 = max(a.layer0.len, b.layer0.len)
  result.layer0.setLen(maxL0)
  result.layer1.setLen((maxL0 + L0_BITS - 1) shr L0_SHIFT)
  
  for i in 0..<maxL0:
    let aVal = if i < a.layer0.len: a.layer0[i] else: BitBlock(0)
    let bVal = if i < b.layer0.len: b.layer0[i] else: BitBlock(0)
    result.layer0[i] = aVal or bVal
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (BitBlock(1) shl (i and L0_MASK))

proc `xor`*(a, b: HiBitSet): HiBitSet =
  ## Bitwise XOR operation: returns bits set in a OR b but not both.
  ## Result capacity is max(a.len, b.len)
  result = newHiBitSet()
  let maxL0 = max(a.layer0.len, b.layer0.len)
  result.layer0.setLen(maxL0)
  result.layer1.setLen((maxL0 + L0_BITS - 1) shr L0_SHIFT)
  
  for i in 0..<maxL0:
    let aVal = if i < a.layer0.len: a.layer0[i] else: BitBlock(0)
    let bVal = if i < b.layer0.len: b.layer0[i] else: BitBlock(0)
    result.layer0[i] = aVal xor bVal
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (BitBlock(1) shl (i and L0_MASK))

proc andNot*(a, b: HiBitSet): HiBitSet =
  ## Bitwise AND NOT operation: returns bits set in `a` but cleared in `b`.
  ## Avoids generating an expensive inverted intermediate HiBitSet.
  result = newHiBitSet()
  result.layer0.setLen(a.layer0.len)
  result.layer1.setLen(a.layer1.len)
  
  for i in 0..<a.layer0.len:
    let bVal = if i < b.layer0.len: b.layer0[i] else: BitBlock(0)
    result.layer0[i] = a.layer0[i] and not bVal
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (BitBlock(1) shl (i and L0_MASK))

proc `not`*(a: HiBitSet): HiBitSet =
  ## Bitwise NOT operation: inverts all bits.
  ## Note: This includes flipping bits beyond the highest set bit.
  result = newHiBitSet()
  result.layer0.setLen(a.layer0.len)
  result.layer1.setLen(a.layer1.len)
  
  for i in 0..<a.layer0.len:
    result.layer0[i] = not a.layer0[i]
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (BitBlock(1) shl (i and L0_MASK))

iterator items*(h: HiBitSet): int =
  ## Iterates over all indices where the bit is set.
  ## Uses trailing zero counts for efficient skipping of empty blocks.
  ## 
  ## Example:
  ##   for idx in bitset:
  ##     echo "bit ", idx, " is set"
  for l1Idx in 0..<h.layer1.len:
    var l1Block = h.layer1[l1Idx]
    while l1Block != 0:
      let l1Tz = countTrailingZeroBits(l1Block)
      let l0Idx = (l1Idx shl L0_SHIFT) or l1Tz
      
      var l0Block = h.layer0[l0Idx]
      while l0Block != 0:
        let l0Tz = countTrailingZeroBits(l0Block)
        yield (l0Idx shl L0_SHIFT) or l0Tz
        l0Block = l0Block and (l0Block - 1)  # Clear rightmost bit
      
      l1Block = l1Block and (l1Block - 1)

iterator blkIter*(h: HiBitSet): int =
  ## Iterates over layer0 block indices that contain at least one set bit.
  ## Faster than items() when you need to process entire blocks.
  ## 
  ## Example:
  ##   for blockIdx in bitset.blkIter:
  ##     let block = bitset.getL0(blockIdx)
  ##     # process entire block
  for l1Idx in 0..<h.layer1.len:
    var l1Block = h.layer1[l1Idx]
    while l1Block != 0:
      let l1Tz = countTrailingZeroBits(l1Block)
      yield (l1Idx shl L0_SHIFT) or l1Tz
      l1Block = l1Block and (l1Block - 1)

proc card*(h: HiBitSet): int =
  ## Returns the number of set bits (cardinality).
  result = 0
  for blk in h.layer0:
    result += countSetBits(blk)

proc maxLen(h: HiBitSet):int =
  return h.layer0.len  

proc `$`*(h: HiBitSet): string =
  ## String representation showing all set bit indices.
  result = "HiBitSet["
  var first = true
  for idx in h:
    if not first: result.add(", ")
    result.add($idx)
    first = false
  result.add("]")

# ============================================================================
# Sparse HiBitSet Implementation
# ============================================================================

proc newSparseHiBitSet*(initialCapacity: int = 64): SparseHiBitSet =
  ## Creates a new sparse HiBitSet.
  ## Memory is only allocated for non-zero blocks, making it ideal for
  ## very sparse data (e.g., ECS with few active entities).
  ## 
  ## The sparse set technique provides O(1) operations without hashing:
  ## - dense: packed array of non-zero values
  ## - sparse: maps index -> position in dense
  ## - denseIdx: maps position in dense -> original index
  ## 
  ## Example:
  ##   var bs = newSparseHiBitSet()
  ##   bs.set(1_000_000)  # Only allocates ~3 uint64s, not 1M bits
  result.layer0Dense = newSeq[BitBlock](initialCapacity)
  result.layer0Sparse = newSeq[int](initialCapacity)
  result.layer0DenseIdx = newSeq[int](initialCapacity)
  result.layer0Count = 0
  
  let l1Cap = max(8, initialCapacity shr L0_SHIFT)
  result.layer1Dense = newSeq[BitBlock](l1Cap)
  result.layer1Sparse = newSeq[int](l1Cap)
  result.layer1DenseIdx = newSeq[int](l1Cap)
  result.layer1Count = 0

proc ensureCapacityL0(h: var SparseHiBitSet, idx: int) {.inline.} =
  ## Ensures sparse arrays can hold index, growing exponentially if needed
  if idx >= h.layer0Sparse.len:
    let newLen = max(idx + 1, h.layer0Sparse.len * 2)
    h.layer0Sparse.setLen(newLen)
    h.layer0Dense.setLen(newLen)
    h.layer0DenseIdx.setLen(newLen)

proc ensureCapacityL1(h: var SparseHiBitSet, idx: int) {.inline.} =
  ## Ensures layer1 sparse arrays can hold index
  if idx >= h.layer1Sparse.len:
    let newLen = max(idx + 1, h.layer1Sparse.len * 2)
    h.layer1Sparse.setLen(newLen)
    h.layer1Dense.setLen(newLen)
    h.layer1DenseIdx.setLen(newLen)

proc hasL0*(h: SparseHiBitSet, l0Idx: int): bool {.inline.} =
  ## Checks if a layer0 block exists (is non-zero).
  ## O(1) lookup using sparse set technique.
  if l0Idx >= h.layer0Sparse.len: return false
  let denseIdx = h.layer0Sparse[l0Idx]
  denseIdx < h.layer0Count and h.layer0DenseIdx[denseIdx] == l0Idx

proc getL0*(h: SparseHiBitSet, l0Idx: int): BitBlock {.inline.} =
  ## Gets a layer0 block value, returns 0 if block doesn't exist.
  ## O(1) lookup.
  if not h.hasL0(l0Idx): return 0
  h.layer0Dense[h.layer0Sparse[l0Idx]]

proc setL0*(h: var SparseHiBitSet, l0Idx: int, value: BitBlock) {.inline.} =
  ## Sets a layer0 block to the given value.
  ## If value is 0, removes the block using swap-and-pop.
  ## If value is non-zero and block exists, updates it.
  ## If value is non-zero and block doesn't exist, adds it.
  ## 
  ## Time complexity: O(1) for all operations
  h.ensureCapacityL0(l0Idx)
  
  if value == 0:
    # Remove block if it exists
    if h.hasL0(l0Idx):
      let denseIdx = h.layer0Sparse[l0Idx]
      let lastIdx = h.layer0Count - 1
      
      if denseIdx != lastIdx:
        # Swap with last element to maintain dense array compactness
        h.layer0Dense[denseIdx] = h.layer0Dense[lastIdx]
        h.layer0DenseIdx[denseIdx] = h.layer0DenseIdx[lastIdx]
        h.layer0Sparse[h.layer0DenseIdx[lastIdx]] = denseIdx
      
      h.layer0Count -= 1
  else:
    if h.hasL0(l0Idx):
      # Update existing block
      h.layer0Dense[h.layer0Sparse[l0Idx]] = value
    else:
      # Add new block
      h.layer0Sparse[l0Idx] = h.layer0Count
      h.layer0Dense[h.layer0Count] = value
      h.layer0DenseIdx[h.layer0Count] = l0Idx
      h.layer0Count += 1

proc hasL1*(h: SparseHiBitSet, l1Idx: int): bool {.inline.} =
  ## Checks if a layer1 block exists
  if l1Idx >= h.layer1Sparse.len: return false
  let denseIdx = h.layer1Sparse[l1Idx]
  denseIdx < h.layer1Count and h.layer1DenseIdx[denseIdx] == l1Idx

proc getL1*(h: SparseHiBitSet, l1Idx: int): BitBlock {.inline.} =
  ## Gets a layer1 block value
  if not h.hasL1(l1Idx): return 0
  h.layer1Dense[h.layer1Sparse[l1Idx]]

proc setL1*(h: var SparseHiBitSet, l1Idx: int, value: BitBlock) {.inline.} =
  ## Sets a layer1 block value using same sparse set technique as layer0
  h.ensureCapacityL1(l1Idx)
  
  if value == 0:
    if h.hasL1(l1Idx):
      let denseIdx = h.layer1Sparse[l1Idx]
      let lastIdx = h.layer1Count - 1
      
      if denseIdx != lastIdx:
        h.layer1Dense[denseIdx] = h.layer1Dense[lastIdx]
        h.layer1DenseIdx[denseIdx] = h.layer1DenseIdx[lastIdx]
        h.layer1Sparse[h.layer1DenseIdx[lastIdx]] = denseIdx
      
      h.layer1Count -= 1
  else:
    if h.hasL1(l1Idx):
      h.layer1Dense[h.layer1Sparse[l1Idx]] = value
    else:
      h.layer1Sparse[l1Idx] = h.layer1Count
      h.layer1Dense[h.layer1Count] = value
      h.layer1DenseIdx[h.layer1Count] = l1Idx
      h.layer1Count += 1

proc setL0Block*(h: var SparseHiBitSet, l0Idx: int, value: BitBlock) {.inline.} =
  ## Efficiently sets an entire block in the sparse bitset.
  ## Updates O(1) summary in layer1.
  h.setL0(l0Idx, value)
  
  # Update layer1
  let l1Idx = l0Idx shr L0_SHIFT
  let l1Bit = l0Idx and L0_MASK
  if value != 0:
    let l1Old = h.getL1(l1Idx)
    h.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))
  else:
    # If the block was cleared, we must ensure layer1 reflects this.
    # Note: h.setL0 already handles removal of the block entry if value is 0.
    let l1Old = h.getL1(l1Idx)
    h.setL1(l1Idx, l1Old and not (BitBlock(1) shl l1Bit))


proc set*(h: var SparseHiBitSet, idx: int) {.inline.} =
  ## Sets the bit at the specified index to 1.
  ## Only allocates memory if the containing block doesn't exist.
  ## 
  ## Time complexity: O(1)
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  
  let oldValue = h.getL0(l0Idx)
  let newValue = oldValue or (BitBlock(1) shl bitPos)
  h.setL0(l0Idx, newValue)
  
  # Update layer1
  let l1Idx = l0Idx shr L0_SHIFT
  let l1Bit = l0Idx and L0_MASK
  let l1Old = h.getL1(l1Idx)
  h.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))

proc setBatch*(h: var SparseHiBitSet, idxs: openArray[uint|int]) =
  ## Sets multiple bits in a sparse bitset. 
  ## Optimized for sequential or grouped indices.
  if idxs.len == 0: return
  
  var lastL0Idx = -1
  
  for idx in idxs:
    let i = idx.int
    let l0Idx = i shr L0_SHIFT
    let bitPos = i and L0_MASK
    
    let oldValue = h.getL0(l0Idx)
    let newValue = oldValue or (BitBlock(1) shl bitPos)
    h.setL0(l0Idx, newValue)
    
    if l0Idx != lastL0Idx:
      # Update layer1
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      let l1Old = h.getL1(l1Idx)
      h.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))
      lastL0Idx = l0Idx

proc unset*(h: var SparseHiBitSet, idx: int) {.inline.} =
  ## Sets the bit at the specified index to 0.
  ## Deallocates the block if it becomes empty.
  ## 
  ## Time complexity: O(1)
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  
  if not h.hasL0(l0Idx): return
  
  let oldValue = h.getL0(l0Idx)
  let newValue = oldValue and not (BitBlock(1) shl bitPos)
  h.setL0(l0Idx, newValue)
  
  # Update layer1 if block becomes empty
  if newValue == 0:
    let l1Idx = l0Idx shr L0_SHIFT
    let l1Bit = l0Idx and L0_MASK
    let l1Old = h.getL1(l1Idx)
    h.setL1(l1Idx, l1Old and not (BitBlock(1) shl l1Bit))

proc unsetBatch*(h: var SparseHiBitSet, idxs: openArray[uint|int]) =
  ## Unsets multiple bits in a sparse bitset.
  for idx in idxs:
    h.unset(idx.int)

proc get*(h: SparseHiBitSet, idx: int): bool {.inline.} =
  ## Returns true if the bit at index is set.
  ## 
  ## Time complexity: O(1)
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  if not h.hasL0(l0Idx): return false
  (h.getL0(l0Idx) and (BitBlock(1) shl bitPos)) != 0

proc `[]`*(h: SparseHiBitSet, idx: int): bool {.inline.} =
  ## Array access syntax
  h.get(idx)

proc `[]=`*(h: var SparseHiBitSet, idx: int, value: bool) {.inline.} =
  ## Array assignment syntax
  if value: h.set(idx) else: h.unset(idx)

template clear*(h: SparseHiBitSet) =
  ## Resets all bits to 0 by clearing the sparse set counters.
  ## Does not deallocate memory, but makes all blocks logically non-existent.
  ## 
  ## Time complexity: O(1)
  h.layer0Count = 0
  h.layer1Count = 0

proc isEmpty*(h: SparseHiBitSet): bool {.inline.} =
  ## Returns true if no bits are set.
  ## 
  ## Time complexity: O(1)
  h.layer0Count == 0

proc `and`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## Bitwise AND operation.
  ## Only processes blocks that exist in both bitsets.
  ## Very efficient for sparse data.
  result = newSparseHiBitSet()
  
  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    if b.hasL0(l0Idx):
      let andValue = a.layer0Dense[i] and b.getL0(l0Idx)
      if andValue != 0:
        result.setL0(l0Idx, andValue)
        
        let l1Idx = l0Idx shr L0_SHIFT
        let l1Bit = l0Idx and L0_MASK
        let l1Old = result.getL1(l1Idx)
        result.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))

proc `or`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## Bitwise OR operation.
  ## Processes all blocks from both bitsets.
  result = newSparseHiBitSet()
  
  # Add all blocks from a, ORed with corresponding blocks from b
  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    let orValue = a.layer0Dense[i] or b.getL0(l0Idx)
    result.setL0(l0Idx, orValue)
    
    let l1Idx = l0Idx shr L0_SHIFT
    let l1Bit = l0Idx and L0_MASK
    let l1Old = result.getL1(l1Idx)
    result.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))
  
  # Add blocks from b that aren't in a
  for i in 0..<b.layer0Count:
    let l0Idx = b.layer0DenseIdx[i]
    if not a.hasL0(l0Idx):
      result.setL0(l0Idx, b.layer0Dense[i])
      
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      let l1Old = result.getL1(l1Idx)
      result.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))

proc `xor`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## Bitwise XOR operation.
  ## Processes all blocks from both bitsets.
  result = newSparseHiBitSet()
  
  # Process all blocks from a
  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    let xorValue = a.layer0Dense[i] xor b.getL0(l0Idx)
    if xorValue != 0:
      result.setL0(l0Idx, xorValue)
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      let l1Old = result.getL1(l1Idx)
      result.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))
  
  # Process blocks from b that aren't in a
  for i in 0..<b.layer0Count:
    let l0Idx = b.layer0DenseIdx[i]
    if not a.hasL0(l0Idx):
      result.setL0(l0Idx, b.layer0Dense[i])
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      let l1Old = result.getL1(l1Idx)
      result.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))

proc `not`*(a: SparseHiBitSet): SparseHiBitSet =
  ## Bitwise NOT operation: inverts all bits.
  ## Note: For sparse bitsets, NOT creates a dense result because
  ## all previously zero blocks become non-zero (all 1s).
  ## This operation is generally not recommended for sparse bitsets
  ## as it defeats the purpose of sparse storage.
  ## 
  ## If you need negation in a sparse context, consider using
  ## set difference or XOR with a mask instead.
  result = newSparseHiBitSet()
  
  if a.layer0Count == 0:
    # NOT of empty set - all bits become 1 (not practical for sparse)
    return result
  
  # Find the maximum block index to determine range
  var maxL0Idx = 0
  for i in 0..<a.layer0Count:
    maxL0Idx = max(maxL0Idx, a.layer0DenseIdx[i])
  
  # Invert all blocks up to max
  for l0Idx in 0..maxL0Idx:
    let notValue = not a.getL0(l0Idx)
    if notValue != 0:
      result.setL0(l0Idx, notValue)
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      let l1Old = result.getL1(l1Idx)
      result.setL1(l1Idx, l1Old or (BitBlock(1) shl l1Bit))

proc andNot*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## Bitwise AND NOT operation: returns bits set in `a` but cleared in `b`.
  ## Avoids generating an expensive inverted intermediate HiBitSet.
  a and not b

proc maxLen(h: SparseHiBitSet): int =
  return h.layer1Count

iterator items*(h: SparseHiBitSet): int =
  ## Iterates over all indices where the bit is set.
  ## Extremely efficient for sparse data as it only processes existing blocks.
  ## 
  ## Example:
  ##   var bs = newSparseHiBitSet()
  ##   bs.set(1_000_000)
  ##   for idx in bs:  # Only visits idx=1_000_000, not millions of zeros
  ##     echo idx
  for i in 0..<h.layer1Count:
    let l1Idx = h.layer1DenseIdx[i]
    var l1Block = h.layer1Dense[i]
    
    while l1Block != 0:
      let l1Tz = countTrailingZeroBits(l1Block)
      let l0Idx = (l1Idx shl L0_SHIFT) or l1Tz
      
      var l0Block = h.getL0(l0Idx)
      while l0Block != 0:
        let l0Tz = countTrailingZeroBits(l0Block)
        yield (l0Idx shl L0_SHIFT) or l0Tz
        l0Block = l0Block and (l0Block - 1)
      
      l1Block = l1Block and (l1Block - 1)

iterator blkIter*(h: SparseHiBitSet): int =
  ## Iterates over layer0 block indices that contain set bits.
  ## Only visits non-zero blocks.
  for i in 0..<h.layer1Count:
    let l1Idx = h.layer1DenseIdx[i]
    var l1Block = h.layer1Dense[i]
    
    while l1Block != 0:
      let l1Tz = countTrailingZeroBits(l1Block)
      let l0Idx = (l1Idx shl L0_SHIFT) or l1Tz
      
      yield (l1Idx shl L0_SHIFT) or l1Tz
      l1Block = l1Block and (l1Block - 1)

proc card*(h: SparseHiBitSet): int =
  ## Returns the number of set bits.
  ## Only counts bits in existing blocks.
  result = 0
  for i in 0..<h.layer0Count:
    result += countSetBits(h.layer0Dense[i])

proc memoryUsage*(h: SparseHiBitSet): int =
  ## Returns approximate memory usage in bytes.
  ## Useful for comparing sparse vs dense implementations.
  result = h.layer0Count * sizeof(BitBlock) * 3  # dense + sparse + denseIdx
  result += h.layer1Count * sizeof(BitBlock) * 3

proc `$`*(h: SparseHiBitSet): string =
  ## String representation showing all set bit indices
  result = "SparseHiBitSet["
  var first = true
  for idx in h:
    if not first: result.add(", ")
    result.add($idx)
    first = false
  result.add("]")