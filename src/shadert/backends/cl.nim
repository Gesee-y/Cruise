##########################################################################################################################################################
############################################################ TRANPILER NIM -> CRUISE IR ##################################################################
##########################################################################################################################################################

import ../ir
import sequtils, strutils

proc emitType(node: CIRNode): string =
  assert node.kind == cnkSym
  case node.name:
  of "int":    "int"
  of "float":  "float"
  of "double": "double"
  of "bool":   "bool"
  of "uint":   "uint"
  # types vecteur OpenCL
  of "vec2":   "float2"
  of "vec3":   "float3"
  of "vec4":   "float4"
  of "ivec2":  "int2"
  of "uvec4":  "uint4"
  else:        node.name   # struct custom, passé tel quel

proc emitQualifier(node: CIRNode): string =
  case node.kind:
  of cnkReadOnly:  "__read_only "
  of cnkWritOnly:  "__write_only "
  of cnkEmpty:     ""
  else:            ""

proc emitCL(node: CIRNode, isKernel = false): string =
  case node.kind:

  of cnkStmtList:
    node.args.mapIt(emitCL(it)).join("\n")

  of cnkSym:      node.name
  of cnkIntLit:   $node.intVal
  of cnkFloatLit: $node.floatVal & "f"
  of cnkIdentDef: emitType(node.args[1]) & emitCL(node.args[0])

  of cnkUniform:
    # __constant float uTime;
    "__constant " & emitType(node.args[2]) & " " & node.args[1].name & ";\n"

  of cnkBuffer:
    # __global float* buf;
    "__global " & emitType(node.args[2]) & "* " & node.args[1].name & ";\n"

  of cnkImage:
    emitQualifier(node.args[0]) & "image2d_t " & node.args[1].name

  of cnkSampler:
    "sampler_t " & node.args[1].name

  of cnkFuncSig:
    let name     = node.args[0].name
    let retType  = if node.args[1].kind == cnkEmpty: "void"
                   else: emitType(node.args[1])
    let prefix   = if isKernel: "__kernel " else: ""
    let params   = node.args[2..^1].mapIt(emitCL(it)).join(", ")
    prefix & retType & " " & name & "(" & params & ")"

  of cnkFuncDef:
    let sig  = emitCL(node.args[0], isKernel)
    let body = emitCL(node.args[1])
    sig & " {\n" & body & "\n}\n"

  of cnkInfix:
    emitCL(node.args[1]) & " " & node.args[0].name & " " & emitCL(node.args[2])

  of cnkPrefix:
    node.args[0].name & emitCL(node.args[1])

  of cnkAsgn:
    emitCL(node.args[0]) & " = " & emitCL(node.args[1]) & ";"

  of cnkDecl:
    # type name = expr;
    let idnt = node.args[0]   # cnkIdentDef
    emitType(idnt.args[1]) & " " & idnt.args[0].name &
      " = " & emitCL(node.args[1]) & ";"

  of cnkIfStmt:
    node.args.mapIt(emitCL(it)).join("\nelse ")

  of cnkElifBranch:
    "if (" & emitCL(node.args[0]) & ") {\n" & emitCL(node.args[1]) & "\n}"

  of cnkElse:
    "{\n" & emitCL(node.args[0]) & "\n}"

  of cnkForStmt:
    let v     = node.args[0].name
    let start = emitCL(node.args[1])
    let stop  = emitCL(node.args[2])
    let body  = emitCL(node.args[3])
    "for (int " & v & " = " & start & "; " & v & " < " & stop & "; ++" & v & ") {\n" & body & "\n}"

  of cnkWhileStmt:
    "while (" & emitCL(node.args[0]) & ") {\n" & emitCL(node.args[1]) & "\n}"

  of cnkCaseStmt:
    let branches = node.args[1..^1].mapIt(emitCL(it)).join("\n")
    "switch (" & emitCL(node.args[0]) & ") {\n" & branches & "\n}"

  of cnkOfBranch:
    # dernière arg = body, les précédentes = valeurs
    let vals = node.args[0..^2].mapIt("case " & emitCL(it) & ":").join("\n")
    vals & "\n" & emitCL(node.args[^1]) & "\nbreak;"

  of cnkReturnStmt:
    "return " & emitCL(node.args[0]) & ";"

  of cnkBracketExpr:
    emitCL(node.args[0]) & "[" & emitCL(node.args[1]) & "]"

  of cnkDotExpr:
    emitCL(node.args[0]) & "." & node.args[1].name

  of cnkCast, cnkConv, cnkHiddenCallConv:
    "(" & emitType(node.args[0]) & ")(" & emitCL(node.args[1]) & ")"

  of cnkCall:
    emitCL(node.args[0]) & "(" & node.args[1..^1].mapIt(emitCL(it)).join(", ") & ")"

  of cnkBreakStmt:    "break;"
  of cnkContinueStmt: "continue;"
  of cnkDiscardStmt:  ""
  of cnkEmpty:        ""
  else: ""


proc emitOpenCL*(ctx: CIRContext): string =
  result &= emitCL(ctx.typeDecl)
  result &= emitCL(ctx.forwardDecl)
  result &= emitCL(ctx.funcDef)
  result &= emitCL(ctx.body, isKernel = true) 

