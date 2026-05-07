##########################################################################################################################################################
################################################################ MEMORY MANAGEMENT #######################################################################
##########################################################################################################################################################


proc toSeq*[B, T](g: GPUSeq[B, T]): seq[T] =
  result = newSeq[T](g.length)

proc toArray*[N,B,T](g: GPUArray[N,B,T]): array[N,T] =
  let res: array[N,T]
  res

proc copyTo*[B,T](g: GPUSeq[B,T], src: openArray[T], start, stop: int) =
  discard

proc add*[B, T](g: var GPUSeq[B, T], item: T) =
  let oldLen = g.length
  g.length += 1
  g.ensureLen()
  
  copyTo(g, @[item], oldLen, oldLen+1)

proc append*[B, T](g: var GPUSeq[B, T], items: seq[T]) =
  let n = items.len
  let oldLen = g.length
  g.length += n
  g.ensureLen()
  
  copyto(g, items, oldLen, oldLen+n)

proc `$`*[B, T](g: GPUSeq[B, T]): string =
  let cpuData = g.toSeq()
  return "GPUSeq(" & $cpuData & ")"

proc `$`*[N, B, T](g: GPUSeq[N, B, T]): string =
  let cpuData = g.toArray()
  return "GPUArray(" & $cpuData & ")"