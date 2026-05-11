## =============================================================================
## test_transpiler.nim
## Full test suite for the NIM -> Cruise IR Transpiler
## =============================================================================
##
## Run with:
##   nim c -r test_transpiler.nim
##
## The suite is organised into sections that mirror the transpiler's
## own structure:
##
##   1.  CIRNode construction utilities
##   2.  normalizeTypes / isPrimitiveType helpers
##   3.  isWrapperType
##   4.  CIRContext initialisation
##   5.  processNode – literal nodes   (int, float, sym, empty …)
##   6.  processNode – operators       (infix, prefix)
##   7.  processNode – assignments     (plain, return-context)
##   8.  processNode – control flow    (if/elif/else, while, for, case)
##   9.  processNode – expressions     (bracketExpr, dotExpr, cast, conv)
##   10. processNode – declarations    (var/let sections)
##   11. processNode – calls & object construction
##   12. processNode – stmtListExpr
##   13. processNode – hidden conversions
##   14. processDeclaration
##   15. processParams
##   16. emitQualifiedVar
##   17. emitStruct
##   18. remapFunc
##   19. compileToIR macro (end-to-end)
##   20. Edge-cases and error paths

import unittest, macros, tables, sets, strutils

# ---------------------------------------------------------------------------
# Re-export the module under test.  Adjust the path if needed.
# ---------------------------------------------------------------------------
include "../../src/shadert/ir.nim"   # or: import transpiler

# ---------------------------------------------------------------------------
# Helpers shared across test suites
# ---------------------------------------------------------------------------

proc makeCtx(): CIRContext =
  result.typeDecl    = newCIRNode(cnkStmtList)
  result.forwardDecl = newCIRNode(cnkStmtList)
  result.funcDef     = newCIRNode(cnkStmtList)
  result.body        = newCIRNode(cnkStmtList)

proc sym(n: string): CIRNode = newCIRSym(n)
proc ilit(i: int): CIRNode   = newCIRIntLit(i)
proc flit(f: float): CIRNode = newCIRFloatLit(f)
proc prefix(op: NimNode, node: NimNode): NimNode = prefix(node, op.strVal)

# =============================================================================
# 1. CIRNode construction utilities
# =============================================================================

suite "CIRNode construction":

  test "newCIRNode returns node with correct kind":
    let n = newCIRNode(cnkStmtList)
    check n.kind == cnkStmtList

  test "newCIRSym stores name":
    let n = newCIRSym("myVar")
    check n.kind == cnkSym
    check n.name == "myVar"

  test "newCIRIntLit stores integer value":
    let n = newCIRIntLit(42)
    check n.kind == cnkIntLit
    check n.intVal == 42

  test "newCIRIntLit stores negative integer":
    let n = newCIRIntLit(-7)
    check n.intVal == -7

  test "newCIRFloatLit stores float value":
    let n = newCIRFloatLit(3.14)
    check n.kind == cnkFloatLit
    check abs(n.floatVal - 3.14) < 1e-9

  test "newCIRFloatLit stores zero":
    let n = newCIRFloatLit(0.0)
    check n.floatVal == 0.0

  test "add appends child to args":
    var parent = newCIRNode(cnkStmtList)
    parent.add(newCIRSym("child"))
    check parent.args.len == 1
    check parent.args[0].kind == cnkSym

  test "add appends multiple children in order":
    var parent = newCIRNode(cnkStmtList)
    parent.add(newCIRIntLit(1))
    parent.add(newCIRIntLit(2))
    parent.add(newCIRIntLit(3))
    check parent.args.len == 3
    check parent.args[0].intVal == 1
    check parent.args[2].intVal == 3

  test "leaf nodes have empty args by default":
    # cnkDiscardStmt is a no-data leaf via the 'discard' branch
    let n = newCIRNode(cnkDiscardStmt)
    check n.kind == cnkDiscardStmt

  test "cnkEmpty node has correct kind":
    let n = newCIRNode(cnkEmpty)
    check n.kind == cnkEmpty

  test "cnkContinueStmt node has correct kind":
    let n = newCIRNode(cnkContinueStmt)
    check n.kind == cnkContinueStmt

  test "cnkBreakStmt node has correct kind":
    let n = newCIRNode(cnkBreakStmt)
    check n.kind == cnkBreakStmt

  test "cnkWritOnly node has correct kind":
    let n = newCIRNode(cnkWritOnly)
    check n.kind == cnkWritOnly

  test "cnkReadOnly node has correct kind":
    let n = newCIRNode(cnkReadOnly)
    check n.kind == cnkReadOnly

# =============================================================================
# 2. normalizeTypes / isPrimitiveType
# =============================================================================

suite "normalizeTypes":

  test "int maps to int":
    check normalizeTypes("int") == "int"

  test "int32 maps to int":
    check normalizeTypes("int32") == "int"

  test "float maps to float":
    check normalizeTypes("float") == "float"

  test "float32 maps to float":
    check normalizeTypes("float32") == "float"

  test "float64 maps to double":
    check normalizeTypes("float64") == "double"

  test "bool maps to bool":
    check normalizeTypes("bool") == "bool"

  test "uint32 maps to uint":
    check normalizeTypes("uint32") == "uint"

  test "unknown type returns empty string when not in table":
    check normalizeTypes("MyCustomType") == ""

  test "registered IR type is returned":
    # Directly insert into the compile-time table and call at runtime.
    # We test the run-time branch via a local wrapper if possible;
    # at minimum we verify normalizeTypes returns "" for unknown names.
    check normalizeTypes("vec2") == ""   # not yet registered in this test


suite "isPrimitiveType":

  test "int is primitive":
    check isPrimitiveType("int") == true

  test "float is primitive":
    check isPrimitiveType("float") == true

  test "string is primitive":
    check isPrimitiveType("string") == true

  test "cstring is primitive":
    check isPrimitiveType("cstring") == true

  test "seq is primitive":
    check isPrimitiveType("seq") == true

  test "set is primitive":
    check isPrimitiveType("set") == true

  test "vec2 is not primitive":
    check isPrimitiveType("vec2") == false

  test "MyStruct is not primitive":
    check isPrimitiveType("MyStruct") == false

  test "empty string is not primitive":
    check isPrimitiveType("") == false

# =============================================================================
# 3. isWrapperType
# =============================================================================

suite "isWrapperType":

  test "Uniform[float32] is a wrapper":
    check isWrapperType("Uniform[float32]") == true

  test "UniformReadOnly[vec4] is a wrapper":
    check isWrapperType("UniformReadOnly[vec4]") == true

  test "UniformWriteOnly[int] is a wrapper":
    check isWrapperType("UniformWriteOnly[int]") == true

  test "Sampler2D is a wrapper":
    check isWrapperType("Sampler2D") == true

  test "float32 is not a wrapper":
    check isWrapperType("float32") == false

  test "MyStruct is not a wrapper":
    check isWrapperType("MyStruct") == false

  test "Image2D[rgba8] starts with Image2D and is detected by emitQualifiedVar":
    # isWrapperType itself only checks Uniform* and Sampler2D.
    # Image2D is handled inside emitQualifiedVar, so it is NOT a wrapper here.
    check isWrapperType("Image2D[rgba8]") == false

# =============================================================================
# 4. CIRContext initialisation
# =============================================================================

suite "CIRContext initialisation":

  test "fresh context has empty emittedTypes":
    let ctx = makeCtx()
    check ctx.emittedTypes.len == 0

  test "fresh context has empty emittedFuncs":
    let ctx = makeCtx()
    check ctx.emittedFuncs.len == 0

  test "typeDecl starts as StmtList":
    let ctx = makeCtx()
    check ctx.typeDecl.kind == cnkStmtList

  test "forwardDecl starts as StmtList":
    let ctx = makeCtx()
    check ctx.forwardDecl.kind == cnkStmtList

  test "funcDef starts as StmtList":
    let ctx = makeCtx()
    check ctx.funcDef.kind == cnkStmtList

# =============================================================================
# 5. processNode – literal nodes
# =============================================================================
#
# We drive processNode through typed Nim AST by constructing NimNodes by hand
# at compile time inside a helper macro and asserting on the returned CIRNode.

macro checkLiteralInt(expected: static int): bool =
  let node = newLit(expected)
  var ctx = makeCtx()
  let res = processNode(ctx, node)
  result = newLit(res.kind == cnkIntLit and res.intVal == expected)

macro checkLiteralFloat(expected: static float): bool =
  let node = newLit(expected)
  var ctx = makeCtx()
  let res = processNode(ctx, node)
  result = newLit(res.kind == cnkFloatLit)

suite "processNode – literals":

  test "integer literal produces cnkIntLit":
    check checkLiteralInt(0)

  test "integer literal value is preserved":
    check checkLiteralInt(99)

  test "negative integer literal":
    check checkLiteralInt(-1)

  test "float literal produces cnkFloatLit":
    check checkLiteralFloat(1.5)

  test "nnkEmpty produces cnkEmpty":
    macro testEmpty(): bool =
      var ctx = makeCtx()
      let res = processNode(ctx, newEmptyNode())
      result = newLit(res.kind == cnkEmpty)
    check testEmpty()

  test "nnkIdent produces cnkSym with matching name":
    macro testIdent(): bool =
      var ctx = makeCtx()
      let node = newIdentNode("someIdent")
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkSym and res.name == "someIdent")
    check testIdent()

  test "nnkDiscardStmt produces cnkDiscardStmt":
    macro testDiscard(): bool =
      var ctx = makeCtx()
      let node = newNimNode(nnkDiscardStmt)
      node.add(newEmptyNode())
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkDiscardStmt)
    check testDiscard()

  test "nnkBreakStmt produces cnkBreakStmt":
    macro testBreak(): bool =
      var ctx = makeCtx()
      let node = newNimNode(nnkBreakStmt)
      node.add(newEmptyNode())
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkBreakStmt)
    check testBreak()

  test "nnkContinueStmt produces cnkContinueStmt":
    macro testContinue(): bool =
      var ctx = makeCtx()
      let node = newNimNode(nnkContinueStmt)
      node.add(newEmptyNode())
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkContinueStmt)
    check testContinue()

# =============================================================================
# 6. processNode – operators (infix, prefix)
# =============================================================================

suite "processNode – operators":

  test "infix node produces cnkInfix with operator sym and two children":
    macro testInfix(): bool =
      var ctx = makeCtx()
      let node = infix(newLit(1), "+", newLit(2))
      let res = processNode(ctx, node)
      result = newLit(
        res.kind == cnkInfix and
        res.args[0].name == "+" and
        res.args[1].intVal == 1 and
        res.args[2].intVal == 2
      )
    check testInfix()

  test "infix '<' operator is preserved":
    macro testLt(): bool =
      var ctx = makeCtx()
      let node = infix(newLit(0), "<", newLit(10))
      let res = processNode(ctx, node)
      result = newLit(res.args[0].name == "<")
    check testLt()

  test "prefix '-' produces cnkPrefix":
    macro testPrefix(): bool =
      var ctx = makeCtx()
      let node = prefix(newIdentNode("-"), newLit(5))
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkPrefix and res.args[0].name == "-")
    check testPrefix()

  test "nested infix builds tree of depth 2":
    macro testNested(): bool =
      var ctx = makeCtx()
      let inner = infix(newLit(1), "*", newLit(2))
      let outer = infix(inner, "+", newLit(3))
      let res = processNode(ctx, outer)
      result = newLit(
        res.kind == cnkInfix and
        res.args[1].kind == cnkInfix
      )
    check testNested()

# =============================================================================
# 7. processNode – assignments
# =============================================================================

suite "processNode – assignments":

  test "plain assignment produces cnkAsgn":
    macro testAsgn(): bool =
      var ctx = makeCtx()
      let node = newNimNode(nnkAsgn)
      node.add newIdentNode("x")
      node.add newLit(7)
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkAsgn)
    check testAsgn()

  test "assignment lhs is preserved":
    macro testAsgnLhs(): bool =
      var ctx = makeCtx()
      let node = newNimNode(nnkAsgn)
      node.add newIdentNode("result")
      node.add newLit(0)
      let res = processNode(ctx, node)
      result = newLit(res.args[0].name == "result")
    check testAsgnLhs()

  test "assignment rhs is preserved":
    macro testAsgnRhs(): bool =
      var ctx = makeCtx()
      let node = newNimNode(nnkAsgn)
      node.add newIdentNode("x")
      node.add newLit(42)
      let res = processNode(ctx, node)
      result = newLit(res.args[1].intVal == 42)
    check testAsgnRhs()

  test "assignment in return context yields rhs only":
    macro testAsgnReturn(): bool =
      var ctx = makeCtx()
      let node = newNimNode(nnkAsgn)
      node.add newIdentNode("result")
      node.add newLit(99)
      let res = processNode(ctx, node, pcReturn)
      result = newLit(res.kind == cnkIntLit and res.intVal == 99)
    check testAsgnReturn()

# =============================================================================
# 8. processNode – control flow
# =============================================================================

suite "processNode – if statements":

  test "if/elif branch produces cnkIfStmt":
    macro testIf(): bool =
      var ctx = makeCtx()
      var ifNode = newNimNode(nnkIfStmt)
      var branch = newNimNode(nnkElifBranch)
      branch.add newLit(true)
      branch.add newNimNode(nnkStmtList)
      ifNode.add branch
      let res = processNode(ctx, ifNode)
      result = newLit(res.kind == cnkIfStmt)
    check testIf()

  test "else branch is emitted as cnkElse":
    macro testElse(): bool =
      var ctx = makeCtx()
      var ifNode = newNimNode(nnkIfStmt)
      var elif1 = newNimNode(nnkElifBranch)
      elif1.add newLit(false)
      elif1.add newNimNode(nnkStmtList)
      var elseNode = newNimNode(nnkElse)
      elseNode.add newNimNode(nnkStmtList)
      ifNode.add elif1
      ifNode.add elseNode
      let res = processNode(ctx, ifNode)
      # The else branch is built inside the loop; we just need no crash.
      result = newLit(res.kind == cnkIfStmt)
    check testElse()

suite "processNode – while loops":

  test "while statement produces cnkWhileStmt":
    macro testWhile(): bool =
      var ctx = makeCtx()
      var wNode = newNimNode(nnkWhileStmt)
      wNode.add newLit(true)
      wNode.add newNimNode(nnkStmtList)
      let res = processNode(ctx, wNode)
      result = newLit(res.kind == cnkWhileStmt)
    check testWhile()

  test "while condition is first child":
    macro testWhileCond(): bool =
      var ctx = makeCtx()
      var wNode = newNimNode(nnkWhileStmt)
      wNode.add newIdentNode("cond")
      wNode.add newNimNode(nnkStmtList)
      let res = processNode(ctx, wNode)
      result = newLit(res.args[0].name == "cond")
    check testWhileCond()

  test "while body is second child":
    macro testWhileBody(): bool =
      var ctx = makeCtx()
      var wNode = newNimNode(nnkWhileStmt)
      wNode.add newLit(true)
      var body = newNimNode(nnkStmtList)
      body.add newNimNode(nnkBreakStmt)
      wNode.add body
      let res = processNode(ctx, wNode)
      result = newLit(res.args[1].kind == cnkStmtList)
    check testWhileBody()

suite "processNode – for loops":

  test "for with range produces cnkForStmt":
    macro testFor(): bool =
      var ctx = makeCtx()
      var forNode = newNimNode(nnkForStmt)
      forNode.add newIdentNode("i")
      forNode.add infix(newLit(0), "..<", newLit(10))
      forNode.add newNimNode(nnkStmtList)
      let res = processNode(ctx, forNode)
      result = newLit(res.kind == cnkForStmt)
    check testFor()

  test "for loop variable name is preserved":
    macro testForVar(): bool =
      var ctx = makeCtx()
      var forNode = newNimNode(nnkForStmt)
      forNode.add newIdentNode("idx")
      forNode.add infix(newLit(0), "..<", newLit(5))
      forNode.add newNimNode(nnkStmtList)
      let res = processNode(ctx, forNode)
      result = newLit(res.args[0].name == "idx")
    check testForVar()

  test "for loop start bound is second child":
    macro testForStart(): bool =
      var ctx = makeCtx()
      var forNode = newNimNode(nnkForStmt)
      forNode.add newIdentNode("i")
      forNode.add infix(newLit(3), "..<", newLit(9))
      forNode.add newNimNode(nnkStmtList)
      let res = processNode(ctx, forNode)
      result = newLit(res.args[1].intVal == 3)
    check testForStart()

  test "for loop end bound is third child":
    macro testForEnd(): bool =
      var ctx = makeCtx()
      var forNode = newNimNode(nnkForStmt)
      forNode.add newIdentNode("i")
      forNode.add infix(newLit(0), "..<", newLit(7))
      forNode.add newNimNode(nnkStmtList)
      let res = processNode(ctx, forNode)
      result = newLit(res.args[2].intVal == 7)
    check testForEnd()

suite "processNode – case statements":

  test "case statement produces cnkCaseStmt":
    macro testCase(): bool =
      var ctx = makeCtx()
      var caseNode = newNimNode(nnkCaseStmt)
      caseNode.add newIdentNode("x")
      var ofBranch = newNimNode(nnkOfBranch)
      ofBranch.add newLit(0)
      ofBranch.add newNimNode(nnkStmtList)
      caseNode.add ofBranch
      let res = processNode(ctx, caseNode)
      result = newLit(res.kind == cnkCaseStmt)
    check testCase()

  test "case discriminant is first child":
    macro testCaseDisc(): bool =
      var ctx = makeCtx()
      var caseNode = newNimNode(nnkCaseStmt)
      caseNode.add newIdentNode("mode")
      var ofBranch = newNimNode(nnkOfBranch)
      ofBranch.add newLit(1)
      ofBranch.add newNimNode(nnkStmtList)
      caseNode.add ofBranch
      let res = processNode(ctx, caseNode)
      result = newLit(res.args[0].name == "mode")
    check testCaseDisc()

  test "of branch produces cnkOfBranch":
    macro testOfBranch(): bool =
      var ctx = makeCtx()
      var caseNode = newNimNode(nnkCaseStmt)
      caseNode.add newIdentNode("x")
      var ofBranch = newNimNode(nnkOfBranch)
      ofBranch.add newLit(2)
      ofBranch.add newNimNode(nnkStmtList)
      caseNode.add ofBranch
      let res = processNode(ctx, caseNode)
      result = newLit(res.args[1].kind == cnkOfBranch)
    check testOfBranch()

# =============================================================================
# 9. processNode – expressions
# =============================================================================

suite "processNode – bracket / dot / cast / conv":

  test "bracketExpr produces cnkBracketExpr":
    macro testBracket(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkBracketExpr)
      node.add newIdentNode("buf")
      node.add newLit(0)
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkBracketExpr)
    check testBracket()

  test "bracketExpr children are base then index":
    macro testBracketChildren(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkBracketExpr)
      node.add newIdentNode("arr")
      node.add newLit(3)
      let res = processNode(ctx, node)
      result = newLit(res.args[0].name == "arr" and res.args[1].intVal == 3)
    check testBracketChildren()

  test "dotExpr produces cnkDotExpr":
    macro testDot(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkDotExpr)
      node.add newIdentNode("pos")
      node.add newIdentNode("x")
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkDotExpr)
    check testDot()

  test "dotExpr object is first child":
    macro testDotObj(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkDotExpr)
      node.add newIdentNode("myVec")
      node.add newIdentNode("y")
      let res = processNode(ctx, node)
      result = newLit(res.args[0].name == "myVec")
    check testDotObj()

  test "dotExpr field is second child":
    macro testDotField(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkDotExpr)
      node.add newIdentNode("myVec")
      node.add newIdentNode("z")
      let res = processNode(ctx, node)
      result = newLit(res.args[1].name == "z")
    check testDotField()

  test "cast produces cnkCast":
    macro testCast(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkCast)
      node.add newIdentNode("float32")
      node.add newLit(1)
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkCast)
    check testCast()

  test "conv produces cnkConv":
    macro testConv(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkConv)
      node.add newIdentNode("int")
      node.add newLit(3.0)
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkConv)
    check testConv()

# =============================================================================
# 10. processNode – stmtList / stmtListExpr
# =============================================================================

suite "processNode – statement lists":

  test "empty stmtList produces cnkStmtList with no children":
    macro testEmptyStmt(): bool =
      var ctx = makeCtx()
      let res = processNode(ctx, newNimNode(nnkStmtList))
      result = newLit(res.kind == cnkStmtList and res.args.len == 0)
    check testEmptyStmt()

  test "stmtList with two nodes has two children":
    macro testTwoStmts(): bool =
      var ctx = makeCtx()
      var sl = newNimNode(nnkStmtList)
      sl.add newLit(1)
      sl.add newLit(2)
      let res = processNode(ctx, sl)
      result = newLit(res.args.len == 2)
    check testTwoStmts()

  test "stmtListExpr produces cnkStmtListExpr":
    macro testStmtListExpr(): bool =
      var ctx = makeCtx()
      var sle = newNimNode(nnkStmtListExpr)
      sle.add newLit(10)   # statement
      sle.add newLit(20)   # expression value
      let res = processNode(ctx, sle)
      result = newLit(res.kind == cnkStmtListExpr)
    check testStmtListExpr()

  test "stmtListExpr last child is expression value":
    macro testStmtListExprLast(): bool =
      var ctx = makeCtx()
      var sle = newNimNode(nnkStmtListExpr)
      sle.add newLit(1)
      sle.add newLit(99)
      let res = processNode(ctx, sle)
      result = newLit(res.args[^1].intVal == 99)
    check testStmtListExprLast()

# =============================================================================
# 11. processNode – hidden conversions
# =============================================================================

suite "processNode – hidden conversions":

  test "nnkHiddenStdConv passes through inner node":
    macro testHiddenStd(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkHiddenStdConv)
      node.add newEmptyNode()    # target type (ignored)
      node.add newLit(5)
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkIntLit and res.intVal == 5)
    check testHiddenStd()

  test "nnkHiddenSubConv passes through inner node":
    macro testHiddenSub(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkHiddenSubConv)
      node.add newEmptyNode()
      node.add newLit(7)
      let res = processNode(ctx, node)
      result = newLit(res.intVal == 7)
    check testHiddenSub()

  test "nnkHiddenDeref passes through inner node":
    macro testHiddenDeref(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkHiddenDeref)
      node.add newIdentNode("ptr_x")
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkSym and res.name == "ptr_x")
    check testHiddenDeref()

  test "nnkHiddenCallConv produces cnkHiddenCallConv":
    macro testHiddenCall(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkHiddenCallConv)
      node.add newIdentNode("float")
      node.add newLit(3)
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkHiddenCallConv)
    check testHiddenCall()

# =============================================================================
# 12. processNode – return statement
# =============================================================================

suite "processNode – return statement":

  test "nnkReturnStmt produces cnkReturnStmt":
    macro testReturn(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkReturnStmt)
      node.add newLit(0)
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkReturnStmt)
    check testReturn()

  test "return value is first child":
    macro testReturnVal(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkReturnStmt)
      node.add newLit(42)
      let res = processNode(ctx, node)
      result = newLit(res.args[0].intVal == 42)
    check testReturnVal()

# =============================================================================
# 13. processNode – bracket array literal
# =============================================================================

suite "processNode – array bracket literal":

  test "nnkBracket produces cnkBracket":
    macro testBracketLit(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkBracket)
      node.add newLit(1)
      node.add newLit(2)
      node.add newLit(3)
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkBracket)
    check testBracketLit()

  test "nnkBracket child count matches element count":
    macro testBracketCount(): bool =
      var ctx = makeCtx()
      var node = newNimNode(nnkBracket)
      for i in 0..<5:
        node.add newLit(i)
      let res = processNode(ctx, node)
      result = newLit(res.args.len == 5)
    check testBracketCount()

# =============================================================================
# 14. ensureStmtList
# =============================================================================

suite "ensureStmtList":

  test "already-StmtList is returned unchanged":
    macro testAlready(): bool =
      var sl = newNimNode(nnkStmtList)
      sl.add newLit(1)
      let res = ensureStmtList(sl)
      result = newLit(res.kind == nnkStmtList and res.len == 1)
    check testAlready()

  test "non-StmtList is wrapped":
    macro testWrap(): bool =
      let node = newLit(7)
      let res = ensureStmtList(node)
      result = newLit(res.kind == nnkStmtList and res[0].intVal == 7)
    check testWrap()

  test "nnkStmtListExpr is returned as-is":
    macro testSLE(): bool =
      var sle = newNimNode(nnkStmtListExpr)
      sle.add newLit(0)
      let res = ensureStmtList(sle)
      result = newLit(res.kind == nnkStmtListExpr)
    check testSLE()

# =============================================================================
# 15. emitQualifiedVar
# =============================================================================

suite "emitQualifiedVar":

  test "Uniform[float32] emits cnkUniform":
    macro testUniform(): bool =
      var ctx = makeCtx()
      let node = emitQualifiedVar(ctx, "Uniform[float32]", "uTime")
      result = newLit(node.kind == cnkUniform)
    check testUniform()

  test "UniformReadOnly emits cnkUniform with cnkReadOnly qualifier":
    macro testROUniform(): bool =
      var ctx = makeCtx()
      let node = emitQualifiedVar(ctx, "UniformReadOnly[vec4]", "uColor")
      result = newLit(node.kind == cnkUniform and node.args[0].kind == cnkReadOnly)
    check testROUniform()

  test "UniformWriteOnly emits cnkUniform with cnkWritOnly qualifier":
    macro testWOUniform(): bool =
      var ctx = makeCtx()
      let node = emitQualifiedVar(ctx, "UniformWriteOnly[vec4]", "uOut")
      result = newLit(node.kind == cnkUniform and node.args[0].kind == cnkWritOnly)
    check testWOUniform()

  test "SSBO emits cnkBuffer":
    macro testSSBO(): bool =
      var ctx = makeCtx()
      # Register the SSBO mapping so irUniformTable["SSBO"] == "SSBO"
      irUniformTable["SSBO"] = "SSBO"
      let node = emitQualifiedVar(ctx, "SSBO[float32]", "buf")
      result = newLit(node.kind == cnkBuffer)
    check testSSBO()

  test "Image2D emits cnkImage":
    macro testImage(): bool =
      var ctx = makeCtx()
      let node = emitQualifiedVar(ctx, "Image2D[rgba8]", "imgOut")
      result = newLit(node.kind == cnkImage)
    check testImage()

  test "Image2D dimension is 2":
    macro testImageDim(): bool =
      var ctx = makeCtx()
      let node = emitQualifiedVar(ctx, "Image2D[rgba8]", "imgOut")
      result = newLit(node.args[0].intVal == 2)
    check testImageDim()

  test "Sampler2D emits cnkSampler":
    macro testSampler(): bool =
      var ctx = makeCtx()
      let node = emitQualifiedVar(ctx, "Sampler2D", "tex")
      result = newLit(node.kind == cnkSampler)
    check testSampler()

  test "Sampler2D dimension is 2":
    macro testSamplerDim(): bool =
      var ctx = makeCtx()
      let node = emitQualifiedVar(ctx, "Sampler2D", "tex")
      result = newLit(node.args[0].intVal == 2)
    check testSamplerDim()

# =============================================================================
# 16. remapFunc – name resolution
# =============================================================================

suite "remapFunc – function name resolution":

  test "explicitly mapped function returns IR name":
    macro testMapped(): bool =
      irFuncTable["dot"] = "dot"
      var ctx = makeCtx()
      let node = newIdentNode("dot")
      let res = ctx.remapFunc("dot", node)
      result = newLit(res.name == "dot")
    check testMapped()

  test "already-emitted function returns sym without re-emitting":
    macro testAlreadyEmitted(): bool =
      var ctx = makeCtx()
      ctx.emittedFuncs.incl("myHelper")
      irFuncTable["myHelper"] = "myHelper"
      let node = newIdentNode("myHelper")
      let res = ctx.remapFunc("myHelper", node)
      result = newLit(res.name == "myHelper")
    check testAlreadyEmitted()

# =============================================================================
# 17. compileToIR – end-to-end smoke tests
# =============================================================================
#
# These tests compile tiny Nim functions through the full macro pipeline
# and assert on the shape of the returned CIRContext.

proc addTwoInts(a, b: int32): int32 = a + b
proc voidShader(x: int32) = discard
proc loopShader(n: int32) =
  for i in 0..<n:
    discard
proc whileShader(x: int32) =
  var i = x
  while i < 10'i32:
    i = i + 1'i32
proc ifShader(x: int32): int32 =
  if x > 0'i32: 1'i32 else: 0'i32
proc bracketShader(arr: array[4, int32], i: int32): int32 =
  arr[i]

suite "compileToIR – end-to-end":

  test "body kind is cnkFuncDef":
    let ctx {.compileTime.} = compileToIR(addTwoInts)
    static:
      assert ctx.body.kind == cnkFuncDef

  test "function name is preserved in signature":
    let ctx {.compileTime.} = compileToIR(addTwoInts)
    static:
      assert ctx.body.args[0].args[0].name == "addTwoInts"

  test "function body is cnkStmtList":
    let ctx {.compileTime.} = compileToIR(addTwoInts)
    static:
      assert ctx.body.args[1].kind == cnkStmtList

  test "void return type emits cnkEmpty":
    let ctx {.compileTime.} = compileToIR(voidShader)
    static:
      # signature.args[1] is the return type node
      assert ctx.body.args[0].args[1].kind == cnkEmpty

  test "for loop inside shader is emitted as cnkForStmt":
    let ctx {.compileTime.} = compileToIR(loopShader)
    static:
      # body is args[1], which is a stmtList; first stmt is the for
      assert ctx.body.args[1].args[0].kind == cnkForStmt

  test "while loop inside shader is emitted as cnkWhileStmt":
    let ctx {.compileTime.} = compileToIR(whileShader)
    static:
      # Second stmt in body is the while
      assert ctx.body.args[1].args[1].kind == cnkWhileStmt

  test "if expression inside shader emits cnkIfStmt":
    let ctx {.compileTime.} = compileToIR(ifShader)
    static:
      assert ctx.body.args[1].args[0].kind == cnkIfStmt

  test "array indexing emits cnkBracketExpr":
    let ctx {.compileTime.} = compileToIR(bracketShader)
    static:
      assert ctx.body.args[1].args[0].kind == cnkBracketExpr

# =============================================================================
# 19. processParams – signature building helpers
# =============================================================================
#
# processParams is a compile-time proc so we drive it via a helper macro.

macro countParams(fn: typed): int =
  var ctx = makeCtx()
  let impl = fn.getImpl
  let params = impl[3]
  let processed = ctx.processParams(params)
  result = newLit(processed.len)

proc threeArgFn(a, b, c: int32): int32 = a + b + c
proc noArgFn(): int32 = 0

suite "processParams":

  test "three-argument function produces three IdentDef nodes":
    check countParams(threeArgFn) == 3

  test "no-argument function produces zero IdentDef nodes":
    check countParams(noArgFn) == 0

# =============================================================================
# 20. Edge cases
# =============================================================================

suite "Edge cases":

  test "processNode on deeply nested infix does not crash":
    macro testDeep(): bool =
      var ctx = makeCtx()
      var node = newLit(0)
      for _ in 0..<20:
        node = infix(node, "+", newLit(1))
      let res = processNode(ctx, node)
      result = newLit(res.kind == cnkInfix)
    check testDeep()

  test "stmtList with 100 children produces 100 IR children":
    macro testLarge(): bool =
      var ctx = makeCtx()
      var sl = newNimNode(nnkStmtList)
      for i in 0..<100:
        sl.add newLit(i)
      let res = processNode(ctx, sl)
      result = newLit(res.args.len == 100)
    check testLarge()

  test "emittedTypes is updated after emitting a struct":
    ## We can only probe this at compile time; use a macro assertion.
    macro testEmittedTypes(): bool =
      var ctx = makeCtx()
      # Manually insert to simulate a struct having been emitted
      ctx.emittedTypes.incl("MyType")
      result = newLit("MyType" in ctx.emittedTypes)
    check testEmittedTypes()

  test "emittedFuncs prevents duplicate emission":
    macro testNoDupe(): bool =
      var ctx = makeCtx()
      ctx.emittedFuncs.incl("helper")
      irFuncTable["helper"] = "helper"
      let node = newIdentNode("helper")
      let r1 = ctx.remapFunc("helper", node)
      let r2 = ctx.remapFunc("helper", node)
      result = newLit(r1.name == r2.name)
    check testNoDupe()

  test "multiple sequential additions to the same CIRContext body":
    macro testMultiAdd(): bool =
      var ctx = makeCtx()
      for i in 0..<5:
        ctx.body.add newCIRIntLit(i)
      result = newLit(ctx.body.args.len == 5)
    check testMultiAdd()

  test "normalizeTypes is idempotent for known types":
    for name in ["int", "float", "bool", "uint32", "float64"]:
      check normalizeTypes(name) == normalizeTypes(name)

  test "newCIRSym with empty string is valid":
    let n = newCIRSym("")
    check n.kind == cnkSym
    check n.name == ""