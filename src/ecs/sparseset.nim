########################################################################################################################################################
##################################################################### SPARSE SETS ######################################################################
########################################################################################################################################################

type
  CSparseSet[T] = object
    sparse: seq[int]
    dense: seq[T]
    actives: set[int16]

########################################################################################################################################################
###################################################################### FUNCTIONS #######################################################################
########################################################################################################################################################

template contains(s: CSparseSet, i: untyped): bool = i in s.actives

template `[]`(s: CSparseSet, i: untyped): untyped =
  s.dense[s.sparse[i]]

template `[]=`(s: CSparseSet, i, v: untyped) =
  if i >= s.sparse.len:
    s.sparse.setLen(i+1)

  if s.sparse[i] == 0:
    s.sparse[i] = s.dense.len+1
    s.dense.setLen(s.dense.len+1)
    s.actives.incl(i.int16)

  s.dense[s.sparse[i]-1] = v

template len(s: CSparseSet): untyped = s.actives.len

iterator items[T](s: CSparseSet[T]): T =
  for d in s.dense:
    yield d

iterator pairs[T](s: CSparseSet[T]): (int, T) =
  for i in s.actives:
    yield (i.int, s.dense[s.sparse[i]-1])
  
template clear(s: CSparseSet) =
  var st: set[int16]
  s.dense.setLen(0)
  s.sparse.setLen(0)
  s.actives = st
