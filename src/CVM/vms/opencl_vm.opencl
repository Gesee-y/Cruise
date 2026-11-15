#if defined(cl_khr_fp64)
#pragma OPENCL EXTENSION cl_khr_fp64 : enable
#elif defined(cl_amd_fp64)
#pragma OPENCL EXTENSION cl_amd_fp64 : enable
#endif

#if defined(cl_khr_fp64) || defined(cl_amd_fp64)
typedef double vm_float_t;
#else
typedef float vm_float_t;
#endif

#define MAX_MEM 256
#define MAX_STACK 256

#define SIZE_POS   24
#define OPCODE_POS 16
#define REGA_POS   8

inline void decodeWord(uint word, int *op, int *dst, int *src, int *size) {
    *op   = (int)((word >> OPCODE_POS) & 0xFF);
    *size = (int)((word >> SIZE_POS) & 0xFF);
    if (*size == 0 && *op != 20) *size = 1;
    *dst  = (int)((word >> REGA_POS)   & 0xFF);
    *src  = (int)(word & 0xFF);
}

inline long readMemInt(const uchar *mem, int address, int size) {
    if (size == 8) {
        return *(const long*)(mem + address);
    } else if (size == 4) {
        return (long)(*(const int*)(mem + address));
    } else if (size == 2) {
        return (long)(*(const short*)(mem + address));
    } else if (size == 1) {
        return (long)(*(const char*)(mem + address));
    } else {
        long v = 0;
        int m = size < 8 ? size : 8;
        for (int i = 0; i < m; i++) ((uchar*)&v)[i] = mem[address + i];
        return v;
    }
}

inline void writeMemInt(uchar *mem, int address, int size, long val) {
    if (size == 8) {
        *(long*)(mem + address) = val;
    } else if (size == 4) {
        *(int*)(mem + address) = (int)val;
    } else if (size == 2) {
        *(short*)(mem + address) = (short)val;
    } else if (size == 1) {
        *(char*)(mem + address) = (char)val;
    } else {
        int m = size < 8 ? size : 8;
        for (int i = 0; i < m; i++) mem[address + i] = ((const uchar*)&val)[i];
    }
}

inline uint readStackWord(const uchar *stack, int address) {
    return (uint)stack[address] | ((uint)stack[address + 1] << 8) |
        ((uint)stack[address + 2] << 16) | ((uint)stack[address + 3] << 24);
}

inline void writeStackWord(uchar *stack, int address, uint value) {
    stack[address] = (uchar)value;
    stack[address + 1] = (uchar)(value >> 8);
    stack[address + 2] = (uchar)(value >> 16);
    stack[address + 3] = (uchar)(value >> 24);
}

inline vm_float_t readMemFloat(const uchar *mem, int address, int size) {
    #if defined(cl_khr_fp64) || defined(cl_amd_fp64)
    if (size == 8) {
        return *(const double*)(mem + address);
    }
    #endif
    return *(const float*)(mem + address);
}

inline void writeMemFloat(uchar *mem, int address, int size, vm_float_t val) {
    #if defined(cl_khr_fp64) || defined(cl_amd_fp64)
    if (size == 8) {
        *(double*)(mem + address) = (double)val;
        return;
    }
    #endif
    *(float*)(mem + address) = val;
}

inline float readFloatWord(const uchar *mem, int wordIndex) {
    return ((__private const float*)mem)[wordIndex];
}

inline void writeFloatWord(uchar *mem, int wordIndex, float value) {
    ((__private float*)mem)[wordIndex] = value;
}

inline ulong readMemUInt(const uchar *mem, int address, int size) {
    if (size == 8) return *(const ulong*)(mem + address);
    if (size == 4) return (ulong)(*(const uint*)(mem + address));
    if (size == 2) return (ulong)(*(const ushort*)(mem + address));
    if (size == 1) return (ulong)mem[address];
    ulong v = 0;
    int m = size < 8 ? size : 8;
    for (int i = 0; i < m; i++) ((uchar*)&v)[i] = mem[address + i];
    return v;
}

inline void writeMemUInt(uchar *mem, int address, int size, ulong val) {
    if (size == 8) *(ulong*)(mem + address) = val;
    else if (size == 4) *(uint*)(mem + address) = (uint)val;
    else if (size == 2) *(ushort*)(mem + address) = (ushort)val;
    else if (size == 1) mem[address] = (uchar)val;
    else {
        int m = size < 8 ? size : 8;
        for (int i = 0; i < m; i++) mem[address + i] = ((const uchar*)&val)[i];
    }
}

inline __global uchar* getBuffer(int bufId,
    __global uchar *b0, __global uchar *b1, __global uchar *b2, __global uchar *b3,
    __global uchar *b4, __global uchar *b5, __global uchar *b6, __global uchar *b7)
{
    switch(bufId) {
        case 0: return b0;
        case 1: return b1;
        case 2: return b2;
        case 3: return b3;
        case 4: return b4;
        case 5: return b5;
        case 6: return b6;
        case 7: return b7;
        default: return b0;
    }
}

__kernel void runVM(
    __constant const uint *program,
    int startPc,
    __constant const uint *uniforms,
    int uniformLen,
    __global uchar *b0,
    __global uchar *b1,
    __global uchar *b2,
    __global uchar *b3,
    __global uchar *b4,
    __global uchar *b5,
    __global uchar *b6,
    __global uchar *b7
) {
    // 8-byte aligned register file
    __attribute__((aligned(8))) uchar mem[MAX_MEM];
    for (int i = 0; i < MAX_MEM; i++) mem[i] = 0;
    
    int registerBase = 0;
    int stackBase = 0;
    int callFrameBase = -1;

    uchar stack[MAX_STACK];
    int stackLen = 0;

    int pc = startPc;
    int halted = 0;
    while (!halted) {
        uint word = program[pc++];
        int op, dst, src, size;
        decodeWord(word, &op, &dst, &src, &size);

        switch (op) {
            case 0: { // vocHalt
                halted = 1;
                break;
            }

            case 1: { // vocAddi
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(long*)(mem + dst) += *(const long*)(mem + src);
                } else if (size == 4) {
                    *(int*)(mem + dst) += *(const int*)(mem + src);
                } else {
                    long a = readMemInt(mem, dst, size);
                    long b = readMemInt(mem, src, size);
                    writeMemInt(mem, dst, size, a + b);
                }
                break;
            }

            case 2: { // vocSubi
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(long*)(mem + dst) -= *(const long*)(mem + src);
                } else if (size == 4) {
                    *(int*)(mem + dst) -= *(const int*)(mem + src);
                } else {
                    long a = readMemInt(mem, dst, size);
                    long b = readMemInt(mem, src, size);
                    writeMemInt(mem, dst, size, a - b);
                }
                break;
            }

            case 3: { // vocMuli
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(long*)(mem + dst) *= *(const long*)(mem + src);
                } else if (size == 4) {
                    *(int*)(mem + dst) *= *(const int*)(mem + src);
                } else {
                    long a = readMemInt(mem, dst, size);
                    long b = readMemInt(mem, src, size);
                    writeMemInt(mem, dst, size, a * b);
                }
                break;
            }

            case 4: { // vocDivi
                dst += registerBase;
                src += registerBase;
                long a = readMemInt(mem, dst, size);
                long b = readMemInt(mem, src, size);
                if (b != 0) writeMemInt(mem, dst, size, a / b);
                break;
            }

            case 5: { // vocMod
                dst += registerBase;
                src += registerBase;
                long a = readMemInt(mem, dst, size);
                long b = readMemInt(mem, src, size);
                if (b != 0) writeMemInt(mem, dst, size, a % b);
                break;
            }

            case 6: { // vocAddf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    int dstWord = dst >> 2;
                    int srcWord = src >> 2;
                    writeFloatWord(mem, dstWord, readFloatWord(mem, dstWord) + readFloatWord(mem, srcWord));
                } else {
                    vm_float_t a = readMemFloat(mem, dst, size);
                    vm_float_t b = readMemFloat(mem, src, size);
                    writeMemFloat(mem, dst, size, a + b);
                }
                break;
            }

            case 7: { // vocSubf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    int dstWord = dst >> 2;
                    int srcWord = src >> 2;
                    writeFloatWord(mem, dstWord, readFloatWord(mem, dstWord) - readFloatWord(mem, srcWord));
                } else {
                    vm_float_t a = readMemFloat(mem, dst, size);
                    vm_float_t b = readMemFloat(mem, src, size);
                    writeMemFloat(mem, dst, size, a - b);
                }
                break;
            }

            case 8: { // vocMulf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    int dstWord = dst >> 2;
                    int srcWord = src >> 2;
                    writeFloatWord(mem, dstWord, readFloatWord(mem, dstWord) * readFloatWord(mem, srcWord));
                } else {
                    vm_float_t a = readMemFloat(mem, dst, size);
                    vm_float_t b = readMemFloat(mem, src, size);
                    writeMemFloat(mem, dst, size, a * b);
                }
                break;
            }

            case 9: { // vocDivf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    int dstWord = dst >> 2;
                    int srcWord = src >> 2;
                    writeFloatWord(mem, dstWord, readFloatWord(mem, dstWord) / readFloatWord(mem, srcWord));
                } else {
                    vm_float_t a = readMemFloat(mem, dst, size);
                    vm_float_t b = readMemFloat(mem, src, size);
                    writeMemFloat(mem, dst, size, a / b);
                }
                break;
            }

            case 10: { // vocConv: packed source and destination VMConvType follow
                dst += registerBase;
                src += registerBase;
                uint descriptor = program[pc++];
                int sourceType = (int)(descriptor & 0xFFu);
                int targetType = (int)((descriptor >> 8) & 0xFFu);
                int sourceSize = sourceType >= 1 && sourceType <= 4 ? (1 << (sourceType - 1)) :
                    (sourceType >= 5 && sourceType <= 8 ? (1 << (sourceType - 5)) :
                    (sourceType == 9 ? 4 : (sourceType == 10 ? 8 :
                    (sourceType == 11 ? 1 : 0))));
                int targetSize = targetType >= 1 && targetType <= 4 ? (1 << (targetType - 1)) :
                    (targetType >= 5 && targetType <= 8 ? (1 << (targetType - 5)) :
                    (targetType == 9 ? 4 : (targetType == 10 ? 8 :
                    (targetType == 11 ? 1 : 0))));
                int sourceFloat = sourceType == 9 || sourceType == 10;
                int targetFloat = targetType == 9 || targetType == 10;
                int sourceUnsigned = (sourceType >= 5 && sourceType <= 8) || sourceType == 11;
                int targetUnsigned = (targetType >= 5 && targetType <= 8) || targetType == 11;

                if (sourceSize > 0 && targetSize > 0) {
                    if (targetType == 11) {
                        int nonZero = sourceFloat ?
                            readMemFloat(mem, src, sourceSize) != (vm_float_t)0 :
                            (sourceUnsigned ? readMemUInt(mem, src, sourceSize) != 0 :
                             readMemInt(mem, src, sourceSize) != 0);
                        writeMemUInt(mem, dst, 1, (ulong)(nonZero != 0));
                    } else if (sourceFloat) {
                        vm_float_t value = readMemFloat(mem, src, sourceSize);
                        if (targetFloat) writeMemFloat(mem, dst, targetSize, value);
                        else if (targetUnsigned) writeMemUInt(mem, dst, targetSize, (ulong)value);
                        else writeMemInt(mem, dst, targetSize, (long)value);
                    } else if (sourceUnsigned) {
                        ulong value = readMemUInt(mem, src, sourceSize);
                        if (targetFloat) writeMemFloat(mem, dst, targetSize, (vm_float_t)value);
                        else if (targetUnsigned) writeMemUInt(mem, dst, targetSize, value);
                        else writeMemInt(mem, dst, targetSize, (long)value);
                    } else {
                        long value = readMemInt(mem, src, sourceSize);
                        if (targetFloat) writeMemFloat(mem, dst, targetSize, (vm_float_t)value);
                        else if (targetUnsigned) writeMemUInt(mem, dst, targetSize, (ulong)value);
                        else writeMemInt(mem, dst, targetSize, value);
                    }
                }
                break;
            }

            case 11: { // vocAnd
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(ulong*)(mem + dst) &= *(const ulong*)(mem + src);
                } else if (size == 4) {
                    *(uint*)(mem + dst) &= *(const uint*)(mem + src);
                } else {
                    long a = readMemInt(mem, dst, size);
                    long b = readMemInt(mem, src, size);
                    writeMemInt(mem, dst, size, a & b);
                }
                break;
            }

            case 12: { // vocOr
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(ulong*)(mem + dst) |= *(const ulong*)(mem + src);
                } else if (size == 4) {
                    *(uint*)(mem + dst) |= *(const uint*)(mem + src);
                } else {
                    long a = readMemInt(mem, dst, size);
                    long b = readMemInt(mem, src, size);
                    writeMemInt(mem, dst, size, a | b);
                }
                break;
            }

            case 13: { // vocNot
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(ulong*)(mem + dst) = ~(*(const ulong*)(mem + src));
                } else if (size == 4) {
                    *(uint*)(mem + dst) = ~(*(const uint*)(mem + src));
                } else {
                    long b = readMemInt(mem, src, size);
                    writeMemInt(mem, dst, size, ~b);
                }
                break;
            }

            case 14: { // vocXor
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(ulong*)(mem + dst) ^= *(const ulong*)(mem + src);
                } else if (size == 4) {
                    *(uint*)(mem + dst) ^= *(const uint*)(mem + src);
                } else {
                    long a = readMemInt(mem, dst, size);
                    long b = readMemInt(mem, src, size);
                    writeMemInt(mem, dst, size, a ^ b);
                }
                break;
            }

            case 15: { // vocPush
                dst += registerBase;
                src += registerBase;
                int reg = (dst != 0) ? dst : src;
                for (int i = 0; i < size && stackLen < MAX_STACK; i++) {
                    stack[stackLen++] = mem[reg + i];
                }
                break;
            }

            case 16: { // vocPop
                dst += registerBase;
                src += registerBase;
                int popSize = size < stackLen ? size : stackLen;
                if (popSize > 0) {
                    int startIdx = stackLen - popSize;
                    for (int i = 0; i < popSize; i++) {
                        mem[dst + i] = stack[startIdx + i];
                    }
                    stackLen = startIdx;
                }
                break;
            }

            case 17: { // vocMov
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(ulong*)(mem + dst) = *(const ulong*)(mem + src);
                } else if (size == 4) {
                    *(uint*)(mem + dst) = *(const uint*)(mem + src);
                } else if (size == 1) {
                    mem[dst] = mem[src];
                } else {
                    for (int i = 0; i < size; i++) {
                        mem[dst + i] = mem[src + i];
                    }
                }
                break;
            }

            case 18: { // vocLoad
                dst += registerBase;
                src += registerBase;
                int addrReg = (int)mem[src];
                for (int i = 0; i < size; i++) {
                    mem[dst + i] = mem[addrReg + i];
                }
                break;
            }

            case 19: { // vocStore
                dst += registerBase;
                src += registerBase;
                int addrReg = (int)mem[dst];
                for (int i = 0; i < size; i++) {
                    mem[addrReg + i] = mem[src + i];
                }
                break;
            }

            case 20: { // vocCall
                src += registerBase;
                int target = (int)program[pc++];
                uint frameInfo = program[pc++];
                int argsBytes = (int)(frameInfo & 0xFFFFu);
                int frameBytes = (int)(frameInfo >> 16);
                int argsBase = stackLen - argsBytes;
                int calleeBase = registerBase + dst;
                if (argsBase < 0 || stackLen + 16 > MAX_STACK || stackLen > 65535 ||
                    stackBase > 65535 || callFrameBase > 65535 || calleeBase + frameBytes > MAX_MEM) {
                    halted = 1; break;
                }
                int frameAt = stackLen;
                uint previousFrame = callFrameBase < 0 ? 65535u : (uint)callFrameBase;
                writeStackWord(stack, frameAt, (uint)pc);
                writeStackWord(stack, frameAt + 4,
                    (uint)registerBase | ((uint)stackBase << 16));
                writeStackWord(stack, frameAt + 8,
                    previousFrame | ((uint)argsBase << 16));
                writeStackWord(stack, frameAt + 12,
                    (uint)src | ((uint)size << 8) | ((uint)calleeBase << 16));
                stackLen += 16;
                callFrameBase = frameAt;
                registerBase = calleeBase;
                stackBase = argsBase;
                pc = target;
                break;
            }

            case 21: { // vocRet
                if (callFrameBase >= 0 && callFrameBase + 16 <= stackLen) {
                    uint returnPc = readStackWord(stack, callFrameBase);
                    uint parentBases = readStackWord(stack, callFrameBase + 4);
                    uint previousAndArgs = readStackWord(stack, callFrameBase + 8);
                    uint resultInfo = readStackWord(stack, callFrameBase + 12);
                    int returnDst = (int)(resultInfo & 0xFFu);
                    int returnSize = (int)((resultInfo >> 8) & 0xFFu);
                    int calleeBase = (int)(resultInfo >> 16);
                    if (returnSize > 0) {
                        for (int i = 0; i < returnSize; ++i)
                            mem[returnDst + i] = mem[calleeBase + i];
                    }
                    stackLen = (int)(previousAndArgs >> 16);
                    uint previousFrame = previousAndArgs & 0xFFFFu;
                    callFrameBase = previousFrame == 65535u ? -1 : (int)previousFrame;
                    registerBase = (int)(parentBases & 0xFFFFu);
                    stackBase = (int)(parentBases >> 16);
                    pc = (int)returnPc;
                } else {
                    halted = 1;
                }
                break;
            }

            case 22: { // vocJmp
                uint target = program[pc];
                pc = (int)target;
                break;
            }

            case 23: { // vocJmpFalse
                dst += registerBase;
                uint target = program[pc++];
                long cond = mem[dst];
                if (cond == 0) {
                    pc = (int)target;
                }
                break;
            }

            case 24: { // vocNegi
                dst += registerBase;
                src += registerBase;
                if (size == 8) {
                    *(long*)(mem + dst) = -(*(const long*)(mem + src));
                } else if (size == 4) {
                    *(int*)(mem + dst) = -(*(const int*)(mem + src));
                } else {
                    long b = readMemInt(mem, src, size);
                    writeMemInt(mem, dst, size, -b);
                }
                break;
            }

            case 25: { // vocNegf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    *(float*)(mem + dst) = -(*(const float*)(mem + src));
                } else {
                    vm_float_t b = readMemFloat(mem, src, size);
                    writeMemFloat(mem, dst, size, -b);
                }
                break;
            }

            case 26: { // vocEqi
                dst += registerBase;
                src += registerBase;
                long a = readMemInt(mem, dst, size);
                long b = readMemInt(mem, src, size);
                mem[dst] = (a == b) ? 1 : 0;
                break;
            }

            case 27: { // vocNeqi
                dst += registerBase;
                src += registerBase;
                long a = readMemInt(mem, dst, size);
                long b = readMemInt(mem, src, size);
                mem[dst] = (a != b) ? 1 : 0;
                break;
            }

            case 28: { // vocLti
                dst += registerBase;
                src += registerBase;
                long a = readMemInt(mem, dst, size);
                long b = readMemInt(mem, src, size);
                mem[dst] = (a < b) ? 1 : 0;
                break;
            }

            case 29: { // vocLei
                dst += registerBase;
                src += registerBase;
                long a = readMemInt(mem, dst, size);
                long b = readMemInt(mem, src, size);
                mem[dst] = (a <= b) ? 1 : 0;
                break;
            }

            case 30: { // vocEqf
                dst += registerBase;
                src += registerBase;
                vm_float_t a = readMemFloat(mem, dst, size);
                vm_float_t b = readMemFloat(mem, src, size);
                mem[dst] = (a == b) ? 1 : 0;
                break;
            }

            case 31: { // vocNeqf
                dst += registerBase;
                src += registerBase;
                vm_float_t a = readMemFloat(mem, dst, size);
                vm_float_t b = readMemFloat(mem, src, size);
                mem[dst] = (a != b) ? 1 : 0;
                break;
            }

            case 32: { // vocLtf
                dst += registerBase;
                src += registerBase;
                vm_float_t a = readMemFloat(mem, dst, size);
                vm_float_t b = readMemFloat(mem, src, size);
                mem[dst] = (a < b) ? 1 : 0;
                break;
            }

            case 33: { // vocLef
                dst += registerBase;
                src += registerBase;
                vm_float_t a = readMemFloat(mem, dst, size);
                vm_float_t b = readMemFloat(mem, src, size);
                mem[dst] = (a <= b) ? 1 : 0;
                break;
            }

            case 34: case 111: { // vocLoadi / vocMovCi
                dst += registerBase;
                uint imm = program[pc++];
                if (size == 8) {
                    *(long*)(mem + dst) = (long)(int)imm;
                } else if (size == 4) {
                    *(int*)(mem + dst) = (int)imm;
                } else {
                    writeMemInt(mem, dst, size, (long)(int)imm);
                }
                break;
            }

            case 35: case 112: { // vocLoadf / vocMovCf
                dst += registerBase;
                uint imm = program[pc++];
                vm_float_t fval = as_float(imm);
                if (size == 4) {
                    *(float*)(mem + dst) = fval;
                } else {
                    writeMemFloat(mem, dst, size, fval);
                }
                break;
            }

            case 36: { // vocSMov
                dst += registerBase;
                int offset = stackBase + src;
                if (offset + size <= stackLen) {
                    for (int i = 0; i < size; i++) {
                        mem[dst + i] = stack[offset + i];
                    }
                }
                break;
            }

            case 37: { // vocLoadUni
                dst += registerBase;
                int uIdx = src;
                if (uIdx < uniformLen) {
                    if (size == 8 && uIdx + 1 < uniformLen) {
                        *(long*)(mem + dst) = *(__constant const long*)(uniforms + uIdx);
                    } else if (size == 4) {
                        *(uint*)(mem + dst) = uniforms[uIdx];
                    } else {
                        int totalAvailBytes = (uniformLen - uIdx) * 4;
                        int copyBytes = size < totalAvailBytes ? size : totalAvailBytes;
                        __constant const uchar *uBytes = ((__constant const uchar*)uniforms) + (uIdx * 4);
                        for (int i = 0; i < copyBytes; i++) {
                            mem[dst + i] = uBytes[i];
                        }
                    }
                }
                break;
            }

            case 38: { // vocLoadBuf (Coalesced SSBO Load)
                dst += registerBase;
                int bufId = src;
                int idxReg = (int)program[pc++] + registerBase;
                long index = readMemInt(mem, idxReg, 4);
                __global uchar *basePtr = getBuffer(bufId, b0, b1, b2, b3, b4, b5, b6, b7);
                __global uchar *elemPtr = basePtr + (index * (long)size);
                if (size == 8) {
                    *(long*)(mem + dst) = *(__global const long*)elemPtr;
                } else if (size == 4) {
                    *(int*)(mem + dst) = *(__global const int*)elemPtr;
                } else {
                    for (int i = 0; i < size; i++) {
                        mem[dst + i] = elemPtr[i];
                    }
                }
                break;
            }

            case 39: { // vocStoreBuf (Coalesced SSBO Store)
                dst += registerBase;
                int bufId = src;
                int idxReg = (int)program[pc++] + registerBase;
                long index = readMemInt(mem, idxReg, 4);
                __global uchar *basePtr = getBuffer(bufId, b0, b1, b2, b3, b4, b5, b6, b7);
                __global uchar *elemPtr = basePtr + (index * (long)size);
                if (size == 8) {
                    *(__global long*)elemPtr = *(const long*)(mem + dst);
                } else if (size == 4) {
                    *(__global int*)elemPtr = *(const int*)(mem + dst);
                } else {
                    for (int i = 0; i < size; i++) {
                        elemPtr[i] = mem[dst + i];
                    }
                }
                break;
            }

            case 40: { // vocLoadAt
                dst += registerBase;
                src += registerBase;
                int arrBase = src;
                int idxReg = (int)program[pc++] + registerBase;
                int index = (int)readMemInt(mem, idxReg, 4);
                int elemAddr = arrBase + index * size;
                if (elemAddr >= 0 && elemAddr + size <= MAX_MEM && dst + size <= MAX_MEM) {
                    for (int i = 0; i < size; i++) {
                        mem[dst + i] = mem[elemAddr + i];
                    }
                }
                break;
            }

            case 41: { // vocStoreAt
                dst += registerBase;
                src += registerBase;
                int arrBase = src;
                int idxReg = (int)program[pc++] + registerBase;
                int index = (int)readMemInt(mem, idxReg, 4);
                int elemAddr = arrBase + index * size;
                if (elemAddr >= 0 && elemAddr + size <= MAX_MEM && dst + size <= MAX_MEM) {
                    for (int i = 0; i < size; i++) {
                        mem[elemAddr + i] = mem[dst + i];
                    }
                }
                break;
            }

            case 42: { // vocLoadGI
                dst += registerBase;
                if (size == 8) {
                    *(long*)(mem + dst) = (long)get_global_id(0);
                } else if (size == 4) {
                    *(int*)(mem + dst) = (int)get_global_id(0);
                } else {
                    writeMemInt(mem, dst, size, (long)get_global_id(0));
                }
                break;
            }

            case 43: { // vocNoOp
                break;
            }

            case 44: { // vocMaddf: dst = mem[src] * mem[rhs] + mem[add]
                dst += registerBase;
                src += registerBase;
                uint packedSources = program[pc++];
                int rhsReg = (int)(packedSources & 0xFF) + registerBase;
                int addReg = (int)((packedSources >> 8) & 0xFF) + registerBase;
                int isVector = size > 4;
                if (isVector) {
                    int srcWord = src >> 2;
                    int rhsWord = rhsReg >> 2;
                    int addWord = addReg >> 2;
                    int dstWord = dst >> 2;
                    for (int lane = 0; lane < (size >> 2); lane++) {
                        float lhs = readFloatWord(mem, srcWord + lane);
                        float rhs = readFloatWord(mem, rhsWord + lane);
                        float addend = readFloatWord(mem, addWord + lane);
                        writeFloatWord(mem, dstWord + lane, fma(lhs, rhs, addend));
                    }
                } else if (size == 4) {
                    float lhs = readFloatWord(mem, src >> 2);
                    float rhs = readFloatWord(mem, rhsReg >> 2);
                    float addend = readFloatWord(mem, addReg >> 2);
                    writeFloatWord(mem, dst >> 2, fma(lhs, rhs, addend));
                } else {
                    vm_float_t lhs = readMemFloat(mem, src, size);
                    vm_float_t rhs = readMemFloat(mem, rhsReg, size);
                    vm_float_t addend = readMemFloat(mem, addReg, size);
                    writeMemFloat(mem, dst, size, fma(lhs, rhs, addend));
                }
                break;
            }

            case 45: { // vocMaddi: dst = src * rhs + add
                dst += registerBase;
                src += registerBase;
                uint packedSources = program[pc++];
                int rhsReg = (int)(packedSources & 0xFF) + registerBase;
                int addReg = (int)((packedSources >> 8) & 0xFF) + registerBase;
                ulong product = readMemUInt(mem, src, size) * readMemUInt(mem, rhsReg, size);
                ulong addend = readMemUInt(mem, addReg, size);
                writeMemUInt(mem, dst, size, product + addend);
                break;
            }

            case 46: { // vocAbsi
                dst += registerBase;
                src += registerBase;
                long val = readMemInt(mem, src, size);
                writeMemInt(mem, dst, size, val < 0 ? -val : val);
                break;
            }

            case 47: { // vocAbsf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    *(float*)(mem + dst) = fabs(*(const float*)(mem + src));
                } else {
                    writeMemFloat(mem, dst, size, fabs(readMemFloat(mem, src, size)));
                }
                break;
            }

            case 48: { // vocAbsu: identity; if source/destination differ, copy it
                dst += registerBase;
                src += registerBase;
                if (dst != src) {
                    for (int i = 0; i < size; i++) mem[dst + i] = mem[src + i];
                }
                break;
            }

            case 49: { // vocMini
                dst += registerBase;
                src += registerBase;
                long a = readMemInt(mem, dst, size);
                long b = readMemInt(mem, src, size);
                writeMemInt(mem, dst, size, min(a, b));
                break;
            }

            case 50: { // vocMaxi
                dst += registerBase;
                src += registerBase;
                long a = readMemInt(mem, dst, size);
                long b = readMemInt(mem, src, size);
                writeMemInt(mem, dst, size, max(a, b));
                break;
            }

            case 51: { // vocMinf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    *(float*)(mem + dst) = fmin(*(const float*)(mem + dst), *(const float*)(mem + src));
                } else {
                    vm_float_t a = readMemFloat(mem, dst, size);
                    vm_float_t b = readMemFloat(mem, src, size);
                    writeMemFloat(mem, dst, size, fmin(a, b));
                }
                break;
            }

            case 52: { // vocMaxf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    *(float*)(mem + dst) = fmax(*(const float*)(mem + dst), *(const float*)(mem + src));
                } else {
                    vm_float_t a = readMemFloat(mem, dst, size);
                    vm_float_t b = readMemFloat(mem, src, size);
                    writeMemFloat(mem, dst, size, fmax(a, b));
                }
                break;
            }

            case 53: { // vocMinu
                dst += registerBase;
                src += registerBase;
                ulong a = readMemUInt(mem, dst, size);
                ulong b = readMemUInt(mem, src, size);
                writeMemUInt(mem, dst, size, min(a, b));
                break;
            }

            case 54: { // vocMaxu
                dst += registerBase;
                src += registerBase;
                ulong a = readMemUInt(mem, dst, size);
                ulong b = readMemUInt(mem, src, size);
                writeMemUInt(mem, dst, size, max(a, b));
                break;
            }

            case 55: { // vocSqrtf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    *(float*)(mem + dst) = sqrt(*(const float*)(mem + src));
                } else {
                    writeMemFloat(mem, dst, size, sqrt(readMemFloat(mem, src, size)));
                }
                break;
            }

            case 56: { // vocRsqrtf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    *(float*)(mem + dst) = rsqrt(*(const float*)(mem + src));
                } else {
                    vm_float_t x = readMemFloat(mem, src, size);
                    writeMemFloat(mem, dst, size, rsqrt(x));
                }
                break;
            }

            case 68: { // vocSinf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    *(float*)(mem + dst) = sin(*(const float*)(mem + src));
                } else {
                    writeMemFloat(mem, dst, size, sin(readMemFloat(mem, src, size)));
                }
                break;
            }

            case 69: { // vocCosf
                dst += registerBase;
                src += registerBase;
                if (size == 4) {
                    *(float*)(mem + dst) = cos(*(const float*)(mem + src));
                } else {
                    writeMemFloat(mem, dst, size, cos(readMemFloat(mem, src, size)));
                }
                break;
            }

            case 57: case 58: case 59: { // integer arithmetic with immediate
                dst += registerBase;
                src += registerBase;
                ulong imm = (ulong)program[pc++];
                ulong value = readMemUInt(mem, dst, size);
                if (op == 57) value += imm;
                else if (op == 58) value -= imm;
                else value *= imm;
                writeMemUInt(mem, dst, size, value);
                break;
            }

            case 60: case 61: case 62: { // floating arithmetic with immediate
                dst += registerBase;
                src += registerBase;
                uint low = program[pc++];
                float imm = as_float(low);
                float value = readMemFloat(mem, dst, size);
                if (op == 60) value += imm;
                else if (op == 61) value -= imm;
                else value *= imm;
                writeMemFloat(mem, dst, size, value);
                break;
            }

            case 71: case 72: case 73: case 74: case 75: case 76: {
                dst += registerBase; src += registerBase;
                int dim = (op <= 72) ? 2 : ((op <= 74) ? 3 : 4);
                int isFloat = (op == 71 || op == 73 || op == 75);
                float floatResult[4];
                long intResult[4];
                for (int row = 0; row < dim; ++row) {
                    if (isFloat) {
                        float sum = 0.0f;
                        for (int k = 0; k < dim; ++k)
                            sum += readMemFloat(mem, src + (k * dim + row) * 4, 4) *
                                   readMemFloat(mem, dst + k * 4, 4);
                        floatResult[row] = sum;
                    } else {
                        long sum = 0;
                        for (int k = 0; k < dim; ++k)
                            sum += readMemInt(mem, src + (k * dim + row) * 4, 4) *
                                   readMemInt(mem, dst + k * 4, 4);
                        intResult[row] = sum;
                    }
                }
                for (int row = 0; row < dim; ++row) {
                    if (isFloat) writeMemFloat(mem, dst + row * 4, 4, floatResult[row]);
                    else writeMemInt(mem, dst + row * 4, 4, intResult[row]);
                }
                break;
            }

            case 77: case 78: case 79: case 80: case 81: case 82: {
                dst += registerBase; src += registerBase;
                int dim = (op <= 78) ? 2 : ((op <= 80) ? 3 : 4);
                int isFloat = (op == 77 || op == 79 || op == 81);
                float floatResult[16];
                long intResult[16];
                for (int col = 0; col < dim; ++col) {
                    for (int row = 0; row < dim; ++row) {
                        if (isFloat) {
                            float sum = 0.0f;
                            for (int k = 0; k < dim; ++k)
                                sum += readMemFloat(mem, dst + (k * dim + row) * 4, 4) *
                                       readMemFloat(mem, src + (col * dim + k) * 4, 4);
                            floatResult[col * dim + row] = sum;
                        } else {
                            long sum = 0;
                            for (int k = 0; k < dim; ++k)
                                sum += readMemInt(mem, dst + (k * dim + row) * 4, 4) *
                                       readMemInt(mem, src + (col * dim + k) * 4, 4);
                            intResult[col * dim + row] = sum;
                        }
                    }
                }
                for (int i = 0; i < dim * dim; ++i) {
                    if (isFloat) writeMemFloat(mem, dst + i * 4, 4, floatResult[i]);
                    else writeMemInt(mem, dst + i * 4, 4, intResult[i]);
                }
                break;
            }

            case 83: case 84: case 85: case 86: case 87: case 88: {
                dst += registerBase; src += registerBase;
                int isFloat = ((op & 1) == 0);
                int count = size > 0 ? size : 1;
                for (int i = 0; i < count; ++i) {
                    if (isFloat) {
                        float value = readFloatWord(mem, (dst >> 2) + i);
                        float scalar = readFloatWord(mem, src >> 2);
                        if (op == 84) value += scalar;
                        else if (op == 86) value -= scalar;
                        else value *= scalar;
                        writeFloatWord(mem, (dst >> 2) + i, value);
                    } else {
                        long value = readMemInt(mem, dst + i * 4, 4);
                        long scalar = readMemInt(mem, src, 4);
                        if (op == 83) value += scalar;
                        else if (op == 85) value -= scalar;
                        else value *= scalar;
                        writeMemInt(mem, dst + i * 4, 4, value);
                    }
                }
                break;
            }

            case 89: {
                dst += registerBase; src += registerBase;
                int count = size > 2 ? size : 2;
                float sum = 0.0f;
                for (int i = 0; i < count; ++i) {
                    float value = readFloatWord(mem, (src >> 2) + i);
                    sum += value * value;
                }
                float length = sqrt(sum);
                float inverseLength = length > 1e-6f ? 1.0f / length : 0.0f;
                for (int i = 0; i < count; ++i)
                    writeFloatWord(mem, (dst >> 2) + i, readFloatWord(mem, (src >> 2) + i) * inverseLength);
                break;
            }

            case 90: case 91: case 102: {
                dst += registerBase; src += registerBase;
                int count = op == 90 ? 2 : (op == 91 ? 3 : 4);
                int rhs = size;
                float sum = 0.0f;
                for (int i = 0; i < count; ++i)
                    sum += readFloatWord(mem, (src >> 2) + i) * readFloatWord(mem, (rhs >> 2) + i);
                writeFloatWord(mem, dst >> 2, sum);
                break;
            }

            case 92: case 93: case 94: {
                dst += registerBase; src += registerBase;
                int dim = op == 92 ? 2 : (op == 93 ? 3 : 4);
                float result[16];
                for (int col = 0; col < dim; ++col)
                    for (int row = 0; row < dim; ++row)
                        result[col * dim + row] = readMemFloat(mem, src + (row * dim + col) * 4, 4);
                for (int i = 0; i < dim * dim; ++i) writeMemFloat(mem, dst + i * 4, 4, result[i]);
                break;
            }

            case 95: case 96: case 97: {
                dst += registerBase; src += registerBase;
                int dim = op == 95 ? 2 : (op == 96 ? 3 : 4);
                float matrix[4][8];
                for (int row = 0; row < dim; ++row) {
                    for (int col = 0; col < dim; ++col)
                        matrix[row][col] = readMemFloat(mem, src + (col * dim + row) * 4, 4);
                    for (int col = 0; col < dim; ++col) matrix[row][dim + col] = row == col ? 1.0f : 0.0f;
                }
                for (int col = 0; col < dim; ++col) {
                    int pivot = col;
                    for (int row = col + 1; row < dim; ++row)
                        if (fabs(matrix[row][col]) > fabs(matrix[pivot][col])) pivot = row;
                    if (fabs(matrix[pivot][col]) <= 1e-20f) {
                        for (int i = 0; i < dim * dim; ++i) writeMemFloat(mem, dst + i * 4, 4, 0.0f);
                        break;
                    }
                    if (pivot != col) for (int j = 0; j < dim * 2; ++j) {
                        float tmp = matrix[col][j]; matrix[col][j] = matrix[pivot][j]; matrix[pivot][j] = tmp;
                    }
                    float divisor = matrix[col][col];
                    for (int j = 0; j < dim * 2; ++j) matrix[col][j] /= divisor;
                    for (int row = 0; row < dim; ++row) if (row != col) {
                        float factor = matrix[row][col];
                        for (int j = 0; j < dim * 2; ++j) matrix[row][j] -= factor * matrix[col][j];
                    }
                }
                for (int col = 0; col < dim; ++col)
                    for (int row = 0; row < dim; ++row)
                        writeMemFloat(mem, dst + (col * dim + row) * 4, 4, matrix[row][dim + col]);
                break;
            }

            case 98: case 99: {
                dst += registerBase; src += registerBase;
                int count = op == 98 ? 2 : 3;
                float incident[3], normal[3], dot = 0.0f;
                for (int i = 0; i < count; ++i) {
                    incident[i] = readFloatWord(mem, (dst >> 2) + i);
                    normal[i] = readFloatWord(mem, (src >> 2) + i);
                    dot += incident[i] * normal[i];
                }
                for (int i = 0; i < count; ++i)
                    writeFloatWord(mem, (dst >> 2) + i, incident[i] - 2.0f * dot * normal[i]);
                break;
            }

            case 100: case 101: {
                dst += registerBase; src += registerBase;
                int count = size > 0 ? size : 1;
                if (op == 100) {
                    int exponent = (int)readMemInt(mem, src, 4);
                    for (int i = 0; i < count; ++i) {
                        long base = readMemInt(mem, dst + i * 4, 4), value = 1;
                        for (int p = 0; p < exponent; ++p) value *= base;
                        writeMemInt(mem, dst + i * 4, 4, value);
                    }
                } else {
                    float exponent = readFloatWord(mem, src >> 2);
                    for (int i = 0; i < count; ++i)
                        writeFloatWord(mem, (dst >> 2) + i, pow(readFloatWord(mem, (dst >> 2) + i), exponent));
                }
                break;
            }

            case 103: case 104: {
                dst += registerBase;
                int count = size > 0 ? size : 1;
                if (op == 103) {
                    for (int i = 0; i < count; ++i)
                        writeFloatWord(mem, (dst >> 2) + i, -readFloatWord(mem, (dst >> 2) + i));
                } else {
                    for (int i = 0; i < count; ++i)
                        writeMemInt(mem, dst + i * 4, 4, -readMemInt(mem, dst + i * 4, 4));
                }
                break;
            }

            case 105: case 106: { // vocFloorf / vocFractf, size is lane count
                dst += registerBase;
                src += registerBase;
                for (int i = 0; i < (size > 1 ? size : 1); ++i) {
                    int lane = (int)i * 4;
                    vm_float_t value = readMemFloat(mem, src + lane, 4);
                    writeMemFloat(mem, dst + lane, 4,
                        op == 105 ? floor(value) : value - floor(value));
                }
                break;
            }

            case 107: {
                dst += registerBase;
                src += registerBase;
                uint descriptor = program[pc++];
                int count = size;
                if (count < 1) count = 1;
                int edgeStep = 1;
                if ((descriptor & 0x100u) != 0u) edgeStep = 0;
                int dstWord = dst >> 2;
                int edgeWord = src >> 2;
                for (int lane = 0; lane < count; ++lane) {
                    int outWord = dstWord + lane;
                    float x = readFloatWord(mem, outWord);
                    float edge = readFloatWord(mem, edgeWord + lane * edgeStep);
                    float value = 1.0f;
                    if (x < edge) value = 0.0f;
                    writeFloatWord(mem, outWord, value);
                }
                break;
            }

            case 108: {
                dst += registerBase;
                src += registerBase;
                uint descriptor = program[pc++];
                int edge1Word = ((int)(descriptor & 0xFFu) + registerBase) >> 2;
                int edge0Step = 1, edge1Step = 1;
                if ((descriptor & 0x100u) != 0u) edge0Step = 0;
                if ((descriptor & 0x200u) != 0u) edge1Step = 0;
                int count = size;
                if (count < 1) count = 1;
                int dstWord = dst >> 2, edge0Word = src >> 2;
                for (int lane = 0; lane < count; ++lane) {
                    int outWord = dstWord + lane;
                    float x = readFloatWord(mem, outWord);
                    float edge0 = readFloatWord(mem, edge0Word + lane * edge0Step);
                    float edge1 = readFloatWord(mem, edge1Word + lane * edge1Step);
                    float t = clamp((x - edge0) / (edge1 - edge0), 0.0f, 1.0f);
                    writeFloatWord(mem, outWord, t * t * (3.0f - 2.0f * t));
                }
                break;
            }

            case 109: {
                dst += registerBase;
                src += registerBase;
                uint descriptor = program[pc++];
                int factorWord = ((int)(descriptor & 0xFFu) + registerBase) >> 2;
                int factorStep = 1;
                if ((descriptor & 0x100u) != 0u) factorStep = 0;
                int count = size;
                if (count < 1) count = 1;
                int dstWord = dst >> 2, srcWord = src >> 2;
                for (int lane = 0; lane < count; ++lane) {
                    int outWord = dstWord + lane;
                    float x = readFloatWord(mem, outWord);
                    float y = readFloatWord(mem, srcWord + lane);
                    float factor = readFloatWord(mem, factorWord + lane * factorStep);
                    writeFloatWord(mem, outWord, mix(x, y, factor));
                }
                break;
            }

            case 110: {
                dst += registerBase;
                src += registerBase;
                uint descriptor = program[pc++];
                int upperWord = ((int)(descriptor & 0xFFu) + registerBase) >> 2;
                int lowerStep = 1, upperStep = 1;
                if ((descriptor & 0x100u) != 0u) lowerStep = 0;
                if ((descriptor & 0x200u) != 0u) upperStep = 0;
                int count = size;
                if (count < 1) count = 1;
                int dstWord = dst >> 2, lowerWord = src >> 2;
                for (int lane = 0; lane < count; ++lane) {
                    int outWord = dstWord + lane;
                    float x = readFloatWord(mem, outWord);
                    float lower = readFloatWord(mem, lowerWord + lane * lowerStep);
                    float upper = readFloatWord(mem, upperWord + lane * upperStep);
                    writeFloatWord(mem, outWord, clamp(x, lower, upper));
                }
                break;
            }

            case 113: { // vocCross3
                dst += registerBase;
                src += registerBase;
                int dstWord = dst >> 2, srcWord = src >> 2;
                float ax = readFloatWord(mem, dstWord), ay = readFloatWord(mem, dstWord + 1), az = readFloatWord(mem, dstWord + 2);
                float bx = readFloatWord(mem, srcWord), by = readFloatWord(mem, srcWord + 1), bz = readFloatWord(mem, srcWord + 2);
                writeFloatWord(mem, dstWord, ay * bz - az * by);
                writeFloatWord(mem, dstWord + 1, az * bx - ax * bz);
                writeFloatWord(mem, dstWord + 2, ax * by - ay * bx);
                break;
            }

            case 114: { // vocLengthf
                dst += registerBase;
                src += registerBase;
                int srcWord = src >> 2;
                int count = size;
                if (count < 2) count = 2;
                float sum = 0.0f;
                for (int i = 0; i < count; ++i) {
                    float value = readFloatWord(mem, srcWord + i);
                    sum += value * value;
                }
                writeFloatWord(mem, dst >> 2, sqrt(sum));
                break;
            }

            case 115: { // vocRefractf
                dst += registerBase;
                src += registerBase;
                uint etaReg = (program[pc++] & 0xFFu) + (uint)registerBase;
                int dstWord = dst >> 2, srcWord = src >> 2;
                int count = size;
                if (count < 2) count = 2;
                float dotNI = 0.0f;
                for (int i = 0; i < count; ++i) {
                    dotNI += readFloatWord(mem, dstWord + i) * readFloatWord(mem, srcWord + i);
                }
                float eta = readFloatWord(mem, (int)etaReg >> 2);
                float k = 1.0f - eta * eta * (1.0f - dotNI * dotNI);
                for (int lane = 0; lane < count; ++lane) {
                    float incident = readFloatWord(mem, dstWord + lane);
                    float normal = readFloatWord(mem, srcWord + lane);
                    float value = 0.0f;
                    if (k >= 0.0f) value = eta * incident - (eta * dotNI + sqrt(k)) * normal;
                    writeFloatWord(mem, dstWord + lane, value);
                }
                break;
            }

            case 116: { // vocSampleLod: keep bytecode aligned; images are not bound by this VM API
                dst += registerBase;
                src += registerBase;
                uint descriptor = program[pc++];
                for (int lane = 0; lane < 16; ++lane) mem[dst + lane] = 0;
                break;
            }

            case 117: { // vocUnaryMathf; selector is the next word
                dst += registerBase;
                src += registerBase;
                uint selector = program[pc++];
                for (int i = 0; i < (size > 1 ? size : 1); ++i) {
                    int lane = (int)i * 4;
                    vm_float_t x = readMemFloat(mem, src + lane, 4);
                    vm_float_t y = x;
                    switch (selector) {
                    case 0: y = tan(x); break;
                    case 1: y = asin(x); break;
                    case 2: y = acos(x); break;
                    case 3: y = atan(x); break;
                    case 4: y = exp(x); break;
                    case 5: y = log(x); break;
                    case 6: y = exp2(x); break;
                    case 7: y = log2(x); break;
                    case 8: y = ceil(x); break;
                    case 9: y = trunc(x); break;
                    case 10: y = round(x); break;
                    case 11: y = x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0); break;
                    case 12: y = x * 0.017453292519943295; break;
                    case 13: y = x * 57.29577951308232; break;
                    case 14: y = sinh(x); break;
                    case 15: y = cosh(x); break;
                    case 16: y = tanh(x); break;
                    case 17: y = log(x + sqrt(x * x + 1.0)); break;
                    case 18: y = log(x + sqrt(x * x - 1.0)); break;
                    case 19: y = 0.5 * log((1.0 + x) / (1.0 - x)); break;
                    case 20: y = fabs(x); break;
                    case 21: y = rsqrt(x); break;
                    }
                    writeMemFloat(mem, dst + lane, 4, y);
                }
                break;
            }

            case 118: { // vocBinaryMathf; selector and optional broadcast flag
                dst += registerBase;
                src += registerBase;
                uint descriptor = program[pc++];
                uint selector = descriptor & 0xFFu;
                bool broadcast = (descriptor & 0x100u) != 0u;
                int srcStep = 1;
                if (broadcast) srcStep = 0;
                int count = size;
                if (count < 1) count = 1;
                int dstWord = dst >> 2, srcWord = src >> 2;
                for (int lane = 0; lane < count; ++lane) {
                    int outWord = dstWord + lane;
                    vm_float_t a = readFloatWord(mem, outWord);
                    vm_float_t b = readFloatWord(mem, srcWord + lane * srcStep);
                    vm_float_t y = a;
                    if (selector == 0) y = atan2(a, b);
                    else if (selector == 1) y = a - b * floor(a / b);
                    else if (selector == 2) y = fmin(a, b);
                    else if (selector == 3) y = fmax(a, b);
                    writeFloatWord(mem, outWord, y);
                }
                break;
            }

            case 119: { // vocFaceforward
                dst += registerBase;
                src += registerBase;
                uint normalReg = (program[pc++] & 0xFFu) + (uint)registerBase;
                vm_float_t d = 0.0;
                for (int i = 0; i < (size > 2 ? size : 2); ++i)
                    d += readMemFloat(mem, normalReg + (int)i * 4, 4) *
                         readMemFloat(mem, src + (int)i * 4, 4);
                vm_float_t factor = d < 0.0 ? 1.0 : -1.0;
                for (int i = 0; i < (size > 2 ? size : 2); ++i) {
                    int lane = (int)i * 4;
                    writeMemFloat(mem, dst + lane, 4, readMemFloat(mem, dst + lane, 4) * factor);
                }
                break;
            }

            case 120: { // vocMatrixCompMult
                dst += registerBase;
                src += registerBase;
                for (int i = 0; i < (size > 1 ? size : 1); ++i) {
                    int lane = (int)i * 4;
                    writeMemFloat(mem, dst + lane, 4,
                        readMemFloat(mem, dst + lane, 4) * readMemFloat(mem, src + lane, 4));
                }
                break;
            }

            case 121: { // vocDeterminantf
                dst += registerBase;
                src += registerBase;
                int dim = max(2, size);
                vm_float_t values[16];
                for (int i = 0; i < dim * dim; ++i) values[i] = readMemFloat(mem, src + i * 4, 4);
                vm_float_t det = 1.0;
                for (int col = 0; col < dim; ++col) {
                    int pivot = col;
                    for (int row = col + 1; row < dim; ++row)
                        if (fabs(values[row * dim + col]) > fabs(values[pivot * dim + col])) pivot = row;
                    if (fabs(values[pivot * dim + col]) <= 1e-20) { det = 0.0; break; }
                    if (pivot != col) {
                        for (int j = 0; j < dim; ++j) {
                            vm_float_t tmp = values[col * dim + j];
                            values[col * dim + j] = values[pivot * dim + j];
                            values[pivot * dim + j] = tmp;
                        }
                        det = -det;
                    }
                    vm_float_t diagonal = values[col * dim + col];
                    det *= diagonal;
                    for (int row = col + 1; row < dim; ++row) {
                        vm_float_t factor = values[row * dim + col] / diagonal;
                        for (int j = col + 1; j < dim; ++j)
                            values[row * dim + j] -= factor * values[col * dim + j];
                    }
                }
                writeMemFloat(mem, dst, 4, det);
                break;
            }

            default:
                break;
        }
    }
}
