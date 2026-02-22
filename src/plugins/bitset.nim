#####################################################################################################################################
######################################################### BITSETS ###################################################################
#####################################################################################################################################

import std/bitops

const WordBits = sizeof(uint)*8
type Word = uint

func wordIdx(bit: int): int  {.inline.} = bit shr 6
func bitMask(bit: int): Word {.inline.} = 1u64 shl (bit and 63)

type
  BitSet* = object
    ## Dynamic bitset backed by a sequence of uint64 words.
    ## Grows automatically on demand; never shrinks the backing store.
    data: seq[Word]
    cap:  int   # capacity in bits (always a multiple of 64)

func newBitSet*(capacity = 64): BitSet =
  ## Creates a BitSet with an initial backing store for `capacity` bits.
  let words = max(1, (capacity + 63) div 64)
  BitSet(data: newSeq[Word](words), cap: words * WordBits)

func initBitSet*(bits: openArray[int]): BitSet =
  ## Creates a BitSet pre-populated with the given bit indices.
  var maxBit = 0
  for b in bits:
    assert b >= 0, "bit index must be non-negative"
    if b > maxBit: maxBit = b
  result = newBitSet(maxBit + 1)
  for b in bits:
    result.data[wordIdx(b)] = result.data[wordIdx(b)] or bitMask(b)

func ensureBit(s: var BitSet; bit: int) {.inline.} =
  if bit >= s.cap:
    let needed = (bit div WordBits) + 1
    s.data.setLen(needed)
    s.cap = needed * WordBits

func incl*(s: var BitSet; bit: int) {.inline.} =
  ## Sets bit `bit` to 1.
  assert bit >= 0, "bit index must be non-negative"
  s.ensureBit(bit)
  s.data[wordIdx(bit)] = s.data[wordIdx(bit)] or bitMask(bit)

func excl*(s: var BitSet; bit: int) {.inline.} =
  ## Clears bit `bit` (sets it to 0). No-op if out of range.
  if bit >= 0 and bit < s.cap:
    s.data[wordIdx(bit)] = s.data[wordIdx(bit)] and not bitMask(bit)

func toggle*(s: var BitSet; bit: int) {.inline.} =
  ## Flips bit `bit`.
  assert bit >= 0, "bit index must be non-negative"
  s.ensureBit(bit)
  s.data[wordIdx(bit)] = s.data[wordIdx(bit)] xor bitMask(bit)

func clear*(s: var BitSet) {.inline.} =
  ## Sets all bits to 0.
  for w in s.data.mitems: w = 0u64

func contains*(s: BitSet; bit: int): bool {.inline.} =
  ## Returns true if `bit` is set.
  bit >= 0 and bit < s.cap and (s.data[wordIdx(bit)] and bitMask(bit)) != 0

func `in`*(bit: int; s: BitSet): bool {.inline.} = s.contains(bit)
func `notin`*(bit: int; s: BitSet): bool {.inline.} = not s.contains(bit)

func isEmpty*(s: BitSet): bool {.inline.} =
  ## Returns true if no bits are set.
  for w in s.data:
    if w != 0u64: return false
  true

func popcount*(s: BitSet): int {.inline.} =
  ## Returns the number of set bits (Hamming weight).
  for w in s.data: result += countSetBits(w)

func len*(s: BitSet): int = s.popcount

func capacity*(s: BitSet): int {.inline.} =
  ## Returns current backing-store capacity in bits.
  s.cap

func min*(s: BitSet): int =
  ## Returns the smallest set bit index, or -1 if the set is empty.
  for wi in 0 ..< s.data.len:
    let w = s.data[wi]
    if w != 0u64:
      return wi * WordBits + countTrailingZeroBits(w)
  -1

func max*(s: BitSet): int =
  ## Returns the largest set bit index, or -1 if the set is empty.
  for wi in countdown(s.data.len - 1, 0):
    let w = s.data[wi]
    if w != 0u64:
      return wi * WordBits + (63 - countLeadingZeroBits(w))
  -1

func nextSetBit*(s: BitSet; start: int): int =
  ## Returns the smallest set bit index >= `start`, or -1 if none.
  if start >= s.cap: return -1
  let clamped = max(start, 0)
  var wi = wordIdx(clamped)
  var w = s.data[wi] shr (clamped and 63)
  while true:
    if w != 0u64:
      return wi * WordBits + countTrailingZeroBits(w)
    inc wi
    if wi >= s.data.len: return -1
    w = s.data[wi]

func prevSetBit*(s: BitSet; start: int): int =
  ## Returns the largest set bit index <= `start`, or -1 if none.
  let clamped = min(start, s.cap - 1)
  if clamped < 0: return -1
  var wi = wordIdx(clamped)
  let offset = clamped and 63
  var w = s.data[wi] and ((2u64 shl offset) - 1u64)
  while true:
    if w != 0u64:
      return wi * WordBits + (63 - countLeadingZeroBits(w))
    dec wi
    if wi < 0: return -1
    w = s.data[wi]

iterator items*(s: BitSet): int =
  ## Yields each set bit index in ascending order.
  for wi in 0 ..< s.data.len:
    var w = s.data[wi]
    while w != 0u64:
      yield wi * WordBits + countTrailingZeroBits(w)
      w = w and (w - 1u64)   # clear the lowest set bit

func wordsLen(s: BitSet): int {.inline.} = s.data.len

func `==`*(a, b: BitSet): bool =
  ## True if both sets contain exactly the same bits.
  let lo = min(a.wordsLen, b.wordsLen)
  for i in 0 ..< lo:
    if a.data[i] != b.data[i]: return false
  let longer = if a.wordsLen > b.wordsLen: a else: b
  for i in lo ..< longer.wordsLen:
    if longer.data[i] != 0u64: return false
  true

func isSubsetOf*(a, b: BitSet): bool =
  ## True if every bit in `a` is also in `b`.
  let lo = min(a.wordsLen, b.wordsLen)
  for i in 0 ..< lo:
    if (a.data[i] and not b.data[i]) != 0u64: return false
  for i in lo ..< a.wordsLen:
    if a.data[i] != 0u64: return false
  true

func isSupersetOf*(a, b: BitSet): bool {.inline.} =
  ## True if every bit in `b` is also in `a`.
  isSubsetOf(b, a)

func disjoint*(a, b: BitSet): bool =
  ## True if `a` and `b` share no set bits.
  let lo = min(a.wordsLen, b.wordsLen)
  for i in 0 ..< lo:
    if (a.data[i] and b.data[i]) != 0u64: return false
  true

func `+`*(a, b: BitSet): BitSet =
  ## Union: bits set in `a` OR `b`.
  let lo = min(a.wordsLen, b.wordsLen)
  result = if a.wordsLen >= b.wordsLen: a else: b   # copy longer as base
  for i in 0 ..< lo:
    result.data[i] = a.data[i] or b.data[i]

func `*`*(a, b: BitSet): BitSet =
  ## Intersection: bits set in `a` AND `b`.
  let lo = min(a.wordsLen, b.wordsLen)
  result = newBitSet(lo * WordBits)
  for i in 0 ..< lo:
    result.data[i] = a.data[i] and b.data[i]

func `-`*(a, b: BitSet): BitSet =
  ## Difference: bits in `a` that are NOT in `b`.
  result = a
  let lo = min(a.wordsLen, b.wordsLen)
  for i in 0 ..< lo:
    result.data[i] = a.data[i] and not b.data[i]

func symmetricDiff*(a, b: BitSet): BitSet =
  ## Symmetric difference: bits set in exactly one of `a` or `b`.
  let lo = min(a.wordsLen, b.wordsLen)
  result = if a.wordsLen >= b.wordsLen: a else: b
  for i in 0 ..< lo:
    result.data[i] = a.data[i] xor b.data[i]

func complement*(s: BitSet): BitSet =
  ## Bitwise complement (flips every bit up to current capacity).
  result = s
  for w in result.data.mitems: w = not w

func `+=`*(a: var BitSet; b: BitSet) =
  ## In-place union.
  if b.wordsLen > a.wordsLen:
    a.data.setLen(b.wordsLen)
    a.cap = b.cap
  for i in 0 ..< b.wordsLen:
    a.data[i] = a.data[i] or b.data[i]

func `*=`*(a: var BitSet; b: BitSet) =
  ## In-place intersection.
  let lo = min(a.wordsLen, b.wordsLen)
  for i in 0 ..< lo:   a.data[i] = a.data[i] and b.data[i]
  for i in lo ..< a.wordsLen: a.data[i] = 0u64

func `-=`*(a: var BitSet; b: BitSet) =
  ## In-place difference.
  let lo = min(a.wordsLen, b.wordsLen)
  for i in 0 ..< lo:
    a.data[i] = a.data[i] and not b.data[i]

func `$`*(s: BitSet): string =
  ## Returns e.g. "{0, 5, 42}".
  result = "{"
  var first = true
  for bit in s:
    if not first: result.add(", ")
    result.add($bit)
    first = false
  result.add("}")
