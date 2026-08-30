  # ######################################################################################################################## #
 # ##################################################### VM OPERATIONS #################################################### #
# ######################################################################################################################## #

type
  # The operations code supported by the Virtual machine
  # Reflect what can be done on GPU
  VMOpCode* = enum
    vocHalt = 0
    vocAddi = 1
    vocSubi = 2
    vocMuli = 3
    vocDivi = 4
    vocModi = 5
    vocAddf = 6
    vocSubf = 7
    vocMulf = 8
    vocDivf = 9
    vocModf = 10
    vocAnd = 11
    vocOr = 12
    vocNot = 13
    vocXor = 14
    vocPush = 15
    vocPop = 16
    vocMov = 17
    ## Load the following word into operand A.
    vocLoad = 18
    ## Call a user function identified by operand B. Arguments are pushed
    ## before the call and the returned word is stored in operand A.
    vocCall = 19
    ## Return the word stored at operand A to the current caller.
    vocRet = 20

  ## Builtins deliberately have a stable, compact ID space: calls occupy one
  ## bytecode word and do not need a name lookup at runtime.
  BuiltinOp* = enum
    boCustom = 0
    boAbs = 1
    boMin = 2
    boMax = 3
    boSqrt = 4
