import std/strutils, std/sets

type
  Liveness = object
    birth: NifCursor
    uses: seq[NifCursor]

  Variable = object
    kind: VarKind
    name: string
    ty: TypeInst
    liveness: Liveness

include "trie.nim"

type
  ScopeKind = enum
    SimpleScope
    CondScope

  ScopeNode = object
    kind: ScopeKind
    id: int
    subId: int
    variables: Trie
    children: seq[int]
    moveState: Table[SymPath, BorrowState]
    inlineVars: Table[SymId, NifCursor]
    parent: int
    stackCount: int
    errorStack: seq[ErrorInstance]

  CodeGenCtx = object
    cache: TypeCache
    scopes: seq[ScopeNode]
    errorStack: seq[ErrorInstance]
    currentLHS: tuple[scopeId: int, varId: int]
    currentCond: int
    shouldStop: bool
    varToAdd: seq[Variable]

# ############################################################################################################ #
# ############################################### Functions ################################################## #
# ############################################################################################################ #

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

proc collectVarData(ctx: var CodeGenCtx, nid: int, root: NifCursor, isCond: bool = false) =
  var n = root
  var current = nid
  var currentCond = ctx.currentCond
  var newS = false

  if n.kind in {IntLit, CharLit, DotToken}: return
  if n.kind != TagLit or n.exprKind in {DotX, DdotX, HderefX}:
    let path = ctx.scopes[current].extractPath(n)
    if path.valid and path.path.len > 0:
      let root = path.path[0].symText
      let strPath = renderPath(path)

      let scopeId = ctx.getOwnerScope(ctx.scopes[current], root)
      if scopeId == -1: return
      var ownerScope = addr ctx.scopes[scopeId]

      let rv = ownerScope.variables.fetchNode(root)
      var id = ownerScope.variables.fetchNode(strPath.split(PATH_SEPARATOR))

      if id != -1:
        ownerScope.variables.nodes[rv].data.liveness.uses.add(n)
      else:
        var v = Variable(name: strPath, kind: ownerScope.variables.nodes[rv].data.kind,
          ty: ctx.cache.getType(ownerScope.variables.nodes[rv].data.ty, strPath.split(PATH_SEPARATOR)[1..^1]),
          liveness: Liveness(birth: n))

    return

  n.loopInto:
    case n.stmtKind
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
        let v = Variable(kind: kind, ty: inst, name: symNode.symText, liveness: Liveness(birth: n))
        let id = ctx.scopes[current].variables.addNode(name)
        ctx.scopes[current].variables.nodes[id].data = v

      collectVarData(ctx, current, n)
    of CommentS:
      return
    of IfS, CaseS:
      ctx.currentCond += 1
      collectVarData(ctx, current, n)
    of StmtsS, BlockS:
      var kind = SimpleScope
      var subId = 0

      if isCond:
        kind = CondScope
        subId = currentCond

      var newNode = ScopeNode(kind: kind, id: ctx.scopes.len, subId: subId, parent: current, variables: newTrie())
      ctx.scopes[current].children.add(newNode.id)
      current = newNode.id
      ctx.scopes.add(newNode)

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

        for field in ty.fields:
          var fname = field.name
          let inst = ctx.cache.getType(field.ty)
          let kind = if VarF in field.subinfo: VarK else: LetK

          let v = Variable(kind: kind, ty: inst, name: fname, liveness: Liveness(birth: n))
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

# ######################################################################################################### #
# ############################################# Move Checks ############################################### #
# ######################################################################################################### #

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

proc cleanVarAlias(ctx: var CodeGenCtx, scope: var ScopeNode, id: int, current: LineInfo) =
  var toDelete: seq[tuple[scopeId: int, varId: int]] = @[]
  for data in scope.variables.nodes[id].data.aliases:
    if cmpLineInfo(ctx.scopes[data.scopeId].getLastUse(data.varId), current) <= 0:
      toDelete.add data

  for i in toDelete:
    scope.variables.nodes[id].data.aliases.excl i

proc isAnyAliasedWithPrefix(ctx: var CodeGenCtx, scope: var ScopeNode; prefix: SymPath, n: NifCursor): bool =
  let str = renderPath(prefix)
  let data = str.split(PATH_SEPARATOR)
  var current = 0
  for d in data:
    let next = scope.variables.nodes[current].children.getOrDefault(d, -1)
    if next == -1: return false
    current = next
    cleanVarAlias(ctx, scope, current, n.info)
    if scope.variables.nodes[current].data.aliases.len > 0:
      return true

  return false

proc isAnyDescendantAliased(ctx: var CodeGenCtx, scope: var ScopeNode; prefix: SymPath, n: NifCursor): bool =
  let str = renderPath(prefix)
  let data = str.split(PATH_SEPARATOR)
  for id in scope.variables.iterateSuffix(data):
    cleanVarAlias(ctx, scope, id, n.info)
    if scope.variables.nodes[id].data.aliases.len > 0:
      return true

  return false

proc movePathsWithPrefix(ctx: var ScopeNode; prefix: SymPath, n: NifCursor) =
  ## When a path (or its root) is mutated, every fact about a longer path that
  ## shares this prefix (e.g. `a.next` when `a` is reassigned) is stale.
  let data = renderPath(prefix).split(PATH_SEPARATOR)
  for id in ctx.variables.iterateSuffix(data):
    ctx.variables.nodes[id].data.state.kind = Moved
    ctx.variables.nodes[id].data.state.pos = n

proc maybeMovePathsWithPrefix(ctx: var ScopeNode; sid: int, prefix: SymPath, n: NifCursor) =
  ## When a path (or its root) is mutated in a conditional scope, every fact about a longer path that
  ## shares this prefix (e.g. `a.next` when `a` is reassigned) is maybe stale.
  let data = renderPath(prefix).split(PATH_SEPARATOR)
  for id in ctx.variables.iterateSuffix(data):
    ctx.variables.nodes[id].data.maybeState.incl sid.uint16

proc relivePathsWithPrefix(ctx: var ScopeNode; prefix: SymPath, n: NifCursor) =
  ## When a path (or its root) is mutated, every fact about a longer path that
  ## shares this prefix (e.g. `a.next` when `a` is reassigned) is stale.
  let data = renderPath(prefix).split(PATH_SEPARATOR)
  for id in ctx.variables.iterateSuffix(data):
    ctx.variables.nodes[id].data.state.kind = Alive

proc isAnyDescendantMoved(ctx: ScopeNode, path: SymPath): bool =
  ## Check if any var with prefix `path` has been moved.
  ## This is to check if an object can be moved even if it's currently alive
  ## Because it's a partial object
  let data = renderPath(path).split(PATH_SEPARATOR)
  for id in ctx.variables.iterateSuffix(data):
    if ctx.variables.nodes[id].data.state.kind == Moved:
      return true

  return false

proc isAnyDescendantMaybeMoved(ctx: ScopeNode, path: SymPath): bool =
  ## Check if any var with prefix `path` has been moved.
  ## This is to check if an object can be moved even if it's currently alive
  ## Because it's a partial object
  let data = renderPath(path).split(PATH_SEPARATOR)
  for id in ctx.variables.iterateSuffix(data):
    if ctx.variables.nodes[id].data.maybeState.len > 0:
      return true

  return false

proc checkPath(ctx: var CodeGenCtx, node: int, r: var Replacer, path: SymPath, isAssign=NoAsgn, isLet=false) =
  var n = r.getCursor()
  let info = n.info
  if path.valid and path.path.len > 0:
    let sym = path.path[0]
    let rootStr = path.path[0].symText


    let strPath = renderPath(path)
    var ownerId = ctx.getOwnerScope(ctx.scopes[node], strPath)
    if ownerId == -1:
      var fname = rootStr.split(".")[0]
      var val = false
      if fname.startsWith("enable"):
        fname = fname[6..^1]
        val = true
      else:
        fname = fname[7..^1]

      case fname:
      of "StrictLets":
        ctx.features.strictLets = val
      of "Aliases":
        ctx.features.aliases = val
      of "Moves":
        ctx.features.moves = val
      return

    template ownerScope(): ScopeNode =
      ctx.scopes[ownerId]
    var strSPath = strPath.split(PATH_SEPARATOR)
    let id = ownerScope().variables.fetchNode(strSPath)
    let rid = ownerScope().variables.fetchNode(rootStr)

    # We are only interested in the kind and lifetime of the root
    let vk = ownerScope().variables.nodes[rid].data.kind
    let l = ownerScope().variables.nodes[rid].data.liveness
    let varType = ownerScope().variables.nodes[id].data.ty

    if isAssign == LHSAsgn:
      ctx.currentLHS = (ownerId, id)
      if l.birth.info != info:
        if vk == LetK and ctx.features.strictLets:
          ctx.errorStack.add errorInstance("Can't modifiy an immutable let variable", n, n)
        else:
          # Fix TRevive
          # If it's an assignment and the LHS receive a new value but is not LetK
          # Then it revive it
          ownerScope().variables.nodes[id].data.state = BorrowState(kind: Alive)
          relivePathsWithPrefix ownerScope(), path, n

      return
    # If we are assigning, we are on the RHS which has been declared as let
    # And try to assign it to a var variable while the data we are trying to assign is not a ref
    elif isAssign == RHSAsgn and vk == LetK and varType.kind notin {ObjectType, PrimitiveType} and ctx.features.strictLets:
      ctx.errorStack.add errorInstance("Can't assign an immutable let variable to a var.", n, n)
      return

    # Here we check is anything on the path to the variable is already moved
    # And prevent use after move
    let state = ownerScope().variables.nodes[id].data.state
    if (state.kind == Moved or isAnyDescendantMoved(ownerScope(), path)):
      ctx.errorStack.add errorInstance("Used after move here", r.getCursor, state.pos)
      return

    let scope = addr ctx.scopes[node]
    if scope.kind != CondScope:
      if ownerScope().variables.nodes[id].data.maybeState.len > 0 or isAnyDescendantMaybeMoved(ownerScope(), path):
        let err = ownerScope().variables.nodes[id].data.state.pos
        ctx.errorStack.add errorInstance("Cannot prove the variable has not been moved during conditional statements", r.getCursor, err)
        return

    # If the variable is used for other things than making aliases while it has active aliases.
    if (isAnyAliasedWithPrefix(ctx, ownerScope(), path, n) or isAnyDescendantAliased(ctx, ownerScope(), path, n)) and not (isAssign == RHSAsgn and ctx.scopes[ctx.currentLHS.scopeId].variables.nodes[ctx.currentLHS.varId].data.kind == LetK):
      ctx.errorStack.add errorInstance("Used while there are still immutable borrows alive", r.getCursor, r.getCursor)
      return

    # If it's a RHSAsgn and the current LHS overlap with the RHS, then we should trigger an error
    # Because it is self-assignment
    if isAssign == RHSAsgn:
      let data = ctx.scopes[ctx.currentLHS.scopeId].variables.nodes[ctx.currentLHS.varId].data
      if data.name.startsWith(strPath):
        ctx.errorStack.add errorInstance("Invalid Self assignment", r.getCursor, r.getCursor)
        return
      elif strPath.startsWith(data.name):
        return

    if isAssign == RHSAsgn:
      # For aliasing
      # If we are assigning to a LetK then we alias
      # If it's a var then we move
      if ctx.scopes[ctx.currentLHS.scopeId].variables.nodes[ctx.currentLHS.varId].data.kind == LetK and ctx.features.aliases:
        ownerScope().variables.nodes[id].data.aliases.incl ctx.currentLHS
      else:
        if scope.kind == CondScope:
          ownerScope().variables.nodes[id].data.maybeState.incl node.uint16
          ownerScope().variables.nodes[id].data.state.pos = n
          maybeMovePathsWithPrefix ownerScope(), node, path, n
        else:
          if varType.kind in {ObjectType, PrimitiveType} or not ctx.features.moves: return
          ownerScope().variables.nodes[id].data.state = BorrowState(kind: Moved, pos: n)
          movePathsWithPrefix ownerScope(), path, n

proc checkMoves(ctx: var CodeGenCtx, id: int, r: var Replacer;
  isAssign = NoAsgn, isLet=false) =
  template scope: ScopeNode =
    ctx.scopes[id]
  var newScope = false

  if ctx.shouldStop:
    keep r, Any
    return

  if r.isAtom:
    let n = r.getCursor
    if n.kind in {Symbol, SymbolDef}:
      let path = extractPath(scope(), n)
      checkPath(ctx, id, r, path, isAssign=isAssign, isLet=isLet)
    keep r, Any
  else:
    if r.kind == TagLit:
      case r.exprKind
      of HderefX, DotX, DdotX, HaddrX, AddrX, DerefX, TupatX, ArratX, AtX, PatX:
        var n = r.getCursor()
        let info = n.info
        let path = extractPath(scope(), r.getCursor)

        checkPath(ctx, id, r, path,
          isAssign=isAssign, isLet=isLet)

        keep r, Any
        return
      else:
        discard
    case r.stmtKind
    of StmtsS, BlockS:
      newScope = true
      loopKeepTag r:
        checkMoves(ctx, scope().children[scope().stackCount], r)

      scope().stackCount += 1
    of AsgnS:
      loopKeepTag r:
        checkMoves(ctx, id, r, isAssign = LHSAsgn)
        checkMoves(ctx, id, r, isAssign = RHSAsgn)
    of CommentS:
      var stmt = createTree()
      var c = getCursor(r)
      stmt.takeTree c
      for err in ctx.errorStack:
        stmt.addTree errorTree(err.msg, err.at, err.orig)
      replace r, Any, stmt
      ctx.shouldStop = true
      return
    of VarS, LetS:
      var cnt = 0
      let isLet = r.stmtKind == LetS
      loopKeepTag r:
        checkMoves(ctx, id, r,
          isAssign = if cnt <= 2: LHSAsgn elif cnt > 2: RHSAsgn else: NoAsgn,
          isLet=isLet)
        cnt += 1
    of TypeS:
      keep r, Any
    else:
      loopKeepTag r:
        checkMoves(ctx, id, r)
