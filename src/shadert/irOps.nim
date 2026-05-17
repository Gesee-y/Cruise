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
  CLiveness = object
    birth: NodePos
    death: NodePos

  CIRControlNode = ref object
    variables: Table[string, CLiveness]
    children: seq[CIRControlNode]
    parent: CIRControlNode
    stackCount: int

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
# I almost cried on this one
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


