##########################################################################################################################################################
################################################################ OPERATORS BROADCASTING ##################################################################
##########################################################################################################################################################

template `+`[T: GPUSeq | GPUArray](g1, g2: T) = discard
template `-`[T: GPUSeq | GPUArray](g1, g2: T) = discard
template `*`[T: GPUSeq | GPUArray](g1, g2: T) = discard
template `/`[T: GPUSeq | GPUArray](g1, g2: T) = discard
template `+`[T: GPUSeq | GPUArray](g: T, n: SomeInteger) = discard
template `-`[T: GPUSeq | GPUArray](g: T, n: SomeInteger) = discard
template `*`[T: GPUSeq | GPUArray](g: T, n: SomeInteger) = discard
template `/`[T: GPUSeq | GPUArray](g: T, n: SomeInteger) = discard
template `+`[T: GPUSeq | GPUArray](g: T, n: SomeFloat) = discard
template `-`[T: GPUSeq | GPUArray](g: T, n: SomeFloat) = discard
template `*`[T: GPUSeq | GPUArray](g: T, n: SomeFloat) = discard
template `/`[T: GPUSeq | GPUArray](g: T, n: SomeFloat) = discard
template sin[T: GPUSeq | GPUArray](g: T) = discard
template cos[T: GPUSeq | GPUArray](g: T) = discard
template tan[T: GPUSeq | GPUArray](g: T) = discard
  
