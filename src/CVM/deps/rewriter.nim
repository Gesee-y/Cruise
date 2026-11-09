  # ###################################################################################################################################### #
 # ########################################################## IR REWRITTER ############################################################## #
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
    case kind: TermKind
    of tkDontCare, tkLeaf: discard
    of tkCompound:
      args: seq[Term]

  # The kind of transformation that we can apply on the code
  # Doing some operations are possible
  RewriteNodeKind = enum
    rnkIdentity
    rnkSubstitute
    rnkInfix
    rnkPrefix
    rnkCall

  SubstituteKind = enum
    skNewNode
    skReplace

  # We can either replace a node by a completely new one
  # Or just make it be replaced by an existing node
  Substitute = object
    case kind: SubstituteKind
    of skNewNode:
      node: CIRNode
    of skReplace:
      path: TermPath

  RewriteNode = object
    case kind: RewriteNodeKind
    of rnkIdentity: discard
    of rnkSubstitute:
      substitute: Substitute
    else:
      op: string
      args: seq[RewriteNode]

  # This is a pattern that can be matched by a root CIRnode
  # The patterns that matches the greatest part of the node win
  # Rules are then applied at the end once terms matches
  # All rules should hold for the rewrite to happend
  # `returnArgsPos` indicate how the rewrite should go
  # Each element indicate for each children of the rewritten node, where to fetch it's children 
  Pattern = object
    term: Term
    rules: seq[TermRule]
    priority: int
    returnKind: CIRNodeKind
    returnArgsPos: seq[RewriteNode]

  # The rewrite engine
  Rewritter = object
    patterns: array[CIRNodeKind, seq[Pattern]]

  # ###################################################################################################################################### #
 # ########################################################### FUNCTIONS ################################################################ #
# ###################################################################################################################################### #

# Check that a CIR node match a given term
proc matchTerm(node: CIRNode, term: Term): bool =
  case term.kind:
  of tkDontCare: return true
  of tkLeaf: return node.kind == term.ty
  of tkCompound:
    if node.kind != term.ty: return false
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
    if not first == fetchNode(node, rule.nodes[i]):
      result = false
      break

proc matchRule(node: CIRNode, rule: TermRule): bool =
  case rule.kind
  of trkEq:
    return node.matchEqRule(rule)

proc matchPattern(node: CIRNode, pattern: Pattern): bool =
  result = node.matchTerm(pattern.term)
  if not result: return

  for rule in pattern.rules:
    result = node.matchRule(rule)
    if not result: break

proc applySubstitution(node: CIRNode, s: Substitute): CIRNode =
  case s.kind:
  of skNewNode:
    return s.node
  of skReplace:
    return fetchNode(node, s.path)

proc applyPrefix(op: string, root, node: CIRNode): CIRNode =
  if op == "not":
    case node.kind:
    of cnkIntLit:
      return CIRNode(kind: cnkIntLit, src: node.info, intVal: not node.intVal)
    of cnkUintLit:
      return CIRNode(kind: cnkUintLit, src: node.info, uintVal: not node.uintVal)
    of cnkBoolLit:
      return CIRNode(kind: cnkUintLit, src: node.info, boolVal: not node.boolVal)
    of cnkFloatLit:
      assert false, "Can't use `not` on float during rewrite."
    else: discard
  elif op == "-":
    case node.kind:
    of cnkIntLit:
      return CIRNode(kind: cnkIntLit, src: node.info, intVal: -node.intVal)
    of cnkUintLit:
      assert false, "Can't negate uint during rewrite."
    of cnkFloatLit:
      return CIRNode(kind: cnkFloatLit, src: node.info, floatVal: -node.floatVal)
    else: discard

  return root

proc applyInfix(op: string, root, left, right: CIRNode): CIRNode =
  if op == "+":
    case left.kind:
    of cnkIntLit:
      return CIRNode(kind: cnkIntLit, src: root.info, intVal: left.intVal + right.intVal)
    of cnkUintLit:
      return CIRNode(kind: cnkUintLit, src: root.info, uintVal: left.uintVal + right.uintVal)
    of cnkFloatLit: 
      return CIRNode(kind: cnkFloatLit, src: root.info, floatVal: left.floatVal + right.floatVal)
    else: discard
  elif op == "-":
    case left.kind:
    of cnkIntLit:
      return CIRNode(kind: cnkIntLit, src: root.info, intVal: left.intVal - right.intVal)
    of cnkUintLit:
      return CIRNode(kind: cnkUintLit, src: root.info, uintVal: left.uintVal - right.uintVal)
    of cnkFloatLit:
      return CIRNode(kind: cnkFloatLit, src: root.info, floatVal: left.floatVal - right.floatVal)
    else: discard
  elif op == "*":
    case left.kind:
    of cnkIntLit:
      return CIRNode(kind: cnkIntLit, src: root.info, intVal: left.intVal * right.intVal)
    of cnkUintLit:
      return CIRNode(kind: cnkUintLit, src: root.info, uintVal: left.uintVal * right.uintVal)
    of cnkFloatLit:
      return CIRNode(kind: cnkFloatLit, src: root.info, floatVal: left.floatVal * right.floatVal)
    else: discard

  return root

proc constructNewNode(node: CIRNode, rn: RewriteNode): CIRNode =
  case rn.kind:
  of rnkIdentity: return node
  of rnkSubstitute: applySubstitution(node, rn.substitute)
  of rnkInfix:
    var left = constructNewNode(node, rn.args[0])
    var right = constructNewNode(node, rn.args[1])

    assert left.kind == right.kind
    assert left.kind in {cnkIntLit, cnkUintLit, cnkFloatLit}
    assert rn.op in ["+", "-", "*"]

    return applyInfix(rn.op, node, left, right)
  of rnkPrefix:
    var left = constructNewNode(node, rn.args[0])

    assert left.kind in {cnkIntLit, cnkUintLit, cnkFloatLit, cnkBoolLit}
    assert rn.op in ["-", "not"]
    if left.kind == cnkUintLit: assert rn.op != "-"
    elif left.kind == cnkFloatLit: assert rn.op != "not"

    return applyPrefix(rn.op, node, left)
  else: discard

  return node

proc rewriteNode(p: Pattern, node: CIRNode): CIRNode =
  result = CIRNode(kind: p.returnKind, info: node.info)
  for rewriter in p.returnArgsPos:
    result.add(constructNewNode(node, rewriter))
