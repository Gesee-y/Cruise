  # ######################################################################################################################## #
 # ##################################################### VM OPERATIONS #################################################### #
# ######################################################################################################################## #

type
  VMConvType* = enum
    vctInvalid = 0
    vctInt8 = 1
    vctInt16 = 2
    vctInt32 = 3
    vctInt64 = 4
    vctUInt8 = 5
    vctUInt16 = 6
    vctUInt32 = 7
    vctUInt64 = 8
    vctFloat32 = 9
    vctFloat64 = 10
    vctBool = 11

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

    vocConv    = 10  ## dst = convert(src); a packed source/destination VMConvType word follows
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
    vocMaddi    = 45  ## Integer dst = src * rhsReg + addReg; two packed source registers follow
    vocAbsi    = 46  ## dst = abs(src), signed integer
    vocAbsf    = 47  ## dst = abs(src), float
    vocAbsu    = 48  ## dst = src, unsigned abs identity
    vocMini    = 49  ## dst = min(dst, src), signed integer
    vocMaxi    = 50  ## dst = max(dst, src), signed integer
    vocMinf    = 51  ## dst = min(dst, src), float
    vocMaxf    = 52  ## dst = max(dst, src), float
    vocMinu    = 53  ## dst = min(dst, src), unsigned integer
    vocMaxu    = 54  ## dst = max(dst, src), unsigned integer
    vocSqrtf   = 55  ## dst = sqrt(src), float
    vocRsqrtf  = 56  ## dst = 1 / sqrt(src), float
    vocAddCi   = 57  ## dst += signed/unsigned immediate (next word, or two for size 8)
    vocSubCi   = 58  ## dst -= signed/unsigned immediate
    vocMulCi   = 59  ## dst *= signed/unsigned immediate
    vocAddCf   = 60  ## dst += float immediate
    vocSubCf   = 61  ## dst -= float immediate
    vocMulCf   = 62  ## dst *= float immediate
    vocLoadVertexInput = 63 ## dst = input block[src .. src+size)
    vocLoadFragmentInput = 64 ## dst = interpolated varying block[src .. src+size)
    vocStoreVertexOutput = 65 ## emit vec4 clip-space position
    vocStoreVertexVarying = 66 ## store VM bytes in varying block at src
    vocStoreFragmentOutput = 67 ## emit vec4 fragment color

    vocSinf = 68 ## dst = sin(src), float
    vocCosf = 69 ## dst = cos(src), float
    
    vocSample2D = 70 ## vocSample2D.16 dstReg, coordReg (next word is the Texture ID)
