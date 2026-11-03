  # ###################################################################################################################################### #
 # ############################################################ SEMANTIC PASS ########################################################### #
# ###################################################################################################################################### #

proc registerBinaryOp(c: var TypeCache, op: string, leftTy, rightTy, retTy: string) =
  var inst = TypeInst(
    name: op,
    kind: ProcType,
    returnType: retTy,
    size: 0
  )
  inst.fields.add(TypeField(name: "a", ty: leftTy))
  inst.fields.add(TypeField(name: "b", ty: rightTy))
  
  c.addInstance(inst)

proc registerUnaryOp(c: var TypeCache, op: string, argTy, retTy: string) =
  var inst = TypeInst(
    name: op,
    kind: ProcType,
    returnType: retTy,
    size: 0
  )
  inst.fields.add(TypeField(name: "a", ty: argTy))
  
  c.addInstance(inst)

proc registerBuiltins*(c: var TypeCache) =
  let numericTypes = ["int", "int32", "int64", "float", "float32", "uint", "uint32"]
  let allTypes = numericTypes & ["bool"]

  for ty in numericTypes:
    for op in ["+", "-", "*", "/", "%"]:
      c.registerBinaryOp(op, ty, ty, ty)

  for ty in allTypes:
    for op in ["==", "!=", "<", "<=", ">", ">="]:
      c.registerBinaryOp(op, ty, ty, "bool")

  for op in ["and", "or", "xor"]:
    c.registerBinaryOp(op, "bool", "bool", "bool")
    for ty in ["int", "int32", "int64", "uint", "uint32"]:
      c.registerBinaryOp(op, ty, ty, ty)

  for ty in numericTypes:
    c.registerUnaryOp("-", ty, ty)
  
  c.registerUnaryOp("not", "bool", "bool")