  # ######################################################################################################################## #
 # ################################################## SCOPE INFORMATIONS ################################################## #
# ######################################################################################################################## #

import std/strutils, std/sets, std/hashes

type
  Liveness* = object
    birth: NifCursor
    uses: seq[NifCursor]

  VarType* = enum
    RootVar
    VarField
    ProcArg

  VarKind = enum
    LetK
    VarK

  Variable* = object
    kind*: VarKind
    vtype*: VarType
    name*: string
    ty*: TypeInst
    liveness*: Liveness
    ownerId*: int
    offset*: int

include "trie.nim"

type
  SymPath = object
    valid: bool
    path: seq[SymId]
    ty: seq[NimonyType]

  ScopeKind* = enum
    SimpleScope
    CondScope

  ScopeNode* = object
    kind*: ScopeKind
    id: int
    subId: int
    variables: Trie
    children: seq[int]
    parent: int
    stackCount: int

  CodeGenCtx = object
    cache: TypeCache
    scopes: seq[ScopeNode]
    currentLHS: tuple[scopeId: int, varId: int]
    currentCond: int
    currentProcName: string
    shouldStop: bool
    varToAdd: seq[Variable]

const 
  PATH_SEPARATOR = "::"

# ############################################################################################################ #
# ############################################### UTILITIES ################################################## #
# ############################################################################################################ #

func hash(s: SymPath): Hash =
  var h: Hash = 0
  for item in s.path:
    h = h !& hash(item)
  h = h !& hash(s.valid)
  result = !$h

func `==`(s1, s2: SymPath): bool =
  if s1.valid != s2.valid:
    return false
  if s1.path.len != s2.path.len:
    return false
  for i in 0 .. s1.path.high:
    if s1.path[i] != s2.path[i]:
      return false
  true

proc renderPath(path: SymPath): string =
  if path.path.len == 0:
    return "<path>"
  result = symText(path.path[0])
  for i in 1 .. path.path.high:
    result.add PATH_SEPARATOR
    result.add symText(path.path[i])

proc cmpLineInfo(l1, l2: LineInfo): int =
  result = 0
  if l1.line < l2.line:
    result = -1
  elif l1.line > l2.line:
    result = 1
  else:
    if l1.col < l2.col:
      result = -1
    elif l1.col > l2.col:
      result = 1

proc getLastUse(scope: var ScopeNode, id: int): LineInfo =
  result = scope.variables.nodes[id].data.liveness.uses[^1].info
  for i in scope.variables.nodes[id].children.values:
    let last = scope.getLastUse(i)
    if cmpLineInfo(result, last) < 0:
      result = last

proc getOwnerScope(ctx: CodeGenCtx, scope: ScopeNode, path: seq[string]): int =
  result = scope.id
  var parent = scope.parent
  while true:
    let id = ctx.scopes[result].variables.fetchNode(path)

    if id == -1 and parent != -1:
      result = ctx.scopes[parent].id
      parent = ctx.scopes[parent].parent
    elif parent == -1 and id == -1:
      result = -1
      break
    else:
      break

proc getOwnerScope(ctx: CodeGenCtx, c: ScopeNode, path: string): int =
  return ctx.getOwnerScope(c, path.split(PATH_SEPARATOR))

proc getOwnerScope(ctx: CodeGenCtx, c: ScopeNode, path: SymPath): int =
  return ctx.getOwnerScope(c, renderPath(path))

proc addPathSegment(res: var SymPath; n: NifCursor) =
  res.path.add n.symId
  res.ty.add n.typeKind

proc extractPath(c: var ScopeNode; n: NifCursor; res: var SymPath; followInlineVars = true) =
  if not res.valid:
    return
  case n.kind
  of TagLit:
    case n.exprKind
    of CallX, CmdX:
      res.valid = false
    of DotX, DdotX:
      var left = n
      inc left
      extractPath(c, left, res, followInlineVars)
      skip left
      if left.kind == Symbol:
        addPathSegment(res, left)
    of HderefX, HaddrX, AddrX, DerefX, TupatX, ArratX, AtX, PatX:
      var inner = n
      inc inner
      extractPath(c, inner, res, followInlineVars)
    of ConvX, HconvX, DconvX:
      var inner = n
      inc inner
      skip inner
      extractPath(c, inner, res, followInlineVars)
    of BaseobjX:
      var inner = n
      inc inner
      skip inner
      skip inner
      extractPath(c, inner, res, followInlineVars)
    of AconstrX, SetconstrX, TupconstrX, OconstrX, NilX, TrueX, FalseX:
      res.valid = false
    else:
      res.valid = false
  of Symbol, SymbolDef:
    addPathSegment(res, n)
  of IntLit, UIntLit, CharLit, FloatLit, StrLit, DotToken:
    res.valid = false
  else:
    res.valid = false

proc extractPath(c: var ScopeNode; n: NifCursor; followInlineVars = true): SymPath =
  result = SymPath(valid: true)
  extractPath(c, n, result, followInlineVars)
  if not result.valid or result.path.len == 0:
    result.valid = false

proc pathsOverlap(a, b: SymPath): bool =
  ## Two paths overlap if one is a prefix of the other (or they are equal).
  ## Disjoint siblings (e.g. a.b vs a.c) do not overlap.
  if a.path.len == 0 or b.path.len == 0: return false
  let minLen = min(a.path.len, b.path.len)
  for i in 0 ..< minLen:
    if a.path[i] != b.path[i]:
      return false
  result = true

proc rootPath(sym: SymId): SymPath =
  result = SymPath(valid: true, path: @[sym])

# ################################################################################################################ #
# ############################################### API Functions ################################################## #
# ################################################################################################################ #


proc collectVarData(ctx: var CodeGenCtx, nid: int, root: NifCursor, isCond: bool = false) =
  var n = root
  var current = nid
  var currentCond = ctx.currentCond
  var newS = false

  if n.kind in {IntLit, CharLit, DotToken}: return

  # If we end up on a mere symbol, of field access
  if n.kind != TagLit or n.exprKind in {DotX, DdotX, HderefX}:
    let path = ctx.scopes[current].extractPath(n)
    if path.valid and path.path.len > 0:
      # We fetch the root of the path (the variable)
      let root = path.path[0].symText
      let strPath = renderPath(path)

      # Fetch the node that own
      let scopeId = ctx.getOwnerScope(ctx.scopes[current], root)
      if scopeId == -1: return
      var ownerScope = addr ctx.scopes[scopeId]


      # We fetch the 2 `Variable` objects representing those symbols      
      let rv = ownerScope.variables.fetchNode(root)
      var id = ownerScope.variables.fetchNode(strPath.split(PATH_SEPARATOR))

      if id == -1:
        # If the symbol don't exist we just make it
        # As the field is owned by the root
        var v = Variable(name: strPath, kind: ownerScope.variables.nodes[rv].data.kind, vtype: VarField,
          ty: ctx.cache.getType(ownerScope.variables.nodes[rv].data.ty, strPath.split(PATH_SEPARATOR)[1..^1]),
          liveness: Liveness(birth: n), ownerId: scopeId)

      # And only extend the root's lifetime
      ownerScope.variables.nodes[rv].data.liveness.uses.add(n)

    return

  # Looping through `n` children
  n.loopInto:
    case n.stmtKind

    # If we end up on a symple variable definition, we just register the variable
    of VarS, LetS, TvarS, TletS:
      let symNode = firstChild(n)
      let kind = if n.stmtKind in {VarS, TvarS}: VarK else: LetK
      if symNode.kind == SymbolDef:
        var typ = symNode
        var name = symNode.symText
        skip typ
        skip typ
        skip typ
        let inst = ctx.cache.getType(typ.getTypeName)
        let v = Variable(kind: kind, vtype: RootVar, ty: inst, name: symNode.symText, liveness: Liveness(birth: n))
        let id = ctx.scopes[current].variables.addNode(name)
        ctx.scopes[current].variables.nodes[id].data = v

      collectVarData(ctx, current, n)

    # Nif already get rid of every comment before being provided to the plugin
    # Except for one comment, that marks the end of the user program and the start of Nim internals
    of CommentS:
      return

    # If we end up on a new statement (that create a new scope)
    of StmtsS, BlockS:
      var kind = if isCond: CondScope else: SimpleScope
      var newNode = ScopeNode(kind: kind, id: ctx.scopes.len, parent: current, variables: newTrie())

      ctx.scopes[current].children.add(newNode.id)
      ctx.scopes.add(newNode)
      current = newNode.id

      if ctx.currentProcName != "":
        let pid = ctx.cache.nameToId.getOrDefault(ctx.currentProcName, -1)
        ctx.cache.instances[pid].scopeId = current
        ctx.currentProcName = ""
        
      # Implicit variabke to add to the scope.
      # Those are generally function arguments
      while ctx.varToAdd.len > 0:
        let v = ctx.varToAdd.pop()
        let id = ctx.scopes[current].variables.addNode(v.name)
        ctx.scopes[current].variables.nodes[id].data = v

      newS = true
      collectVarData(ctx, current, n)
    of TypeS: discard
    of ProcS, FuncS:
      var symNode = firstChild(n)
      if symNode.kind == SymbolDef:
        let name = symNode.symText
        let ty = ctx.cache.getType(name)
        ctx.currentProcName = name

        # add the parameters of the proc as implicit arguments
        for field in ty.fields:
          var fname = field.name
          let inst = ctx.cache.getType(field.ty)
          let kind = if VarF in field.subinfo: VarK else: LetK # Mutability of the argument

          let v = Variable(kind: kind, vtype: ProcArg, ty: inst, name: fname, liveness: Liveness(birth: n))
          ctx.varToAdd.add(v)

      collectVarData(ctx, current, n)
    else:
      case n.otherKind:
      of ElifU, ElseU, OfU:
        collectVarData(ctx, current, n, isCond=true)
      else:
        collectVarData(ctx, current, n, isCond=isCond)

    if newS:
      newS = false
      let parent = ctx.scopes[current].parent
      if parent != -1:
        current = parent

    n.skip()
