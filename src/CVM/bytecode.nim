# ################################################################################################################################################################## #
# ##################################################################### BYTECODE BACKEND ########################################################################### #
# ################################################################################################################################################################## #

import std/[os, syncio]
import deps/vmops

type
  BytecodeFeature* = enum
    bfCalls
    bfMatrices
    bfSampling
    bfMixing
    bfVectorMath
    bfTranscendentals
    bfReg32
    bfReg48
    bfReg64
    bfReg128
    bfReg256
    bfNoStack

  BytecodeProfile* = object
    features*: set[BytecodeFeature]
    registerWords*: int

template translateToBytecode*() = {.plugin: "deps/bytecode_plugin.nim".}
func setShaderName*(str: static[string]) = discard
func setShaderType*[T](base: typedesc[T], ty: static[string]) {.untyped.} = discard

  # ###################################################################################################### #
 # ############################################# DEFAULT TYPES ########################################## #
# ###################################################################################################### #

template uniform*(val: static[string]) {.pragma.}
template ssbo*() {.pragma.}
template globalIndex*() {.pragma.}
template fragmentOutput*() {.pragma.}
template vertexOutput*() {.pragma.}
template vertexVarying*() {.pragma.}
template vertexInput*() {.pragma.}
template fragmentInput*() {.pragma.}
template texture*() {.pragma.}

proc readBytecode*(path: string, maxBytecodeWord=256): seq[uint32] =
  result = @[]
  if not fileExists(path):
    return
  var file = open(path, fmRead)
  defer: file.close()
  var word = 0'u32
  while file.readBuffer(addr word, sizeof(word)) == sizeof(word):
    result.add word

  # ###################################################################################################### #
 # ########################################### BYTECODE ANALYSIS ######################################## #
# ###################################################################################################### #

proc addRegister(endByte: var int, address: uint32, width: int) {.inline.} =
  endByte = max(endByte, int(address) + max(1, width))

proc getRegisterTier(regSize: int): BytecodeFeature =
  if regSize <= 32: return bfReg32
  if regSize <= 48: return bfReg48
  if regSize <= 64: return bfReg64
  if regSize <= 128: return bfReg128
  return bfReg256

proc analyzeBytecode*(code: openArray[uint32]): BytecodeProfile =
  var pc = 0
  var maxRegisterEnd = 0
  var nestedFrameBytes = 0

  while pc < code.len:
    let word = code[pc]
    # The generator guarantees a valid opcode; a raw cast avoids Nim's enum
    # hole conversion check in this bytecode scan.
    let opcode = cast[VMOpCode]((word shr 16) and 255'u32)
    let size = int(word shr 24)
    let dst = (word shr 8) and 255'u32
    let src = word and 255'u32
    var dstWidth = 0
    var srcWidth = 0

    case opcode
    of vocCall:
      result.features.incl(bfCalls)
      let frameInfo = code[pc + 2]
      nestedFrameBytes += int(frameInfo shr 16)
      maxRegisterEnd = max(maxRegisterEnd, int(dst))
      srcWidth = if size == 0: 0 else: size
    of vocRet, vocPush, vocPop, vocSMov:
      result.features.incl(bfCalls)
      dstWidth = max(4, size)
      srcWidth = max(4, size)
    of vocMmatvec2f, vocMmatvec2i:
      result.features.incl(bfMatrices)
      dstWidth = 8
      srcWidth = 16
    of vocMmatvec3f, vocMmatvec3i:
      result.features.incl(bfMatrices)
      dstWidth = 12
      srcWidth = 36
    of vocMmatvec4f, vocMmatvec4i:
      result.features.incl(bfMatrices)
      dstWidth = 16
      srcWidth = 64
    of vocMmat2f, vocMmat2i:
      result.features.incl(bfMatrices)
      dstWidth = 16
      srcWidth = 16
    of vocMmat3f, vocMmat3i:
      result.features.incl(bfMatrices)
      dstWidth = 36
      srcWidth = 36
    of vocMmat4f, vocMmat4i:
      result.features.incl(bfMatrices)
      dstWidth = 64
      srcWidth = 64
    of vocTranspose2, vocInvert2, vocDet2:
      result.features.incl(bfMatrices)
      dstWidth = if opcode == vocDet2: 4 else: 16
      srcWidth = 16
    of vocTranspose3, vocInvert3, vocDet3:
      result.features.incl(bfMatrices)
      dstWidth = if opcode == vocDet3: 4 else: 36
      srcWidth = 36
    of vocTranspose4, vocInvert4, vocDet4:
      result.features.incl(bfMatrices)
      dstWidth = if opcode == vocDet4: 4 else: 64
      srcWidth = 64
    of vocMatrixCompMult:
      result.features.incl(bfMatrices)
      dstWidth = max(1, size) * 4
      srcWidth = dstWidth
    of vocSample2D:
      result.features.incl(bfSampling)
      dstWidth = 16
      srcWidth = 8
    of vocSampleLod:
      result.features.incl(bfSampling)
      dstWidth = 16
      srcWidth = 8
    of vocStepf, vocSmoothstepf, vocMixf, vocClampf:
      result.features.incl(bfMixing)
      dstWidth = 4
      srcWidth = 4
    of vocNormalize, vocDot2, vocDot3, vocDot4, vocReflect2, vocReflect3,
       vocCross3, vocLengthf, vocRefractf, vocFaceforward:
      result.features.incl(bfVectorMath)
      case opcode
      of vocDot2:
        dstWidth = 4
        srcWidth = 8
        addRegister(maxRegisterEnd, uint32(size), 8)
      of vocDot3:
        dstWidth = 4
        srcWidth = 12
        addRegister(maxRegisterEnd, uint32(size), 12)
      of vocDot4:
        dstWidth = 4
        srcWidth = 16
        addRegister(maxRegisterEnd, uint32(size), 16)
      of vocCross3:
        dstWidth = 12
        srcWidth = 12
      of vocLengthf:
        dstWidth = 4
        srcWidth = max(2, size) * 4
      of vocReflect2:
        dstWidth = 8
        srcWidth = 8
      of vocReflect3:
        dstWidth = 12
        srcWidth = 12
      else:
        dstWidth = max(2, size) * 4
        srcWidth = dstWidth
    of vocPowi, vocPowf, vocVecNegi, vocVecNegf, vocFloorf, vocFractf,
       vocVecAddi, vocVecAddf, vocVecSubi, vocVecSubf, vocVecMuli, vocVecMulf:
      dstWidth = max(1, size) * 4
      srcWidth = max(4, dstWidth)
    of vocTan, vocAtan2f, vocAsin, vocAcos, vocAtan, vocExp, vocLog,
       vocExp2, vocLog2, vocCeil, vocTrunc, vocRound, vocSign, vocRadians,
       vocDegrees, vocSinh, vocCosh, vocTanh, vocAsinh, vocAcosh, vocAtanh:
      result.features.incl(bfTranscendentals)
      dstWidth = 4
      srcWidth = 4
    of vocSqrtf, vocRsqrtf, vocSinf, vocCosf, vocAbsi, vocAbsf, vocAbsu,
       vocMini, vocMaxi, vocMinf, vocMaxf, vocMinu, vocMaxu, vocModf:
      dstWidth = max(4, size)
      srcWidth = dstWidth
      if opcode in {vocSinf, vocCosf, vocSqrtf, vocRsqrtf, vocModf}:
        result.features.incl(bfTranscendentals)
    of vocLoadBuf, vocStoreBuf, vocLoadAt, vocStoreAt:
      dstWidth = max(1, size)
      srcWidth = dstWidth
      addRegister(maxRegisterEnd, code[pc + 1] and 255'u32, 4)
    of vocMovCi, vocMovCf, vocLoadi, vocLoadf, vocLoadGI:
      dstWidth = 4
    of vocConvInt32ToUInt32, vocConvInt32ToFloat32, vocConvUInt32ToInt32,
       vocConvUInt32ToFloat32, vocConvBoolToInt32, vocConvBoolToUInt32,
       vocConvBoolToFloat32:
      dstWidth = 4
      srcWidth = if opcode in {vocConvBoolToInt32, vocConvBoolToUInt32,
                                vocConvBoolToFloat32}: 1 else: 4
    of vocConvInt32ToBool, vocConvUInt32ToBool, vocConvFloat32ToBool:
      dstWidth = 1
      srcWidth = 4
    of vocLoadUni, vocLoadVertexInput, vocLoadFragmentInput,
       vocStoreVertexOutput, vocStoreVertexVarying, vocStoreFragmentOutput,
       vocLoad, vocStore, vocMov, vocAnd, vocOr, vocNot, vocXor,
       vocAddi, vocSubi, vocMuli, vocDivi, vocMod, vocAddf, vocSubf,
       vocMulf, vocDivf, vocNegi, vocNegf, vocEqi, vocNeqi, vocLti, vocLei,
       vocEqf, vocNeqf, vocLtf, vocLef, vocMaddf, vocMaddi, vocAddCi,
       vocSubCi, vocMulCi, vocAddCf, vocSubCf, vocMulCf:
      dstWidth = max(4, size)
      srcWidth = dstWidth
    else:
      discard

    addRegister(maxRegisterEnd, dst, dstWidth)
    addRegister(maxRegisterEnd, src, srcWidth)

    case opcode
    of vocLoadi, vocLoadf, vocMovCi, vocMovCf,
       vocAddCi, vocSubCi, vocMulCi, vocAddCf, vocSubCf, vocMulCf,
       vocJmp, vocJmpFalse, vocLoadBuf, vocStoreBuf, vocLoadAt, vocStoreAt,
       vocSample2D, vocMaddf, vocMaddi, vocRefractf, vocSampleLod,
       vocSmoothstepf, vocMixf, vocClampf, vocFaceforward:
      if opcode == vocRefractf or opcode == vocFaceforward:
        addRegister(maxRegisterEnd, code[pc + 1] and 255'u32, 4)
      elif opcode == vocSampleLod:
        addRegister(maxRegisterEnd, (code[pc + 1] shr 8) and 255'u32, 4)
      elif opcode == vocMaddf or opcode == vocMaddi:
        let packed = code[pc + 1]
        addRegister(maxRegisterEnd, packed and 255'u32, max(4, size))
        addRegister(maxRegisterEnd, (packed shr 8) and 255'u32, max(4, size))
      elif opcode == vocSmoothstepf or opcode == vocMixf or opcode == vocClampf:
        addRegister(maxRegisterEnd, code[pc + 1] and 255'u32, 4)
      inc pc
    of vocCall:
      pc += 2
    else:
      discard
    inc pc

  let requiredBytes = maxRegisterEnd + nestedFrameBytes
  result.registerWords = min(64, max(1, (requiredBytes + 3) div 4))

proc featureMask*(profile: BytecodeProfile): uint16 =
  for feature in profile.features:
    result = result or (1'u16 shl ord(feature))
