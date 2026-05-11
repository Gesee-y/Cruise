##########################################################################################################################################################
############################################################ TRANPILER NIM -> CRUISE IR ##################################################################
##########################################################################################################################################################

import ../ir
import sequtils, strutils, strformat

const INDENT_SYM = "    "

proc emitType(node: CIRNode): string =
  assert node.kind == cnkSym
  case node.name:
  of "int":    "int"
  of "float":  "float"
  of "double": "double"
  of "bool":   "bool"
  of "uint":   "uint"

  of "vec2":   "float2"
  of "vec3":   "float3"
  of "vec4":   "float4"
  of "ivec2":  "int2"
  of "uvec4":  "uint4"
  else:        node.name

proc emitQualifier(node: CIRNode): string =
  case node.kind:
  of cnkReadOnly:  "__read_only "
  of cnkWritOnly:  "__write_only "
  of cnkEmpty:     ""
  else:            ""

proc emitCL(node: CIRNode, isKernel = false, depth=1): string =
  let indent = repeat(INDENT_SYM, depth)
  case node.kind:

  of cnkStmtList:
    var res = ""
    for n in node.args:
      let code = emitCL(n, depth=(depth+1))
      if code != "": res &= indent & code & ";\n"

    res

  of cnkSym:      node.name
  of cnkIntLit:   $node.intVal
  of cnkFloatLit: $node.floatVal & "f"
  of cnkIdentDef: emitType(node.args[1]) & " " & emitCL(node.args[0])

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
    sig & " {\n" & body & "}\n"

  of cnkInfix:
    emitCL(node.args[1]) & " " & node.args[0].name & " " & emitCL(node.args[2])

  of cnkPrefix:
    node.args[0].name & emitCL(node.args[1])

  of cnkAsgn:
    emitCL(node.args[0]) & " = " & emitCL(node.args[1])

  of cnkDecl:
    # type name = expr;
    let idnt = node.args[0]   # cnkIdentDef
    emitType(idnt.args[1]) & " " & idnt.args[0].name &
      " = " & emitCL(node.args[1])

  of cnkIfStmt:
    let ifIndent = repeat(INDENT_SYM, depth-1)
    node.args.mapIt(emitCL(it, depth=depth-1)).join(&"\n{ifIndent}else ")

  of cnkElifBranch:
    "if (" & emitCL(node.args[0]) & ") {\n" & emitCL(node.args[1], depth=depth+1) & indent & "}"

  of cnkElse:
    "{\n" & emitCL(node.args[0], depth=depth+1) & indent & "}"

  of cnkForStmt:
    let forIndent = repeat(INDENT_SYM, depth-1)
    let v     = node.args[0].name
    let start = emitCL(node.args[1])
    let stop  = emitCL(node.args[2])
    let body  = emitCL(node.args[3], depth=depth)
    "for (int " & v & " = " & start & "; " & v & " < " & stop & "; ++" & v & ") {\n" & body & forIndent & "}"

  of cnkWhileStmt:
    "while (" & emitCL(node.args[0]) & ") {\n" & emitCL(node.args[1]) & "}"

  of cnkCaseStmt:
    let switchIndent = repeat(INDENT_SYM, depth-1)
    var branches = ""

    for i in 1..<node.args.len:
      let n = node.args[i]
      branches &= switchIndent & emitCL(n) & "\n"

    "switch (" & emitCL(node.args[0]) & ") {\n" & branches & "\n}"

  of cnkOfBranch:
    let brIndent = repeat(INDENT_SYM, depth+1)
    let vals = node.args[0..^2].mapIt("case " & emitCL(it) & ":").join("\n")
    vals & "\n" & emitCL(node.args[^1], depth=depth+1) & brIndent & "break;"

  of cnkDefaultBranch:
    let brIndent = repeat(INDENT_SYM, depth+1)
    "default:\n" & emitCL(node.args[0], depth=depth+1) & brIndent & "break;"

  of cnkReturnStmt:
    "return " & emitCL(node.args[0])

  of cnkBracketExpr:
    emitCL(node.args[0]) & "[" & emitCL(node.args[1]) & "]"

  of cnkDotExpr:
    emitCL(node.args[0]) & "." & node.args[1].name

  of cnkCast, cnkConv, cnkHiddenCallConv:
    "(" & emitType(node.args[0]) & ")(" & emitCL(node.args[1]) & ")"

  of cnkCall:
    emitCL(node.args[0]) & "(" & node.args[1..^1].mapIt(emitCL(it)).join(", ") & ")"

  of cnkBreakStmt:    "break"
  of cnkContinueStmt: "continue"
  of cnkDiscardStmt:  ""
  of cnkEmpty:        ""
  else: ""


proc emitOpenCL*(ctx: CIRContext): string =
  result &= emitCL(ctx.typeDecl)
  result &= emitCL(ctx.forwardDecl)
  result &= emitCL(ctx.funcDef)
  result &= emitCL(ctx.body, isKernel = true) 

proc tester(x: int, y: int) =
  var c = x + y
  var d = x - y
  let f = d + c

  if c == 2:
    d = c * f
  elif c == 3:
    d = f + 2
  else:
    c = 5

  case d:
    of 1: c += 1
    of 2: c += 6
    else: discard

  for i in 0..<8:
    d += i

var ctx = compileToIR(tester)
echo emitOpenCL(ctx)