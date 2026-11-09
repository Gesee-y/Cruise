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
    returnArgsPos: seq[TermPath]

  # The rewrite engine
  Rewritter = object
    patterns: array[CIRNodeKind, seq[Pattern]]

  # ###################################################################################################################################### #
 # ########################################################### FUNCTIONS ################################################################ #
# ###################################################################################################################################### #



