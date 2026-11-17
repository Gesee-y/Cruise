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
    pgArithmeticIdentity
    pgDivideBySqrt
    pgConvLiteral
    pgHomogeneousFma

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

proc isZero(node: CIRNode): bool =
  case node.kind
  of cnkIntLit: node.intVal == 0
  of cnkUintLit: node.uintVal == 0'u
  of cnkFloatLit: node.floatVal == 0.0
  of cnkConv, cnkCast:
    node.args.len > 1 and node.args[^1].isZero
  else: false

proc supportsLiteralConversion(targetType: string, source: CIRNodeKind): bool =
  case targetType
  of "float", "float32": source in {cnkIntLit, cnkUintLit, cnkFloatLit, cnkBoolLit}
  of "int32", "uint32": source in {cnkIntLit, cnkUintLit, cnkBoolLit}
  of "bool": source in {cnkIntLit, cnkUintLit, cnkFloatLit, cnkBoolLit}
  else: false

proc literalAsFloat(node: CIRNode): float64 =
  case node.kind
  of cnkIntLit: float64(node.intVal)
  of cnkUintLit: float64(node.uintVal)
  of cnkFloatLit: float64(node.floatVal)
  of cnkCharLit: float64(ord(node.charVal))
  of cnkBoolLit:
    if node.boolVal: 1.0 else: 0.0
  else: 0.0

proc literalAsSigned(node: CIRNode): int64 =
  case node.kind
  of cnkIntLit: int64(node.intVal)
  of cnkUintLit: cast[int64](uint64(node.uintVal))
  of cnkFloatLit: int64(node.floatVal)
  of cnkCharLit: int64(ord(node.charVal))
  of cnkBoolLit:
    if node.boolVal: 1'i64 else: 0'i64
  else: 0'i64

proc literalAsUnsigned(node: CIRNode): uint64 =
  case node.kind
  of cnkIntLit: cast[uint64](int64(node.intVal))
  of cnkUintLit: uint64(node.uintVal)
  of cnkFloatLit: cast[uint64](int64(node.floatVal))
  of cnkCharLit: uint64(ord(node.charVal))
  of cnkBoolLit:
    if node.boolVal: 1'u64 else: 0'u64
  else: 0'u64

proc rewriteConversionLiteral(node: CIRNode): CIRNode =
  let source = node.args[1]
  let targetType = node.args[0].name
  let info = node.info
  case targetType
  of "float", "float32":
    result = newCIRFloatLit(info, float(source.literalAsFloat))
  of "int32":
    result = newCIRIntLit(info, int(cast[int32](source.literalAsSigned)))
  of "uint32":
    result = newCIRUintLit(info, uint(cast[uint32](source.literalAsUnsigned)))
  of "bool":
    result = newCIRBoolLit(info, source.literalAsFloat != 0.0)
  else:
    result = node

proc isArithmeticIdentity(node: CIRNode): bool =
  if node.args.len != 3: return false
  case node.args[0].name
  of "+": node.args[1].isZero or node.args[2].isZero
  of "-": node.args[2].isZero
  of "*": node.args[1].isOne or node.args[2].isOne
  of "/": node.args[2].isOne
  else: false

proc rewriteArithmeticIdentity(node: CIRNode): CIRNode =
  case node.args[0].name
  of "+":
    if node.args[1].isZero: node.args[2] else: node.args[1]
  of "*":
    if node.args[1].isOne: node.args[2] else: node.args[1]
  else:
    node.args[1]

proc rewriteDivideBySqrt(node: CIRNode): CIRNode =
  let root = node.args[2]
  var rsqrt = newCIRNode(root.info, cnkRsqrt)
  rsqrt.add(root.args[1])

  result = newCIRNode(node.info, cnkInfix)
  result.add(newCIRRSym(node.args[0].info, "*", node.args[0].tid))
  result.add(node.args[1])
  result.add(rsqrt)

proc newRewriterEngine(): RewriterEngine =
  result = RewriterEngine()
  let any = anyTerm()
  let product = operationTerm(cnkInfix, "*", @[any, any])

  # Constant conversions are compile-time work; runtime conversions are lowered
  # to destination-specialized VM instructions by the code generator.
  result.addPattern(cnkConv, Pattern(
    term: operationTerm(cnkConv, "", @[any]),
    rewriter: rewriteConversionLiteral,
    guard: pgConvLiteral
  ))

  # Remove arithmetic identities before code generation.
  for op in ["+", "-", "*", "/"]:
    result.addPattern(cnkInfix, Pattern(
      term: operationTerm(cnkInfix, op, @[any, any]),
      rewriter: rewriteArithmeticIdentity,
      guard: pgArithmeticIdentity
    ))

  # a * b + c -> fma(a, b, c), including the commuted c + a * b form.
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "+", @[product, any]),
    guard: pgHomogeneousFma,
    rewriter: proc(node: CIRNode): CIRNode =
      result = newCIRNode(node.info, cnkFma)
      result.add(node.args[1].args[1])
      result.add(node.args[1].args[2])
      result.add(node.args[2])
  ))
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "+", @[any, product]),
    guard: pgHomogeneousFma,
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

  # a / sqrt(x) -> a * rsqrt(x), a native GPU operation on common hardware.
  result.addPattern(cnkInfix, Pattern(
    term: operationTerm(cnkInfix, "/", @[
      any,
      operationTerm(cnkCall, "sqrt", @[any])
    ]),
    rewriter: rewriteDivideBySqrt,
    guard: pgDivideBySqrt
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

proc isFmaSupportedType(typeName: string): bool =
  typeName in ["float", "float32",
    "int", "int8", "int16", "int32", "int64",
    "uint", "uint8", "uint16", "uint32", "uint64",
    "vec2f", "vec3f", "vec4f"]

proc matchPattern*(node: CIRNode, pattern: Pattern,
                   cache: var TypeCache): bool =
  result = node.matchTerm(pattern.term)
  if not result: return

  case pattern.guard
  of pgNone: discard
  of pgArithmeticIdentity:
    if not node.isArithmeticIdentity:
      return false
  of pgDivideBySqrt:
    if node.args[2].kind != cnkCall or node.args[2].args[0].name != "sqrt":
      return false
  of pgConvLiteral:
    if not node.args[1].isLit or
       node.args[0].kind notin {cnkSym, cnkRSym} or
       not supportsLiteralConversion(node.args[0].name, node.args[1].kind):
      return false
  of pgHomogeneousFma:
    if node.args.len != 3:
      return false
    let productOnLeft = node.args[1].kind == cnkInfix and
      node.args[1].args.len > 0 and node.args[1].args[0].name == "*"
    let product = if productOnLeft: node.args[1] else: node.args[2]
    let addend = if productOnLeft: node.args[2] else: node.args[1]
    if product.kind != cnkInfix or product.args.len != 3 or
       product.args[0].name != "*":
      return false
    let lhsType = cache.inferType(product.args[1])
    let rhsType = cache.inferType(product.args[2])
    let addendType = cache.inferType(addend)
    if lhsType != rhsType or lhsType != addendType or
       not isFmaSupportedType(lhsType):
      return false

  for rule in pattern.rules:
    result = node.matchRule(rule)
    if not result: break

proc rewriteIfMatch*(re: RewriterEngine, node: var CIRNode,
                     cache: var TypeCache): bool =
  for pattern in re.patterns[node.kind]:
    if node.matchPattern(pattern, cache):
      node = pattern.rewriter(node)
      return true

  return false

proc addPattern*(re: var RewriterEngine, kind: CIRNodeKind, p: Pattern) =
  re.patterns[kind].add(p)

proc rewriteNode*(re: RewriterEngine, node: var CIRNode,
                  cache: var TypeCache) =
  if node.isLeaf: return
  if re.rewriteIfMatch(node, cache):
    re.rewriteNode(node, cache)
    return

  for n in node.args.mitems:
    re.rewriteNode(n, cache)

proc rewritePass*(re: RewriterEngine, root: var CIRNode,
                  cache: var TypeCache) =
  re.rewriteNode(root, cache)

