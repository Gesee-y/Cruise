##########################################################################################################################################################
################################################################ GPU SEQUENCE CORE #######################################################################
##########################################################################################################################################################

import logging, atomics

type
  SomeInteger = int8 | int16 | int32 | int64 | int | uint8 | uint16 | uint32 | uint64 | uint
  SomeFLoat = float32 | float64 | float

  ScalarIndexingMode* = enum
    ScalarDisallowed, ScalarAllowed, ScalarWarn

  ScalarIndexingError* = object of CatchableError
  RefCountError* = object of CatchableError

  RefCount = ref object
    count: Atomic[int]

  GPUSeq*[B,T] = object
    data: B
    capacity: int
    lenght: int
    startIdx: int
    count: RefCount

  GPUArray*[N: static int,B,T] = object
    data: B
    startIdx: int
    count: RefCount

const DEFAULT_CAPACITY = 32

#########################################################################################################################################################
################################################################### ABSTRACTION #########################################################################
#########################################################################################################################################################

var CURRENT_INDEXING {.threadVar.}: ScalarIndexingMode

template assert_scalar(op: untyped, behavior: ScalarIndexingMode) =
    let errdesc = &"""Invocation of '{op}' resulted in scalar indexing of a GPU array.
              This is typically caused by calling an iterating implementation of a method.
              Such implementations *do not* execute on the GPU, but very slowly on the CPU,
              and therefore should be avoided.

              If you want to allow scalar iteration, use `allowscalar` or `@allowscalar`
              to enable scalar iteration globally or for the operations in question."""
    let warnDesc = &"Performing scalar indexing on: {op}"

    if behavior == ScalarDisallowed:
      raise newException(ScalarIndexingError, desc)
    elif behavior == ScalarWarn:
      warn(warnDesc)

template allowScalar*(body: untyped) =
  let oldMode = CURRENT_INDEXING
  CURRENT_INDEXING = ScalarAllowed
  
  try:
    body
  finally:
    CURRENT_INDEXING = oldMode
