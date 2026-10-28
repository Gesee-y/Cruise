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
    # src*: NodePos ## source position assigned during processNode
    case kind*: CIRNodeKind
    of cnkSym:
      name*: string
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

proc newCIRNode*(kind: static CIRNodeKind): CIRNode = CIRNode(kind: kind)
proc add*(a: var CIRNode, b: CIRNode) = a.args.add(b)
proc newCIRSym*(name: string): CIRNode = CIRNode(kind: cnkSym, name: name)
proc newCIRIntLit*(i: int): CIRNode = CIRNode(kind: cnkIntLit, intVal: i)
proc newCIRCharLit*(i: char): CIRNode = CIRNode(kind: cnkCharLit, charVal: i)
proc newCIRUintLit*(i: uint): CIRNode = CIRNode(kind: cnkUintLit, uintVal: i)
proc newCIRBoolLit*(i: bool): CIRNode = CIRNode(kind: cnkBoolLit, boolVal: i)
proc newCIRFloatLit*(i: float): CIRNode = CIRNode(kind: cnkFloatLit, floatVal: i)

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
    result = newCIRNode(cnkElifBranch)
    var elifChild = firstChild(it)
    let condCur = firstChild(elifChild) 
    var bodyCur = elifChild
    skip bodyCur

    result.add(toIR(condCur))
    result.add(toIR(bodyCur))
  of ElseU:
    result = newCIRNode(cnkElse)
    result.add(toIR(firstChild(it)))
  of OfU:
    result = newCIRNode(cnkOfBranch)
    var n = firstChild(it)

    while n.hasMore:
      result.add(toIR(it))
      skip n
  else: assert false, "Unknown op"


proc toIR(n: NifCursor): CIRNode =
  var c = n
  echo c.renderNode
  result = newCIRNode(cnkEmpty)

  case c.kind:
  of Symbol, SymbolDef:
    result = newCIRSym(c.symText)
  of DotToken: discard
  of IntLit:
    result = newCIRIntLit(c.intVal)
  of UIntLit:
    result = newCIRUintLit(c.uintVal)
  of FloatLit:
    result = newCIRFloatLit(c.floatVal)
  of CharLit:
    result = newCIRCharLit(c.charLit)
  of LineInfoLit: return
  of TagLit:
    case c.exprKind:
    of DotX, DdotX, HderefX:
      result = newCIRNode(cnkDotExpr)
      let path = c.extractPath()

      if path.valid and path.path.len > 0:
        for p in path.path:
          result.add(newCIRSym(p.symText))
    of CallX, CmdX:
      result = makeCallIR(c)
    of ConvX:
      var it = firstChild(c)
      result = newCIRNode(cnkConv)
      result.add(newCIRSym(it.getTypeName))
      skip it
      result.add(toIR(it))
    of TrueX:
      result = newCIRNode(cnkBoolLit)
      result.boolVal = true
    of FalseX:
      result = newCIRNode(cnkBoolLit)
      result.boolVal = false
    of AddX, SubX, MulX, DivX, AndX, OrX, XorX, EqX, NeqX, LtX, LeX:
      result = newCIRNode(cnkInfix)
      var it = firstChild(c)
      result.add(newCIRSym(c.toInfixOp))
      skip it # Skip type

      result.add(toIR(it))
      skip it
      result.add(toIR(it))
    of NotX, NegX:
      var it = firstChild(c)
      result = newCIRNode(cnkPrefix)
      result.add(newCIRSym(toPrefixOp(c)))
      skip it
      result.add(toIR(it))

    of NoExpr:
      case c.stmtKind:
      of VarS, LetS:
        result = newCIRNode(cnkVarTy)
        var sd = newCIRNode(cnkSymDef)
        let symNode = firstChild(n)
        let kind = if n.stmtKind in {VarS, TvarS}: VarK else: LetK
        var typ = symNode
        skip typ
        skip typ
        skip typ
        var name = symNode.symText

        sd.add(newCIRSym(name))
        sd.add(newCIRSym(typ.getTypeName))
        result.add(sd)
        skip typ

        assert typ.kind != DotToken, "A variable can't be uninitialized to be translated to bytecode."
        result.add(toIR(typ))
      of AsgnS:
        result = newCIRNode(cnkAsgn)
        var it = firstChild(c)
        result.add(newCIRSym(it.symText))
        skip it
        result.add(toIR(it))
      of StmtsS, BlockS, ScopeS:
        result = newCIRNode(cnkStmtList)
        var it = firstChild(c)
        while it.hasMore:
          result.add(toIR(it))
          skip it
      of ForS:
        result = newCIRNode(cnkForStmt)
        var child = firstChild(c)
        let iterCur = child
        skip child
        var varsCur = child
        skip child
        let bodyCur = child
        var vchild = firstChild(varsCur)
        var found = false
        while vchild.hasMore:
          if vchild.stmtKind in {VarS, LetS}:
            assert not found, "Can't use more than one iterator in for statement"
            var v = newCIRNode(cnkVarTy)
            var sd = newCIRNode(cnkSymDef)
            var symNode = firstChild(vchild)
            var typ = symNode
            skip typ
            skip typ
            skip typ
            var name = symNode.symText
            sd.add(newCIRSym(name))
            sd.add(newCIRSym(typ.getTypeName))
            v.add(sd)

            result.add(v)
            found = true
          skip vchild

        assert found, "Can't make for loop statement without loop variable"
        assert iterCur.exprKind == InfixX and iterCur.firstChild.symText.contains(".."), "Only `..` and `..<` can be used as iterators" 
        var it = newCIRNode(cnkInfix)
        var ic = firstChild(iterCur)
        let opStr = ic.symText

        it.add(newCIRSym(opStr))
        skip ic # skip op to start operand
        it.add(toIR(ic))
        skip ic # skip start operand to stop operand
        it.add(toIR(ic))

        result.add(it)

        assert bodyCur.stmtKind == StmtsS, "For loop body should be a statement."
        result.add(toIR(bodyCur))

      of CommentS, DiscardS, ImportS, TypeS, NoStmt: return
      of ProcS, FuncS:
        result = newCIRNode(cnkFuncDef)
        var symNode = firstChild(c) # Definition of the proc
        let name = symNode.symText
        result.add(newCIRSym(name))

        # Skip directly to parameters
        skip symNode
        skip symNode
        skip symNode
        skip symNode

        let body = symNode
        if body.otherKind == ParamsU:
          var fieldCursor = firstChild(body)
          var p = newCIRNode(cnkParams)

          while fieldCursor.hasMore:
            if fieldCursor.exprKind != DotX:
              var f = newCIRNode(cnkSymDef)
              var field = firstChild(fieldCursor)
              let fieldName = field.symText
              skip field
              skip field
              skip field # pragmas
              let fieldType = field
              let fieldTyName = fieldType.getTypeName
              f.add(newCIRSym(fieldName))
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




          


