  # ###################################################################################################################################### #
 # ########################################################### IR REWRITER ############################################################## #
# ###################################################################################################################################### #

type
  # This type represent the different type of possible term for rewrite
  # `tkLeaf` is mostly literals, symbols or node when we only care about the kind.
  # `tkDontCare` is a node whose has no influence and is just a placeholder
  TermKind = enum
    tkLeaf = 1
    tkCompound = 2
    tkDontCare = 11111111

  # This is the kind of rules that can be applied to terms
  # For now we just have checking a bunch of terms are equal
  TermRuleKind = enum
    trkEq

  PatternGuardKind = enum
    pgNone
    pgOneOverSqrt

  # This represent the path to a term going from a parent `Term`
  TermPath = seq[int]

  # A rule that should hold between a set of terms
  TermRule = object
    kind: TermRuleKind
    nodes: seq[TermPath]

  # A term, represent one possible rule.
  # A leaf term is easy to check (only the kind), a compound harder
  # The `args` of a compound term matches the args of a compound `CIRNode`
  # So each term represent a constraint of each of the children of the IR node
  Term = object
    ty: CIRNodeKind
    name: string
    kind: TermKind
    args: seq[Term]

  Rewriter* = proc (node: CIRNode): CIRNode

  # This is a pattern that can be matched by a root CIRnode
  # The patterns that matches the greatest part of the node win
  # Rules are then applied at the end once terms matches
  # All rules should hold for the rewrite to happend
  # `rewriter` is a user defined func that takes the original node as input
  # And output the rewriten node
  Pattern* = object
    term: Term
    rules: seq[TermRule]
    priority: int
    rewriter: Rewriter
    guard: PatternGuardKind

  # The rewrite engine
  RewriterEngine* = object
    patterns: array[CIRNodeKind, seq[Pattern]]

  # ###################################################################################################################################### #
 # ########################################################### FUNCTIONS ################################################################ #
# ###################################################################################################################################### #

proc anyTerm(): Term =
  Term(ty: cnkNone, kind: tkDontCare)

proc operationTerm(kind: CIRNodeKind, op: string,
                   operands: seq[Term]): Term =
  var args = @[anyTerm()]
  for operand in operands:
    args.add(operand)
  Term(ty: kind, name: op, kind: tkCompound, args: args)

proc rewriteNegatedOperand(node: CIRNode): CIRNode =
  let rootOp = node.args[0].name
  var op = if rootOp == "+": "-" else: "+"
  var lhs = node.args[1]
  var rhs = node.args[2]

  if rhs.kind == cnkPrefix:
    rhs = rhs.args[1]
  else:
    # (+) is commutative, so (-a) + b can also become b - a.
    op = "-"
    lhs = node.args[2]
    rhs = node.args[1].args[1]

  result = newCIRNode(node.info, cnkInfix)
  if node.args[0].kind == cnkRSym:
    result.add(newCIRRSym(node.args[0].info, op, node.args[0].tid))
  else:
    result.add(newCIRSym(node.args[0].info, op))
  result.add(lhs)
  result.add(rhs)

proc removeDoublePrefix(node: CIRNode): CIRNode =
  node.args[1].args[1]

proc isOne(node: CIRNode): bool =
  case node.kind
  of cnkIntLit: node.intVal == 1
  of cnkUintLit: node.uintVal == 1'u
  of cnkFloatLit: node.floatVal == 1.0
  of cnkConv, cnkCast:
    node.args.len > 1 and node.args[^1].isOne
  else: false

proc isOneOverSqrt(node: CIRNode): bool =
  node.args.len == 3 and node.args[1].isOne

proc rewriteRsqrt(node: CIRNode): CIRNode =
  result = newCIRNode(node.info, cnkRsqrt)
  result.add(node.args[2].args[1])

proc newRewriterEngine(): RewriterEngine =
  result = RewriterEngine()
  let any = anyTerm()
  let product = operationTerm(cnkInfix, "*", @[any, any])

  # a * b + c -> fma(a, b, c), including the commuted c + a * b form.
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "+", @[product, any]),
    rewriter: proc(node: CIRNode): CIRNode =
      result = newCIRNode(node.info, cnkFma)
      result.add(node.args[1].args[1])
      result.add(node.args[1].args[2])
      result.add(node.args[2])
  ))
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "+", @[any, product]),
    rewriter: proc(node: CIRNode): CIRNode =
      result = newCIRNode(node.info, cnkFma)
      result.add(node.args[2].args[1])
      result.add(node.args[2].args[2])
      result.add(node.args[1])
  ))

  # a + (-b) -> a - b; a - (-b) -> a + b; (-a) + b -> b - a.
  let neg = operationTerm(cnkPrefix, "-", @[any])
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "+", @[any, neg]),
    rewriter: rewriteNegatedOperand
  ))
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "-", @[any, neg]),
    rewriter: rewriteNegatedOperand
  ))
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "+", @[neg, any]),
    rewriter: rewriteNegatedOperand
  ))

  # -(-x) -> x.
  result.addPattern(cnkPrefix, Pattern(
    term: operationTerm(cnkPrefix, "-", @[
      operationTerm(cnkPrefix, "-", @[any])
    ]),
    rewriter: removeDoublePrefix
  ))

  # 1 / sqrt(x) -> rsqrt(x), a native GPU operation on common hardware.
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "/", @[
      any,
      operationTerm(cnkCall, "sqrt", @[any])
    ]),
    rewriter: rewriteRsqrt,
    guard: pgOneOverSqrt
  ))

# Check that a CIR node match a given term
proc matchTerm*(node: CIRNode, term: Term): bool =
  case term.kind:
  of tkDontCare: return true
  of tkLeaf: return node.kind == term.ty
  of tkCompound:
    if node.kind != term.ty: return false
    if term.name != "":
      if term.name != node.args[0].name: return false
    var r = true
    var i = 0
    while r and i < term.args.len:
      r = node.args[i].matchTerm(term.args[i])
      inc i
    return r

proc fetchNode(node: CIRNode, path: TermPath): CIRNode =
  var current = addr node
  for id in path:
    current = addr current.args[id]

  return current[]

proc matchEqRule(node: CIRNode, rule: TermRule): bool =
  if rule.nodes.len < 2: return true
  
  result = true
  var first = fetchNode(node, rule.nodes[0])
  for i in 1..<rule.nodes.len:
    if first != fetchNode(node, rule.nodes[i]):
      result = false
      break

proc matchRule*(node: CIRNode, rule: TermRule): bool =
  case rule.kind
  of trkEq:
    return node.matchEqRule(rule)

proc matchPattern*(node: CIRNode, pattern: Pattern): bool =
  result = node.matchTerm(pattern.term)
  if not result: return

  case pattern.guard
  of pgNone: discard
  of pgOneOverSqrt:
    if not node.isOneOverSqrt:
      return false

  for rule in pattern.rules:
    result = node.matchRule(rule)
    if not result: break

proc rewriteIfMatch*(re: RewriterEngine, node: var CIRNode): bool =
  for pattern in re.patterns[node.kind]:
    if node.matchPattern(pattern):
      node = pattern.rewriter(node)
      return true

  return false

proc addPattern*(re: var RewriterEngine, kind: CIRNodeKind, p: Pattern) =
  re.patterns[kind].add(p)

proc rewriteNode*(re: RewriterEngine, node: var CIRNode) =
  if node.isLeaf: return
  if re.rewriteIfMatch(node):
    re.rewriteNode(node)
    return

  for n in node.args.mitems:
    re.rewriteNode(n)

proc rewritePass*(re: RewriterEngine, root: var CIRNode) =
  re.rewriteNode(root)

