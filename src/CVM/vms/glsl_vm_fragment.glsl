#version 330 core

in vec4 varyingBlock[8];
layout(location = 0) out vec4 cvmFragmentColor;

uniform uint uFragmentBytecode[512];
uniform uint uFragmentUniforms[256];
uniform sampler2D uSamplers[8];

const int CVM_MEM_WORDS = 64;
const int CVM_STACK_WORDS = 16;

uint cvmMem[CVM_MEM_WORDS];
uint cvmStack[CVM_STACK_WORDS];

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

void writeMemoryByte(uint byteAddress, uint value) {
    int wordIndex = int(byteAddress >> 2);
    uint shift = (byteAddress & 3u) * 8u;
    cvmMem[wordIndex] = (cvmMem[wordIndex] & ~(255u << shift)) | ((value & 255u) << shift);
}

void writeStackByte(uint byteAddress, uint value) {
    uint shift = (byteAddress & 3u) * 8u;
    uint mask = 255u << shift;
    cvmStack[byteAddress >> 2u] = (cvmStack[byteAddress >> 2u] & ~mask) | ((value & 255u) << shift);
}

uint readStackByte(uint byteAddress) {
    return (cvmStack[byteAddress >> 2u] >> ((byteAddress & 3u) * 8u)) & 255u;
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

uint readVaryingByte(uint byteAddress) {
    int vectorIndex = int(byteAddress >> 4u);
    int componentIndex = int((byteAddress >> 2u) & 3u);
    uint word = floatBitsToUint(varyingBlock[vectorIndex][componentIndex]);
    return (word >> ((byteAddress & 3u) * 8u)) & 255u;
}

void copyWords(uint dst, uint src, uint sizeBytes) {
    for (uint offset = 0u; offset < sizeBytes; offset += 4u) {
        cvmMem[int((dst + offset) >> 2)] = cvmMem[int((src + offset) >> 2)];
    }
}

vec2 readVec2(uint a) { return vec2(readFloat(a), readFloat(a + 4u)); }
vec3 readVec3(uint a) { return vec3(readFloat(a), readFloat(a + 4u), readFloat(a + 8u)); }
vec4 readVec4(uint a) { return vec4(readFloat(a), readFloat(a + 4u), readFloat(a + 8u), readFloat(a + 12u)); }
void writeVec2(uint a, vec2 v) { writeFloat(a, v.x); writeFloat(a + 4u, v.y); }
void writeVec3(uint a, vec3 v) { writeFloat(a, v.x); writeFloat(a + 4u, v.y); writeFloat(a + 8u, v.z); }
void writeVec4(uint a, vec4 v) { writeFloat(a, v.x); writeFloat(a + 4u, v.y); writeFloat(a + 8u, v.z); writeFloat(a + 12u, v.w); }
mat2 readMat2(uint a) { return mat2(readVec2(a), readVec2(a + 8u)); }
mat3 readMat3(uint a) { return mat3(readVec3(a), readVec3(a + 12u), readVec3(a + 24u)); }
mat4 readMat4(uint a) { return mat4(readVec4(a), readVec4(a + 16u), readVec4(a + 32u), readVec4(a + 48u)); }
void writeMat2(uint a, mat2 m) { for (int i = 0; i < 4; ++i) writeFloat(a + uint(i * 4), m[i / 2][i % 2]); }
void writeMat3(uint a, mat3 m) { for (int i = 0; i < 9; ++i) writeFloat(a + uint(i * 4), m[i / 3][i % 3]); }
void writeMat4(uint a, mat4 m) { for (int i = 0; i < 16; ++i) writeFloat(a + uint(i * 4), m[i / 4][i % 4]); }

vec2 safeNormalize(vec2 v) { if (dot(v, v) == 0.0) return vec2(0.0); return normalize(v); }
vec3 safeNormalize(vec3 v) { if (dot(v, v) == 0.0) return vec3(0.0); return normalize(v); }
vec4 safeNormalize(vec4 v) { if (dot(v, v) == 0.0) return vec4(0.0); return normalize(v); }
void refractVec2(uint d, uint n, float eta) { writeVec2(d, refract(readVec2(d), readVec2(n), eta)); }
void refractVec3(uint d, uint n, float eta) { writeVec3(d, refract(readVec3(d), readVec3(n), eta)); }
void refractVec4(uint d, uint n, float eta) { writeVec4(d, refract(readVec4(d), readVec4(n), eta)); }
void faceforwardVec2(uint d, uint i, uint n) { writeVec2(d, faceforward(readVec2(d), readVec2(i), readVec2(n))); }
void faceforwardVec3(uint d, uint i, uint n) { writeVec3(d, faceforward(readVec3(d), readVec3(i), readVec3(n))); }
void faceforwardVec4(uint d, uint i, uint n) { writeVec4(d, faceforward(readVec4(d), readVec4(i), readVec4(n))); }

void main() {
    cvmFragmentColor = vec4(1.0, 1.0, 1.0, 1.0);

    uint pc = uFragmentBytecode[1];
    uint registerBase = 0u;
    uint stackBase = 0u;
    uint stackPointer = 0u;

    while (true) {
        uint word = uFragmentBytecode[pc++];
        uint op = (word >> 16) & 255u;
        uint size = (word >> 24) & 255u;
        if (size == 0u && op != 20u) size = 1u;
        uint dst = (word >> 8) & 255u;
        uint src = word & 255u;
        int d;
        int s;

        switch (op) {
        case 0u: return;
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
        case 143u: { dst += registerBase; src += registerBase; writeScalar(dst, readScalarUnsigned(src, 4u), 4u); break; } // i32 -> u32
        case 144u: { dst += registerBase; src += registerBase; writeFloat(dst, float(readScalarSigned(src, 4u))); break; } // i32 -> f32
        case 145u: { dst += registerBase; src += registerBase; writeScalar(dst, uint(readScalarSigned(src, 4u) != 0), 1u); break; } // i32 -> bool
        case 146u: { dst += registerBase; src += registerBase; writeScalar(dst, readScalarUnsigned(src, 4u), 4u); break; } // u32 -> i32
        case 147u: { dst += registerBase; src += registerBase; writeFloat(dst, float(readScalarUnsigned(src, 4u))); break; } // u32 -> f32
        case 148u: { dst += registerBase; src += registerBase; writeScalar(dst, uint(readScalarUnsigned(src, 4u) != 0u), 1u); break; } // u32 -> bool
        case 149u: { dst += registerBase; src += registerBase; writeScalar(dst, uint(readFloat(src) != 0.0), 1u); break; } // f32 -> bool
        case 150u: { dst += registerBase; src += registerBase; writeScalar(dst, readScalarUnsigned(src, 1u), 4u); break; } // bool -> i32
        case 151u: { dst += registerBase; src += registerBase; writeScalar(dst, readScalarUnsigned(src, 1u), 4u); break; } // bool -> u32
        case 152u: { dst += registerBase; src += registerBase; writeFloat(dst, float(readScalarUnsigned(src, 1u))); break; } // bool -> f32

        case 17u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); copyWords(dst, src, size); break; }
        case 15u:
            dst += registerBase;
            for (uint i = 0u; i < size; ++i) writeStackByte(stackPointer + i, readMemoryByte(dst + i));
            stackPointer += size;
            break;
        case 16u: {
            dst += registerBase;
            stackPointer -= size;
            for (uint i = 0u; i < size; ++i) writeMemoryByte(dst + i, readStackByte(stackPointer + i));
            break;
        }
        case 20u: { // call
            // Frame words: return PC, parent bases, args base + return dst/size.
            uint frameWord = (stackPointer + 3u) >> 2u;
            cvmStack[frameWord] = pc + 2u;
            cvmStack[frameWord + 1u] = registerBase | (stackBase << 16u);
            stackBase = stackPointer - (uFragmentBytecode[pc + 1u] & 65535u);
            cvmStack[frameWord + 2u] = (stackBase << 16u) | (size << 8u) | src;
            stackPointer = (frameWord << 2u) + 12u;
            registerBase += dst;
            pc = uFragmentBytecode[pc];
            break;
        }
        case 21u: { // ret
            // R0 is the return value; popping the frame restores both bases.
            if (stackPointer != 0u) {
                uint frameWord = (stackPointer - 12u) >> 2u;
                uint parentBases = cvmStack[frameWord + 1u];
                uint resultInfo = cvmStack[frameWord + 2u];
                for (uint i = 0u; i < ((resultInfo >> 8u) & 255u); ++i)
                    writeMemoryByte((parentBases & 65535u) + (resultInfo & 255u) + i,
                                    readMemoryByte(registerBase + i));
                stackPointer = resultInfo >> 16u;
                registerBase = parentBases & 65535u;
                stackBase = parentBases >> 16u;
                pc = cvmStack[frameWord];
            } else return;
            break;
        }
        case 22u:
            pc = uFragmentBytecode[pc];
            break;
        case 23u:
            {
            dst += registerBase; d = int(dst >> 2);
                uint target = uFragmentBytecode[pc++];
                if (cvmMem[d] == 0u) pc = target;
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
        case 34u:
        case 35u:
        case 111u: // mov constant int
        case 112u: // mov constant float
            dst += registerBase; d = int(dst >> 2);
            cvmMem[d] = uFragmentBytecode[pc++];
            break;
        case 36u:
            dst += registerBase; d = int(dst >> 2);
            for (uint offset = 0u; offset < size; ++offset)
                writeMemoryByte(dst + offset, readStackByte(stackBase + src + offset));
            break;
        case 37u: // load bytes from the uint32 uniform table at src word offset
            if (src + (size + 3u) / 4u <= 256u) {
            dst += registerBase; d = int(dst >> 2);
                for (uint offset = 0u; offset < size; ++offset) {
                    uint value = uFragmentUniforms[int(src) + int(offset >> 2)];
                    uint byteValue = (value >> ((offset & 3u) * 8u)) & 255u;
                    writeMemoryByte(dst + offset, byteValue);
                }
            }
            break;
        case 40u: { // indexed access to the VM's packed local register memory
            dst += registerBase;
            src += registerBase;
            uint indexReg = uFragmentBytecode[pc++] + registerBase;
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
            uint indexReg = uFragmentBytecode[pc++] + registerBase;
            int element = int(cvmMem[int(indexReg >> 2u)]) * int(size);
            uint dstByte = uint(int(src) + element);
            for (uint offset = 0u; offset < size; ++offset) {
                uint value = readMemoryByte(dst + offset);
                writeMemoryByte(dstByte + offset, value);
            }
            break;
        }
        case 43u: { break; }
        case 44u: {
            dst += registerBase; src += registerBase;
            uint packedSources = uFragmentBytecode[pc++];
            for (uint i = 0u; i < (size >> 2u); ++i) writeFloat(dst + (i << 2u), readFloat(src + (i << 2u)) * readFloat(((packedSources & 255u) + registerBase) + (i << 2u)) + readFloat((((packedSources >> 8u) & 255u) + registerBase) + (i << 2u)));
            break;
        }
        case 45u: {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            {
                uint packedSources = uFragmentBytecode[pc++];
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
            uint imm = uFragmentBytecode[pc++];
            if (op == 57u) cvmMem[d] += imm;
            else if (op == 58u) cvmMem[d] -= imm;
            else cvmMem[d] *= imm;
            break;
        }
        case 68u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, sin(readFloat(src))); break; }
        case 69u: { dst += registerBase; d = int(dst >> 2); src += registerBase; s = int(src >> 2); writeFloat(dst, cos(readFloat(src))); break; }
        case 60u:
        case 61u:
        case 62u:
            {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
                float imm = uintBitsToFloat(uFragmentBytecode[pc++]);
                if (op == 60u) writeFloat(dst, readFloat(dst) + imm);
                else if (op == 61u) writeFloat(dst, readFloat(dst) - imm);
                else writeFloat(dst, readFloat(dst) * imm);
            }
            break;
        case 64u: // load packed fragment input bytes
            dst += registerBase; d = int(dst >> 2);
            for (uint offset = 0u; offset < size; ++offset) {
                writeMemoryByte(dst + offset, readVaryingByte(src + offset));
            }
            break;
        case 67u: // fragment color output vec4
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            cvmFragmentColor = vec4(readFloat(dst), readFloat(dst + 4u),
                                    readFloat(dst + 8u), readFloat(dst + 12u));
            break;
        case 70u: // vocSample2D: sample texture with (uv.x, uv.y)
            {
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
                uint texId = uFragmentBytecode[pc++];
                vec2 uv = vec2(readFloat(src), readFloat(src + 4u));
                vec4 texColor = vec4(0.0);
                switch (texId) {
                case 0u: texColor = texture(uSamplers[0], uv); break;
                case 1u: texColor = texture(uSamplers[1], uv); break;
                case 2u: texColor = texture(uSamplers[2], uv); break;
                case 3u: texColor = texture(uSamplers[3], uv); break;
                case 4u: texColor = texture(uSamplers[4], uv); break;
                case 5u: texColor = texture(uSamplers[5], uv); break;
                case 6u: texColor = texture(uSamplers[6], uv); break;
                case 7u: texColor = texture(uSamplers[7], uv); break;
                default: break;
                }
                writeFloat(dst, texColor.r);
                writeFloat(dst + 4u, texColor.g);
                writeFloat(dst + 8u, texColor.b);
                writeFloat(dst + 12u, texColor.a);
            }
            break;
        case 71u: { dst += registerBase; src += registerBase; writeVec2(dst, readMat2(src) * readVec2(dst)); break; }
        case 73u: { dst += registerBase; src += registerBase; writeVec3(dst, readMat3(src) * readVec3(dst)); break; }
        case 75u: { dst += registerBase; src += registerBase; writeVec4(dst, readMat4(src) * readVec4(dst)); break; }
        case 77u: { dst += registerBase; src += registerBase; writeMat2(dst, readMat2(dst) * readMat2(src)); break; }
        case 79u: { dst += registerBase; src += registerBase; writeMat3(dst, readMat3(dst) * readMat3(src)); break; }
        case 81u: { dst += registerBase; src += registerBase; writeMat4(dst, readMat4(dst) * readMat4(src)); break; }
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
        case 89u: { dst += registerBase; src += registerBase;
            if (size == 2u) writeVec2(dst, safeNormalize(readVec2(src)));
            else if (size == 3u) writeVec3(dst, safeNormalize(readVec3(src)));
            else writeVec4(dst, safeNormalize(readVec4(src)));
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
        case 92u: { dst += registerBase; src += registerBase; writeMat2(dst, transpose(readMat2(src))); break; }
        case 93u: { dst += registerBase; src += registerBase; writeMat3(dst, transpose(readMat3(src))); break; }
        case 94u: { dst += registerBase; src += registerBase; writeMat4(dst, transpose(readMat4(src))); break; }
        case 95u: { dst += registerBase; src += registerBase; writeMat2(dst, inverse(readMat2(src))); break; }
        case 96u: { dst += registerBase; src += registerBase; writeMat3(dst, inverse(readMat3(src))); break; }
        case 97u: { dst += registerBase; src += registerBase; writeMat4(dst, inverse(readMat4(src))); break; }
        case 98u: { dst += registerBase; src += registerBase; writeVec2(dst, reflect(readVec2(dst), readVec2(src))); break; }
        case 99u: { dst += registerBase; src += registerBase; writeVec3(dst, reflect(readVec3(dst), readVec3(src))); break; }
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
        case 107u: { dst += registerBase; src += registerBase; writeFloat(dst, step(readFloat(dst), readFloat(src))); break; }
        case 108u: { dst += registerBase; src += registerBase; uint edge1 = (uFragmentBytecode[pc++] & 0xFFu) + registerBase; writeFloat(dst, smoothstep(readFloat(src), readFloat(edge1), readFloat(dst))); break; }
        case 109u: { dst += registerBase; src += registerBase; uint factor = (uFragmentBytecode[pc++] & 0xFFu) + registerBase; writeFloat(dst, mix(readFloat(dst), readFloat(src), readFloat(factor))); break; }
        case 110u: { dst += registerBase; src += registerBase; uint upper = (uFragmentBytecode[pc++] & 0xFFu) + registerBase; writeFloat(dst, clamp(readFloat(dst), readFloat(src), readFloat(upper))); break; }
        case 113u: { dst += registerBase; src += registerBase; writeVec3(dst, cross(readVec3(dst), readVec3(src))); break; }
        case 114u: { dst += registerBase; src += registerBase;
            if (size == 2u) writeFloat(dst, length(readVec2(src)));
            else if (size == 3u) writeFloat(dst, length(readVec3(src)));
            else writeFloat(dst, length(readVec4(src)));
            break;
        }
        case 115u: { uint eta = (uFragmentBytecode[pc++] & 0xFFu) + registerBase; dst += registerBase; src += registerBase;
            if (size == 2u) refractVec2(dst, src, readFloat(eta));
            else if (size == 3u) refractVec3(dst, src, readFloat(eta));
            else refractVec4(dst, src, readFloat(eta));
            break;
        }
        case 116u: { // vocSampleLod: explicit-mip texture sample
            dst += registerBase; d = int(dst >> 2);
            src += registerBase; s = int(src >> 2);
            uint descriptor = uFragmentBytecode[pc++];
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
        case 117u: { dst += registerBase; src += registerBase; writeFloat(dst, tan(readFloat(src))); break; }
        case 122u: { dst += registerBase; src += registerBase; writeFloat(dst, asin(readFloat(src))); break; }
        case 123u: { dst += registerBase; src += registerBase; writeFloat(dst, acos(readFloat(src))); break; }
        case 124u: { dst += registerBase; src += registerBase; writeFloat(dst, atan(readFloat(src))); break; }
        case 125u: { dst += registerBase; src += registerBase; writeFloat(dst, exp(readFloat(src))); break; }
        case 126u: { dst += registerBase; src += registerBase; writeFloat(dst, log(readFloat(src))); break; }
        case 127u: { dst += registerBase; src += registerBase; writeFloat(dst, exp2(readFloat(src))); break; }
        case 128u: { dst += registerBase; src += registerBase; writeFloat(dst, log2(readFloat(src))); break; }
        case 129u: { dst += registerBase; src += registerBase; writeFloat(dst, ceil(readFloat(src))); break; }
        case 130u: { dst += registerBase; src += registerBase; writeFloat(dst, trunc(readFloat(src))); break; }
        case 131u: { dst += registerBase; src += registerBase; writeFloat(dst, round(readFloat(src))); break; }
        case 132u: { dst += registerBase; src += registerBase; writeFloat(dst, sign(readFloat(src))); break; }
        case 133u: { dst += registerBase; src += registerBase; writeFloat(dst, radians(readFloat(src))); break; }
        case 134u: { dst += registerBase; src += registerBase; writeFloat(dst, degrees(readFloat(src))); break; }
        case 135u: { dst += registerBase; src += registerBase; writeFloat(dst, (exp(readFloat(src)) - exp(-readFloat(src))) * 0.5); break; }
        case 136u: { dst += registerBase; src += registerBase; writeFloat(dst, (exp(readFloat(src)) + exp(-readFloat(src))) * 0.5); break; }
        case 137u: { dst += registerBase; src += registerBase; writeFloat(dst, (exp(2.0 * readFloat(src)) - 1.0) / (exp(2.0 * readFloat(src)) + 1.0)); break; }
        case 138u: { dst += registerBase; src += registerBase; float x = readFloat(src); writeFloat(dst, log(x + sqrt(x * x + 1.0))); break; }
        case 139u: { dst += registerBase; src += registerBase; float x = readFloat(src); writeFloat(dst, log(x + sqrt(x * x - 1.0))); break; }
        case 140u: { dst += registerBase; src += registerBase; float x = readFloat(src); writeFloat(dst, 0.5 * log((1.0 + x) / (1.0 - x))); break; }
        case 118u: { dst += registerBase; src += registerBase; writeFloat(dst, atan(readFloat(dst), readFloat(src))); break; }
        case 142u: { dst += registerBase; src += registerBase; writeFloat(dst, mod(readFloat(dst), readFloat(src))); break; }
        case 119u: { uint nref = (uFragmentBytecode[pc++] & 0xFFu) + registerBase; dst += registerBase; src += registerBase;
            if (size == 2u) faceforwardVec2(dst, src, nref);
            else if (size == 3u) faceforwardVec3(dst, src, nref);
            else faceforwardVec4(dst, src, nref);
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
        case 153u: {
            dst += registerBase; src += registerBase;
            writeFloat(dst, determinant(readMat2(src)));
            break;
        }
        case 154u: {
            dst += registerBase; src += registerBase;
            writeFloat(dst, determinant(readMat3(src)));
            break;
        }
        case 155u: {
            dst += registerBase; src += registerBase;
            writeFloat(dst, determinant(readMat4(src)));
            break;
        }
        default: break;
        }
    }
}
