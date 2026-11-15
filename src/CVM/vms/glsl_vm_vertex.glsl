#version 330 core

layout(location = 0) in uint inputs[32];
out vec4 varyingBlock[8];
uniform sampler2D uSamplers[8];

uniform uint uVertexBytecode[512];
uniform uint uVertexUniforms[256];

const int CVM_MEM_WORDS = 64; // 256-byte VM register file

uint cvmMem[CVM_MEM_WORDS];

float readFloatWord(uint wordIndex) {
    return uintBitsToFloat(cvmMem[int(wordIndex)]);
}

void writeFloatWord(uint wordIndex, float value) {
    cvmMem[int(wordIndex)] = floatBitsToUint(value);
}

float readFloat(uint byteAddress) {
    return readFloatWord(byteAddress >> 2);
}

void writeFloat(uint byteAddress, float value) {
    writeFloatWord(byteAddress >> 2, value);
}

void copyWords(uint dst, uint src, uint sizeBytes) {
    for (uint offset = 0u; offset < sizeBytes; offset += 4u) {
        cvmMem[int((dst + offset) >> 2)] = cvmMem[int((src + offset) >> 2)];
    }
}

uint readVertexInputByte(uint byteAddress) {
    uint word = inputs[int(byteAddress >> 2)];
    return (word >> ((byteAddress & 3u) * 8u)) & 255u;
}

void writeMemoryByte(uint byteAddress, uint value) {
    int wordIndex = int(byteAddress >> 2);
    uint shift = (byteAddress & 3u) * 8u;
    uint mask = 255u << shift;
    cvmMem[wordIndex] = (cvmMem[wordIndex] & ~mask) | ((value & 255u) << shift);
}

uint readMemoryByte(uint byteAddress) {
    return (cvmMem[int(byteAddress >> 2)] >> ((byteAddress & 3u) * 8u)) & 255u;
}

uint readScalarUnsigned(uint byteAddress, uint byteSize) {
    uint value = 0u;
    for (uint offset = 0u; offset < byteSize; ++offset) {
        value |= readMemoryByte(byteAddress + offset) << (offset * 8u);
    }
    return value;
}

int readScalarSigned(uint byteAddress, uint byteSize) {
    uint value = readScalarUnsigned(byteAddress, byteSize);
    if (byteSize < 4u) {
        uint shift = 32u - byteSize * 8u;
        return int(value << shift) >> int(shift);
    }
    return int(value);
}

void writeScalar(uint byteAddress, uint value, uint byteSize) {
    for (uint offset = 0u; offset < byteSize; ++offset) {
        writeMemoryByte(byteAddress + offset, value >> (offset * 8u));
    }
}

void writeVaryingByte(uint byteAddress, uint value) {
    int wordIndex = int(byteAddress >> 2);
    uint shift = (byteAddress & 3u) * 8u;
    int vectorIndex = wordIndex >> 2;
    int componentIndex = wordIndex & 3;
    uint word = floatBitsToUint(varyingBlock[vectorIndex][componentIndex]);
    uint mask = 255u << shift;
    word = (word & ~mask) | ((value & 255u) << shift);
    varyingBlock[vectorIndex][componentIndex] = uintBitsToFloat(word);
}

void main() {
    gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
    for (int i = 0; i < 8; ++i) {
        varyingBlock[i] = vec4(0.0);
    }

    int pc = int(uVertexBytecode[1]);
    bool halted = false;
    int callFrameBase = -1;
    uint registerBase = 0u;
    int stackBase = 0;
    uint cvmStack[256];
    int stackLen = 0;

    while (!halted) {
        uint word = uVertexBytecode[pc++];
        uint op = (word >> 16) & 255u;
        uint size = (word >> 24) & 255u;
        if (size == 0u && op != 20u) size = 1u;
        uint dst = (word >> 8) & 255u;
        uint src = word & 255u;
        int d = 0;
        int s = 0;

        switch (op) {
        case 0u: // halt
            halted = true;
            break;
        case 1u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size >> 2);
            for (uint i = 0u; i < count; ++i) cvmMem[d + int(i)] += cvmMem[s + int(i)];
            break;
        }
        case 2u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size >> 2);
            for (uint i = 0u; i < count; ++i) cvmMem[d + int(i)] -= cvmMem[s + int(i)];
            break;
        }
        case 3u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size >> 2);
            for (uint i = 0u; i < count; ++i) cvmMem[d + int(i)] *= cvmMem[s + int(i)];
            break;
        }
        case 4u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size >> 2);
            for (uint i = 0u; i < count; ++i) cvmMem[d + int(i)] = uint(int(cvmMem[d + int(i)]) / int(cvmMem[s + int(i)]));
            break;
        }
        case 6u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size >> 2);
            for (uint i = 0u; i < count; ++i) writeFloatWord(uint(d) + i, readFloatWord(uint(d) + i) + readFloatWord(uint(s) + i));
            break;
        }
        case 7u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size >> 2);
            for (uint i = 0u; i < count; ++i) writeFloatWord(uint(d) + i, readFloatWord(uint(d) + i) - readFloatWord(uint(s) + i));
            break;
        }
        case 8u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size >> 2);
            for (uint i = 0u; i < count; ++i) writeFloatWord(uint(d) + i, readFloatWord(uint(d) + i) * readFloatWord(uint(s) + i));
            break;
        }
        case 9u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size >> 2);
            for (uint i = 0u; i < count; ++i) writeFloatWord(uint(d) + i, readFloatWord(uint(d) + i) / readFloatWord(uint(s) + i));
            break;
        }
        case 10u: { // packed source and target VMConvType follow
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            {
                uint descriptor = uVertexBytecode[pc++];
                uint sourceType = descriptor & 255u;
                uint targetType = (descriptor >> 8) & 255u;
                uint sourceSize = sourceType >= 1u && sourceType <= 4u ? (1u << (sourceType - 1u)) :
                    (sourceType >= 5u && sourceType <= 8u ? (1u << (sourceType - 5u)) :
                    (sourceType == 9u ? 4u : (sourceType == 11u ? 1u : 0u)));
                uint targetSize = targetType >= 1u && targetType <= 4u ? (1u << (targetType - 1u)) :
                    (targetType >= 5u && targetType <= 8u ? (1u << (targetType - 5u)) :
                    (targetType == 9u ? 4u : (targetType == 11u ? 1u : 0u)));
                bool sourceFloat = sourceType == 9u;
                bool targetFloat = targetType == 9u;
                bool sourceUnsigned = (sourceType >= 5u && sourceType <= 8u) || sourceType == 11u;
                bool targetUnsigned = (targetType >= 5u && targetType <= 8u) || targetType == 11u;
                if (sourceSize > 0u && sourceSize <= 4u &&
                    targetSize > 0u && targetSize <= 4u) {
                    if (sourceFloat) {
                        float value = readFloat(src);
                        if (targetFloat) writeFloat(dst, value);
                        else if (targetType == 11u) writeScalar(dst, uint(value != 0.0), 1u);
                        else if (targetUnsigned) writeScalar(dst, uint(value), targetSize);
                        else writeScalar(dst, uint(int(value)), targetSize);
                    } else if (sourceUnsigned) {
                        uint value = readScalarUnsigned(src, sourceSize);
                        if (targetFloat) writeFloat(dst, float(value));
                        else if (targetType == 11u) writeScalar(dst, uint(value != 0u), 1u);
                        else writeScalar(dst, value, targetSize);
                    } else {
                        int value = readScalarSigned(src, sourceSize);
                        if (targetFloat) writeFloat(dst, float(value));
                        else if (targetType == 11u) writeScalar(dst, uint(value != 0), 1u);
                        else writeScalar(dst, uint(value), targetSize);
                    }
                }
            }
            break;
        }
        case 17u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); copyWords(dst, src, size); break; }
        case 15u: // push argument bytes
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            for (uint i = 0u; i < size && stackLen < 256; ++i) cvmStack[stackLen++] = readMemoryByte(dst + i);
            break;
        case 16u: { // pop bytes
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            int count = min(int(size), stackLen);
            for (int i = 0; i < count; ++i) writeMemoryByte(dst + uint(i), cvmStack[stackLen - count + i]);
            stackLen -= count;
            break;
        }
        case 20u: { // call
            src += registerBase;
            int target = int(uVertexBytecode[pc++]);
            uint frameInfo = uVertexBytecode[pc++];
            int argsBytes = int(frameInfo & 65535u);
            int frameBytes = int(frameInfo >> 16u);
            int argsBase = stackLen - argsBytes;
            uint calleeBase = registerBase + dst;
            int frameAt = stackLen;
            uint previousFrame = 65535u;
            if (callFrameBase >= 0) previousFrame = uint(callFrameBase);
            cvmStack[frameAt] = uint(pc);
            cvmStack[frameAt + 1] = registerBase | (uint(stackBase) << 16u);
            cvmStack[frameAt + 2] = previousFrame | (uint(argsBase) << 16u);
            cvmStack[frameAt + 3] = src | (size << 8u) | (calleeBase << 16u);
            stackLen += 16;
            callFrameBase = frameAt;
            registerBase = calleeBase;
            stackBase = argsBase;
            pc = target;
            break;
        }
        case 21u: { // ret
            if (callFrameBase >= 0) {
                uint returnPc = cvmStack[callFrameBase];
                uint parentBases = cvmStack[callFrameBase + 1];
                uint previousAndArgs = cvmStack[callFrameBase + 2];
                uint resultInfo = cvmStack[callFrameBase + 3];
                uint returnDst = resultInfo & 255u;
                uint returnSize = (resultInfo >> 8u) & 255u;
                uint calleeBase = resultInfo >> 16u;
                for (uint i = 0u; i < returnSize; ++i)
                    writeMemoryByte(returnDst + i, readMemoryByte(calleeBase + i));
                stackLen = int(previousAndArgs >> 16u);
                uint previousFrame = previousAndArgs & 65535u;
                callFrameBase = int(previousFrame);
                if (previousFrame == 65535u) callFrameBase = -1;
                registerBase = parentBases & 65535u;
                stackBase = int(parentBases >> 16u);
                pc = int(returnPc);
            } else halted = true;
            break;
        }
        case 22u: // jump
            pc = int(uVertexBytecode[pc]);
            break;
        case 23u: // jump if false
            {
            dst += registerBase; d = int(dst >> 2);
                uint target = uVertexBytecode[pc++];
                if (cvmMem[d] == 0u) pc = int(target);
            }
            break;
        case 24u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(-int(cvmMem[s])); break; }
        case 25u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, -readFloat(src)); break; }
        case 26u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(cvmMem[d] == cvmMem[s]); break; }
        case 27u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(cvmMem[d] != cvmMem[s]); break; }
        case 28u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(int(cvmMem[d]) < int(cvmMem[s])); break; }
        case 29u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(int(cvmMem[d]) <= int(cvmMem[s])); break; }
        case 30u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(readFloat(dst) == readFloat(src)); break; }
        case 31u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(readFloat(dst) != readFloat(src)); break; }
        case 32u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(readFloat(dst) < readFloat(src)); break; }
        case 33u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(readFloat(dst) <= readFloat(src)); break; }
        case 34u: // loadi
        case 35u: // loadf
        case 111u: // mov constant int
        case 112u: // mov constant float
            dst += registerBase; d = int(dst >> 2);
            cvmMem[d] = uVertexBytecode[pc++];
            break;
        case 36u: // copy stack argument bytes to a local register
            dst += registerBase; d = int(dst >> 2);
            for (uint offset = 0u; offset < size; ++offset)
                writeMemoryByte(dst + offset, cvmStack[stackBase + int(src) + int(offset)]);
            break;
        case 37u: // load bytes from the uint32 uniform table at src word offset
            if (src + (size + 3u) / 4u <= 256u) {
            dst += registerBase; d = int(dst >> 2);
                for (uint offset = 0u; offset < size; ++offset) {
                    uint value = uVertexUniforms[int(src) + int(offset >> 2)];
                    uint byteValue = (value >> ((offset & 3u) * 8u)) & 255u;
                    writeMemoryByte(dst + offset, byteValue);
                }
            }
            break;
        case 40u: { // indexed access to the VM's packed local register memory
            dst += registerBase;
            src += registerBase;
            uint indexReg = uVertexBytecode[pc++] + registerBase;
            int element = int(cvmMem[int(indexReg >> 2u)]) * int(size);
            int srcByte = int(src) + element;
            for (uint offset = 0u; offset < size; ++offset) {
                uint value = readMemoryByte(uint(srcByte) + offset);
                writeMemoryByte(dst + offset, value);
            }
            break;
        }
        case 41u: { // indexed write to the VM's packed local register memory
            dst += registerBase;
            src += registerBase;
            uint indexReg = uVertexBytecode[pc++] + registerBase;
            int element = int(cvmMem[int(indexReg >> 2u)]) * int(size);
            uint dstByte = uint(int(src) + element);
            for (uint offset = 0u; offset < size; ++offset) {
                uint value = readMemoryByte(dst + offset);
                writeMemoryByte(dstByte + offset, value);
            }
            break;
        }
        case 42u: { dst += registerBase; d = int(dst >> 2); cvmMem[d] = uint(gl_VertexID); break; }
        case 43u: { break; }
        case 44u: { // fused multiply-add
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            {
                uint packedSources = uVertexBytecode[pc++];
                uint rhs = (packedSources & 255u) + registerBase;
                uint addend = ((packedSources >> 8) & 255u) + registerBase;
                bool isVector = size > 4u;
                uint dstWord = uint(d);
                uint srcWord = uint(s);
                uint rhsWord = rhs >> 2u;
                uint addendWord = addend >> 2u;
                if (isVector) {
                    for (uint lane = 0u; lane < (size >> 2u); ++lane)
                        writeFloatWord(dstWord + lane, (readFloatWord(srcWord + lane) * readFloatWord(rhsWord + lane) + readFloatWord(addendWord + lane)));
                } else {
                    writeFloatWord(dstWord, (readFloatWord(srcWord) * readFloatWord(rhsWord) + readFloatWord(addendWord)));
                }
            }
            break;
        }
        case 45u: { // integer fused multiply-add
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            {
                uint packedSources = uVertexBytecode[pc++];
                uint rhs = (packedSources & 255u) + registerBase;
                uint addend = ((packedSources >> 8) & 255u) + registerBase;
                int product = int(cvmMem[int(src >> 2u)]) * int(cvmMem[int(rhs >> 2u)]);
                cvmMem[int(dst >> 2u)] = uint(product) + cvmMem[int(addend >> 2u)];
            }
            break;
        }
        case 46u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(abs(int(cvmMem[s]))); break; }
        case 47u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, abs(readFloat(src))); break; }
        case 48u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = cvmMem[s]; break; }
        case 49u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(min(int(cvmMem[d]), int(cvmMem[s]))); break; }
        case 50u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = uint(max(int(cvmMem[d]), int(cvmMem[s]))); break; }
        case 51u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, min(readFloat(dst), readFloat(src))); break; }
        case 52u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, max(readFloat(dst), readFloat(src))); break; }
        case 53u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = min(cvmMem[d], cvmMem[s]); break; }
        case 54u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); cvmMem[d] = max(cvmMem[d], cvmMem[s]); break; }
        case 55u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, sqrt(readFloat(src))); break; }
        case 56u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, inversesqrt(readFloat(src))); break; }
        case 57u:
        case 58u:
        case 59u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint imm = uVertexBytecode[pc++];
            if (op == 57u) cvmMem[d] += imm;
            else if (op == 58u) cvmMem[d] -= imm;
            else cvmMem[d] *= imm;
            break;
        }
        case 68u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, sin(readFloat(src))); break; }
        case 69u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, cos(readFloat(src))); break; }
        case 60u: // add constant float
        case 61u: // subtract constant float
        case 62u: // multiply by constant float
            {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
                float imm = uintBitsToFloat(uVertexBytecode[pc++]);
                if (op == 60u) writeFloat(dst, readFloat(dst) + imm);
                else if (op == 61u) writeFloat(dst, readFloat(dst) - imm);
                else writeFloat(dst, readFloat(dst) * imm);
            }
            break;
        case 63u: // packed vertex input block
            dst += registerBase; d = int(dst >> 2);
            for (uint offset = 0u; offset < size; ++offset) {
                writeMemoryByte(dst + offset, readVertexInputByte(src + offset));
            }
            break;
        case 65u: // vertex position output vec4
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            gl_Position = vec4(readFloat(dst), readFloat(dst + 4u),
                               readFloat(dst + 8u), readFloat(dst + 12u));
            break;
        case 66u: // store packed varying bytes at their generated block offset
            dst += registerBase; d = int(dst >> 2);
            for (uint offset = 0u; offset < size; ++offset) {
                writeVaryingByte(src + offset, readMemoryByte(dst + offset));
            }
            break;
        case 71u: { // vocMmatvec2f dstAndVec, mat
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat2 M = mat2(vec2(readFloat(src), readFloat(src + 4u)),
                          vec2(readFloat(src + 8u), readFloat(src + 12u)));
            vec2 v = vec2(readFloat(dst), readFloat(dst + 4u));
            vec2 res = M * v;
            writeFloat(dst, res.x);
            writeFloat(dst + 4u, res.y);
            break;
        }
        case 72u: { // vocMmatvec2i dstAndVec, mat
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            int vx = int(cvmMem[d]); int vy = int(cvmMem[d + 1]);
            cvmMem[d]     = uint(int(cvmMem[s]) * vx + int(cvmMem[s + 2]) * vy);
            cvmMem[d + 1] = uint(int(cvmMem[s + 1]) * vx + int(cvmMem[s + 3]) * vy);
            break;
        }
        case 73u: { // vocMmatvec3f dstAndVec, mat
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat3 M = mat3(vec3(readFloat(src), readFloat(src + 4u), readFloat(src + 8u)),
                          vec3(readFloat(src + 12u), readFloat(src + 16u), readFloat(src + 20u)),
                          vec3(readFloat(src + 24u), readFloat(src + 28u), readFloat(src + 32u)));
            vec3 v = vec3(readFloat(dst), readFloat(dst + 4u), readFloat(dst + 8u));
            vec3 res = M * v;
            writeFloat(dst, res.x);
            writeFloat(dst + 4u, res.y);
            writeFloat(dst + 8u, res.z);
            break;
        }
        case 74u: { // vocMmatvec3i dstAndVec, mat
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            int vx = int(cvmMem[d]); int vy = int(cvmMem[d + 1]); int vz = int(cvmMem[d + 2]);
            cvmMem[d]     = uint(int(cvmMem[s]) * vx + int(cvmMem[s + 3]) * vy + int(cvmMem[s + 6]) * vz);
            cvmMem[d + 1] = uint(int(cvmMem[s + 1]) * vx + int(cvmMem[s + 4]) * vy + int(cvmMem[s + 7]) * vz);
            cvmMem[d + 2] = uint(int(cvmMem[s + 2]) * vx + int(cvmMem[s + 5]) * vy + int(cvmMem[s + 8]) * vz);
            break;
        }
        case 75u: { // vocMmatvec4f dstAndVec, mat
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat4 M = mat4(vec4(readFloat(src), readFloat(src + 4u), readFloat(src + 8u), readFloat(src + 12u)),
                          vec4(readFloat(src + 16u), readFloat(src + 20u), readFloat(src + 24u), readFloat(src + 28u)),
                          vec4(readFloat(src + 32u), readFloat(src + 36u), readFloat(src + 40u), readFloat(src + 44u)),
                          vec4(readFloat(src + 48u), readFloat(src + 52u), readFloat(src + 56u), readFloat(src + 60u)));
            vec4 v = vec4(readFloat(dst), readFloat(dst + 4u), readFloat(dst + 8u), readFloat(dst + 12u));
            vec4 res = M * v;
            writeFloat(dst, res.x);
            writeFloat(dst + 4u, res.y);
            writeFloat(dst + 8u, res.z);
            writeFloat(dst + 12u, res.w);
            break;
        }
        case 76u: { // vocMmatvec4i dstAndVec, mat
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            int vx = int(cvmMem[d]); int vy = int(cvmMem[d + 1]); int vz = int(cvmMem[d + 2]); int vw = int(cvmMem[d + 3]);
            cvmMem[d]     = uint(int(cvmMem[s]) * vx + int(cvmMem[s + 4]) * vy + int(cvmMem[s + 8]) * vz + int(cvmMem[s + 12]) * vw);
            cvmMem[d + 1] = uint(int(cvmMem[s + 1]) * vx + int(cvmMem[s + 5]) * vy + int(cvmMem[s + 9]) * vz + int(cvmMem[s + 13]) * vw);
            cvmMem[d + 2] = uint(int(cvmMem[s + 2]) * vx + int(cvmMem[s + 6]) * vy + int(cvmMem[s + 10]) * vz + int(cvmMem[s + 14]) * vw);
            cvmMem[d + 3] = uint(int(cvmMem[s + 3]) * vx + int(cvmMem[s + 7]) * vy + int(cvmMem[s + 11]) * vz + int(cvmMem[s + 15]) * vw);
            break;
        }
        case 77u: { // vocMmat2f
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat2 A = mat2(vec2(readFloat(dst), readFloat(dst + 4u)),
                          vec2(readFloat(dst + 8u), readFloat(dst + 12u)));
            mat2 B = mat2(vec2(readFloat(src), readFloat(src + 4u)),
                          vec2(readFloat(src + 8u), readFloat(src + 12u)));
            mat2 R = A * B;
            for (int col = 0; col < 2; ++col) {
                for (int row = 0; row < 2; ++row) writeFloat(dst + uint((col * 2 + row) * 4), R[col][row]);
            }
            break;
        }
        case 78u: { // vocMmat2i
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            int a[4], b[4], r[4];
            for (int i = 0; i < 4; ++i) { a[i] = int(cvmMem[d + i]); b[i] = int(cvmMem[s + i]); }
            for (int c = 0; c < 2; ++c) for (int row = 0; row < 2; ++row) {
                int sum = 0;
                for (int k = 0; k < 2; ++k) sum += a[k * 2 + row] * b[c * 2 + k];
                r[c * 2 + row] = sum;
            }
            for (int i = 0; i < 4; ++i) cvmMem[d + i] = uint(r[i]);
            break;
        }
        case 79u: { // vocMmat3f
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat3 A = mat3(vec3(readFloat(dst), readFloat(dst + 4u), readFloat(dst + 8u)),
                          vec3(readFloat(dst + 12u), readFloat(dst + 16u), readFloat(dst + 20u)),
                          vec3(readFloat(dst + 24u), readFloat(dst + 28u), readFloat(dst + 32u)));
            mat3 B = mat3(vec3(readFloat(src), readFloat(src + 4u), readFloat(src + 8u)),
                          vec3(readFloat(src + 12u), readFloat(src + 16u), readFloat(src + 20u)),
                          vec3(readFloat(src + 24u), readFloat(src + 28u), readFloat(src + 32u)));
            mat3 R = A * B;
            for (int col = 0; col < 3; ++col) {
                for (int row = 0; row < 3; ++row) writeFloat(dst + uint((col * 3 + row) * 4), R[col][row]);
            }
            break;
        }
        case 80u: { // vocMmat3i
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            int a[9], b[9], r[9];
            for (int i = 0; i < 9; ++i) { a[i] = int(cvmMem[d + i]); b[i] = int(cvmMem[s + i]); }
            for (int c = 0; c < 3; ++c) for (int row = 0; row < 3; ++row) {
                int sum = 0;
                for (int k = 0; k < 3; ++k) sum += a[k * 3 + row] * b[c * 3 + k];
                r[c * 3 + row] = sum;
            }
            for (int i = 0; i < 9; ++i) cvmMem[d + i] = uint(r[i]);
            break;
        }
        case 81u: { // vocMmat4f
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat4 A = mat4(vec4(readFloat(dst), readFloat(dst + 4u), readFloat(dst + 8u), readFloat(dst + 12u)),
                          vec4(readFloat(dst + 16u), readFloat(dst + 20u), readFloat(dst + 24u), readFloat(dst + 28u)),
                          vec4(readFloat(dst + 32u), readFloat(dst + 36u), readFloat(dst + 40u), readFloat(dst + 44u)),
                          vec4(readFloat(dst + 48u), readFloat(dst + 52u), readFloat(dst + 56u), readFloat(dst + 60u)));
            mat4 B = mat4(vec4(readFloat(src), readFloat(src + 4u), readFloat(src + 8u), readFloat(src + 12u)),
                          vec4(readFloat(src + 16u), readFloat(src + 20u), readFloat(src + 24u), readFloat(src + 28u)),
                          vec4(readFloat(src + 32u), readFloat(src + 36u), readFloat(src + 40u), readFloat(src + 44u)),
                          vec4(readFloat(src + 48u), readFloat(src + 52u), readFloat(src + 56u), readFloat(src + 60u)));
            mat4 R = A * B;
            for (int col = 0; col < 4; ++col) {
                for (int row = 0; row < 4; ++row) writeFloat(dst + uint((col * 4 + row) * 4), R[col][row]);
            }
            break;
        }
        case 82u: { // vocMmat4i
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            int a[16], b[16], r[16];
            for (int i = 0; i < 16; ++i) { a[i] = int(cvmMem[d + i]); b[i] = int(cvmMem[s + i]); }
            for (int c = 0; c < 4; ++c) for (int row = 0; row < 4; ++row) {
                int sum = 0;
                for (int k = 0; k < 4; ++k) sum += a[k * 4 + row] * b[c * 4 + k];
                r[c * 4 + row] = sum;
            }
            for (int i = 0; i < 16; ++i) cvmMem[d + i] = uint(r[i]);
            break;
        }
        case 83u: { // vocVecAddi.N
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            int sVal = int(cvmMem[s]);
            for (uint i = 0u; i < count; ++i) cvmMem[d + int(i)] = uint(int(cvmMem[d + int(i)]) + sVal);
            break;
        }
        case 84u: { // vocVecAddf.N
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            float sVal = readFloat(src);
            for (uint i = 0u; i < count; ++i) writeFloat(dst + (i << 2), readFloat(dst + (i << 2)) + sVal);
            break;
        }
        case 85u: { // vocVecSubi.N
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            int sVal = int(cvmMem[s]);
            for (uint i = 0u; i < count; ++i) cvmMem[d + int(i)] = uint(int(cvmMem[d + int(i)]) - sVal);
            break;
        }
        case 86u: { // vocVecSubf.N
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            float sVal = readFloat(src);
            for (uint i = 0u; i < count; ++i) writeFloat(dst + (i << 2), readFloat(dst + (i << 2)) - sVal);
            break;
        }
        case 87u: { // vocVecMuli.N
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            int sVal = int(cvmMem[s]);
            for (uint i = 0u; i < count; ++i) cvmMem[d + int(i)] = uint(int(cvmMem[d + int(i)]) * sVal);
            break;
        }
        case 88u: { // vocVecMulf.N
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            float sVal = readFloat(src);
            for (uint i = 0u; i < count; ++i) writeFloat(dst + (i << 2), readFloat(dst + (i << 2)) * sVal);
            break;
        }
        case 89u: { // vocNormalize.N dst, src
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint dim = max(2u, size);
            if (dim == 2u) {
                vec2 v = vec2(readFloat(src), readFloat(src + 4u));
                vec2 r = length(v) > 0.0 ? normalize(v) : vec2(0.0);
                writeFloat(dst, r.x); writeFloat(dst + 4u, r.y);
            } else if (dim == 3u) {
                vec3 v = vec3(readFloat(src), readFloat(src + 4u), readFloat(src + 8u));
                vec3 r = length(v) > 0.0 ? normalize(v) : vec3(0.0);
                writeFloat(dst, r.x); writeFloat(dst + 4u, r.y); writeFloat(dst + 8u, r.z);
            } else {
                vec4 v = vec4(readFloat(src), readFloat(src + 4u), readFloat(src + 8u), readFloat(src + 12u));
                vec4 r = length(v) > 0.0 ? normalize(v) : vec4(0.0);
                writeFloat(dst, r.x); writeFloat(dst + 4u, r.y); writeFloat(dst + 8u, r.z); writeFloat(dst + 12u, r.w);
            }
            break;
        }
        case 90u: { // vocDot2 dst, src, size (regB)
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            vec2 a = vec2(readFloat(src), readFloat(src + 4u));
            vec2 b = vec2(readFloat(size), readFloat(size + 4u));
            writeFloat(dst, dot(a, b));
            break;
        }
        case 91u: { // vocDot3 dst, src, size (regB)
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            vec3 a = vec3(readFloat(src), readFloat(src + 4u), readFloat(src + 8u));
            vec3 b = vec3(readFloat(size), readFloat(size + 4u), readFloat(size + 8u));
            writeFloat(dst, dot(a, b));
            break;
        }
        case 102u: { // vocDot4 dst, src, size (regB)
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            vec4 a = vec4(readFloat(src), readFloat(src + 4u), readFloat(src + 8u), readFloat(src + 12u));
            vec4 b = vec4(readFloat(size), readFloat(size + 4u), readFloat(size + 8u), readFloat(size + 12u));
            writeFloat(dst, dot(a, b));
            break;
        }
        case 92u: { // vocTranspose2
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat2 M = mat2(vec2(readFloat(src), readFloat(src + 4u)), vec2(readFloat(src + 8u), readFloat(src + 12u)));
            mat2 R = transpose(M);
            for (int c = 0; c < 2; ++c) {
                for (int r = 0; r < 2; ++r) writeFloat(dst + uint((c * 2 + r) * 4), R[c][r]);
            }
            break;
        }
        case 93u: { // vocTranspose3
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat3 M = mat3(vec3(readFloat(src), readFloat(src + 4u), readFloat(src + 8u)),
                          vec3(readFloat(src + 12u), readFloat(src + 16u), readFloat(src + 20u)),
                          vec3(readFloat(src + 24u), readFloat(src + 28u), readFloat(src + 32u)));
            mat3 R = transpose(M);
            for (int c = 0; c < 3; ++c) {
                for (int r = 0; r < 3; ++r) writeFloat(dst + uint((c * 3 + r) * 4), R[c][r]);
            }
            break;
        }
        case 94u: { // vocTranspose4
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat4 M = mat4(vec4(readFloat(src), readFloat(src + 4u), readFloat(src + 8u), readFloat(src + 12u)),
                          vec4(readFloat(src + 16u), readFloat(src + 20u), readFloat(src + 24u), readFloat(src + 28u)),
                          vec4(readFloat(src + 32u), readFloat(src + 36u), readFloat(src + 40u), readFloat(src + 44u)),
                          vec4(readFloat(src + 48u), readFloat(src + 52u), readFloat(src + 56u), readFloat(src + 60u)));
            mat4 R = transpose(M);
            for (int c = 0; c < 4; ++c) {
                for (int r = 0; r < 4; ++r) writeFloat(dst + uint((c * 4 + r) * 4), R[c][r]);
            }
            break;
        }
        case 95u: { // vocInvert2
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat2 M = mat2(vec2(readFloat(src), readFloat(src + 4u)), vec2(readFloat(src + 8u), readFloat(src + 12u)));
            mat2 R = inverse(M);
            for (int c = 0; c < 2; ++c) {
                for (int r = 0; r < 2; ++r) writeFloat(dst + uint((c * 2 + r) * 4), R[c][r]);
            }
            break;
        }
        case 96u: { // vocInvert3
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat3 M = mat3(vec3(readFloat(src), readFloat(src + 4u), readFloat(src + 8u)),
                          vec3(readFloat(src + 12u), readFloat(src + 16u), readFloat(src + 20u)),
                          vec3(readFloat(src + 24u), readFloat(src + 28u), readFloat(src + 32u)));
            mat3 R = inverse(M);
            for (int c = 0; c < 3; ++c) {
                for (int r = 0; r < 3; ++r) writeFloat(dst + uint((c * 3 + r) * 4), R[c][r]);
            }
            break;
        }
        case 97u: { // vocInvert4
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            mat4 M = mat4(vec4(readFloat(src), readFloat(src + 4u), readFloat(src + 8u), readFloat(src + 12u)),
                          vec4(readFloat(src + 16u), readFloat(src + 20u), readFloat(src + 24u), readFloat(src + 28u)),
                          vec4(readFloat(src + 32u), readFloat(src + 36u), readFloat(src + 40u), readFloat(src + 44u)),
                          vec4(readFloat(src + 48u), readFloat(src + 52u), readFloat(src + 56u), readFloat(src + 60u)));
            mat4 R = inverse(M);
            for (int c = 0; c < 4; ++c) {
                for (int r = 0; r < 4; ++r) writeFloat(dst + uint((c * 4 + r) * 4), R[c][r]);
            }
            break;
        }
        case 98u: { // vocReflect2 dst, src (I), size (N)
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            vec2 I = vec2(readFloat(dst), readFloat(dst + 4u));
            vec2 N = vec2(readFloat(src), readFloat(src + 4u));
            vec2 R = reflect(I, N);
            writeFloat(dst, R.x);
            writeFloat(dst + 4u, R.y);
            break;
        }
        case 99u: { // vocReflect3 dst, src (I), size (N)
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            vec3 I = vec3(readFloat(dst), readFloat(dst + 4u), readFloat(dst + 8u));
            vec3 N = vec3(readFloat(src), readFloat(src + 4u), readFloat(src + 8u));
            vec3 R = reflect(I, N);
            writeFloat(dst, R.x);
            writeFloat(dst + 4u, R.y);
            writeFloat(dst + 8u, R.z);
            break;
        }
        case 100u: { // vocPowi.N dst, val
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            int expVal = int(cvmMem[s]);
            for (uint i = 0u; i < count; ++i) {
                int baseVal = int(cvmMem[d + int(i)]);
                int r = 1;
                for (int p = 0; p < expVal; ++p) r *= baseVal;
                cvmMem[d + int(i)] = uint(r);
            }
            break;
        }
        case 101u: { // vocPowf.N dst, val
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            float expVal = readFloat(src);
            for (uint i = 0u; i < count; ++i) {
                float baseVal = readFloat(dst + (i << 2));
                writeFloat(dst + (i << 2), pow(baseVal, expVal));
            }
            break;
        }
        case 103u: { // vocVecNegf.N
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            for (uint i = 0u; i < count; ++i) {
                writeFloat(dst + (i << 2), -readFloat(dst + (i << 2)));
            }
            break;
        }
        case 104u: { // vocVecNegi.N
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            for (uint i = 0u; i < count; ++i) {
                int address = d + int(i);
                cvmMem[address] = uint(-int(cvmMem[address]));
            }
            break;
        }
        case 105u:
        case 106u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint count = max(1u, size);
            for (uint i = 0u; i < count; ++i) {
                uint address = dst + (i << 2);
                float value = readFloat(src + (i << 2));
                writeFloat(address, op == 105u ? floor(value) : fract(value));
            }
            break;
        }
        case 107u: { // step: precompute lane bases and broadcast stride once
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint descriptor = uVertexBytecode[pc++];
            bool edgeBroadcast = (descriptor & 0x100u) != 0u;
            uint edgeStep = 1u;
            if (edgeBroadcast) edgeStep = 0u;
            uint dstWord = uint(d), edgeWord = uint(s);
            uint count = max(1u, size);
            for (uint i = 0u; i < count; ++i) {
                uint outWord = dstWord + i;
                float x = readFloatWord(outWord);
                float edge = readFloatWord(edgeWord + i * edgeStep);
                float value = 1.0;
                if (x < edge) value = 0.0;
                writeFloatWord(outWord, value);
            }
            break;
        }
        case 108u: { // smoothstep
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint descriptor = uVertexBytecode[pc++];
            uint edge1Word = ((descriptor & 0xFFu) + registerBase) >> 2u;
            bool edge0Broadcast = (descriptor & 0x100u) != 0u;
            bool edge1Broadcast = (descriptor & 0x200u) != 0u;
            uint edge0Step = 1u, edge1Step = 1u;
            if (edge0Broadcast) edge0Step = 0u;
            if (edge1Broadcast) edge1Step = 0u;
            uint dstWord = uint(d), edge0Word = uint(s);
            uint count = max(1u, size);
            for (uint i = 0u; i < count; ++i) {
                uint outWord = dstWord + i;
                float x = readFloatWord(outWord);
                float e0 = readFloatWord(edge0Word + i * edge0Step);
                float e1 = readFloatWord(edge1Word + i * edge1Step);
                float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
                writeFloatWord(outWord, t * t * (3.0 - 2.0 * t));
            }
            break;
        }
        case 109u: { // mix
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint descriptor = uVertexBytecode[pc++];
            uint factorWord = ((descriptor & 0xFFu) + registerBase) >> 2u;
            bool factorBroadcast = (descriptor & 0x100u) != 0u;
            uint factorStep = 1u;
            if (factorBroadcast) factorStep = 0u;
            uint dstWord = uint(d), srcWord = uint(s);
            uint count = max(1u, size);
            for (uint i = 0u; i < count; ++i) {
                uint outWord = dstWord + i;
                float x = readFloatWord(outWord);
                float y = readFloatWord(srcWord + i);
                float a = readFloatWord(factorWord + i * factorStep);
                writeFloatWord(outWord, mix(x, y, a));
            }
            break;
        }
        case 110u: { // clamp
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint descriptor = uVertexBytecode[pc++];
            uint upperWord = ((descriptor & 0xFFu) + registerBase) >> 2u;
            bool lowerBroadcast = (descriptor & 0x100u) != 0u;
            bool upperBroadcast = (descriptor & 0x200u) != 0u;
            uint lowerStep = 1u, upperStep = 1u;
            if (lowerBroadcast) lowerStep = 0u;
            if (upperBroadcast) upperStep = 0u;
            uint dstWord = uint(d), lowerWord = uint(s);
            uint count = max(1u, size);
            for (uint i = 0u; i < count; ++i) {
                uint outWord = dstWord + i;
                float x = readFloatWord(outWord);
                float lo = readFloatWord(lowerWord + i * lowerStep);
                float hi = readFloatWord(upperWord + i * upperStep);
                writeFloatWord(outWord, clamp(x, lo, hi));
            }
            break;
        }
        case 113u: { // cross3
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint dstWord = uint(d), srcWord = uint(s);
            float ax = readFloatWord(dstWord), ay = readFloatWord(dstWord + 1u), az = readFloatWord(dstWord + 2u);
            float bx = readFloatWord(srcWord), by = readFloatWord(srcWord + 1u), bz = readFloatWord(srcWord + 2u);
            writeFloatWord(dstWord, ay * bz - az * by);
            writeFloatWord(dstWord + 1u, az * bx - ax * bz);
            writeFloatWord(dstWord + 2u, ax * by - ay * bx);
            break;
        }
        case 114u: { // length
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint srcWord = uint(s);
            float sum = 0.0;
            for (uint i = 0u; i < max(2u, size); ++i) {
                float value = readFloatWord(srcWord + i);
                sum += value * value;
            }
            writeFloatWord(uint(d), sqrt(sum));
            break;
        }
        case 115u: { // refract
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint etaWord = ((uVertexBytecode[pc++] & 0xFFu) + registerBase) >> 2u;
            uint dstWord = uint(d), srcWord = uint(s);
            float dotNI = 0.0;
            for (uint i = 0u; i < max(2u, size); ++i)
                dotNI += readFloatWord(dstWord + i) * readFloatWord(srcWord + i);
            float eta = readFloatWord(etaWord);
            float k = 1.0 - eta * eta * (1.0 - dotNI * dotNI);
            for (uint lane = 0u; lane < max(2u, size); ++lane) {
                float incident = readFloatWord(dstWord + lane);
                float normal = readFloatWord(srcWord + lane);
                float value = 0.0;
                if (k >= 0.0) value = eta * incident - (eta * dotNI + sqrt(k)) * normal;
                writeFloatWord(dstWord + lane, value);
            }
            break;
        }
        case 116u: { // vocSampleLod: explicit-mip texture sample
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint descriptor = uVertexBytecode[pc++];
            uint texId = descriptor & 0xFFu;
            uint lodReg = ((descriptor >> 8u) & 0xFFu) + registerBase;
            vec2 uv = vec2(readFloat(src), readFloat(src + 4u));
            float lod = readFloat(lodReg);
            vec4 texColor = vec4(0.0);
            switch (texId) {
            case 0u: texColor = textureLod(uSamplers[0], uv, lod); break;
            case 1u: texColor = textureLod(uSamplers[1], uv, lod); break;
            case 2u: texColor = textureLod(uSamplers[2], uv, lod); break;
            case 3u: texColor = textureLod(uSamplers[3], uv, lod); break;
            case 4u: texColor = textureLod(uSamplers[4], uv, lod); break;
            case 5u: texColor = textureLod(uSamplers[5], uv, lod); break;
            case 6u: texColor = textureLod(uSamplers[6], uv, lod); break;
            case 7u: texColor = textureLod(uSamplers[7], uv, lod); break;
            default: break;
            }
            writeFloat(dst, texColor.r); writeFloat(dst + 4u, texColor.g);
            writeFloat(dst + 8u, texColor.b); writeFloat(dst + 12u, texColor.a);
            break;
        }
        case 117u: { // vocUnaryMathf; next word selects the operation
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint selector = uVertexBytecode[pc++];
            uint srcWord = uint(s), dstWord = uint(d);
            for (uint i = 0u; i < max(1u, size); ++i) {
                float x = readFloatWord(srcWord + i);
                float y = x;
                switch (selector) {
                case 0u: y = tan(x); break;
                case 1u: y = asin(x); break;
                case 2u: y = acos(x); break;
                case 3u: y = atan(x); break;
                case 4u: y = exp(x); break;
                case 5u: y = log(x); break;
                case 6u: y = exp2(x); break;
                case 7u: y = log2(x); break;
                case 8u: y = ceil(x); break;
                case 9u: y = trunc(x); break;
                case 10u: y = round(x); break;
                case 11u: y = sign(x); break;
                case 12u: y = radians(x); break;
                case 13u: y = degrees(x); break;
                case 14u: y = (exp(x) - exp(-x)) * 0.5; break;
                case 15u: y = (exp(x) + exp(-x)) * 0.5; break;
                case 16u: y = (exp(2.0 * x) - 1.0) / (exp(2.0 * x) + 1.0); break;
                case 17u: y = log(x + sqrt(x * x + 1.0)); break;
                case 18u: y = log(x + sqrt(x * x - 1.0)); break;
                case 19u: y = 0.5 * log((1.0 + x) / (1.0 - x)); break;
                case 20u: y = abs(x); break;
                case 21u: y = inversesqrt(x); break;
                default: break;
                }
                writeFloatWord(dstWord + i, y);
            }
            break;
        }
        case 118u: { // vocBinaryMathf; selector 0=atan(y,x), 1=mod(x,y)
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint descriptor = uVertexBytecode[pc++];
            uint selector = descriptor & 0xFFu;
            bool broadcast = (descriptor & 0x100u) != 0u;
            uint srcStep = 1u;
            if (broadcast) srcStep = 0u;
            uint srcWord = uint(s), dstWord = uint(d);
            for (uint i = 0u; i < max(1u, size); ++i) {
                uint outWord = dstWord + i;
                float a = readFloatWord(outWord);
                float b = readFloatWord(srcWord + i * srcStep);
                float value = a;
                if (selector == 0u) value = atan(a, b);
                else if (selector == 1u) value = mod(a, b);
                else if (selector == 2u) value = min(a, b);
                else if (selector == 3u) value = max(a, b);
                writeFloatWord(outWord, value);
            }
            break;
        }
        case 119u: { // vocFaceforward
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint normalReg = (uVertexBytecode[pc++] & 0xFFu) + registerBase;
            float d = 0.0;
            for (uint i = 0u; i < max(2u, size); ++i)
                d += readFloat(normalReg + (i << 2)) * readFloat(src + (i << 2));
            float factor = d < 0.0 ? 1.0 : -1.0;
            for (uint i = 0u; i < max(2u, size); ++i) {
                uint lane = i << 2;
                writeFloat(dst + lane, readFloat(dst + lane) * factor);
            }
            break;
        }
        case 120u: { // vocMatrixCompMult
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            for (uint i = 0u; i < max(1u, size); ++i) {
                uint lane = i << 2;
                writeFloat(dst + lane, readFloat(dst + lane) * readFloat(src + lane));
            }
            break;
        }
        case 121u: { // vocDeterminantf
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            int dim = int(max(2u, size));
            float values[16];
            for (int i = 0; i < dim * dim; ++i) values[i] = readFloat(src + uint(i * 4));
            float det = 1.0;
            for (int col = 0; col < dim; ++col) {
                int pivot = col;
                for (int row = col + 1; row < dim; ++row)
                    if (abs(values[row * dim + col]) > abs(values[pivot * dim + col])) pivot = row;
                if (abs(values[pivot * dim + col]) <= 1e-20) { det = 0.0; break; }
                if (pivot != col) {
                    for (int j = 0; j < dim; ++j) {
                        float tmp = values[col * dim + j];
                        values[col * dim + j] = values[pivot * dim + j];
                        values[pivot * dim + j] = tmp;
                    }
                    det = -det;
                }
                float diagonal = values[col * dim + col];
                det *= diagonal;
                for (int row = col + 1; row < dim; ++row) {
                    float factor = values[row * dim + col] / diagonal;
                    for (int j = col + 1; j < dim; ++j)
                        values[row * dim + j] -= factor * values[col * dim + j];
                }
            }
            writeFloat(dst, det);
            break;
        }
        default: break;
        }
    }
}
