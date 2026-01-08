####################################################################################################################################################
################################################################ ARCHETYPES MASK ###################################################################
####################################################################################################################################################

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

proc maskOf(ids: varargs[int]): ArchetypeMask =
  var m: ArchetypeMask
  let S = sizeof(uint)*8
  for id in ids:
    let layer = id div S
    let bit   = id mod S
    m[layer] = m[layer] or (1.uint shl bit)
  return m