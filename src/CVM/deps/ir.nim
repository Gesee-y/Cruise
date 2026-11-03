  # ###################################################################################################################################### #
 # ############################################################ CODE IR ################################################################# #
# ###################################################################################################################################### #

import std/[strutils, sequtils]

type
  CIRNodeKind* = enum
    cnkNone
    cnkStmtList
    cnkSection
    cnkDecl, cnkFuncSig, cnkFuncDef
    cnkCall
    cnkObjConstr
    cnkBracketExpr
    cnkDotExpr
    cnkIfStmt, cnkElifBranch
    cnkForStmt
    cnkWhileStmt
    cnkReturnStmt
    cnkSym, cnkSymDef, cnkUniform, cnkBuffer, cnkSampler, cnkImage, cnkArray
    cnkHiddenDeref
    cnkPar
    cnkIntLit
    cnkCharLit
    cnkUintLit
    cnkFloatLit
    cnkBoolLit
    cnkInfix
    cnkPrefix
    cnkAsgn
    cnkParams
    cnkBreakStmt
    cnkContinueStmt
    cnkCast
    cnkConv
    cnkBracket
    cnkConstDef, cnkTypeDef, cnkIdentDef
    cnkCaseStmt
    cnkOfBranch, cnkDefaultBranch
    cnkElse
    cnkHiddenStdConv
    cnkHiddenSubConv
    cnkHiddenCallConv
    cnkStmtListExpr
    cnkEmpty
    cnkDiscardStmt
    cnkWritOnly, cnkReadOnly
    cnkVarTy, cnkGlobalIndex, cnkLocalIndex, cnkLocalSize

  CIRNode* = object
    ## A single node in the Cruise IR tree.
    ##
    ## Every node carries a `src` field populated during transpilation so
    ## that later passes (liveness analysis, register allocation) can
    ## operate directly on the tree without flattening it first.
    src*: LineInfo ## source position assigned during processNode
    case kind*: CIRNodeKind
    of cnkSym:
      na: string
    of cnkRSym:
      n: string
      tid*: int
    of cnkIntLit:
      intVal*: int
    of cnkCharLit:
      charVal*: char
    of cnkUintLit:
      uintVal*: uint
    of cnkFloatLit:
      floatVal*: float
    of cnkBoolLit:
      boolVal*: bool
    of cnkDiscardStmt, cnkEmpty, cnkContinueStmt, cnkWritOnly,
        cnkReadOnly: discard
    else:
      args*: seq[CIRNode]

proc newCIRNode*(info: LineInfo, kind: static CIRNodeKind): CIRNode = CIRNode(src: info, kind: kind)
proc add*(a: var CIRNode, b: CIRNode) = a.args.add(b)
proc newCIRSym*(info: LineInfo, name: string): CIRNode = CIRNode(src: info, kind: cnkSym, na: name)
proc newCIRRSym*(info: LineInfo, name: string, tid: int): CIRNode = CIRNode(src: info, kind: cnkSym, n: name, tid: tid)
proc newCIRIntLit*(info: LineInfo, i: int): CIRNode = CIRNode(src: info, kind: cnkIntLit, intVal: i)
proc newCIRCharLit*(info: LineInfo, i: char): CIRNode = CIRNode(src: info, kind: cnkCharLit, charVal: i)
proc newCIRUintLit*(info: LineInfo, i: uint): CIRNode = CIRNode(src: info, kind: cnkUintLit, uintVal: i)
proc newCIRBoolLit*(info: LineInfo, i: bool): CIRNode = CIRNode(src: info, kind: cnkBoolLit, boolVal: i)
proc newCIRFloatLit*(info: LineInfo, i: float): CIRNode = CIRNode(src: info, kind: cnkFloatLit, floatVal: i)
proc name*(c: CIRNode): string =
  case c.kind:
  of cnkSym
    result = c.na
  of cnkRSym:
    result = c.n
  else:
    result = "\0"

proc renderIR*(node: CIRNode, indent: int = 0): string =
  let ind = repeat("  ", indent)
  
  case node.kind
  of cnkNone, cnkEmpty:
    result = ""
  of cnkSym:
    result = node.name
  of cnkIntLit:
    result = $node.intVal
  of cnkUintLit:
    result = $node.uintVal
  of cnkFloatLit:
    result = $node.floatVal
  of cnkCharLit:
    result = escape($node.charVal)
  of cnkBoolLit:
    result = if node.boolVal: "true" else: "false"
  of cnkDiscardStmt:
    result = ind & "discard"
  of cnkContinueStmt:
    result = ind & "continue"
  of cnkBreakStmt:
    result = ind & "break"
  of cnkWritOnly:
    result = "writeonly"
  of cnkReadOnly:
    result = "readonly"
  of cnkSymDef:
    if node.args.len >= 2:
      result = renderIR(node.args[0], 0) & ": " & renderIR(node.args[1], 0)
    elif node.args.len == 1:
      result = renderIR(node.args[0], 0)
    else:
      result = ""
  of cnkVarTy:
    result = ind & "var "
    if node.args.len > 0:
      result.add(renderIR(node.args[0], 0))
    if node.args.len > 1:
      result.add(" = " & renderIR(node.args[1], 0))
  of cnkAsgn:
    result = ind
    if node.args.len >= 2:
      result.add(renderIR(node.args[0], 0) & " = " & renderIR(node.args[1], 0))
    elif node.args.len == 1:
      result.add(renderIR(node.args[0], 0))
  of cnkInfix:
    if node.args.len >= 3:
      let op = renderIR(node.args[0], 0)
      let left = renderIR(node.args[1], 0)
      let right = renderIR(node.args[2], 0)
      result = "(" & left & " " & op & " " & right & ")"
    elif node.args.len == 2:
      let op = renderIR(node.args[0], 0)
      let arg = renderIR(node.args[1], 0)
      result = "(" & op & " " & arg & ")"
    else:
      result = ""
  of cnkPrefix:
    if node.args.len >= 2:
      let op = renderIR(node.args[0], 0)
      let val = renderIR(node.args[1], 0)
      result = op & val
    else:
      result = ""
  of cnkCall:
    if node.args.len > 0:
      let fnName = renderIR(node.args[0], 0)
      var argStrs: seq[string] = @[]
      for i in 1..<node.args.len:
        argStrs.add(renderIR(node.args[i], 0))
      result = ind & fnName & "(" & argStrs.join(", ") & ")"
    else:
      result = ""

  of cnkConv:
    let ty = node.args[0].name
    let v = renderIR(node.args[1])
    result = ty & "(" & v & ")"
  of cnkStmtList, cnkSection:
    var lines: seq[string] = @[]
    for child in node.args:
      let rendered = renderIR(child, indent)
      if rendered.len > 0:
        lines.add(rendered)
    result = lines.join("\n")
  of cnkFuncDef:
    var name = ""
    var params = ""
    var retType = "void"
    var body = ""
    if node.args.len > 0: name = renderIR(node.args[0], 0)
    if node.args.len > 1: params = renderIR(node.args[1], 0)
    if node.args.len > 2: retType = renderIR(node.args[2], 0)
    if node.args.len > 3: body = renderIR(node.args[3], indent + 1)
    
    result = ind & "proc " & name & "(" & params & "): " & retType & " =\n" & body
  of cnkParams:
    var paramStrs: seq[string] = @[]
    for arg in node.args:
      paramStrs.add(renderIR(arg, 0))
    result = paramStrs.join(", ")
  of cnkReturnStmt:
    result = ind & "return"
    if node.args.len > 0:
      result.add(" " & renderIR(node.args[0], 0))
  of cnkIfStmt:
    result = ""
    for i, branch in node.args:
      result.add(renderIR(branch, indent))
      if i < node.args.len - 1:
        result.add("\n")
  of cnkElifBranch:
    if node.args.len >= 2:
      let cond = renderIR(node.args[0], 0)
      let body = renderIR(node.args[1], indent + 1)
      result = ind & "elif " & cond & ":\n" & body
    else:
      result = ""
  of cnkElse:
    if node.args.len >= 1:
      let body = renderIR(node.args[0], indent + 1)
      result = ind & "else:\n" & body
    else:
      result = ""
  of cnkWhileStmt:
    if node.args.len >= 2:
      let cond = renderIR(node.args[0], 0)
      let body = renderIR(node.args[1], indent + 1)
      result = ind & "while " & cond & ":\n" & body
    else:
      result = ""
  of cnkForStmt:
    if node.args.len >= 3:
      let iterVar = renderIR(node.args[1], 0) # ou équivalent selon la structure exacte
      let body = renderIR(node.args[^1], indent + 1)
      result = ind & "for ...:\n" & body
    else:
      result = ""
  of cnkDotExpr:
    var parts: seq[string] = @[]
    for arg in node.args:
      parts.add(renderIR(arg, 0))
    result = parts.join(".")
  else:
    var childStrs: seq[string] = @[]
    for arg in node.args:
      childStrs.add(renderIR(arg, indent))
    result = ind & "[" & $node.kind & ": " & childStrs.join(", ") & "]"

proc toInfixOp(c: NifCursor): string =
  result = ""
  assert c.exprKind in {AddX, SubX, MulX, DivX, AndX, OrX, XorX, EqX, NeqX, LtX, LeX}, "Can't get infix op of an unknown operation"
  case c.exprKind:
  of AddX: return "+"
  of SubX: return "-"
  of MulX: return "*"
  of DivX: return "/"
  of AndX: return "and"
  of OrX: return "or"
  of XorX: return "xor"
  of EqX: return "=="
  of NeqX: return "!="
  of LeX: return "<="
  of LtX: return "<"
  else: return

proc toPrefixOp(c: NifCursor): string =
  result = ""
  assert c.exprKind in {NegX, NotX}, "Can't get prefix op of an unknown operation"
  case c.exprKind:
  of NegX: return "-"
  of NotX: return "not"
  else: return

proc makeCallIR(c: NifCursor): CIRNode =
  result = newCIRNode(cnkCall)
  var it = firstChild(c)
  result.add(newCIRSym(it.symText))
  skip it

  while it.hasMore:
    result.add(toIR(it))
    skip it

proc makeBranchIR(c: NifCursor): CIRNode =
  var it = c

  case it.otherKind:
  of ElifU:
    result = newCIRNode(it.info, cnkElifBranch)
    var elifChild = firstChild(it)
    let condCur = firstChild(elifChild) 
    var bodyCur = elifChild
    skip bodyCur

    result.add(toIR(condCur))
    result.add(toIR(bodyCur))
  of ElseU:
    result = newCIRNode(it.info, cnkElse)
    result.add(toIR(firstChild(it)))
  of OfU:
    result = newCIRNode(it.info, cnkOfBranch)
    var n = firstChild(it)

    while n.hasMore:
      result.add(toIR(it))
      skip n
  else: assert false, "Unknown op"


proc toIR(n: NifCursor): CIRNode =
  var c = n
  result = newCIRNode(n.info, cnkEmpty)

  case c.kind:
  of Symbol, SymbolDef:
    result = newCIRSym(c.info, c.symText)
  of DotToken: discard
  of IntLit:
    result = newCIRIntLit(c.info, c.intVal)
  of UIntLit:
    result = newCIRUintLit(c.info, c.uintVal)
  of FloatLit:
    result = newCIRFloatLit(c.info, c.floatVal)
  of CharLit:
    result = newCIRCharLit(c.info, c.charLit)
  of LineInfoLit: return
  of TagLit:
    case c.exprKind:
    of DotX, DdotX, HderefX:
      result = newCIRNode(c.info, cnkDotExpr)
      let path = c.extractPath()

      if path.valid and path.path.len > 0:
        for p in path.path:
          result.add(newCIRSym(p.info, p.symText))
    of CallX, CmdX:
      result = makeCallIR(c)
    of ConvX:
      var it = firstChild(c)
      result = newCIRNode(it.info, cnkConv)
      result.add(newCIRSym(it.info, it.getTypeName))
      skip it
      result.add(toIR(it))
    of TrueX:
      result = newCIRNode(c.info, cnkBoolLit)
      result.boolVal = true
    of FalseX:
      result = newCIRNode(c.info, cnkBoolLit)
      result.boolVal = false
    of AddX, SubX, MulX, DivX, EqX, NeqX, LtX, LeX, AndX, OrX, XorX:
      result = newCIRNode(c.info, cnkInfix)
      var it = firstChild(c)
      var ty = it.getTypeName
      result.add(newCIRSym(it.info, it.toInfixOp))
      skip it # Skip type

      result.add(toIR(it))
      skip it
      result.add(toIR(it))
    of NotX, NegX:
      var it = firstChild(c)
      var ty = it.getTypeName
      result = newCIRNode(c.info, cnkPrefix)
      result.add(newCIRSym(c.info, toPrefixOp(c)))
      skip it
      result.add(toIR(it))
    of InfixX:
      result = newCIRNode(c.info, cnkInfix)
      var it = firstChild(c)
      result.add(newCIRSym(it.info, it.symText))
      skip it # Skip op

      result.add(toIR(it))
      skip it
      result.add(toIR(it))
    of PrefixX:
      var it = firstChild(c)
      result = newCIRNode(c.info, cnkPrefix)
      result.add(newCIRSym(it.info, it.symText))
      skip it # skip op
      result.add(toIR(it))
    of NoExpr:
      case c.stmtKind:
      of VarS, LetS:
        result = newCIRNode(c.info, cnkVarTy)
        let symNode = firstChild(n)
        var sd = newCIRNode(symNode.info, cnkSymDef)
        let kind = if n.stmtKind in {VarS, TvarS}: VarK else: LetK
        var typ = symNode
        skip typ
        skip typ
        skip typ
        var name = symNode.symText

        sd.add(newCIRSym(symNode.info, name))
        sd.add(newCIRSym(typ.info, typ.getTypeName))
        result.add(sd)
        skip typ

        if typ.kind == DotToken:
          reportIRError typ.info, "A variable can't be uninitialized to be translated to bytecode."
        result.add(toIR(typ))
      of AsgnS:
        result = newCIRNode(c.info, cnkAsgn)
        var it = firstChild(c)
        result.add(newCIRSym(it.info, it.symText))
        skip it
        result.add(toIR(it))
      of StmtsS, BlockS, ScopeS:
        result = newCIRNode(c.info, cnkStmtList)
        var it = firstChild(c)
        while it.hasMore:
          result.add(toIR(it))
          skip it
      of ForS:
        result = newCIRNode(c.info, cnkForStmt)
        var child = firstChild(c)
        let iterCur = child
        skip child
        var varsCur = child
        skip child
        let bodyCur = child
        var vchild = firstChild(varsCur)
        var sec = newCIRNode(varsCur.info, cnkSection)
        var found = false
        while vchild.hasMore:
          if vchild.stmtKind in {VarS, LetS}:
            if found:
              reportIRError vchild.info, "Can't use more than one iterator in for statement"
              break
            var v = newCIRNode(vchild.info, cnkVarTy)
            var symNode = firstChild(vchild)
            var sd = newCIRNode(symNode.info, cnkSymDef)
            var typ = symNode
            skip typ
            skip typ
            skip typ
            var name = symNode.symText
            sd.add(newCIRSym(symNode.info, name))
            sd.add(newCIRSym(typ.info, typ.getTypeName))
            v.add(sd)

            sec.add(v)
            found = true
          skip vchild

        result.add(sec)

        assert found, "Can't make for loop statement without loop variable"
        if iterCur.exprKind != InfixX or not iterCur.firstChild.symText.contains(".."):
          reportIRError iterCur.info, "Only `..` and `..<` can be used as iterators" 
          return
        var it = newCIRNode(iterCur.info, cnkInfix)
        var ic = firstChild(iterCur)
        let opStr = ic.symText

        it.add(newCIRSym(ic.info, opStr))
        skip ic # skip op to start operand
        it.add(toIR(ic))
        skip ic # skip start operand to stop operand
        it.add(toIR(ic))

        result.add(it)

        assert bodyCur.stmtKind == StmtsS, "For loop body should be a statement."
        result.add(toIR(bodyCur))

      of CommentS, DiscardS, ImportS, TypeS, NoStmt: return
      of ProcS, FuncS:
        result = newCIRNode(c.info, cnkFuncDef)
        var symNode = firstChild(c) # Definition of the proc
        let name = symNode.symText
        result.add(newCIRSym(symNode.info, name))

        # Skip directly to parameters
        skip symNode
        skip symNode
        skip symNode
        skip symNode

        let body = symNode
        if body.otherKind == ParamsU:
          var fieldCursor = firstChild(body)
          var p = newCIRNode(body.info, cnkParams)

          while fieldCursor.hasMore:
            if fieldCursor.exprKind != DotX:
              var field = firstChild(fieldCursor)
              var f = newCIRNode(fieldCursor, cnkSymDef)
              let fieldName = field
              skip field
              skip field
              skip field # pragmas
              let fieldType = field
              let fieldTyName = fieldType.getTypeName
              f.add(newCIRSym(fieldName.symText))
              f.add(newCIRSym(fieldTyName))
              p.add(f)
            skip fieldCursor

          result.add(p)

        var retNode = symNode
        var returnType = "void"
        skip retNode # Skip ParamsU to reach return type slot
        if retNode.hasMore and retNode.kind != DotToken:
          returnType = retNode.getTypeName

        result.add(newCIRSym(returnType))
        skip symNode
        skip symNode
        skip symNode
        skip symNode

        # Function's body
        result.add(toIR(symNode))

      of RetS:
        result = newCIRNode(cnkReturnStmt)
        result.add(toIR(firstChild(c)))

      of CallS:
        result = makeCallIR(c)

      of UnpackdeclS:
        result = newCIRNode(cnkSection)
        var inner = firstChild(n)
        while inner.hasMore:
          if inner.stmtKind in {VarS, LetS}:
            result.add(toIR(inner))
          skip inner

      of IfS:
        result = newCIRNode(cnkIfStmt)
        var it = firstChild(c)
        
        while it.hasMore:
          result.add(makeBranchIR(it))
          skip it

      of WhileS:
        result = newCIRNode(cnkWhileStmt)
        var child   = firstChild(c)
        let condCur = child
        var bodyCur = child
        skip bodyCur

        result.add(toIR(condCur))
        result.add(toIR(bodyCur))

      of AssumeS, AssertS: return
      of ContinueS:
        result = newCIRNode(cnkContinueStmt)
      of BreakS:
        result = newCIRNode(cnkBreakStmt)
      else: return
    else: assert false, "Unknown node: " & renderNode(c) & ". Kind = " & $c.kind & ", Expr = " & $c.exprKind & ", Stmt = " & $c.exprKind & ", Other = " & $c.otherKind
  else: assert false, "Unknown node: " & renderNode(c) & ". Kind = " & $c.kind & ", Expr = " & $c.exprKind & ", Stmt = " & $c.exprKind & ", Other = " & $c.otherKind
