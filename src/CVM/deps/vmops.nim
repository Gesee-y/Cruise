  # ######################################################################################################################## #
 # ##################################################### VM OPERATIONS #################################################### #
# ######################################################################################################################## #

type
  # All operations the virtual machine can execute.
  # Integer and float variants are kept separate so the back-end can select the
  # right hardware instruction without extra type information at runtime.
  VMOpCode* = enum
    vocHalt    = 0   ## Stop execution.

    # Arithmetic — integer
    vocAddi    = 1   ## dst += src  (int)
    vocSubi    = 2   ## dst -= src  (int)
    vocMuli    = 3   ## dst *= src  (int)
    vocDivi    = 4   ## dst /= src  (int)
    vocMod     = 5   ## dst %= src

    # Arithmetic — float
    vocAddf    = 6   ## dst += src  (float)
    vocSubf    = 7   ## dst -= src  (float)
    vocMulf    = 8   ## dst *= src  (float)
    vocDivf    = 9   ## dst /= src  (float)

    # Boolean / bitwise
    vocAnd     = 11  ## dst &= src
    vocOr      = 12  ## dst |= src
    vocNot     = 13  ## dst = ~src
    vocXor     = 14  ## dst ^= src

    # Stack / data movement
    vocPush    = 15  ## push src onto the call stack
    vocPop     = 16  ## pop top into dst
    vocMov     = 17  ## dst = src
    vocLoad    = 18  ## dst = mem[src]  (indirect load)
    vocStore   = 19  ## mem[dst] = src  (indirect store)

    # Control flow
    vocCall    = 20  ## call procedure at address encoded in the next word
    vocRet     = 21  ## return from current procedure
    vocJmp     = 22  ## unconditional jump; target in the next bytecode word
    vocJmpFalse = 23 ## jump if dst == 0; target in the next bytecode word

    # Negation — integer / float
    vocNegi    = 24  ## dst = -src  (int)
    vocNegf    = 25  ## dst = -src  (float)

    # Comparison — integer (result: 1 = true, 0 = false)
    vocEqi     = 26  ## dst = (src == dst)  (int)
    vocNeqi    = 27  ## dst = (src != dst)  (int)
    vocLti     = 28  ## dst = (dst  < src)  (int)
    vocLei     = 29  ## dst = (dst <= src)  (int)

    # Comparison — float
    vocEqf     = 30  ## dst = (src == dst)  (float)
    vocNeqf    = 31  ## dst = (src != dst)  (float)
    vocLtf     = 32  ## dst = (dst  < src)  (float)
    vocLef     = 33  ## dst = (dst <= src)  (float)

    # Immediate loads — value is encoded in the *next* bytecode word
    vocLoadi   = 34  ## dst = <next word>  (int immediate)
    vocLoadf   = 35  ## dst = <next word>  (float immediate)
    
    vocSMov    = 36  ## A move from a value on the stack to a register

    # Memory model (uniforms, buffers, GPU indexing)
    vocLoadUni  = 37  ## dst = uniforms[src]
    vocLoadBuf  = 38  ## dst = ssbo[src][index] (followed by vocNoOp index)
    vocStoreBuf = 39  ## ssbo[src][index] = dst (followed by vocNoOp index)
    vocLoadAt   = 40  ## dst = src[index] (followed by vocNoOp index)
    vocStoreAt  = 41  ## src[index] = dst (followed by vocNoOp index)
    vocLoadGI   = 42  ## dst = globalIndex
    vocNoOp     = 43  ## No operation / index operand carrier
    vocMaddf    = 44  ## dst = src * rhsReg + addReg; two packed source registers follow

  # Builtins deliberately have a stable, compact ID space: calls occupy one
  # bytecode word and do not need a name lookup at runtime.
  BuiltinOp* = enum
    boCustom = 0
    boAbs    = 1
    boMin    = 2
    boMax    = 3
    boSqrt   = 4

proc toBuiltinCall(op: string): BuiltinOp =
  case op
  of "abs": boAbs
  of "min": boMin
  of "max": boMax
  of "sqrt": boSqrt
  else: boCustom
