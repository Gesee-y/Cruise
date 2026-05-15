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
proc getLiveness(ctx: CIRContext): CIRControlNode =
  var stack: seq[CIRNode] = @[ctx.body.args[1]]
  result = CIRControlNode()
  var currentNode = result


  while stack.len > 0:
    let current = stack.pop()
    # echo current.kind
    # echo currentNode.variables
    # echo currentNode.stackCount

    case current.kind:
      of cnkIntLit, cnkFloatLit, cnkEmpty: continue
      of cnkIdentDef:
        let name = current.args[0].name
        if name in currentNode.variables:
          currentNode.variables[name].birth = current.src
      of cnkSym:
        if current.name notin currentNode.variables:
          currentNode.variables[current.name] = newCLiveness(death = current.src)
      of cnkCall, cnkInfix, cnkPrefix, cnkConv:
        # Exclude functions name so they are not counted in the analysis
        for n in current.args[1..^1]:
          stack.add(n)
      of cnkStmtList:
        let node = CIRControlNode()
        node.stackCount = current.args.len
        node.parent = currentNode
        currentNode.children.add(node)
        currentNode = node
        stack.add(newCIRNode(cnkNone))

        for n in current.args:
          stack.add(n)

      of cnkNone:
        var parent = currentNode.parent
        if parent.isNil:
          break
        var toDelete: seq[string]

        for name, live in currentNode.variables:
          if live.birth.invalid:
            if name notin parent.variables:
              parent.variables[name] = live

            toDelete.add(name)

        for name in toDelete:
          currentNode.variables.del(name)

        currentNode = parent

      else:
        for n in current.args:
          stack.add(n)


