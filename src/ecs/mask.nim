####################################################################################################################################################
################################################################ ARCHETYPES MASK ###################################################################
####################################################################################################################################################
##
## Operations on ``ArchetypeMask`` — a fixed-width bitmask used to represent
## component sets in the archetype graph.
##
## An ``ArchetypeMask`` is an ``array[MAX_COMPONENT_LAYER, uint]`` where each
## element holds ``sizeof(uint)*8`` component bits.  On a 64-bit platform with
## ``MAX_COMPONENT_LAYER = 4`` this gives 256 addressable component slots.
##
## Usage example
## =============
##
## .. code-block:: nim
##   import cruise/ecs/mask
##
##   var m: ArchetypeMask
##   m.withComponentInPlace(0)    # position
##   m.withComponentInPlace(1)    # velocity
##
##   assert m.hasComponent(0)
##   assert m.componentCount == 2
##
##   let ids = m.getComponents()
##   echo ids   # @[0, 1]
##
##   # Pattern matching against an archetype
##   var incl = m
##   var excl: ArchetypeMask
##   excl.withComponentInPlace(2)  # exclude component 2
##   assert m.matches(incl, excl)  # m has 0,1, not 2 → match

import std/[bitops, hashes]
import ./types
export types

template `and`*(a, b: ArchetypeMask | ptr ArchetypeMask): untyped =
  var res: ArchetypeMask

  for i in 0..<MAX_COMPONENT_LAYER:
    res[i] = (a[i] and b[i])

  res

template `or`*(a, b: ArchetypeMask | ptr ArchetypeMask): untyped =
  var res: ArchetypeMask

  for i in 0..<MAX_COMPONENT_LAYER:
    res[i] = (a[i] or b[i])

  res

template `xor`*(a, b: ArchetypeMask | ptr ArchetypeMask): untyped =
  var res: ArchetypeMask

  for i in 0..<MAX_COMPONENT_LAYER:
    res[i] = (a[i] xor b[i])

  res

template `not`*(a: ArchetypeMask | ptr ArchetypeMask): untyped =
  var res: ArchetypeMask

  for i in 0..<MAX_COMPONENT_LAYER:
    res[i] = not a[i]

  res

template setBit*(a: var ArchetypeMask, i, j: int) =
  a[i] = a[i] or 1.uint shl j

template setBit*(a: var ArchetypeMask, i: int) =
  let s = sizeof(uint)*8
  a.setBit(i div s, i mod s)

template setBit*(a: var ArchetypeMask, ids: openArray) =
  let s = sizeof(uint)*8

  for i in ids:
    a.setBit(i div s, i mod s)

template unSetBit*(a: var ArchetypeMask, i, j: int) =
  a[i] = a[i] and not (1.uint shl j)

template unSetBit*(a: var ArchetypeMask, ids: openArray) =
  let s = sizeof(uint)*8

  for i in ids:
    a.unSetBit(i div s, i mod s)

template unSetBit*(a: var ArchetypeMask, i: int) =
  let s = sizeof(uint)*8
  a.unSetBit(i div s, i mod s)

template getBit*(a: var ArchetypeMask, i, j: int): uint =
  (a[i] shr j) and 1

template getBit*(a: var ArchetypeMask, i: int): uint =
  let s = sizeof(uint)*8
  a.getBit(i div s, i mod s)

{.push inline.}

proc maskOf*(ids: varargs[int]): ArchetypeMask =
  ## Creates an ``ArchetypeMask`` with the given component IDs set.
  ##
  ## Example
  ## -------
  ## .. code-block:: nim
  ##   let m = maskOf(0, 3, 64)
  ##   assert m.hasComponent(0)
  ##   assert m.hasComponent(3)
  ##   assert m.hasComponent(64)
  var m: ArchetypeMask
  for id in ids:
    let layer = id shr 6
    let bit   = id and 63
    m[layer] = m[layer] or (1.uint shl bit)
  return m

proc isEmpty*(mask: ArchetypeMask): bool =
  ## Returns ``true`` if no component bits are set.
  for layer in mask:
    if layer != 0:
      return false
  return true

proc `==`*(a, b: ArchetypeMask | ptr ArchetypeMask): bool =
  for i in 0..<MAX_COMPONENT_LAYER:
    if a[i] != b[i]:
      return false
  return true

proc withComponentInPlace*(mask: var ArchetypeMask, comp: ComponentId) =
  ## Sets the bit for ``comp`` in place.
  let layer = comp shr 6  # div 64
  let bit = comp and 63   # mod 64
  mask[layer] = mask[layer] or (1'u shl bit)

proc withComponent*(mask: ArchetypeMask | ptr ArchetypeMask, comp: ComponentId): ArchetypeMask =
  ## Returns a new mask with ``comp`` added.
  result = mask
  let layer = comp shr 6  # div 64
  let bit = comp and 63   # mod 64
  result[layer] = result[layer] or (1'u shl bit)

proc withoutComponentInPlace*(mask: var ArchetypeMask, comp: ComponentId) =
  ## Clears the bit for ``comp`` in place.
  let layer = comp shr 6  # div 64
  let bit = comp and 63   # mod 64
  mask[layer] = mask[layer] and not (1'u shl bit)

proc withoutComponent*(mask: ArchetypeMask | ptr ArchetypeMask, comp: ComponentId): ArchetypeMask =
  ## Returns a new mask with ``comp`` removed.
  result = mask
  let layer = comp shr 6
  let bit = comp and 63
  result[layer] = result[layer] and not (1'u shl bit)

proc hasComponent*(mask: ArchetypeMask | ptr ArchetypeMask, comp: ComponentId | int): bool =
  ## Returns ``true`` if ``comp`` is set in the mask.
  let layer = comp shr 6
  let bit = comp and 63
  return (mask[layer] and (1'u shl bit)) != 0

proc componentCount*(mask: ArchetypeMask | ptr ArchetypeMask): int =
  ## Returns the number of set component bits (popcount).
  result = 0
  for layer in mask:
    result += popcount(layer)

{.pop.}

proc getComponents*(mask: ArchetypeMask | ptr ArchetypeMask): seq[int] =
  ## Returns an ordered sequence of all set component IDs.
  ##
  ## Example
  ## -------
  ## .. code-block:: nim
  ##   let m = maskOf(2, 5, 128)
  ##   echo m.getComponents()   # @[2, 5, 128]
  let count = mask.componentCount()
  result = newSeqOfCap[int](count)

  for layer in 0..<MAX_COMPONENT_LAYER:
    var bits = mask[layer]
    if bits == 0: continue

    let baseId = layer shl 6  # * 64

    while bits != 0:
      let tz = countTrailingZeroBits(bits)
      result.add(baseId + tz)
      bits = bits and (bits - 1)

proc matches*(arch, incl, excl: ArchetypeMask | ptr ArchetypeMask): bool {.inline.} =
  ## Aggressive, single-pass archetype matching.
  ## Returns ``true`` if ``arch`` contains all bits in ``incl`` **and** none
  ## of the bits in ``excl``.
  ##
  ## .. code-block:: nim
  ##   let arch = maskOf(0, 1, 2)
  ##   let incl = maskOf(0, 1)
  ##   var excl: ArchetypeMask
  ##   assert arch.matches(incl, excl)
  for i in 0..<MAX_COMPONENT_LAYER:
    let a = arch[i]
    let in_m = incl[i]
    let ex_m = excl[i]
    if (a and in_m) != in_m: return false
    if (a and ex_m) != 0: return false
  return true
