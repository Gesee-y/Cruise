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

# Reverse liveness analysis.
proc getLiveness(ctx: CIRContext): Table[string, CLiveness] =
  var stack: seq[CIRNode] = @[ctx.body.args[1]]
  result = initTable[string, CLiveness]()

  while stack.len > 0:
    let current = stack.pop()

    case current.kind:
      of cnkIntLit, cnkFloatLit, cnkEmpty: continue
      of cnkIdentDef:
        let name = current.args[0].name
        if name in result:
          result[name].birth = current.src
      of cnkForStmt:
        let name = current.args[0].name
        if name in result:
          result[name].birth = current.src

        for n in current.args[1..^1]:
          stack.add(n)
      of cnkSym:
        if current.name notin result:
          result[current.name] = CLiveness(death: current.src)
      of cnkCall, cnkInfix, cnkPrefix, cnkConv:
        # Exclude functions name so they are not counted in the analysis
        for n in current.args[1..^1]:
          stack.add(n)
      else:
        for n in current.args:
          stack.add(n)


