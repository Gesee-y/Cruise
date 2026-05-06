##########################################################################################################################################################
############################################################ TRANSPILER TESTS ############################################################################
##########################################################################################################################################################

import unittest, tables, strutils, sequtils, math
import ../../src/shadert/transpiler

## ── Helper ───────────────────────────────────────────────────────────────────
## Trim whitespace for comparison — we don't care about exact spacing
proc normalize(s: string): string =
  s.split('\n')
   .mapIt(it.strip())
   .filterIt(it.len > 0)
   .join("\n")

template assertContains(glsl, fragment: string) =
  check normalize(glsl).contains(normalize(fragment))

template assertNotContains(glsl, fragment: string) =
  check not normalize(glsl).contains(normalize(fragment))

type
  Vec4 = object
    x, y, z, w: float32

registerUniformType(seq, "SSBO")
registerGLSLType(Vec4, "vec4")

##########################################################################################################################################################
## 1. PRIMITIVES & DECLARATIONS
##########################################################################################################################################################

suite "Primitives and declarations":

  test "int declaration":
    proc kernel(buf: var seq[int32]) =
      var x: int32 = 42
    const s = compileToGLSL(kernel)
    assertContains(s.result, "int x = 42")

  test "float declaration":
    proc kernel(buf: var seq[float32]) =
      let f: float32 = 3.14
    const s = compileToGLSL(kernel)
    assertContains(s.result, "float f = 3.14")

  test "bool declaration":
    proc kernel(buf: var seq[float32]) =
      let b: bool = true
    const s = compileToGLSL(kernel)
    assertContains(s.result, "bool b = true")

  test "inferred type from expression":
    proc kernel(buf: var seq[float32]) =
      var x = 1 + 2
    const s = compileToGLSL(kernel)
    assertContains(s.result, "int x =")

##########################################################################################################################################################
## 2. ARITHMETIC & OPERATORS
##########################################################################################################################################################

suite "Arithmetic and operators":

  test "infix operators":
    proc kernel(buf: var seq[float32]) =
      var y: float32 = 1.0
      var x: float32 = 2.0
      var z = x + y*3.0 - 4.0*x / 2.0
    const s = compileToGLSL(kernel)
    assertContains(s.result, "x + y * 3.0 - 4.0 * x / 2.0")

  test "prefix negation":
    proc kernel(buf: var seq[float32]) =
      var x: float32 = -1.0
    const s = compileToGLSL(kernel)
    assertContains(s.result, "-1.0")

  test "assignment":
    proc kernel(buf: var seq[float32]) =
      var x: int32 = 0
      x = 5
    const s = compileToGLSL(kernel)
    assertContains(s.result, "x = 5")

  test "comparison operators":
    proc kernel(buf: var seq[float32]) =
      var a: bool = 1 < 2
      var b: bool = a == true
      var c: bool = b >= a
    const s = compileToGLSL(kernel)
    assertContains(s.result, "a == true")
    assertContains(s.result, "a <= b") # Nim reorder instruction to fallback to less than

##########################################################################################################################################################
## 3. CONTROL FLOW
##########################################################################################################################################################

suite "Control flow":

  test "if / elif / else":
    proc kernel(buf: var seq[float32]) =
      var x: int32 = 0
      if x == 0:
        x = 1
      elif x == 1:
        x = 2
      else:
        x = 3
    const s = compileToGLSL(kernel)
    assertContains(s.result, "if (x == 0)")
    assertContains(s.result, "else if (x == 1)")
    assertContains(s.result, "else {")

  test "for range loop":
    proc kernel(buf: var seq[float32]) =
      for i in 0..<10:
        buf[i] = float32(i)
    const s = compileToGLSL(kernel)
    assertContains(s.result, "for (int i = 0; i < 10; i++)")

  test "while loop":
    proc kernel(buf: var seq[float32]) =
      var i: int32 = 0
      while i < 10:
        i = i + 1
    const s = compileToGLSL(kernel)
    assertContains(s.result, "while (i < 10)")

  test "break":
    proc kernel(buf: var seq[float32]) =
      for i in 0..<10:
        if i == 5: break
    const s = compileToGLSL(kernel)
    assertContains(s.result, "break")

  test "continue":
    proc kernel(buf: var seq[float32]) =
      for i in 0..<10:
        if i == 5: continue
    const s = compileToGLSL(kernel)
    assertContains(s.result, "continue")

  test "case / switch":
    proc kernel(buf: var seq[int32]) =
      var x: int32 = 1
      case x:
      of 0: x = 10
      of 1: x = 20
      else: x = 30
    const s = compileToGLSL(kernel)
    assertContains(s.result, "switch (x)")
    assertContains(s.result, "case 0:")
    assertContains(s.result, "case 1:")
    assertContains(s.result, "default:")

  test "return":
    proc helper(x: float32): float32 =
      return x * 2.0
    proc kernel(buf: var seq[float32]) =
      buf[0] = helper(1.0)

    const s = compileToGLSL(kernel)
    assertContains(s.result, "return x * 2.0")

##########################################################################################################################################################
## 4. ARRAYS
##########################################################################################################################################################

suite "Arrays":

  test "fixed-size array declaration":
    proc kernel(buf: var seq[float32]) =
      var arr: array[4, float32]
    const s = compileToGLSL(kernel)
    assertContains(s.result, "float arr[4]")

  test "array indexing":
    proc kernel(buf: var seq[float32]) =
      buf[0] = 1.0
    const s = compileToGLSL(kernel)
    assertContains(s.result, "buf[0] = 1.0")

  test "array literal":
    proc kernel(buf: var seq[float32]) =
      var arr: array[3, float32] = [1.0, 2.0, 3.0]
    const s = compileToGLSL(kernel)
    assertContains(s.result, "{1.0, 2.0, 3.0}")

##########################################################################################################################################################
## 5. TYPES
##########################################################################################################################################################

suite "Type system":

  test "cast":
    proc kernel(buf: var seq[float32]) =
      var x: int32 = 5
      var f: float32 = cast[float32](x)
    const s = compileToGLSL(kernel)
    assertContains(s.result, "float(x)")

  test "conv":
    proc kernel(buf: var seq[float32]) =
      var i: int32 = 3
      var f: float32 = float32(i)
    const s = compileToGLSL(kernel)
    assertContains(s.result, "float(i)")

  test "custom struct emitted to header":
    type MyStruct = object
      x: float32
      y: float32
    proc kernel(buf: var seq[float32]) =
      var s: MyStruct
    const sh = compileToGLSL(kernel)
    assertContains(sh.result, "struct MyStruct")
    assertContains(sh.result, "float x")
    assertContains(sh.result, "float y")

  test "registerGLSLType mapping":
    type ExternalVec = object
      x, y: float32
    registerGLSLType(ExternalVec, "vec2")
    proc kernel(buf: var seq[float32]) =
      var v: ExternalVec
    const s = compileToGLSL(kernel)
    assertContains(s.result, "vec2 v")

##########################################################################################################################################################
## 6. QUALIFIERS & BINDINGS
##########################################################################################################################################################

suite "Qualifiers and bindings":

  test "seq in header":
    proc kernel(buf: var seq[float32]) =
      discard
    const s = compileToGLSL(kernel)
    assertContains(s.result, "layout(std430, binding =")
    assertContains(s.result, "float buf[]")

  test "Uniform in header":
    proc kernel(buf: var seq[float32], scale: Uniform[float32]) =
      discard
    const s = compileToGLSL(kernel)
    assertContains(s.result, "uniform float scale")

  test "Sampler2D in header":
    proc kernel(fragColor: var Vec4, tex: Sampler2D) =
      discard
    const s = compileToGLSL(kernel)
    assertContains(s.result, "uniform sampler2D tex")

  test "same binding name → same index across shaders":
    proc kernelA(positions: var seq[float32]) = discard
    proc kernelB(fragColor: var Vec4, positions: seq[float32]) = discard
    const sA = compileToGLSL(kernelA)
    const sB = compileToGLSL(kernelB)
    check sA.bindings["positions"] == sB.bindings["positions"]

  test "bindings table populated":
    proc kernel(buf: var seq[float32], scale: Uniform[float32]) =
      discard
    const s = compileToGLSL(kernel)
    check "buf" in s.bindings
    check "scale" in s.bindings

##########################################################################################################################################################
## 7. SHADER KIND INFERENCE
##########################################################################################################################################################

suite "Shader kind inference":

  test "compute shader has local_size header":
    proc kernel(buf: var seq[float32]) = discard
    const s = compileToGLSL(kernel)
    assertContains(s.result, "layout(local_size_x = 64) in")

  test "fragment/vertex shader has no local_size":
    proc frag(fragColor: var Vec4) = discard
    const s = compileToGLSL(frag)
    assertNotContains(s.result, "local_size")

##########################################################################################################################################################
## 8. FUNCTION TRANSPILATION
##########################################################################################################################################################

suite "Function transpilation":

  test "builtin remapped — not transpiled":
    proc kernel(buf: var seq[float32]) =
      buf[0] = sqrt(4.0)
    const s = compileToGLSL(kernel)
    ## sqrt should appear as a call, not be defined in the header
    assertContains(s.result, "sqrt(4.0)")
    assertNotContains(s.result, "float sqrt(")

  test "custom function transpiled to header":
    proc double(x: float32): float32 =
      return x * 2.0
    proc kernel(buf: var seq[float32]) =
      buf[0] = double(1.0)
    const s = compileToGLSL(kernel)
    assertContains(s.result, "float double(float x)")
    assertContains(s.result, "return x * 2.0")

  test "registerGLSLFunc — not transpiled":
    proc myAbs(x: float32): float32 = abs(x)
    registerGLSLFunc(myAbs, "abs")
    proc kernel(buf: var seq[float32]) =
      buf[0] = myAbs(-1.0)
    const s = compileToGLSL(kernel)
    assertContains(s.result, "abs(-1.0)")
    assertNotContains(s.result, "float myAbs(")

  test "recursive function emits forward declaration":
    proc b(n: int32): int32
    proc a(n: int32): int32 =
      if n <= 0: return 0
      return b(n - 1)
    proc b(n: int32): int32 =
      if n <= 0: return 0
      return a(n - 1)
    proc kernel(buf: var seq[int32]) =
      buf[0] = a(10)
    const s = compileToGLSL(kernel)
    assertContains(s.result, "int b(int n);")  ## forward decl

##########################################################################################################################################################
## 9. INDENTATION
##########################################################################################################################################################

suite "Indentation":

  test "nested blocks are indented":
    proc kernel(buf: var seq[float32]) =
      for i in 0..<10:
        if i == 5:
          buf[i] = 1.0
    const s = compileToGLSL(kernel)
    ## The assignment inside the nested if should be indented deeper
    let lines = s.result.split('\n')
    let assignLine = lines.filterIt("buf[i] = 1.0" in it)
    check assignLine.len > 0
    check assignLine[0].startsWith("            ")  ## 3 levels × 4 spaces

##########################################################################################################################################################
## 10. FIELD ACCESS & DOT EXPR
##########################################################################################################################################################

suite "Field access":

  test "dot expression":
    type Vec2 = object
      x, y: float32
    registerGLSLType(Vec2, "vec2")
    proc kernel(buf: var seq[float32]) =
      var v: Vec2
      buf[0] = v.x
    const s = compileToGLSL(kernel)
    assertContains(s.result, "v.x")