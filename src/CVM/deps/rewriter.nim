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

  # The rewrite engine
  RewriterEngine* = object
    patterns: array[CIRNodeKind, seq[Pattern]]

  # ###################################################################################################################################### #
 # ########################################################### FUNCTIONS ################################################################ #
# ###################################################################################################################################### #

# Check that a CIR node match a given term
proc matchTerm*(node: CIRNode, term: Term): bool =
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

proc matchRule*(node: CIRNode, rule: TermRule): bool =
  case rule.kind
  of trkEq:
    return node.matchEqRule(rule)

proc matchPattern*(node: CIRNode, pattern: Pattern): bool =
  result = node.matchTerm(pattern.term)
  if not result: return

  for rule in pattern.rules:
    result = node.matchRule(rule)
    if not result: break

proc rewriteNode*(p: Pattern, node: CIRNode): CIRNode =
  result = p.rewriter(node)
