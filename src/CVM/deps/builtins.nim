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

proc registerFn(c: var TypeCache, name: string, argTys: openArray[string], retTy: string) =
  var inst = TypeInst(
    name: name,
    kind: ProcType,
    returnType: retTy,
    size: 0
  )
  for i, a in argTys:
    inst.fields.add(TypeField(name: "p" & $i, ty: a))
  c.addInstance(inst)

proc registerBuiltins*(c: var TypeCache) =
  const numericTypes = ["int8", "int16", "int32", "int64", "float", "float32", "float64", "uint", "uint32"]
  const allTypes = ["int8", "int16", "int32", "int64", "float", "float32", "float64", "uint", "uint32", "bool"]
  const bitwiseTypes = ["int8", "int16", "int32", "int64", "uint", "uint32"]
  const matrixType = ["mat2f", "mat2i", "mat3f", "mat3i", "mat4f", "mat4i"]
  const vectorType = ["vec2f", "vec2i", "vec3f", "vec3i", "vec4f", "vec4i"]
  const floatVectorTypes = ["vec2f", "vec3f", "vec4f"]

  for ty in numericTypes:
    for op in ["+", "-", "*", "/", "%"]:
      c.registerBinaryOp(op, ty, ty, ty)
  for op in ["+", "-", "*", "/"]:
    c.registerBinaryOp(op, "float32", "float", "float32")
    c.registerBinaryOp(op, "float", "float32", "float32")

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
    for op in ["+", "-", "*", "/"]:
      c.registerBinaryOp(op, ty, ty, ty)
    c.registerUnaryOp("-", ty, ty)

  for i in 0..<matrixType.len:
    c.registerBinaryOp("*", matrixType[i], vectorType[i], vectorType[i])

  # Vector * scalar and Vector +/- scalar
  for ty in floatVectorTypes:
    for sTy in ["float", "float32"]:
      c.registerBinaryOp("*", ty, sTy, ty)
      c.registerBinaryOp("*", sTy, ty, ty)
      c.registerBinaryOp("/", ty, sTy, ty)
      c.registerBinaryOp("+", ty, sTy, ty)
      c.registerBinaryOp("-", ty, sTy, ty)

  c.registerBinaryOp("sample", "sampler2D", "vec2f", "vec4f")

  # Dot product
  c.registerBinaryOp("dot", "vec2f", "vec2f", "float32")
  c.registerBinaryOp("dot", "vec3f", "vec3f", "float32")
  c.registerBinaryOp("dot", "vec4f", "vec4f", "float32")

  # Normalize
  c.registerUnaryOp("normalize", "vec2f", "vec2f")
  c.registerUnaryOp("normalize", "vec3f", "vec3f")
  c.registerUnaryOp("normalize", "vec4f", "vec4f")

  # Reflect
  c.registerBinaryOp("reflect", "vec2f", "vec2f", "vec2f")
  c.registerBinaryOp("reflect", "vec3f", "vec3f", "vec3f")
  c.registerBinaryOp("cross", "vec3f", "vec3f", "vec3f")
  c.registerUnaryOp("length", "float", "float")
  c.registerUnaryOp("length", "float32", "float32")
  c.registerUnaryOp("length", "vec2f", "float32")
  c.registerUnaryOp("length", "vec3f", "float32")
  c.registerUnaryOp("length", "vec4f", "float32")
  for ty in floatVectorTypes:
    for scalarTy in ["float", "float32"]:
      c.registerFn("refract", [ty, ty, scalarTy], ty)
    c.registerBinaryOp("distance", ty, ty, "float32")
  c.registerBinaryOp("distance", "float", "float", "float")
  c.registerBinaryOp("distance", "float32", "float32", "float32")
  c.registerFn("sampleLod", ["sampler2D", "vec2f", "float32"], "vec4f")
  c.registerFn("sampleLod", ["sampler2D", "vec2f", "float"], "vec4f")
  c.registerFn("textureLod", ["sampler2D", "vec2f", "float32"], "vec4f")
  c.registerFn("textureLod", ["sampler2D", "vec2f", "float"], "vec4f")

  # Pow
  for sTy in ["float", "float32"]:
    c.registerBinaryOp("pow", sTy, sTy, sTy)
    for vTy in floatVectorTypes:
      c.registerBinaryOp("pow", vTy, sTy, vTy)

  # Transpose and Invert
  for mTy in ["mat2f", "mat3f", "mat4f"]:
    c.registerUnaryOp("transpose", mTy, mTy)
    c.registerUnaryOp("inverse", mTy, mTy)
    c.registerUnaryOp("invert", mTy, mTy)
    c.registerUnaryOp("determinant", mTy, "float32")
    c.registerBinaryOp("matrixCompMult", mTy, mTy, mTy)

  # Vector constructors (newVec2f, newVec3f, newVec4f)
  for name in ["newVec2", "newVec2f"]:
    c.registerFn(name, ["float32", "float32"], "vec2f")
    c.registerFn(name, ["float", "float"], "vec2f")

  for name in ["newVec3", "newVec3f"]:
    c.registerUnaryOp(name, "vec4f", "vec3f")
    c.registerFn(name, ["vec2f", "float32"], "vec3f")
    c.registerFn(name, ["vec2f", "float"], "vec3f")
    c.registerFn(name, ["float32", "float32", "float32"], "vec3f")
    c.registerFn(name, ["float", "float", "float"], "vec3f")

  for name in ["newVec4", "newVec4f"]:
    c.registerFn(name, ["vec3f", "float32"], "vec4f")
    c.registerFn(name, ["vec3f", "float"], "vec4f")
    c.registerFn(name, ["vec2f", "float32", "float32"], "vec4f")
    c.registerFn(name, ["vec2f", "float", "float"], "vec4f")
    c.registerFn(name, ["float32", "float32", "float32", "float32"], "vec4f")
    c.registerFn(name, ["float", "float", "float", "float"], "vec4f")

  for ty in numericTypes:
    c.registerUnaryOp("-", ty, ty)
    c.registerUnaryOp("abs", ty, ty)
    c.registerBinaryOp("min", ty, ty, ty)
    c.registerBinaryOp("max", ty, ty, ty)

  const shaderUnaryMath = ["tan", "asin", "acos", "atan", "exp", "log",
    "exp2", "log2", "ceil", "trunc", "round", "sign", "radians",
    "degrees", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh"]
  for ty in ["float", "float32"]:
    for name in shaderUnaryMath:
      c.registerUnaryOp(name, ty, ty)
    c.registerBinaryOp("atan", ty, ty, ty)
    c.registerBinaryOp("mod", ty, ty, ty)
  for ty in floatVectorTypes:
    c.registerUnaryOp("inversesqrt", ty, ty)
    c.registerUnaryOp("abs", ty, ty)
    c.registerBinaryOp("min", ty, ty, ty)
    c.registerBinaryOp("max", ty, ty, ty)
    c.registerBinaryOp("min", ty, "float", ty)
    c.registerBinaryOp("min", ty, "float32", ty)
    c.registerBinaryOp("max", ty, "float", ty)
    c.registerBinaryOp("max", ty, "float32", ty)
    for name in shaderUnaryMath:
      c.registerUnaryOp(name, ty, ty)
    c.registerBinaryOp("atan", ty, ty, ty)
    c.registerBinaryOp("mod", ty, ty, ty)
    c.registerBinaryOp("mod", ty, "float", ty)
    c.registerBinaryOp("mod", ty, "float32", ty)
    c.registerFn("faceforward", [ty, ty, ty], ty)
  
  c.registerUnaryOp("not", "bool", "bool")
  c.registerUnaryOp("sqrt", "float", "float")
  c.registerUnaryOp("sqrt", "float32", "float32")
  c.registerUnaryOp("sqrt", "float64", "float64")
  c.registerUnaryOp("rsqrt", "float", "float")
  c.registerUnaryOp("rsqrt", "float32", "float32")
  c.registerUnaryOp("rsqrt", "float64", "float64")
  c.registerUnaryOp("inversesqrt", "float", "float")
  c.registerUnaryOp("inversesqrt", "float32", "float32")
  c.registerUnaryOp("inversesqrt", "float64", "float64")
  for op in ["sin", "cos"]:
    c.registerUnaryOp(op, "float", "float")
    c.registerUnaryOp(op, "float32", "float32")
    c.registerUnaryOp(op, "float64", "float64")

  # Common GLSL-style shading functions. Scalar and vector overloads share
  # the same VM opcodes; scalar arguments may be broadcast over a vector.
  for ty in ["float", "float32"]:
    c.registerUnaryOp("floor", ty, ty)
    c.registerUnaryOp("fract", ty, ty)
    c.registerBinaryOp("step", ty, ty, ty)
    c.registerFn("smoothstep", [ty, ty, ty], ty)
    c.registerFn("mix", [ty, ty, ty], ty)
    c.registerFn("lerp", [ty, ty, ty], ty)
    c.registerFn("clamp", [ty, ty, ty], ty)

  for ty in floatVectorTypes:
    c.registerUnaryOp("floor", ty, ty)
    c.registerUnaryOp("fract", ty, ty)
    c.registerBinaryOp("step", ty, ty, ty)
    c.registerFn("smoothstep", [ty, ty, ty], ty)
    c.registerFn("mix", [ty, ty, ty], ty)
    c.registerFn("lerp", [ty, ty, ty], ty)
    c.registerFn("clamp", [ty, ty, ty], ty)
    for scalarTy in ["float", "float32"]:
      c.registerBinaryOp("step", scalarTy, ty, ty)
      c.registerFn("smoothstep", [scalarTy, scalarTy, ty], ty)
      c.registerFn("mix", [ty, ty, scalarTy], ty)
      c.registerFn("lerp", [ty, ty, scalarTy], ty)
      c.registerFn("clamp", [ty, scalarTy, scalarTy], ty)
