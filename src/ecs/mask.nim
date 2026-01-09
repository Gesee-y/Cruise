####################################################################################################################################################
################################################################ ARCHETYPES MASK ###################################################################
####################################################################################################################################################

const 
  MAX_COMPONENTS = MAX_COMPONENT_LAYER * sizeof(uint) * 8

type
  ComponentId* = range[0..MAX_COMPONENTS-1]

template `and`(a,b:ArchetypeMask):untyped =
  var res:ArchetypeMask

  for i in 0..<MAX_COMPONENT_LAYER:
    res[i] = (a[i] and b[i])

  res

template `or`(a,b:ArchetypeMask):untyped =
  var res:ArchetypeMask

  for i in 0..<MAX_COMPONENT_LAYER:
    res[i] = (a[i] or b[i])

  res

template `xor`(a,b:ArchetypeMask):untyped =
  var res:ArchetypeMask

  for i in 0..<MAX_COMPONENT_LAYER:
    res[i] = (a[i] xor b[i])

  res
  
template `not`(a: ArchetypeMask):untyped =
  var res:ArchetypeMask

  for i in 0..<MAX_COMPONENT_LAYER:
    res[i] = not a[i]

  res

template setBit(a:var ArchetypeMask, i,j:int) =
  a[i] = a[i] or 1.uint shl j

template setBit(a:var ArchetypeMask, i:int) =
  let s = sizeof(uint)*8
  a.setBit(i div s, i mod s)

template unSetBit(a:var ArchetypeMask, i,j:int) =
  a[i] = a[i] and not (1.uint shl j)

template unSetBit(a:var ArchetypeMask, i:int) =
  let s = sizeof(uint)*8
  a.unSetBit(i div s, i mod s)

template getBit(a:var ArchetypeMask, i,j:int):uint =
  (a[i] shr j) and 1

template getBit(a:var ArchetypeMask, i:int):uint =
  let s = sizeof(uint)*8
  a.getBit(i div s, i mod s)

{.push inline.}

proc maskOf(ids: varargs[int]): ArchetypeMask =
  var m: ArchetypeMask
  let S = sizeof(uint)*8
  for id in ids:
    let layer = id shr 6
    let bit   = id and 63
    m[layer] = m[layer] or (1.uint shl bit)
  return m

proc isEmpty*(mask: ArchetypeMask): bool =
  for layer in mask:
    if layer != 0:
      return false
  return true

proc `==`*(a, b: ArchetypeMask): bool =
  for i in 0..<MAX_COMPONENT_LAYER:
    if a[i] != b[i]:
      return false
  return true

proc withComponent*(mask: ArchetypeMask, comp: ComponentId): ArchetypeMask =
  result = mask
  let layer = comp shr 6  # div 64
  let bit = comp and 63   # mod 64
  result[layer] = result[layer] or (1'u shl bit)

proc withoutComponent*(mask: ArchetypeMask, comp: ComponentId): ArchetypeMask =
  result = mask
  let layer = comp shr 6
  let bit = comp and 63
  result[layer] = result[layer] and not (1'u shl bit)

proc hasComponent*(mask: ArchetypeMask, comp: ComponentId): bool =
  let layer = comp shr 6
  let bit = comp and 63
  return (mask[layer] and (1'u shl bit)) != 0

proc componentCount*(mask: ArchetypeMask): int =
  result = 0
  for layer in mask:
    result += popcount(layer)

{.pop.}

proc hash*(mask: ArchetypeMask): Hash =
  result = !$(hash(mask[0]) !& hash(mask[1]) !& hash(mask[2]) !& hash(mask[3]))

proc getComponents*(mask: ArchetypeMask): seq[ComponentId] =
  let count = mask.componentCount()
  result = newSeqOfCap[ComponentId](count)
  
  for layer in 0..<MAX_COMPONENT_LAYER:
    var bits = mask[layer]
    if bits == 0: continue
    
    let baseId = layer shl 6  # * 64
    
    while bits != 0:
      let tz = countTrailingZeroBits(bits)
      result.add(ComponentId(baseId + tz))
      bits = bits and (bits - 1)
