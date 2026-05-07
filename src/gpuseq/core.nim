##########################################################################################################################################################
################################################################ GPU SEQUENCE CORE #######################################################################
##########################################################################################################################################################

import logging

type
  ScalarIndexingMode = enum
    ScalarAllowed, ScalarWarn, ScalarDisallowed

  ScalarIndexingError = ref object of Exception

  GPUSeq[B,T] = object
    data: B
    capacity: int
    lenght: int

#########################################################################################################################################################
################################################################### ABSTRACTION #########################################################################
#########################################################################################################################################################

var CURRENT_INDEXING {.threadVar.}

template assert_scalar(op: untyped, behavior: ScalarIndexingMode)
    let errdesc = &"""Invocation of '{op}' resulted in scalar indexing of a GPU array.
              This is typically caused by calling an iterating implementation of a method.
              Such implementations *do not* execute on the GPU, but very slowly on the CPU,
              and therefore should be avoided.

              If you want to allow scalar iteration, use `allowscalar` or `@allowscalar`
              to enable scalar iteration globally or for the operations in question."""
    let warnDesc = &"Performing s"

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
