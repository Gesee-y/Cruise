############################################################################################################################
######################################################## CRUISE SPACES #####################################################
############################################################################################################################

type
  CBoundedSpace = concept b
    compile(b.domain)
    compile(b.toRGBA)

  CUnboundedSpace = concept b
    not compile(b.domain)
    compile(b.toCartesian)

  CVectorSpace = CBoundedSpace | CUnboundedSpace

  CSomeSigned = int8 | int16 | int32 | int64 | int 
  CSomeUnsigned = uint8 | uint16 | uint32 | uint64 | uint
  CSomeInteger = CSomeSigned | CSomeUnsigned
  CSomeFloat = float32 | float64 | float
  CReal = CSomeInteger | CSomeFloat

  CCartesianCoord[N: static int, T: CReal] = object
    components: array[N, T]

  CRGBA = object
    r, g, b, a: float32
    
template toCartesian(c: CCartesianCoord): untyped = c
template toRGBA(c: CRGBA): untyped = c

template convertTo[T: CBoundedSpace](dst: typedesc[T], src: CBoundedSpace): T =
    fromRGBA(dst, toRGBA(src))

template convertTo[T: CUnboundedSpace, N, U](dst: typedesc[T], src: CUnboundedSpace): T =
    fromCartesian(dst, toCartesian(src))

proc fromCartesian[T: CUnboundedSpace](c: CCartesianCoord): T = result
proc fromRGBA[T: CBoundedSpace](c: CRGBA): T = result
