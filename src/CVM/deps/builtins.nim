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
  const numericTypes = ["int8", "int16", "int32", "int64", "float", "float32", "float64", "uint", "uint32"]
  const allTypes = ["int8", "int16", "int32", "int64", "float", "float32", "float64", "uint", "uint32", "bool"]
  const bitwiseTypes = ["int8", "int16", "int32", "int64", "uint", "uint32"]
  const matrixType = ["mat2f", "mat2i", "mat3f", "mat3i", "mat4f", "mat4i"]
  const vectorType = ["vec2f", "vec2i", "vec3f", "vec3i", "vec4f", "vec4i"]

  for ty in numericTypes:
    for op in ["+", "-", "*", "/", "%"]:
      c.registerBinaryOp(op, ty, ty, ty)

  for ty in allTypes:
    for op in ["==", "!=", "<", "<=", ">", ">="]:
      c.registerBinaryOp(op, ty, ty, "bool")

  for op in ["and", "or", "xor"]:
    c.registerBinaryOp(op, "bool", "bool", "bool")
    for ty in bitwiseTypes:
      c.registerBinaryOp(op, ty, ty, ty)

  for ty in matrixType:
    for op in ["+", "-", "*"]:
      c.registerBinaryOp(op, ty, ty, ty)

  for ty in vectorType:
    for op in ["+", "-"]:
      c.registerBinaryOp(op, ty, ty, ty)

  for i in 0..<matrixType.len:
    c.registerBinaryOp("*", matrixType[i], vectorType[i], vectorType[i])

  c.registerBinaryOp("sample", "sampler2D", "vec2f", "vec4f")

  for ty in numericTypes:
    c.registerUnaryOp("-", ty, ty)
    c.registerUnaryOp("abs", ty, ty)
    c.registerBinaryOp("min", ty, ty, ty)
    c.registerBinaryOp("max", ty, ty, ty)
  
  c.registerUnaryOp("not", "bool", "bool")
  c.registerUnaryOp("sqrt", "float", "float")
  c.registerUnaryOp("sqrt", "float32", "float32")
  c.registerUnaryOp("sqrt", "float64", "float64")
  c.registerUnaryOp("rsqrt", "float", "float")
  c.registerUnaryOp("rsqrt", "float32", "float32")
  c.registerUnaryOp("rsqrt", "float64", "float64")
  for op in ["sin", "cos"]:
    c.registerUnaryOp(op, "float", "float")
    c.registerUnaryOp(op, "float32", "float32")
    c.registerUnaryOp(op, "float64", "float64")
