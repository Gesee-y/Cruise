######################################################################################################################################################################
############################################################################# IR OPERATIONS ##########################################################################
######################################################################################################################################################################

#########################################
############## Bitcode Map ##############
#########################################
#
# OP 1 = R1 + R2
# OP 2 = R1 - R2
# OP 3 = R1 * R2
# OP 4 = R1 / R2

# We need to get the necessary registers.
# In fact the VM is virtual, with virtual loads and unload. so we virtually allocate and deallocate shader.
# A shader is allocated based on the number of register it uses for each type
# Those register are simply the number of necessary variables.
# We will analyze the liveliness of each variable

type
  CBytecodeOps = enum
    cbAdd
    cbSub
    cbMul
    cbDiv

  InfixPrec* = enum
    ipBit
    ipAdd
    ipMul
    ipCall
    ipPar

  FlatOp* = object
    op*:    string
    left*:  CIRNode
    right*: CIRNode
    prec*:  InfixPrec
    src*:   NodePos
    inner*: seq[FlatOp]

  CLiveness = object
    birth: NodePos
    death: NodePos

  CIRControlNode = ref object
    variables: Table[string, CLiveness]
    registers: Table[string, int] 
    children: seq[CIRControlNode]
    parent: CIRControlNode
    stackCount: int

  CRegisterStats = object
    counts: Table[string, int]

  CBytecode = object
    bindings: Table[string, int]
    uniform: Table[string, CIRNode]
    data: seq[uint32]

proc newCLiveness(birth=NodePos(line: -1, pos: -1), death=NodePos(line: -1, pos: -1)): CLiveness =
  CLiveness(birth:birth, death: death)

proc dumpTree(node: CIRControlNode, indent = 0) =
  let pad = "  ".repeat(indent)
  echo pad & "scope (stackCount=" & $node.stackCount & "):"
  for name, live in node.variables:
    echo pad & "  " & name & " birth=" & $live.birth & " death=" & $live.death
  for child in node.children:
    dumpTree(child, indent + 1)

proc invalid(n: NodePos): bool = n.line == -1 and n.pos == -1

# Reverse liveness analysis.
# This greatly simplify analysis because the first time a symbol is encountered is his death
# and the declaration is his birth
proc getLiveness(ctx: CIRContext): CIRControlNode =
  # Our stack to do a DFS
  var stack: seq[CIRNode] = @[ctx.body.args[1]]
  
  # We initialize a new scope node
  result = CIRControlNode()
  var currentNode = result # and set it as the current node

  while stack.len > 0:
    let current = stack.pop()

    case current.kind:
      # If we just encountered literals we can skip them, we can't analyze the liveness of a literal
      of cnkIntLit, cnkFloatLit, cnkEmpty: continue

      # He we encounter a declaration
      of cnkIdentDef:
        let name = current.args[0].name

        # Since we did post order iteration, if the variable has been ever used, it will be in the current node variables
        # So we set the birth of the variable
        if name in currentNode.variables:
          currentNode.variables[name].birth = current.src

      # We encountered a symbol, meaning a variable was used
      of cnkSym:

        # We make sure the variable is not already there
        # Since the first time we see a variable it means its dead
        # So we only need that occurence
        if current.name notin currentNode.variables:
          currentNode.variables[current.name] = newCLiveness(death = current.src)
      
      # In case we encountered a function, we don't want to count the function name in the variables
      of cnkCall, cnkInfix, cnkPrefix, cnkConv:
        for n in current.args[1..^1]:
          stack.add(n)
      
      # In case we encounter a new scope
      of cnkStmtList:
        # We make a new control node and set the parent
        let node = CIRControlNode()
        node.parent = currentNode
        currentNode.children.add(node)

        # Now the currentNode becomes the new scope
        currentNode = node
        stack.add(newCIRNode(cnkNone)) # This is a sentinel value that tells us we should escape the current scope

        for n in current.args:
          stack.add(n)

      # In case we need to escape the current scope
      of cnkNone:
        var parent = currentNode.parent
        var toDelete: seq[string] # Symbol that aren't valuable for the current scope gets deleted and goes to the parent scope

        for name, live in currentNode.variables:
          # invalid birth means the variable wasn't declared in this scope
          if live.birth.invalid:
            # We check the parent doesn't already have it (because it would override a valid death value for an incorrect one)
            if name notin parent.variables:
              parent.variables[name] = live

            toDelete.add(name)
        
        for name in toDelete:
          currentNode.variables.del(name)

        currentNode = parent

      else:
        for n in current.args:
          stack.add(n)

proc findVar(node: CIRControlNode, name: string): CLiveness {.raises: [KeyError].} =
  ## Search `node` and all descendants for `name`. Raises if not found.
  if name in node.variables: return node.variables[name]
  if not node.parent.isNil:
    return node.parent.findVar(name)

  raise newException(KeyError, "variable '" & name & "' not found in scope tree")

proc findReg(node: CIRControlNode, name: string): int {.raises: [KeyError].} =
  ## Search `node` and all descendants for `name`. Raises if not found.
  if name in node.registers: return node.registers[name]
  if not node.parent.isNil:
    return node.parent.findReg(name)

  raise newException(KeyError, "Register '" & name & "' not found in scope tree")


# ###########################
# Cruise Memory Map
# ## 0-7 -> Outputs registers, store the outputs of a shader (vertex, fragments)
# ## 8-51 -> Buffers register, Used to identify buffers, stored by bindings
# ## 52-67 -> Sampler data
# ## 68-end -> User data, All user data
# 

const
  OUTPUT_START_REG = 0
  BUFFER_START_REG = 8
  SAMPLER_START_REG = 52
  USER_START_REG = 68
  REG_SIZE = 8
  MAX_REGISTER = 2048

proc getTypeSize(name: string): int =
  case name:
    of "float", "int", "uint": 32
    of "vec2": 64
    of "vec3": 96
    of "vec4": 128
    else: 0

proc infixPrec(op: string): InfixPrec =
  case op:
  of "and", "or", "not": ipBit
  of "+", "-": ipAdd
  of "*", "/": ipMul
  else:        ipAdd 

proc flattenNode*(node: CIRNode): seq[FlatOp]
proc collectNode(acc: var seq[FlatOp], n: CIRNode): int =
    case n.kind:

    of cnkInfix:
      let opName = n.args[0].name
      let left   = n.args[1]
      let right  = n.args[2]
      let lid = acc.collectNode(left)
      let rid = acc.collectNode(right)
      acc.add FlatOp(
        op:    opName,
        left:  left,
        right: right,
        prec:  infixPrec(opName),
        src:   n.src)

    of cnkCall:
      var argInner: seq[FlatOp]
      for i in 1 ..< n.args.len:
        argInner.add flattenNode(n.args[i])
      let firstArg =
        if n.args.len > 1: n.args[1]
        else: newCIRNode(cnkEmpty)
      acc.add FlatOp(
        op:    n.args[0].name,
        left:  firstArg,
        right: newCIRNode(cnkEmpty),
        prec:  ipCall,
        src:   n.src,
        inner: argInner)

    of cnkPar:
      let innerOps = flattenNode(n.args[0])
      acc.add FlatOp(
        op:    "()",
        left:  n.args[0],
        right: newCIRNode(cnkEmpty),
        prec:  ipPar,
        src:   n.src,
        inner: innerOps)

    of cnkBracketExpr:
      let lid = acc.collectNode(n.args[0])  # base
      let rid = acc.collectNode(n.args[1])  # index 
      acc.add FlatOp(
        op:    "[]",
        left:  n.args[0],
        right: n.args[1],
        prec:  ipCall,
        src:   n.src)

    of cnkPrefix:
      let id = acc.collectNode(n.args[1])
      acc.add FlatOp(
        op:    n.args[0].name,
        left:  n.args[1],
        right: newCIRNode(cnkEmpty),
        prec:  ipMul,
        src:   n.src)

    else:
      discard

    acc.len

proc flattenNode*(node: CIRNode): seq[FlatOp] =
  var acc: seq[FlatOp]
  let id = acc.collectNode(node)
  acc.sort(proc(a, b: FlatOp): int = cmp(b.prec, a.prec))
  acc

#proc processFlatOps(node: CIRNode, allocator: var CRegisterAllocator, data: seq[FlatOp]): int =
#  for n in data:
#    if n.inner.len > 0:
#      processFlatOps(n.inner)

proc emitCBytecode(ctx: var CIRContext): CBytecode =
  ## Emit bytecode that should be
  var allocator: CRegisterAllocator
  var liveNode = ctx.getLiveness

  var stack: seq[CIRNode] = @[ctx.body.args[1]]
  var ccursor = 0
  var currentOp = 0

  while ccursor < stack.len:
    let current = stack[ccursor]
    let line = current.src.line

    case current.kind:
      of cnkSym:
        let v = liveNode.findVar(current.name)
        let reg = liveNode.findReg(current.name)
        result.data[^1] = result.data[^1] or (reg.uint32 shl (currentOp*REG_SIZE))
      of cnkIdentDef:
        let s = allocator.alloc(getTypeSize(current.args[1].name), line)
        #liveNode.registers[current.args[0].name] = 
      else: discard


    allocator.updateTick(current.src.line)





