##########################################################################################################################################################
############################################################ LIVENESS ANALYSIS TESTS ####################################################################
##########################################################################################################################################################
## Test suite for getLiveness — verifies that birth/dead NodePos are assigned
## correctly for variables in various control flow patterns.
##
## Strategy: compile small Nim shader functions to CIR, run getLiveness,
## then assert the expected birth/dead ordering for each variable.
##
## Since NodePos is a lexicographic order (line, pos), we only need to check:
##   - birth < dead  (variable born before it dies)
##   - relative ordering between variables (which dies first)
##   - that transient temps die before long-lived vars

import std/unittest
include "../../src/shadert/ir.nim"

suite "Liveness Analysis":

  ## ── Test 1: Linear sequence ───────────────────────────────────────────────
  ## let x = 1.0
  ## let y = x * 2.0   ← last use of x
  ## let z = y + 1.0   ← last use of y
  ## z dies at end
  test "linear sequence: x dies before y dies before z":
    proc linearShader(): float32 =
      let x = 1.0'f32
      let y = x * 2.0'f32
      let z = y + 1.0'f32
      return z
    const ir   = compileToIR(linearShader)
    let live   = getLiveness(ir)

    check live["x"].birth < live["x"].death
    check live["y"].birth < live["y"].death
    check live["z"].birth < live["z"].death
    ## x is last used on the line that declares y
    check live["x"].death  < live["y"].death
    check live["y"].death  < live["z"].death

  ## ── Test 2: Variable used multiple times ──────────────────────────────────
  ## x is read on 3 different lines — dead should be the LAST read
  test "multiple uses: dead is the last read":
    proc multiUse(): float32 =
      let x = 1.0'f32
      let a = x + 1.0'f32
      let b = x * 2.0'f32 # ← last use of x
      let c = a + b
      return c

    const ir   = compileToIR(multiUse)
    let live   = getLiveness(ir)

    ## x must still be alive when b is declared
    check live["x"].death < live["b"].birth
    ## x must die no later than b (it's not used after)
    check live["x"].death <  live["c"].birth

  ## ── Test 3: Sub-expression precision ──────────────────────────────────────
  ## x = a + b + c + d
  ## c should die at its operand position, not at end of statement
  test "sub-expression: c dies before d in same statement":
    proc subExpr(): float32 =
      let a = 1.0'f32
      let b = 2.0'f32
      let c = 3.0'f32
      let d = 4.0'f32
      let x = a + b + c + d
      x
    const ir   = compileToIR(subExpr)
    let live   = getLiveness(ir)

    ## All on the same line → compare by pos only
    check live["a"].death.line == live["c"].death.line
    check live["a"].death.pos  <  live["c"].death.pos
    check live["c"].death.pos  <  live["d"].death.pos

  ## ── Test 4: If branch ─────────────────────────────────────────────────────
  ## x is declared before the if, used in both branches
  ## x should be alive across the entire if
  test "if branch: variable alive across both branches":
    proc ifShader(): float32 =
      let x    = 1.0'f32
      let cond = x > 0.0'f32
      var r    = 0.0'f32
      if cond:
        r = x * 2.0'f32 # ← x used here
      else:
        r = x + 1.0'f32 # ← and here
      return r

    const ir   = compileToIR(ifShader)
    let live   = getLiveness(ir)

    ## x must outlive cond (used inside the branches which come after)
    check live["cond"].death < live["x"].death

  ## ── Test 5: Register reuse opportunity ────────────────────────────────────
  ## a and b die before c is born → a and b's registers can be reused for c
  test "register reuse: a and b dead before c born":
    proc reuseShader(): float32 =
      let a = 1.0'f32
      let b = a * 2.0'f32 # ← a dies here
      let c = b + 3.0'f32 # ← b dies here, c born here
      c
    const ir   = compileToIR(reuseShader)
    let live   = getLiveness(ir)

    check live["a"].death <= live["c"].birth
    check live["b"].death <= live["c"].birth

  ## ── Test 6: For loop variable ─────────────────────────────────────────────
  ## Loop counter i should be born at the for and die at end of body
  test "for loop: i alive across entire body":
    proc loopShader(): float32 =
      var acc = 0.0'f32
      for i in 0..<4:
        acc = acc + float32(i)
      acc
    const ir   = compileToIR(loopShader)
    echo ir.body.args[1]
    let live   = getLiveness(ir)
    echo live

    check live["i"].birth   < live["i"].death
    check live["acc"].birth < live["acc"].death
    ## i dies inside the loop body, acc outlives i
    check live["i"].death    < live["acc"].death