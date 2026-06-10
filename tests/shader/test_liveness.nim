##########################################################################################################################################################
############################################################ LIVENESS ANALYSIS TESTS ####################################################################
##########################################################################################################################################################

import std/unittest
include "../../src/shadert/ir.nim"

## Helpers to query the scope tree without index arithmetic in every test.

proc findVar(node: CIRControlNode, name: string): CLiveness =
  ## Search `node` and all descendants for `name`. Raises if not found.
  if name in node.variables: return node.variables[name]
  for child in node.children:
    try: return findVar(child, name)
    except KeyError: discard
  raise newException(KeyError, "variable '" & name & "' not found in scope tree")

proc scopeContains(node: CIRControlNode, name: string): bool =
  ## True if `name` is declared directly in `node` (not a child scope).
  name in node.variables

proc childCount(node: CIRControlNode): int = node.children.len

# ---------------------------------------------------------------------------
# Subject functions — compiled to IR at compile time, tested at runtime.
# ---------------------------------------------------------------------------

proc simpleAssign(x: float32): float32 =
  let a = x
  return a

proc twoVars(x: float32, y: float32): float32 =
  let a = x
  let b = y
  return a + b

proc varInIf(x: float32): float32 =
  let a = x
  if a > 0.0:
    let b = a * 2.0
    return b
  return a

proc varInFor(n: int): int =
  var acc = 0
  for i in 0..<n:
    acc = acc + i
  return acc

proc shadowedVar(x: float32): float32 =
  let a = x
  if a > 0.0:
    let a = x * 2.0   # shadows outer a
    return a
  return a

proc nestedScopes(x: float32): float32 =
  let a = x
  if a > 0.0:
    let b = a + 1.0
    if b > 1.0:
      let c = b * 2.0
      return c
  return a

proc unusedAfterIf(x: float32): float32 =
  let a = x
  let b = a + 1.0
  if b > 0.0:
    return b
  return a

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "getLiveness — scope tree structure":

  test "single variable: root has exactly one child scope with one variable":
    const ir = compileToIR(simpleAssign)
    let root = getLiveness(ir)
    check root.childCount == 1
    check scopeContains(root.children[0], "a")

  test "two variables live in the same scope":
    const ir = compileToIR(twoVars)
    let root = getLiveness(ir)
    let scope = root.children[0]
    check scopeContains(scope, "a")
    check scopeContains(scope, "b")

  test "variable declared inside if lives in a child scope":
    const ir = compileToIR(varInIf)
    let root = getLiveness(ir)
    let outer = root.children[0]
    check scopeContains(outer, "a")
    check not scopeContains(outer, "b")
    check outer.childCount >= 1
    check scopeContains(outer.children[0], "b")

suite "getLiveness — birth and death positions":

  test "birth is before death for a simple variable":
    const ir = compileToIR(simpleAssign)
    let live = findVar(getLiveness(ir), "a")
    check not live.birth.invalid
    check not live.death.invalid
    check live.birth < live.death

  test "death of outer variable is after the if block":
    const ir = compileToIR(unusedAfterIf)
    let liveA = findVar(getLiveness(ir), "a")
    let liveB = findVar(getLiveness(ir), "b")
    check liveA.death > liveB.birth

  test "for loop variable birth is at the for statement":
    const ir = compileToIR(varInFor)
    let root = getLiveness(ir)
    let liveI = findVar(root, "i")
    echo liveI
    check not liveI.birth.invalid
    check liveI.birth < liveI.death

suite "getLiveness — shadowing":

  test "shadowed variable gets its own entry in the child scope":
    const ir = compileToIR(shadowedVar)
    let root = getLiveness(ir)
    let outer = root.children[0]
    let inner = outer.children[0]
    # Both scopes have an 'a', they are independent entries.
    check scopeContains(outer, "a")
    check scopeContains(inner, "a")

  test "shadowed variable intervals do not overlap":
    const ir = compileToIR(shadowedVar)
    let root  = getLiveness(ir)
    let outer = root.children[0]
    let inner = outer.children[0]
    let outerA = outer.variables["a"]
    let innerA = inner.variables["a"]
    # Inner 'a' is born after outer 'a'.
    check innerA.birth > outerA.birth
    # Inner 'a' dies before or at the point outer 'a' is used again.
    check innerA.death <= outerA.death

suite "getLiveness — nested scopes":

  test "three nesting levels produce three child scopes":
    const ir = compileToIR(nestedScopes)
    let root  = getLiveness(ir)
    let l1    = root.children[0]
    let l2    = l1.children[0]
    let l3    = l2.children[0]
    check scopeContains(l1, "a")
    check scopeContains(l2, "b")
    check scopeContains(l3, "c")

  test "variable from outer scope has death after inner scopes close":
    const ir  = compileToIR(nestedScopes)
    var root = getLiveness(ir)
    let liveA = findVar(root, "a")
    let liveC = findVar(root, "c")
    check liveA.death > liveC.birth