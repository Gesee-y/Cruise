import std/[strutils, strformat]#, syncio]
import deps/vmops

const
  SIZE_POS   = 24
  OPCODE_POS = 16
  REGA_POS   = 8
  
proc disassembleWord*(word: uint32, op: var VMOpCode, dst, src: var uint8, size: var uint8) {.inline.} =
  ## Décode un mot 32-bit en (Opcode, Register A/Dst, Register B/Src, Size)
  size = uint8((word shr SIZE_POS) and 0xFF'u32)
  op   = VMOpCode((word shr OPCODE_POS) and 0xFF'u32)
  dst  = uint8((word shr REGA_POS) and 0xFF'u32)
  src  = uint8(word and 0xFF'u32)

proc disassembleWord*(word: uint32, op: var VMOpCode, dst, src: var uint8) {.inline.} =
  var dummySize: uint8
  disassembleWord(word, op, dst, src, dummySize)

proc disassemble*(code: openArray[uint32]) =
  ## Parcourt le bytecode et l'affiche sous forme d'instructions ASM lisibles.
  var pc = 0
  echo "=== DISASSEMBLY ==="
  echo "ADDR   | RAW HEX    | INSTRUCTION"
  echo "----------------------------------------"

  while pc < code.len:
    let word = code[pc]
    var op: VMOpCode
    var dst, src, size: uint8
    
    disassembleWord(word, op, dst, src, size)
    
    let addrStr = "0x" & pc.toHex(4)
    let hexStr  = int(word).toHex(8)
    let opStr   = if size > 1: $op & "." & $size else: $op

    case op
    # Instructions avec valeur immédiate dans le mot suivant (ex: vocLoadi R0, #10)
    of vocLoadi, vocLoadf, vocMovCi, vocMovCf:
      if pc + 1 < code.len:
        let imm = code[pc + 1]
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, #{imm}"
        pc += 2
      else:
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, <TRUNCATED IMM>"
        pc += 1

    # Arithmetic immediates carry one word (up to 32 bits) or two words (64 bits).
    of vocAddCi, vocSubCi, vocMulCi, vocAddCf, vocSubCf, vocMulCf:
      if pc + 1 < code.len:
        var imm = uint64(code[pc + 1])
        pc += 2
        if size > 4 and pc < code.len:
          imm = imm or (uint64(code[pc]) shl 32)
          inc pc
          echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, #0x{imm.toHex(16)}"
        elif size > 4:
          echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, <TRUNCATED IMM64>"
        else:
          echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, #0x{imm.toHex(8)}"
      else:
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, <TRUNCATED IMM>"
        pc += 1

    # Instructions de saut / appel dont la cible est dans le mot suivant
    of vocJmp, vocJmpFalse, vocCall:
      if pc + 1 < code.len:
        let target = code[pc + 1]
        let targetHex = "0x" & target.toHex(4)
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, @{targetHex}"
        pc += 2
      else:
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, <TRUNCATED TARGET>"
        pc += 1

    of vocMaddf, vocMaddi:
      if pc + 1 < code.len:
        let packedSources = code[pc + 1]
        let rhsReg = packedSources and 0xFF'u32
        let addReg = (packedSources shr 8) and 0xFF'u32
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, R{src} * R{rhsReg} + R{addReg}"
        pc += 2
      else:
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, <TRUNCATED SOURCES>"
        pc += 1

    of vocConv:
      if pc + 1 < code.len:
        let descriptor = code[pc + 1]
        let sourceType = VMConvType(descriptor and 0xFF'u32)
        let targetType = VMConvType((descriptor shr 8) and 0xFF'u32)
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, R{src} ({sourceType} -> {targetType})"
        pc += 2
      else:
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, R{src}, <TRUNCATED TYPE>"
        pc += 1

    of vocSample2D:
      if pc + 1 < code.len:
        let texId = code[pc + 1]
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, Tex{texId}, [R{src}]"
        pc += 2
      else:
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, <TRUNCATED TEXID>"
        pc += 1

    of vocStepf, vocSmoothstepf, vocMixf, vocClampf:
      if pc + 1 < code.len:
        let descriptor = code[pc + 1]
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, R{src}, descriptor=0x{descriptor.toHex(8)}"
        pc += 2
      else:
        echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, R{src}, <TRUNCATED DESCRIPTOR>"
        pc += 1

    # Halte / Fin d'exécution
    of vocHalt:
      echo &"{addrStr} | {hexStr}   | {opStr}"
      pc += 1

    of vocLoadGI, vocNoOp:
      echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}"
      pc += 1

    of vocLoadUni:
      echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, U{src}"
      pc += 1

    of vocLoadBuf:
      echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, B{src}"
      pc += 1

    of vocStoreBuf:
      echo &"{addrStr} | {hexStr}   | {opStr:<12} B{src}, R{dst}"
      pc += 1

    of vocLoadAt:
      echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, [R{src}]"
      pc += 1

    of vocStoreAt:
      echo &"{addrStr} | {hexStr}   | {opStr:<12} [R{src}], R{dst}"
      pc += 1

    # Instructions standard à deux opérandes (R_dst, R_src)
    else:
      echo &"{addrStr} | {hexStr}   | {opStr:<12} R{dst}, R{src}"
      pc += 1

  echo "----------------------------------------"
