############################################################################################################################
######################################################## CRUISE SPACES #####################################################
############################################################################################################################

type
  ## Represents a bounded vector space (to a specific domain)
  ## This mainly represent colors
  CBoundedSpace = concept b
    compile(b.toRGBA)
    compile(b.fromRGBA)

  ## Represents an unbounded vector space
  ## This mainly represent coordinates
  CUnboundedSpace = concept b
    compile(b.toCartesian)
    compile(b.fromCartesian)

  # A generalized vector space
  CVectorSpace = CBoundedSpace | CUnboundedSpace

  # Utility types
  CSomeSigned = int8 | int16 | int32 | int64 | int 
  CSomeUnsigned = uint8 | uint16 | uint32 | uint64 | uint
  CSomeInteger = CSomeSigned | CSomeUnsigned
  CSomeFloat = float32 | float64 | float
  CReal = CSomeInteger | CSomeFloat

  ## Pivot types for unbounded space
  ## In order to go from an unbounded space to another first convert to this type then to the target type
  CCartesianCoord[N: static int, T: CReal] = object
    components: array[N, T]

  ## Pivot types for bounded space
  ## In order to go from an bounded space to another first convert to this type then to the target type
  CRGBA = object
    r, g, b, a: float32
    
proc crgba*(r, g, b, a: float32 = 1f): CRGBA =
  CRGBA(r:r, g:g, b:b, a:a)

template convertTo*[T: CBoundedSpace](dst: typedesc[T], src: CBoundedSpace): T =
    fromRGBA(dst, toRGBA(src))

template convertTo*[T: CUnboundedSpace, N, U](dst: typedesc[T], src: CUnboundedSpace): T =
    fromCartesian(dst, toCartesian(src))

template toCartesian*(c: CCartesianCoord): untyped = 
  ## Default. return himself
  c
template toRGBA*(c: CRGBA): untyped = 
  ## Default. return himself
  c

proc fromCartesian*[T: CCartesianCoord](c: CCartesianCoord): T = result
proc fromRGBA*[T: CRGBA](c: CRGBA): T = result

proc `$`*(c: CRGBA): string =
  ## Returns colors as "(r, g, b, a)".
  "CRGBA(" & $c.r & ", " & $c.g & ", " & $c.b & ", " & $c.a & ")"

proc `$`*[T: CBoundedSpace](c: T): string =
  ## Returns colors as "(r, g, b, a)".
  let col = c.toRGBA
  "CRGBA(" & $col.r & ", " & $col.g & ", " & $col.b & ", " & $col.a & ")"

func hash*(c: CRGBA): Hash =
  ## Hashes a Color - used in tables.
  hash((c.r, c.g, c.b, c.a))

func hash*[T: CBoundedSpace](c: T): Hash =
  ## Hashes a Color - used in tables.
  let col = c.toRGBA
  hash((col.r, col.g, col.b, col.a))
