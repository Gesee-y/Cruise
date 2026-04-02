########################################################################################################################################
######################################################### CRUISE HIBITSETS #############################################################
########################################################################################################################################

import std/[bitops, times, strformat]
## Hierarchical BitSets (HiBitSet) for Nim — 3-Level Implementation
##
## This module provides two implementations of 3-level hierarchical bitsets:
##   - HiBitSet:       Dense implementation with fixed memory allocation.
##   - SparseHiBitSet: Sparse implementation using sparse sets; only allocates non-zero blocks.
##
## Both use a 3-level hierarchy:
##   layer2  →  summarises 64 blocks of layer1  (top)
##   layer1  →  summarises 64 blocks of layer0  (middle)
##   layer0  →  holds the actual bits            (bottom)
##
## Maximum addressable index (native, 64-bit):
##   64 * 64 * 64 = 262 144 blocks of 64 bits  →  ~16 million bits per L2 block
##   Practically unlimited with dynamic growth.

when defined(js):
  const
    L0_BITS*  = 32
    L0_SHIFT* = 5
    L0_MASK*  = 31
  type BitBlock* = uint32
else:
  const
    L0_BITS*  = 64
    L0_SHIFT* = 6
    L0_MASK*  = 63
  type BitBlock* = uint64

# ============================================================================
# Dense HiBitSet — 3-level
# ============================================================================

type
  HiBitSet* = object
    ## Dense 3-level hierarchical bitset.
    ## Memory usage: O(capacity / 8) bytes, allocated up front.
    layer0: seq[BitBlock]   ## Bottom  — actual bits
    layer1: seq[BitBlock]   ## Middle  — one bit per layer0 block
    layer2: seq[BitBlock]   ## Top     — one bit per layer1 block

proc newHiBitSet*(capacity: int = 4096): HiBitSet =
  ## Creates a new dense HiBitSet able to hold `capacity` bits.
  let l0Size = (capacity + L0_BITS - 1)  shr L0_SHIFT
  let l1Size = (l0Size   + L0_BITS - 1)  shr L0_SHIFT
  let l2Size = (l1Size   + L0_BITS - 1)  shr L0_SHIFT
  result.layer0 = newSeq[BitBlock](l0Size)
  result.layer1 = newSeq[BitBlock](l1Size)
  result.layer2 = newSeq[BitBlock](l2Size)

proc len*(h: HiBitSet): int {.inline.} =
  ## Total capacity of the bitset in bits.
  h.layer0.len * L0_BITS

# ---------- internal growth helper ----------

template ensureCapacity(h: var HiBitSet, idx: int) =
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

template set*(h: var HiBitSet, idx: int) =
  ## Sets the bit at `idx` to 1. Grows automatically.
  ## Time complexity: O(1)
  h.ensureCapacity(idx)
  let l0Idx  = idx   shr L0_SHIFT
  let bitPos = idx   and L0_MASK
  h.layer0[l0Idx] = h.layer0[l0Idx] or (BitBlock(1) shl bitPos)

  let l1Idx  = l0Idx shr L0_SHIFT
  h.layer1[l1Idx] = h.layer1[l1Idx] or (BitBlock(1) shl (l0Idx and L0_MASK))

  let l2Idx  = l1Idx shr L0_SHIFT
  h.layer2[l2Idx] = h.layer2[l2Idx] or (BitBlock(1) shl (l1Idx and L0_MASK))

template unset*(h: var HiBitSet, idx: int) =
  ## Sets the bit at `idx` to 0.
  ## Propagates the clearing up through layer1 / layer2 when a block empties.
  ## Time complexity: O(1)
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

proc setL0Block*(h: var HiBitSet, l0Idx: int, value: BitBlock) {.inline.} =
  ## Sets an entire layer0 block and updates layer1 / layer2 accordingly. O(1).
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

template setBatch*(h: var HiBitSet, idxs: openArray[uint|int]) =
  ## Sets multiple bits at once, grouping layer1/layer2 updates.
  if idxs.len == 0: return
  var lastL0Idx = -1
  for idx in idxs:
    let i = idx.int
    h.ensureCapacity(i)
    let l0Idx  = i shr L0_SHIFT
    let bitPos = i and L0_MASK
    h.layer0[l0Idx] = h.layer0[l0Idx] or (BitBlock(1) shl bitPos)
    if l0Idx != lastL0Idx:
      let l1Idx = l0Idx shr L0_SHIFT
      h.layer1[l1Idx] = h.layer1[l1Idx] or (BitBlock(1) shl (l0Idx and L0_MASK))
      let l2Idx = l1Idx shr L0_SHIFT
      h.layer2[l2Idx] = h.layer2[l2Idx] or (BitBlock(1) shl (l1Idx and L0_MASK))
      lastL0Idx = l0Idx

proc unsetBatch*(h: var HiBitSet, idxs: openArray[uint|int]) =
  ## Unsets multiple bits at once.
  for idx in idxs:
    h.unset(idx.int)

proc get*(h: HiBitSet, idx: int): bool {.inline.} =
  ## Returns true if the bit at `idx` is set. Time complexity: O(1)
  if idx >= h.len: return false
  let l0Idx  = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  (h.layer0[l0Idx] and (BitBlock(1) shl bitPos)) != 0

proc getL0*(h: HiBitSet, idx: int): BitBlock {.inline.} =
  ## Returns the raw block at layer0 index `idx`.
  if idx >= h.layer0.len: return 0
  h.layer0[idx]

proc hasL0*(h: HiBitSet, l0Idx: int): bool {.inline.} =
  l0Idx < h.layer0.len

proc `[]`*(h: HiBitSet, idx: int): bool {.inline.} = h.get(idx)

proc `[]=`*(h: var HiBitSet, idx: int, value: bool) {.inline.} =
  if value: h.set(idx) else: h.unset(idx)

proc clear*(h: var HiBitSet) =
  ## Resets all bits to 0. Time complexity: O(n)
  for i in 0..<h.layer0.len: h.layer0[i] = 0
  for i in 0..<h.layer1.len: h.layer1[i] = 0
  for i in 0..<h.layer2.len: h.layer2[i] = 0

# ---------- block-level helpers used by set operations ----------

template rebuildL1L2(res: var HiBitSet) =
  ## Recomputes layer1 and layer2 from scratch based on layer0.
  ## Used after bulk operations that set layer0 directly.
  for l1Idx in 0..<res.layer1.len: res.layer1[l1Idx] = 0
  for l2Idx in 0..<res.layer2.len: res.layer2[l2Idx] = 0
  for l0Idx in 0..<res.layer0.len:
    if res.layer0[l0Idx] != 0:
      let l1Idx = l0Idx shr L0_SHIFT
      res.layer1[l1Idx] = res.layer1[l1Idx] or (BitBlock(1) shl (l0Idx and L0_MASK))
      let l2Idx = l1Idx shr L0_SHIFT
      res.layer2[l2Idx] = res.layer2[l2Idx] or (BitBlock(1) shl (l1Idx and L0_MASK))

# ---------- bitwise operators ----------

template `and`*(a, b: var HiBitSet): HiBitSet =
  ## Bitwise AND — result capacity is min(a.len, b.len).
  var res = newHiBitSet()
  let minL0 = min(a.layer0.len, b.layer0.len)
  let minL1 = (minL0 + L0_BITS - 1) shr L0_SHIFT
  let minL2 = (minL1 + L0_BITS - 1) shr L0_SHIFT
  res.layer0.setLen(minL0)
  res.layer1.setLen(minL1)
  res.layer2.setLen(minL2)
  for i in 0..<minL0:
    res.layer0[i] = a.layer0[i] and b.layer0[i]
  res.rebuildL1L2()
  res

template `andi`*(a: var HiBitSet, b: var HiBitSet) =
  ## In-place AND.
  let minL0 = min(a.layer0.len, b.layer0.len)
  a.layer0.setLen(minL0)
  let minL1 = (minL0 + L0_BITS - 1) shr L0_SHIFT
  let minL2 = (minL1 + L0_BITS - 1) shr L0_SHIFT
  a.layer1.setLen(minL1)
  a.layer2.setLen(minL2)
  for i in 0..<minL0:
    a.layer0[i] = a.layer0[i] and b.layer0[i]
  a.rebuildL1L2()

template `or`*(a, b: var HiBitSet): HiBitSet =
  ## Bitwise OR — result capacity is max(a.len, b.len).
  var res = newHiBitSet()
  let maxL0 = max(a.layer0.len, b.layer0.len)
  let maxL1 = (maxL0 + L0_BITS - 1) shr L0_SHIFT
  let maxL2 = (maxL1 + L0_BITS - 1) shr L0_SHIFT
  res.layer0.setLen(maxL0)
  res.layer1.setLen(maxL1)
  res.layer2.setLen(maxL2)
  for i in 0..<maxL0:
    let aVal = if i < a.layer0.len: a.layer0[i] else: BitBlock(0)
    let bVal = if i < b.layer0.len: b.layer0[i] else: BitBlock(0)
    res.layer0[i] = aVal or bVal
  res.rebuildL1L2()
  res

template `ori`*(a: var HiBitSet, b: var HiBitSet) =
  ## In-place OR.
  let maxL0 = max(a.layer0.len, b.layer0.len)
  let maxL1 = (maxL0 + L0_BITS - 1) shr L0_SHIFT
  let maxL2 = (maxL1 + L0_BITS - 1) shr L0_SHIFT
  a.layer0.setLen(maxL0)
  a.layer1.setLen(maxL1)
  a.layer2.setLen(maxL2)
  for i in 0..<maxL0:
    let bVal = if i < b.layer0.len: b.layer0[i] else: BitBlock(0)
    a.layer0[i] = a.layer0[i] or bVal
  a.rebuildL1L2()

template `xor`*(a, b: var HiBitSet): HiBitSet =
  ## Bitwise XOR — result capacity is max(a.len, b.len).
  var res = newHiBitSet()
  let maxL0 = max(a.layer0.len, b.layer0.len)
  let maxL1 = (maxL0 + L0_BITS - 1) shr L0_SHIFT
  let maxL2 = (maxL1 + L0_BITS - 1) shr L0_SHIFT
  res.layer0.setLen(maxL0)
  res.layer1.setLen(maxL1)
  res.layer2.setLen(maxL2)
  for i in 0..<maxL0:
    let aVal = if i < a.layer0.len: a.layer0[i] else: BitBlock(0)
    let bVal = if i < b.layer0.len: b.layer0[i] else: BitBlock(0)
    res.layer0[i] = aVal xor bVal
  res.rebuildL1L2()
  res

template andNot*(a, b: HiBitSet): HiBitSet =
  ## AND NOT — bits in `a` that are not in `b`.
  var res = newHiBitSet()
  res.layer0.setLen(a.layer0.len)
  res.layer1.setLen(a.layer1.len)
  res.layer2.setLen(a.layer2.len)
  for i in 0..<a.layer0.len:
    let bVal = if i < b.layer0.len: b.layer0[i] else: BitBlock(0)
    res.layer0[i] = a.layer0[i] and not bVal
  res.rebuildL1L2()
  res

template andNoti*(a: var HiBitSet, b: HiBitSet) =
  ## In-place AND NOT.
  for i in 0..<a.layer0.len:
    let bVal = if i < b.layer0.len: b.layer0[i] else: BitBlock(0)
    a.layer0[i] = a.layer0[i] and not bVal
  a.rebuildL1L2()

template `not`*(a: HiBitSet): HiBitSet =
  ## Bitwise NOT — inverts all bits within the allocated range.
  var res = newHiBitSet()
  res.layer0.setLen(a.layer0.len)
  res.layer1.setLen(a.layer1.len)
  res.layer2.setLen(a.layer2.len)
  for i in 0..<a.layer0.len:
    res.layer0[i] = not a.layer0[i]
  res.rebuildL1L2()
  res

template `noti`*(a: var HiBitSet) =
  ## In-place NOT.
  for i in 0..<a.layer0.len:
    a.layer0[i] = not a.layer0[i]
  a.rebuildL1L2()

# ---------- iteration ----------

iterator items*(h: HiBitSet): int =
  ## Iterates over all set bit indices using trailing-zero-count skipping.
  ##
  ## Example:
  ##   for idx in bitset:
  ##     echo "bit ", idx, " is set"
  for l2Idx in 0..<h.layer2.len:
    var l2Block = h.layer2[l2Idx]
    while l2Block != 0:
      let l2Tz  = countTrailingZeroBits(l2Block)
      let l1Idx = (l2Idx shl L0_SHIFT) or l2Tz

      if l1Idx < h.layer1.len:
        var l1Block = h.layer1[l1Idx]
        while l1Block != 0:
          let l1Tz  = countTrailingZeroBits(l1Block)
          let l0Idx = (l1Idx shl L0_SHIFT) or l1Tz

          if l0Idx < h.layer0.len:
            var l0Block = h.layer0[l0Idx]
            while l0Block != 0:
              let l0Tz = countTrailingZeroBits(l0Block)
              yield (l0Idx shl L0_SHIFT) or l0Tz
              l0Block = l0Block and (l0Block - 1)

          l1Block = l1Block and (l1Block - 1)

      l2Block = l2Block and (l2Block - 1)

iterator blkIter*(h: HiBitSet): int =
  ## Iterates over layer0 block indices that contain at least one set bit.
  for l2Idx in 0..<h.layer2.len:
    var l2Block = h.layer2[l2Idx]
    while l2Block != 0:
      let l2Tz  = countTrailingZeroBits(l2Block)
      let l1Idx = (l2Idx shl L0_SHIFT) or l2Tz

      if l1Idx < h.layer1.len:
        var l1Block = h.layer1[l1Idx]
        while l1Block != 0:
          let l1Tz  = countTrailingZeroBits(l1Block)
          let l0Idx = (l1Idx shl L0_SHIFT) or l1Tz
          yield l0Idx
          l1Block = l1Block and (l1Block - 1)

      l2Block = l2Block and (l2Block - 1)

proc card*(h: HiBitSet): int =
  ## Returns the number of set bits (cardinality).
  for blk in h.layer0: result += countSetBits(blk)

proc `$`*(h: HiBitSet): string =
  result = "HiBitSet["
  var first = true
  for idx in h:
    if not first: result.add(", ")
    result.add($idx)
    first = false
  result.add("]")

# ============================================================================
# Sparse HiBitSet — 3-level
# ============================================================================

type
  SparseHiBitSet* = object
    ## Sparse 3-level hierarchical bitset.
    ## Uses the sparse-set technique at every level so only non-zero blocks
    ## consume memory.  O(1) insert / delete / lookup without hashing.
    ##
    ## Memory per set bit: ~3 * sizeof(uint64) amortised.

    # Layer 0 — actual bits
    layer0Dense:    seq[BitBlock]
    layer0Sparse:   seq[int]
    layer0DenseIdx: seq[int]
    layer0Count:    int

    # Layer 1 — one bit per layer0 block
    layer1Dense:    seq[BitBlock]
    layer1Sparse:   seq[int]
    layer1DenseIdx: seq[int]
    layer1Count:    int

    # Layer 2 — one bit per layer1 block  (new)
    layer2Dense:    seq[BitBlock]
    layer2Sparse:   seq[int]
    layer2DenseIdx: seq[int]
    layer2Count:    int

proc newSparseHiBitSet*(initialCapacity: int = 64): SparseHiBitSet =
  ## Creates a new sparse 3-level HiBitSet.
  ##
  ## Example:
  ##   var bs = newSparseHiBitSet()
  ##   bs.set(10_000_000)   # only 3 blocks allocated, not 10 M bits
  result.layer0Dense    = newSeq[BitBlock](initialCapacity)
  result.layer0Sparse   = newSeq[int](initialCapacity)
  result.layer0DenseIdx = newSeq[int](initialCapacity)
  result.layer0Count    = 0

  let l1Cap = max(8, initialCapacity shr L0_SHIFT)
  result.layer1Dense    = newSeq[BitBlock](l1Cap)
  result.layer1Sparse   = newSeq[int](l1Cap)
  result.layer1DenseIdx = newSeq[int](l1Cap)
  result.layer1Count    = 0

  let l2Cap = max(4, l1Cap shr L0_SHIFT)
  result.layer2Dense    = newSeq[BitBlock](l2Cap)
  result.layer2Sparse   = newSeq[int](l2Cap)
  result.layer2DenseIdx = newSeq[int](l2Cap)
  result.layer2Count    = 0

# ---------- sparse-set helpers (generic grow + lookup) ----------

proc ensureCapL0(h: var SparseHiBitSet, idx: int) {.inline.} =
  if idx >= h.layer0Sparse.len:
    let n = max(idx + 1, h.layer0Sparse.len * 2)
    h.layer0Sparse.setLen(n); h.layer0Dense.setLen(n); h.layer0DenseIdx.setLen(n)

proc ensureCapL1(h: var SparseHiBitSet, idx: int) {.inline.} =
  if idx >= h.layer1Sparse.len:
    let n = max(idx + 1, h.layer1Sparse.len * 2)
    h.layer1Sparse.setLen(n); h.layer1Dense.setLen(n); h.layer1DenseIdx.setLen(n)

proc ensureCapL2(h: var SparseHiBitSet, idx: int) {.inline.} =
  if idx >= h.layer2Sparse.len:
    let n = max(idx + 1, h.layer2Sparse.len * 2)
    h.layer2Sparse.setLen(n); h.layer2Dense.setLen(n); h.layer2DenseIdx.setLen(n)

# ---------- L0 sparse-set ----------

proc hasL0*(h: SparseHiBitSet, l0Idx: int): bool {.inline.} =
  if l0Idx >= h.layer0Sparse.len: return false
  let d = h.layer0Sparse[l0Idx]
  d < h.layer0Count and h.layer0DenseIdx[d] == l0Idx

proc getL0*(h: SparseHiBitSet, l0Idx: int): BitBlock {.inline.} =
  if not h.hasL0(l0Idx): return 0
  h.layer0Dense[h.layer0Sparse[l0Idx]]

proc setL0(h: var SparseHiBitSet, l0Idx: int, value: BitBlock) {.inline.} =
  h.ensureCapL0(l0Idx)
  if value == 0:
    if h.hasL0(l0Idx):
      let d    = h.layer0Sparse[l0Idx]
      let last = h.layer0Count - 1
      if d != last:
        h.layer0Dense[d]    = h.layer0Dense[last]
        h.layer0DenseIdx[d] = h.layer0DenseIdx[last]
        h.layer0Sparse[h.layer0DenseIdx[last]] = d
      h.layer0Count -= 1
  else:
    if h.hasL0(l0Idx):
      h.layer0Dense[h.layer0Sparse[l0Idx]] = value
    else:
      h.layer0Sparse[l0Idx]          = h.layer0Count
      h.layer0Dense[h.layer0Count]   = value
      h.layer0DenseIdx[h.layer0Count] = l0Idx
      h.layer0Count += 1

# ---------- L1 sparse-set ----------

proc hasL1*(h: SparseHiBitSet, l1Idx: int): bool {.inline.} =
  if l1Idx >= h.layer1Sparse.len: return false
  let d = h.layer1Sparse[l1Idx]
  d < h.layer1Count and h.layer1DenseIdx[d] == l1Idx

proc getL1*(h: SparseHiBitSet, l1Idx: int): BitBlock {.inline.} =
  if not h.hasL1(l1Idx): return 0
  h.layer1Dense[h.layer1Sparse[l1Idx]]

proc setL1(h: var SparseHiBitSet, l1Idx: int, value: BitBlock) {.inline.} =
  h.ensureCapL1(l1Idx)
  if value == 0:
    if h.hasL1(l1Idx):
      let d    = h.layer1Sparse[l1Idx]
      let last = h.layer1Count - 1
      if d != last:
        h.layer1Dense[d]    = h.layer1Dense[last]
        h.layer1DenseIdx[d] = h.layer1DenseIdx[last]
        h.layer1Sparse[h.layer1DenseIdx[last]] = d
      h.layer1Count -= 1
  else:
    if h.hasL1(l1Idx):
      h.layer1Dense[h.layer1Sparse[l1Idx]] = value
    else:
      h.layer1Sparse[l1Idx]          = h.layer1Count
      h.layer1Dense[h.layer1Count]   = value
      h.layer1DenseIdx[h.layer1Count] = l1Idx
      h.layer1Count += 1

# ---------- L2 sparse-set ----------

proc hasL2*(h: SparseHiBitSet, l2Idx: int): bool {.inline.} =
  if l2Idx >= h.layer2Sparse.len: return false
  let d = h.layer2Sparse[l2Idx]
  d < h.layer2Count and h.layer2DenseIdx[d] == l2Idx

proc getL2*(h: SparseHiBitSet, l2Idx: int): BitBlock {.inline.} =
  if not h.hasL2(l2Idx): return 0
  h.layer2Dense[h.layer2Sparse[l2Idx]]

proc setL2(h: var SparseHiBitSet, l2Idx: int, value: BitBlock) {.inline.} =
  h.ensureCapL2(l2Idx)
  if value == 0:
    if h.hasL2(l2Idx):
      let d    = h.layer2Sparse[l2Idx]
      let last = h.layer2Count - 1
      if d != last:
        h.layer2Dense[d]    = h.layer2Dense[last]
        h.layer2DenseIdx[d] = h.layer2DenseIdx[last]
        h.layer2Sparse[h.layer2DenseIdx[last]] = d
      h.layer2Count -= 1
  else:
    if h.hasL2(l2Idx):
      h.layer2Dense[h.layer2Sparse[l2Idx]] = value
    else:
      h.layer2Sparse[l2Idx]          = h.layer2Count
      h.layer2Dense[h.layer2Count]   = value
      h.layer2DenseIdx[h.layer2Count] = l2Idx
      h.layer2Count += 1

# ---------- public block setter ----------

proc setL0Block*(h: var SparseHiBitSet, l0Idx: int, value: BitBlock) {.inline.} =
  ## Sets an entire layer0 block and propagates changes to layer1 and layer2.
  h.setL0(l0Idx, value)

  let l1Idx = l0Idx shr L0_SHIFT
  let l1Bit = l0Idx and L0_MASK
  let l1Old = h.getL1(l1Idx)
  let l1New = if value != 0: l1Old or  (BitBlock(1) shl l1Bit)
              else:           l1Old and not (BitBlock(1) shl l1Bit)
  h.setL1(l1Idx, l1New)

  let l2Idx = l1Idx shr L0_SHIFT
  let l2Bit = l1Idx and L0_MASK
  let l2Old = h.getL2(l2Idx)
  let l2New = if l1New != 0: l2Old or  (BitBlock(1) shl l2Bit)
              else:           l2Old and not (BitBlock(1) shl l2Bit)
  h.setL2(l2Idx, l2New)

# ---------- bit set / unset ----------

proc set*(h: var SparseHiBitSet, idx: int) {.inline.} =
  ## Sets the bit at `idx` to 1. Allocates a block only if the block is new.
  ## Time complexity: O(1)
  let l0Idx  = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  let newVal = h.getL0(l0Idx) or (BitBlock(1) shl bitPos)
  h.setL0(l0Idx, newVal)

  let l1Idx = l0Idx shr L0_SHIFT
  let l1Bit = l0Idx and L0_MASK
  h.setL1(l1Idx, h.getL1(l1Idx) or (BitBlock(1) shl l1Bit))

  let l2Idx = l1Idx shr L0_SHIFT
  let l2Bit = l1Idx and L0_MASK
  h.setL2(l2Idx, h.getL2(l2Idx) or (BitBlock(1) shl l2Bit))

proc setBatch*(h: var SparseHiBitSet, idxs: openArray[uint|int]) =
  ## Sets multiple bits. Optimised for sequential / grouped indices.
  if idxs.len == 0: return
  var lastL0Idx = -1
  for idx in idxs:
    let i      = idx.int
    let l0Idx  = i shr L0_SHIFT
    let bitPos = i and L0_MASK
    h.setL0(l0Idx, h.getL0(l0Idx) or (BitBlock(1) shl bitPos))
    if l0Idx != lastL0Idx:
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      h.setL1(l1Idx, h.getL1(l1Idx) or (BitBlock(1) shl l1Bit))
      let l2Idx = l1Idx shr L0_SHIFT
      let l2Bit = l1Idx and L0_MASK
      h.setL2(l2Idx, h.getL2(l2Idx) or (BitBlock(1) shl l2Bit))
      lastL0Idx = l0Idx

proc unset*(h: var SparseHiBitSet, idx: int) {.inline.} =
  ## Sets the bit at `idx` to 0. Deallocates blocks that become empty.
  ## Time complexity: O(1)
  let l0Idx  = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  if not h.hasL0(l0Idx): return

  let newVal = h.getL0(l0Idx) and not (BitBlock(1) shl bitPos)
  h.setL0(l0Idx, newVal)

  let l1Idx = l0Idx shr L0_SHIFT
  let l1Bit = l0Idx and L0_MASK
  if newVal == 0:
    let l1New = h.getL1(l1Idx) and not (BitBlock(1) shl l1Bit)
    h.setL1(l1Idx, l1New)

    let l2Idx = l1Idx shr L0_SHIFT
    let l2Bit = l1Idx and L0_MASK
    if l1New == 0:
      h.setL2(l2Idx, h.getL2(l2Idx) and not (BitBlock(1) shl l2Bit))

proc unsetBatch*(h: var SparseHiBitSet, idxs: openArray[uint|int]) =
  for idx in idxs: h.unset(idx.int)

proc get*(h: SparseHiBitSet, idx: int): bool {.inline.} =
  ## Returns true if the bit at `idx` is set. Time complexity: O(1)
  let l0Idx  = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  if not h.hasL0(l0Idx): return false
  (h.getL0(l0Idx) and (BitBlock(1) shl bitPos)) != 0

proc `[]`*(h: SparseHiBitSet, idx: int): bool {.inline.} = h.get(idx)

proc `[]=`*(h: var SparseHiBitSet, idx: int, value: bool) {.inline.} =
  if value: h.set(idx) else: h.unset(idx)

proc clear*(h: var SparseHiBitSet) {.inline.} =
  ## Resets all bits to 0 in O(1) by zeroing the counters.
  ## Allocated memory is retained for reuse.
  h.layer0Count = 0
  h.layer1Count = 0
  h.layer2Count = 0

proc isEmpty*(h: SparseHiBitSet): bool {.inline.} =
  h.layer0Count == 0

# ---------- bitwise operators ----------

proc `and`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## AND — only processes blocks present in both sets. Very fast for sparse data.
  result = newSparseHiBitSet()
  for i in 0..<a.layer0Count:
    let l0Idx  = a.layer0DenseIdx[i]
    if b.hasL0(l0Idx):
      let v = a.layer0Dense[i] and b.getL0(l0Idx)
      if v != 0:
        result.setL0(l0Idx, v)
        let l1Idx = l0Idx shr L0_SHIFT
        result.setL1(l1Idx, result.getL1(l1Idx) or (BitBlock(1) shl (l0Idx and L0_MASK)))
        let l2Idx = l1Idx shr L0_SHIFT
        result.setL2(l2Idx, result.getL2(l2Idx) or (BitBlock(1) shl (l1Idx and L0_MASK)))

proc `or`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## OR — processes all blocks from both sets.
  result = newSparseHiBitSet()

  template addBlock(l0Idx: int, blk: BitBlock) =
    result.setL0(l0Idx, blk)
    let l1Idx = l0Idx shr L0_SHIFT
    result.setL1(l1Idx, result.getL1(l1Idx) or (BitBlock(1) shl (l0Idx and L0_MASK)))
    let l2Idx = l1Idx shr L0_SHIFT
    result.setL2(l2Idx, result.getL2(l2Idx) or (BitBlock(1) shl (l1Idx and L0_MASK)))

  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    addBlock(l0Idx, a.layer0Dense[i] or b.getL0(l0Idx))

  for i in 0..<b.layer0Count:
    let l0Idx = b.layer0DenseIdx[i]
    if not a.hasL0(l0Idx):
      addBlock(l0Idx, b.layer0Dense[i])

proc `xor`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## XOR — bits set in exactly one of the two sets.
  result = newSparseHiBitSet()

  template addBlock(l0Idx: int, blk: BitBlock) =
    if blk != 0:
      result.setL0(l0Idx, blk)
      let l1Idx = l0Idx shr L0_SHIFT
      result.setL1(l1Idx, result.getL1(l1Idx) or (BitBlock(1) shl (l0Idx and L0_MASK)))
      let l2Idx = l1Idx shr L0_SHIFT
      result.setL2(l2Idx, result.getL2(l2Idx) or (BitBlock(1) shl (l1Idx and L0_MASK)))

  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    addBlock(l0Idx, a.layer0Dense[i] xor b.getL0(l0Idx))

  for i in 0..<b.layer0Count:
    let l0Idx = b.layer0DenseIdx[i]
    if not a.hasL0(l0Idx):
      addBlock(l0Idx, b.layer0Dense[i])

proc `not`*(a: SparseHiBitSet): SparseHiBitSet =
  ## NOT — inverts all bits up to the highest allocated block.
  ## Warning: the result may be dense even when `a` is sparse.
  result = newSparseHiBitSet()
  if a.layer0Count == 0: return

  var maxL0Idx = 0
  for i in 0..<a.layer0Count:
    if a.layer0DenseIdx[i] > maxL0Idx: maxL0Idx = a.layer0DenseIdx[i]

  for l0Idx in 0..maxL0Idx:
    let v = not a.getL0(l0Idx)
    if v != 0:
      result.setL0(l0Idx, v)
      let l1Idx = l0Idx shr L0_SHIFT
      result.setL1(l1Idx, result.getL1(l1Idx) or (BitBlock(1) shl (l0Idx and L0_MASK)))
      let l2Idx = l1Idx shr L0_SHIFT
      result.setL2(l2Idx, result.getL2(l2Idx) or (BitBlock(1) shl (l1Idx and L0_MASK)))

proc andNot*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## AND NOT — bits in `a` that are not in `b`.
  result = newSparseHiBitSet()
  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    let v     = a.layer0Dense[i] and not b.getL0(l0Idx)
    if v != 0:
      result.setL0(l0Idx, v)
      let l1Idx = l0Idx shr L0_SHIFT
      result.setL1(l1Idx, result.getL1(l1Idx) or (BitBlock(1) shl (l0Idx and L0_MASK)))
      let l2Idx = l1Idx shr L0_SHIFT
      result.setL2(l2Idx, result.getL2(l2Idx) or (BitBlock(1) shl (l1Idx and L0_MASK)))

# ---------- iteration ----------

iterator items*(h: SparseHiBitSet): int =
  ## Iterates over all set bit indices. Visits only allocated blocks.
  ##
  ## Example:
  ##   var bs = newSparseHiBitSet()
  ##   bs.set(10_000_000)
  ##   for idx in bs:   # visits only idx=10_000_000
  ##     echo idx
  for i2 in 0..<h.layer2Count:
    let l2Idx   = h.layer2DenseIdx[i2]
    var l2Block = h.layer2Dense[i2]

    while l2Block != 0:
      let l2Tz  = countTrailingZeroBits(l2Block)
      let l1Idx = (l2Idx shl L0_SHIFT) or l2Tz

      var l1Block = h.getL1(l1Idx)
      while l1Block != 0:
        let l1Tz  = countTrailingZeroBits(l1Block)
        let l0Idx = (l1Idx shl L0_SHIFT) or l1Tz

        var l0Block = h.getL0(l0Idx)
        while l0Block != 0:
          let l0Tz = countTrailingZeroBits(l0Block)
          yield (l0Idx shl L0_SHIFT) or l0Tz
          l0Block = l0Block and (l0Block - 1)

        l1Block = l1Block and (l1Block - 1)

      l2Block = l2Block and (l2Block - 1)

iterator blkIter*(h: SparseHiBitSet): int =
  ## Iterates over layer0 block indices that contain set bits.
  for i2 in 0..<h.layer2Count:
    let l2Idx   = h.layer2DenseIdx[i2]
    var l2Block = h.layer2Dense[i2]

    while l2Block != 0:
      let l2Tz  = countTrailingZeroBits(l2Block)
      let l1Idx = (l2Idx shl L0_SHIFT) or l2Tz

      var l1Block = h.getL1(l1Idx)
      while l1Block != 0:
        let l1Tz  = countTrailingZeroBits(l1Block)
        yield (l1Idx shl L0_SHIFT) or l1Tz
        l1Block = l1Block and (l1Block - 1)

      l2Block = l2Block and (l2Block - 1)

proc card*(h: SparseHiBitSet): int =
  ## Returns the number of set bits.
  for i in 0..<h.layer0Count:
    result += countSetBits(h.layer0Dense[i])

proc memoryUsage*(h: SparseHiBitSet): int =
  ## Approximate memory usage in bytes.
  result  = h.layer0Count * sizeof(BitBlock) * 3
  result += h.layer1Count * sizeof(BitBlock) * 3
  result += h.layer2Count * sizeof(BitBlock) * 3

proc `$`*(h: SparseHiBitSet): string =
  result = "SparseHiBitSet["
  var first = true
  for idx in h:
    if not first: result.add(", ")
    result.add($idx)
    first = false
  result.add("]")

type HiBitSetType = HiBitSet