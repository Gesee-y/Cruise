import unittest, strutils, sequtils
include "../../src/shadert/backends/cl.nim"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc sym(n: string): CIRNode = newCIRSym(n)
proc ilit(i: int): CIRNode   = newCIRIntLit(i)
proc flit(f: float): CIRNode = newCIRFloatLit(f)

proc makeCtx(): CIRContext =
  result.typeDecl    = newCIRNode(cnkStmtList)
  result.forwardDecl = newCIRNode(cnkStmtList)
  result.funcDef     = newCIRNode(cnkStmtList)
  result.body        = newCIRNode(cnkStmtList)

proc stmtList(children: varargs[CIRNode]): CIRNode =
  result = newCIRNode(cnkStmtList)
  for c in children: result.add(c)

proc identDef(name: string, ty: CIRNode): CIRNode =
  result = newCIRNode(cnkIdentDef)
  result.add(sym(name))
  result.add(ty)

proc funcSig(name: string, retTy: CIRNode,
             params: varargs[CIRNode]): CIRNode =
  result = newCIRNode(cnkFuncSig)
  result.add(sym(name))
  result.add(retTy)
  for p in params: result.add(p)

proc funcDef(sig: CIRNode, body: CIRNode): CIRNode =
  result = newCIRNode(cnkFuncDef)
  result.add(sig)
  result.add(body)

# =============================================================================
# 1. emitType
# =============================================================================

suite "emitType – primitive types":

  test "int → int":
    check emitType(sym("int")) == "int"

  test "float → float":
    check emitType(sym("float")) == "float"

  test "double → double":
    check emitType(sym("double")) == "double"

  test "bool → bool":
    check emitType(sym("bool")) == "bool"

  test "uint → uint":
    check emitType(sym("uint")) == "uint"

  test "vec2 → float2":
    check emitType(sym("vec2")) == "float2"

  test "vec3 → float3":
    check emitType(sym("vec3")) == "float3"

  test "vec4 → float4":
    check emitType(sym("vec4")) == "float4"

  test "ivec2 → int2":
    check emitType(sym("ivec2")) == "int2"

  test "uvec4 → uint4":
    check emitType(sym("uvec4")) == "uint4"

  test "unknown type is passed through":
    check emitType(sym("MyStruct")) == "MyStruct"

  test "empty name is passed through":
    check emitType(sym("")) == ""

# =============================================================================
# 2. emitQualifier
# =============================================================================

suite "emitQualifier":

  test "cnkReadOnly → '__read_only '":
    check emitQualifier(newCIRNode(cnkReadOnly)) == "__read_only "

  test "cnkWritOnly → '__write_only '":
    check emitQualifier(newCIRNode(cnkWritOnly)) == "__write_only "

  test "cnkEmpty → ''":
    check emitQualifier(newCIRNode(cnkEmpty)) == ""

  test "other kind → ''":
    check emitQualifier(newCIRNode(cnkSym)) == ""

# =============================================================================
# 3. emitCL – scalar literals
# =============================================================================

suite "emitCL – literals":

  test "cnkSym emits name":
    check emitCL(sym("myVar")) == "myVar"

  test "cnkIntLit 0":
    check emitCL(ilit(0)) == "0"

  test "cnkIntLit positive":
    check emitCL(ilit(42)) == "42"

  test "cnkIntLit negative":
    check emitCL(ilit(-7)) == "-7"

  test "cnkFloatLit appends 'f' suffix":
    let s = emitCL(flit(1.5))
    check s.endsWith("f")

  test "cnkFloatLit 0.0":
    check emitCL(flit(0.0)) == "0.0f"

  test "cnkEmpty emits empty string":
    check emitCL(newCIRNode(cnkEmpty)) == ""

  test "cnkDiscardStmt emits empty string":
    check emitCL(newCIRNode(cnkDiscardStmt)) == ""

  test "cnkBreakStmt emits 'break;'":
    check emitCL(newCIRNode(cnkBreakStmt)) == "break;"

  test "cnkContinueStmt emits 'continue;'":
    check emitCL(newCIRNode(cnkContinueStmt)) == "continue;"

# =============================================================================
# 4. emitCL – identDef
# =============================================================================

suite "emitCL – cnkIdentDef":

  test "identDef emits 'type name'":
    let n = identDef("x", sym("float"))
    check emitCL(n) == "float x"

  test "identDef with vec type":
    let n = identDef("pos", sym("vec4"))
    check emitCL(n) == "float4 pos"

  test "identDef with custom struct":
    let n = identDef("obj", sym("Particle"))
    check emitCL(n) == "Particle obj"

# =============================================================================
# 5. emitCL – operators
# =============================================================================

suite "emitCL – infix":

  test "infix '+' emits 'a + b'":
    var n = newCIRNode(cnkInfix)
    n.add(sym("+"))
    n.add(sym("a"))
    n.add(sym("b"))
    check emitCL(n) == "a + b"

  test "infix '<' emits 'i < n'":
    var n = newCIRNode(cnkInfix)
    n.add(sym("<"))
    n.add(sym("i"))
    n.add(sym("n"))
    check emitCL(n) == "i < n"

  test "infix '*' with literals":
    var n = newCIRNode(cnkInfix)
    n.add(sym("*"))
    n.add(ilit(3))
    n.add(ilit(4))
    check emitCL(n) == "3 * 4"

  test "nested infix":
    var inner = newCIRNode(cnkInfix)
    inner.add(sym("*"))
    inner.add(sym("x"))
    inner.add(sym("y"))
    var outer = newCIRNode(cnkInfix)
    outer.add(sym("+"))
    outer.add(inner)
    outer.add(ilit(1))
    check emitCL(outer) == "x * y + 1"

suite "emitCL – prefix":

  test "prefix '-' emits '-x'":
    var n = newCIRNode(cnkPrefix)
    n.add(sym("-"))
    n.add(sym("x"))
    check emitCL(n) == "-x"

  test "prefix '!' emits '!flag'":
    var n = newCIRNode(cnkPrefix)
    n.add(sym("!"))
    n.add(sym("flag"))
    check emitCL(n) == "!flag"

# =============================================================================
# 6. emitCL – assignment / declaration
# =============================================================================

suite "emitCL – assignment":

  test "cnkAsgn emits 'lhs = rhs;'":
    var n = newCIRNode(cnkAsgn)
    n.add(sym("x"))
    n.add(ilit(5))
    check emitCL(n) == "x = 5;"

  test "cnkAsgn with expression rhs":
    var rhs = newCIRNode(cnkInfix)
    rhs.add(sym("+"))
    rhs.add(sym("a"))
    rhs.add(sym("b"))
    var n = newCIRNode(cnkAsgn)
    n.add(sym("result"))
    n.add(rhs)
    check emitCL(n) == "result = a + b;"

suite "emitCL – declaration":

  test "cnkDecl emits 'type name = expr;'":
    var idnt = identDef("x", sym("float"))
    var n = newCIRNode(cnkDecl)
    n.add(idnt)
    n.add(flit(0.0))
    let s = emitCL(n)
    check s.startsWith("float x =")
    check s.endsWith(";")

  test "cnkDecl with int type":
    var idnt = identDef("count", sym("int"))
    var n = newCIRNode(cnkDecl)
    n.add(idnt)
    n.add(ilit(0))
    check emitCL(n) == "int count = 0;"

# =============================================================================
# 7. emitCL – control flow
# =============================================================================

suite "emitCL – if/elif/else":

  test "single elif branch emits 'if (cond) { body }'":
    var branch = newCIRNode(cnkElifBranch)
    branch.add(sym("cond"))
    branch.add(stmtList(newCIRNode(cnkBreakStmt)))
    var n = newCIRNode(cnkIfStmt)
    n.add(branch)
    let s = emitCL(n)
    check s.contains("if (cond)")
    check s.contains("break;")

  test "else branch emits '{ body }'":
    var el = newCIRNode(cnkElse)
    el.add(stmtList(newCIRNode(cnkContinueStmt)))
    var n = newCIRNode(cnkIfStmt)
    var branch = newCIRNode(cnkElifBranch)
    branch.add(sym("x"))
    branch.add(stmtList())
    n.add(branch)
    n.add(el)
    let s = emitCL(n)
    check s.contains("else")
    check s.contains("continue;")

  test "if/else structure uses 'else' joiner":
    var b1 = newCIRNode(cnkElifBranch)
    b1.add(sym("a"))
    b1.add(stmtList())
    var b2 = newCIRNode(cnkElse)
    b2.add(stmtList())
    var n = newCIRNode(cnkIfStmt)
    n.add(b1)
    n.add(b2)
    check emitCL(n).contains("\nelse ")

suite "emitCL – while":

  test "while emits 'while (cond) { body }'":
    var n = newCIRNode(cnkWhileStmt)
    n.add(sym("running"))
    n.add(stmtList(newCIRNode(cnkBreakStmt)))
    let s = emitCL(n)
    check s.startsWith("while (running)")
    check s.contains("break;")

  test "while body is wrapped in braces":
    var n = newCIRNode(cnkWhileStmt)
    n.add(sym("cond"))
    n.add(stmtList())
    let s = emitCL(n)
    check s.contains("{")
    check s.contains("}")

suite "emitCL – for":

  test "for emits C-style for loop":
    var n = newCIRNode(cnkForStmt)
    n.add(sym("i"))
    n.add(ilit(0))
    n.add(ilit(10))
    n.add(stmtList())
    let s = emitCL(n)
    check s.contains("for (int i = 0; i < 10; ++i)")

  test "for body is included":
    var n = newCIRNode(cnkForStmt)
    n.add(sym("j"))
    n.add(ilit(0))
    n.add(ilit(5))
    n.add(stmtList(newCIRNode(cnkBreakStmt)))
    check emitCL(n).contains("break;")

  test "for uses custom variable name":
    var n = newCIRNode(cnkForStmt)
    n.add(sym("idx"))
    n.add(ilit(0))
    n.add(ilit(4))
    n.add(stmtList())
    check emitCL(n).contains("int idx = 0")

suite "emitCL – case/switch":

  test "case emits switch statement":
    var n = newCIRNode(cnkCaseStmt)
    n.add(sym("mode"))
    var branch = newCIRNode(cnkOfBranch)
    branch.add(ilit(0))
    branch.add(stmtList())
    n.add(branch)
    let s = emitCL(n)
    check s.startsWith("switch (mode)")

  test "of branch emits 'case val:' with break":
    var branch = newCIRNode(cnkOfBranch)
    branch.add(ilit(1))
    branch.add(stmtList(newCIRNode(cnkDiscardStmt)))
    let s = emitCL(branch)
    check s.contains("case 1:")
    check s.contains("break;")

  test "multi-value of branch emits multiple case labels":
    var branch = newCIRNode(cnkOfBranch)
    branch.add(ilit(0))
    branch.add(ilit(1))
    branch.add(stmtList())
    let s = emitCL(branch)
    check s.contains("case 0:")
    check s.contains("case 1:")

# =============================================================================
# 8. emitCL – expressions
# =============================================================================

suite "emitCL – bracket / dot / cast / conv":

  test "bracketExpr emits 'arr[idx]'":
    var n = newCIRNode(cnkBracketExpr)
    n.add(sym("arr"))
    n.add(ilit(3))
    check emitCL(n) == "arr[3]"

  test "bracketExpr with variable index":
    var n = newCIRNode(cnkBracketExpr)
    n.add(sym("buf"))
    n.add(sym("i"))
    check emitCL(n) == "buf[i]"

  test "dotExpr emits 'obj.field'":
    var n = newCIRNode(cnkDotExpr)
    n.add(sym("pos"))
    n.add(sym("x"))
    check emitCL(n) == "pos.x"

  test "dotExpr chained":
    var inner = newCIRNode(cnkDotExpr)
    inner.add(sym("p"))
    inner.add(sym("pos"))
    var outer = newCIRNode(cnkDotExpr)
    outer.add(inner)
    outer.add(sym("y"))
    check emitCL(outer) == "p.pos.y"

  test "cnkCast emits '(type)(expr)'":
    var n = newCIRNode(cnkCast)
    n.add(sym("float"))
    n.add(sym("x"))
    check emitCL(n) == "(float)(x)"

  test "cnkConv emits '(type)(expr)'":
    var n = newCIRNode(cnkConv)
    n.add(sym("int"))
    n.add(flit(3.0))
    let s = emitCL(n)
    check s.startsWith("(int)(")

  test "cnkHiddenCallConv emits '(type)(expr)'":
    var n = newCIRNode(cnkHiddenCallConv)
    n.add(sym("uint"))
    n.add(sym("v"))
    check emitCL(n) == "(uint)(v)"

# =============================================================================
# 9. emitCL – function calls
# =============================================================================

suite "emitCL – function calls":

  test "zero-arg call emits 'fn()'":
    var n = newCIRNode(cnkCall)
    n.add(sym("barrier"))
    check emitCL(n) == "barrier()"

  test "one-arg call emits 'fn(arg)'":
    var n = newCIRNode(cnkCall)
    n.add(sym("sqrt"))
    n.add(sym("x"))
    check emitCL(n) == "sqrt(x)"

  test "multi-arg call emits comma-separated args":
    var n = newCIRNode(cnkCall)
    n.add(sym("clamp"))
    n.add(sym("x"))
    n.add(flit(0.0))
    n.add(flit(1.0))
    let s = emitCL(n)
    check s.startsWith("clamp(")
    check s.contains(",")

  test "get_global_id(0) emits correctly":
    var n = newCIRNode(cnkCall)
    n.add(sym("get_global_id"))
    n.add(ilit(0))
    check emitCL(n) == "get_global_id(0)"

  test "nested call as argument":
    var inner = newCIRNode(cnkCall)
    inner.add(sym("abs"))
    inner.add(sym("x"))
    var outer = newCIRNode(cnkCall)
    outer.add(sym("sqrt"))
    outer.add(inner)
    check emitCL(outer) == "sqrt(abs(x))"

# =============================================================================
# 10. emitCL – return statement
# =============================================================================

suite "emitCL – return":

  test "return emits 'return expr;'":
    var n = newCIRNode(cnkReturnStmt)
    n.add(sym("result"))
    check emitCL(n) == "return result;"

  test "return with literal":
    var n = newCIRNode(cnkReturnStmt)
    n.add(ilit(0))
    check emitCL(n) == "return 0;"

# =============================================================================
# 11. emitCL – qualifiers (Uniform, Buffer, Image, Sampler)
# =============================================================================

suite "emitCL – qualified variables":

  test "cnkUniform emits '__constant type name;'":
    var n = newCIRNode(cnkUniform)
    n.add(newCIRNode(cnkEmpty))   # qualifier
    n.add(sym("uTime"))           # name
    n.add(sym("float"))           # type
    let s = emitCL(n)
    check s.contains("__constant")
    check s.contains("float")
    check s.contains("uTime")

  test "cnkBuffer emits '__global type* name;'":
    var n = newCIRNode(cnkBuffer)
    n.add(newCIRNode(cnkEmpty))
    n.add(sym("dataBuffer"))
    n.add(sym("float"))
    let s = emitCL(n)
    check s.contains("__global")
    check s.contains("float*")
    check s.contains("dataBuffer")

  test "cnkImage with ReadOnly emits '__read_only image2d_t name'":
    var n = newCIRNode(cnkImage)
    n.add(newCIRNode(cnkReadOnly))
    n.add(sym("inputImg"))
    n.add(sym("float4"))
    let s = emitCL(n)
    check s.contains("__read_only")
    check s.contains("image2d_t")
    check s.contains("inputImg")

  test "cnkImage with WriteOnly emits '__write_only image2d_t name'":
    var n = newCIRNode(cnkImage)
    n.add(newCIRNode(cnkWritOnly))
    n.add(sym("outputImg"))
    n.add(sym("float4"))
    let s = emitCL(n)
    check s.contains("__write_only")
    check s.contains("image2d_t")

  test "cnkSampler emits 'sampler_t name'":
    var n = newCIRNode(cnkSampler)
    n.add(ilit(2))        # dimension (unused in emission)
    n.add(sym("texSampler"))
    let s = emitCL(n)
    check s.contains("sampler_t")
    check s.contains("texSampler")

# =============================================================================
# 12. emitCL – function signatures and definitions
# =============================================================================

suite "emitCL – function signature":

  test "non-kernel signature has no __kernel prefix":
    let sig = funcSig("helper", sym("float"), identDef("x", sym("float")))
    let s = emitCL(sig, isKernel = false)
    check not s.contains("__kernel")
    check s.contains("float helper(")

  test "kernel signature has __kernel prefix":
    let sig = funcSig("myKernel", newCIRNode(cnkEmpty))
    let s = emitCL(sig, isKernel = true)
    check s.startsWith("__kernel void myKernel(")

  test "void return uses 'void'":
    let sig = funcSig("voidFn", newCIRNode(cnkEmpty))
    check emitCL(sig).contains("void voidFn(")

  test "non-void return uses type":
    let sig = funcSig("add", sym("int"),
                      identDef("a", sym("int")),
                      identDef("b", sym("int")))
    let s = emitCL(sig)
    check s.startsWith("int add(")
    check s.contains("int a")
    check s.contains("int b")

  test "multiple params are comma-separated":
    let sig = funcSig("fn", sym("float"),
                      identDef("x", sym("float")),
                      identDef("y", sym("float")),
                      identDef("z", sym("float")))
    let s = emitCL(sig)
    check s.count(",") == 2

suite "emitCL – function definition":

  test "kernel funcDef has __kernel prefix":
    let sig  = funcSig("kern", newCIRNode(cnkEmpty))
    let body = stmtList()
    var fd   = newCIRNode(cnkFuncDef)
    fd.add(sig)
    fd.add(body)
    let s = emitCL(fd, isKernel = true)
    check s.contains("__kernel void kern(")

# =============================================================================
# 13. emitCL – stmtList
# =============================================================================

suite "emitCL – stmtList":

  test "empty stmtList emits empty string":
    check emitCL(stmtList()) == ""

  test "stmtList with one child emits that child":
    check emitCL(stmtList(newCIRNode(cnkBreakStmt))) == "break;"

  test "stmtList with multiple children joins with newline":
    let s = emitCL(stmtList(
      newCIRNode(cnkBreakStmt),
      newCIRNode(cnkContinueStmt)
    ))
    check s == "break;\ncontinue;"

# =============================================================================
# 14. emitOpenCL – full context emission order
# =============================================================================

suite "emitOpenCL – context assembly":

  test "typeDecl appears before forwardDecl":
    var ctx = makeCtx()
    var typeDef = newCIRNode(cnkTypeDef)
    typeDef.add(sym("Particle"))
    ctx.typeDecl.add(typeDef)
    let sig = funcSig("helper", sym("float"))
    ctx.forwardDecl.add(sig)
    let s = emitOpenCL(ctx)
    check s.find("Particle") < s.find("helper")

  test "forwardDecl appears before funcDef":
    var ctx = makeCtx()
    let proto = funcSig("helper", sym("int"))
    ctx.forwardDecl.add(proto)
    let body = stmtList()
    var fd = newCIRNode(cnkFuncDef)
    fd.add(funcSig("helper", sym("int")))
    fd.add(body)
    ctx.funcDef.add(fd)
    let s = emitOpenCL(ctx)
    # Both "helper" occurrences exist; first is the forward decl
    let first  = s.find("helper")
    let second = s.find("helper", first + 1)
    check first < second

  test "funcDef appears before body":
    var ctx = makeCtx()
    var helperFd = newCIRNode(cnkFuncDef)
    helperFd.add(funcSig("helperFn", sym("void")))
    helperFd.add(stmtList())
    ctx.funcDef.add(helperFd)
    var kernelFd = newCIRNode(cnkFuncDef)
    kernelFd.add(funcSig("mainKernel", newCIRNode(cnkEmpty)))
    kernelFd.add(stmtList())
    ctx.body = kernelFd
    let s = emitOpenCL(ctx)
    check s.find("helperFn") < s.find("mainKernel")

  test "body kernel is emitted with __kernel prefix":
    var ctx = makeCtx()
    var kernelFd = newCIRNode(cnkFuncDef)
    kernelFd.add(funcSig("compute", newCIRNode(cnkEmpty)))
    kernelFd.add(stmtList())
    ctx.body = kernelFd
    let s = emitOpenCL(ctx)
    check s.contains("__kernel void compute(")

  test "empty context emits empty or whitespace only":
    var ctx = makeCtx()
    ctx.body = stmtList()
    let s = emitOpenCL(ctx)
    check s.strip() == ""

# =============================================================================
# 15. End-to-end: minimal compute kernel
# =============================================================================

suite "End-to-end – minimal kernel":

  ## Simulate:
  ##   __kernel void add(__global float* a, __global float* b, __global float* out) {
  ##     int i = get_global_id(0);
  ##     out[i] = a[i] + b[i];
  ##   }

  test "minimal add kernel emits valid structure":
    var ctx = makeCtx()

    # Parameters
    var bufA = newCIRNode(cnkBuffer)
    bufA.add(newCIRNode(cnkEmpty)); bufA.add(sym("a")); bufA.add(sym("float"))
    var bufB = newCIRNode(cnkBuffer)
    bufB.add(newCIRNode(cnkEmpty)); bufB.add(sym("b")); bufB.add(sym("float"))
    var bufOut = newCIRNode(cnkBuffer)
    bufOut.add(newCIRNode(cnkEmpty)); bufOut.add(sym("out")); bufOut.add(sym("float"))

    # get_global_id(0)
    var gid = newCIRNode(cnkCall)
    gid.add(sym("get_global_id")); gid.add(ilit(0))

    # int i = get_global_id(0);
    var decl = newCIRNode(cnkDecl)
    decl.add(identDef("i", sym("int")))
    decl.add(gid)

    # a[i]
    var readA = newCIRNode(cnkBracketExpr)
    readA.add(sym("a")); readA.add(sym("i"))
    # b[i]
    var readB = newCIRNode(cnkBracketExpr)
    readB.add(sym("b")); readB.add(sym("i"))
    # a[i] + b[i]
    var addExpr = newCIRNode(cnkInfix)
    addExpr.add(sym("+")); addExpr.add(readA); addExpr.add(readB)
    # out[i]
    var writeOut = newCIRNode(cnkBracketExpr)
    writeOut.add(sym("out")); writeOut.add(sym("i"))
    # out[i] = a[i] + b[i];
    var asgn = newCIRNode(cnkAsgn)
    asgn.add(writeOut); asgn.add(addExpr)

    # Kernel sig + body
    let sig = funcSig("add", newCIRNode(cnkEmpty),
                      identDef("a",   sym("float")),   # simplified params
                      identDef("b",   sym("float")),
                      identDef("out", sym("float")))
    var body = stmtList(decl, asgn)
    var fd = newCIRNode(cnkFuncDef)
    fd.add(sig); fd.add(body)
    ctx.body = fd

    let s = emitOpenCL(ctx)
    check s.contains("__kernel void add(")
    check s.contains("int i = get_global_id(0);")
    check s.contains("out[i] = a[i] + b[i];")

# =============================================================================
# 16. Edge cases
# =============================================================================

suite "Edge cases":

  test "deeply nested bracketExpr":
    var inner = newCIRNode(cnkBracketExpr)
    inner.add(sym("mat")); inner.add(ilit(0))
    var outer = newCIRNode(cnkBracketExpr)
    outer.add(inner); outer.add(ilit(1))
    check emitCL(outer) == "mat[0][1]"

  test "infix with float literal rhs has 'f' suffix":
    var n = newCIRNode(cnkInfix)
    n.add(sym("*"))
    n.add(sym("x"))
    n.add(flit(2.0))
    check emitCL(n).endsWith("2.0f")

  test "call with no args emits empty parens":
    var n = newCIRNode(cnkCall)
    n.add(sym("mem_fence"))
    check emitCL(n) == "mem_fence()"

  test "stmtList of 50 break statements has 50 'break;' occurrences":
    var sl = newCIRNode(cnkStmtList)
    for _ in 0..<50:
      sl.add(newCIRNode(cnkBreakStmt))
    check emitCL(sl).count("break;") == 50

  test "for loop with empty body emits valid C":
    var n = newCIRNode(cnkForStmt)
    n.add(sym("i")); n.add(ilit(0)); n.add(ilit(1)); n.add(stmtList())
    let s = emitCL(n)
    check s.contains("for (int i = 0; i < 1; ++i)")
    check s.contains("{")
    check s.contains("}")

  test "cnkUniform with vec4 type":
    var n = newCIRNode(cnkUniform)
    n.add(newCIRNode(cnkEmpty))
    n.add(sym("uColor"))
    n.add(sym("vec4"))
    let s = emitCL(n)
    check s.contains("float4")   # vec4 → float4 via emitType
    check s.contains("uColor")