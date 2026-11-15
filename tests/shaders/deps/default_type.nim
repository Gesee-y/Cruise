type
  Vec2* = object
    x*, y*: float32
  Vec3* = object
    x*, y*, z*: float32
  Vec4* = object
    x*, y*, z*, w*: float32
  Mat2* = object
  Mat3* = object
  Mat4* = object
  Sampler2D* = object

proc sample*(s: Sampler2D, v: Vec2): Vec4 = Vec4()
proc sampleLod*(s: Sampler2D, v: Vec2, lod: float32): Vec4 = Vec4()
proc sampleLod*(s: Sampler2D, v: Vec2, lod: float): Vec4 = Vec4()
proc textureLod*(s: Sampler2D, v: Vec2, lod: float32): Vec4 = Vec4()
proc textureLod*(s: Sampler2D, v: Vec2, lod: float): Vec4 = Vec4()
proc `*`*(m: Mat2, v: Vec2): Vec2 = v
proc `*`*(m1, m2: Mat2): Mat2 = Mat2()
proc `*`*(m: Mat3, v: Vec3): Vec3 = v
proc `*`*(m: Mat3, v: Vec2): Vec3 = Vec3()
proc `*`*(m1, m2: Mat3): Mat3 = Mat3()
proc `*`*(m: Mat4, v: Vec4): Vec4 = v
proc `*`*(m: Mat4, v: Vec3): Vec4 = Vec4()
proc `*`*(m1, m2: Mat4): Mat4 = Mat4()

proc `*`*(v1, v2: Vec2): Vec2 = Vec2()
proc `*`*(v1, v2: Vec3): Vec3 = Vec3()
proc `*`*(v1, v2: Vec4): Vec4 = Vec4()

proc `+`*(v1, v2: Vec2): Vec2 = v1
proc `+`*(v1, v2: Vec3): Vec3 = v1
proc `+`*(v1, v2: Vec4): Vec4 = v1

proc `-`*(v1, v2: Vec2): Vec2 = v1
proc `-`*(v1, v2: Vec3): Vec3 = v1
proc `-`*(v1, v2: Vec4): Vec4 = v1

proc `-`*(v: Vec2): Vec2 = v
proc `-`*(v: Vec3): Vec3 = v
proc `-`*(v: Vec4): Vec4 = v

proc `*`*(v: Vec2, s: float32): Vec2 = v
proc `*`*(s: float32, v: Vec2): Vec2 = v
proc `*`*(v: Vec3, s: float32): Vec3 = v
proc `*`*(s: float32, v: Vec3): Vec3 = v
proc `*`*(v: Vec4, s: float32): Vec4 = v
proc `*`*(s: float32, v: Vec4): Vec4 = v

proc `/`*(v: Vec2, s: float32): Vec2 = v
proc `/`*(v: Vec3, s: float32): Vec3 = v
proc `/`*(v: Vec4, s: float32): Vec4 = v

proc `+`*(v: Vec3, s: float32): Vec3 = v
proc `-`*(v: Vec3, s: float32): Vec3 = v
proc `*`*(v: Vec2, s: float): Vec2 = v
proc `*`*(v: Vec3, s: float): Vec3 = v
proc `*`*(v: Vec4, s: float): Vec4 = v
proc `*`*(s: float, v: Vec2): Vec2 = v
proc `*`*(s: float, v: Vec3): Vec3 = v
proc `*`*(s: float, v: Vec4): Vec4 = v
proc `+`*(v: Vec3, s: float): Vec3 = v
proc `-`*(v: Vec3, s: float): Vec3 = v

proc dot*(a, b: Vec2): float32 = 0.0f
proc dot*(a, b: Vec3): float32 = 0.0f
proc dot*(a, b: Vec4): float32 = 0.0f

proc normalize*(v: Vec2): Vec2 = v
proc normalize*(v: Vec3): Vec3 = v
proc normalize*(v: Vec4): Vec4 = v
proc inversesqrt*(x: float32): float32 = x
proc inversesqrt*(x: Vec2): Vec2 = x
proc inversesqrt*(x: Vec3): Vec3 = x
proc inversesqrt*(x: Vec4): Vec4 = x

proc reflect*(i, n: Vec2): Vec2 = i
proc reflect*(i, n: Vec3): Vec3 = i
proc refract*(i, n: Vec2, eta: float32): Vec2 = i
proc refract*(i, n: Vec3, eta: float32): Vec3 = i
proc refract*(i, n: Vec4, eta: float32): Vec4 = i
proc cross*(a, b: Vec3): Vec3 = a
proc length*(v: Vec2): float32 = 0.0f
proc length*(v: Vec3): float32 = 0.0f
proc length*(v: Vec4): float32 = 0.0f
proc length*(v: float32): float32 = v
proc distance*(a, b: Vec2): float32 = 0.0f
proc distance*(a, b: Vec3): float32 = 0.0f
proc distance*(a, b: Vec4): float32 = 0.0f
proc distance*(a, b: float32): float32 = 0.0f
proc abs*(x: Vec2): Vec2 = x
proc abs*(x: Vec3): Vec3 = x
proc abs*(x: Vec4): Vec4 = x
proc min*(x, y: Vec2): Vec2 = x
proc min*(x, y: Vec3): Vec3 = x
proc min*(x, y: Vec4): Vec4 = x
proc max*(x, y: Vec2): Vec2 = x
proc max*(x, y: Vec3): Vec3 = x
proc max*(x, y: Vec4): Vec4 = x
proc min*(x: Vec2, y: float32): Vec2 = x
proc min*(x: Vec3, y: float32): Vec3 = x
proc min*(x: Vec4, y: float32): Vec4 = x
proc max*(x: Vec2, y: float32): Vec2 = x
proc max*(x: Vec3, y: float32): Vec3 = x
proc max*(x: Vec4, y: float32): Vec4 = x
proc faceforward*(n, i, nref: Vec2): Vec2 = n
proc faceforward*(n, i, nref: Vec3): Vec3 = n
proc faceforward*(n, i, nref: Vec4): Vec4 = n

proc pow*(x: Vec2, y: float32): Vec2 = x
proc pow*(x: Vec3, y: float32): Vec3 = x
proc pow*(x: Vec4, y: float32): Vec4 = x

# Shading builtins are declared here for the shader source type-checker. Their
# bodies are placeholders; the CVM generator lowers these calls to VM opcodes.
proc fract*(x: float32): float32 = x
proc fract*(x: Vec2): Vec2 = x
proc fract*(x: Vec3): Vec3 = x
proc fract*(x: Vec4): Vec4 = x
proc floor*(x: Vec2): Vec2 = x
proc floor*(x: Vec3): Vec3 = x
proc floor*(x: Vec4): Vec4 = x

proc step*(edge, x: float32): float32 = x
proc step*(edge, x: Vec2): Vec2 = x
proc step*(edge, x: Vec3): Vec3 = x
proc step*(edge, x: Vec4): Vec4 = x
proc step*(edge: float32, x: Vec2): Vec2 = x
proc step*(edge: float32, x: Vec3): Vec3 = x
proc step*(edge: float32, x: Vec4): Vec4 = x

proc smoothstep*(edge0, edge1, x: float32): float32 = x
proc smoothstep*(edge0, edge1, x: Vec2): Vec2 = x
proc smoothstep*(edge0, edge1, x: Vec3): Vec3 = x
proc smoothstep*(edge0, edge1, x: Vec4): Vec4 = x
proc smoothstep*(edge0, edge1: float32, x: Vec2): Vec2 = x
proc smoothstep*(edge0, edge1: float32, x: Vec3): Vec3 = x
proc smoothstep*(edge0, edge1: float32, x: Vec4): Vec4 = x

proc mix*(x, y, a: float32): float32 = x
proc mix*(x, y: Vec2, a: float32): Vec2 = x
proc mix*(x, y: Vec3, a: float32): Vec3 = x
proc mix*(x, y: Vec4, a: float32): Vec4 = x
proc mix*(x, y, a: Vec2): Vec2 = x
proc mix*(x, y, a: Vec3): Vec3 = x
proc mix*(x, y, a: Vec4): Vec4 = x
proc lerp*(x, y, a: float32): float32 = x
proc lerp*(x, y: Vec2, a: float32): Vec2 = x
proc lerp*(x, y: Vec3, a: float32): Vec3 = x
proc lerp*(x, y: Vec4, a: float32): Vec4 = x
proc lerp*(x, y, a: Vec2): Vec2 = x
proc lerp*(x, y, a: Vec3): Vec3 = x
proc lerp*(x, y, a: Vec4): Vec4 = x

proc clamp*(x, lo, hi: Vec2): Vec2 = x
proc clamp*(x, lo, hi: Vec3): Vec3 = x
proc clamp*(x, lo, hi: Vec4): Vec4 = x
proc clamp*(x: Vec2, lo, hi: float32): Vec2 = x
proc clamp*(x: Vec3, lo, hi: float32): Vec3 = x
proc clamp*(x: Vec4, lo, hi: float32): Vec4 = x

# The compiler lowers these GLSL-style math calls to CVM math opcodes.
proc tan*(x: Vec2): Vec2 = x
proc tan*(x: Vec3): Vec3 = x
proc tan*(x: Vec4): Vec4 = x
proc asin*(x: Vec2): Vec2 = x
proc asin*(x: Vec3): Vec3 = x
proc asin*(x: Vec4): Vec4 = x
proc acos*(x: Vec2): Vec2 = x
proc acos*(x: Vec3): Vec3 = x
proc acos*(x: Vec4): Vec4 = x
proc atan*(x: Vec2): Vec2 = x
proc atan*(x: Vec3): Vec3 = x
proc atan*(x: Vec4): Vec4 = x
proc asin*(x: float32): float32 = x
proc acos*(x: float32): float32 = x
proc atan*(x: float32): float32 = x
proc atan*(y, x: float32): float32 = y
proc atan*(y, x: Vec2): Vec2 = y
proc atan*(y, x: Vec3): Vec3 = y
proc atan*(y, x: Vec4): Vec4 = y

proc exp*(x: Vec2): Vec2 = x
proc exp*(x: Vec3): Vec3 = x
proc exp*(x: Vec4): Vec4 = x
proc log*(x: Vec2): Vec2 = x
proc log*(x: Vec3): Vec3 = x
proc log*(x: Vec4): Vec4 = x
proc exp2*(x: Vec2): Vec2 = x
proc exp2*(x: Vec3): Vec3 = x
proc exp2*(x: Vec4): Vec4 = x
proc log2*(x: Vec2): Vec2 = x
proc log2*(x: Vec3): Vec3 = x
proc log2*(x: Vec4): Vec4 = x
proc ceil*(x: Vec2): Vec2 = x
proc ceil*(x: Vec3): Vec3 = x
proc ceil*(x: Vec4): Vec4 = x
proc trunc*(x: Vec2): Vec2 = x
proc trunc*(x: Vec3): Vec3 = x
proc trunc*(x: Vec4): Vec4 = x
proc round*(x: Vec2): Vec2 = x
proc round*(x: Vec3): Vec3 = x
proc round*(x: Vec4): Vec4 = x
proc sign*(x: float32): float32 = x
proc sign*(x: Vec2): Vec2 = x
proc sign*(x: Vec3): Vec3 = x
proc sign*(x: Vec4): Vec4 = x
proc radians*(x: Vec2): Vec2 = x
proc radians*(x: Vec3): Vec3 = x
proc radians*(x: Vec4): Vec4 = x
proc degrees*(x: Vec2): Vec2 = x
proc degrees*(x: Vec3): Vec3 = x
proc degrees*(x: Vec4): Vec4 = x
proc radians*(x: float32): float32 = x
proc degrees*(x: float32): float32 = x
proc sinh*(x: Vec2): Vec2 = x
proc sinh*(x: Vec3): Vec3 = x
proc sinh*(x: Vec4): Vec4 = x
proc cosh*(x: Vec2): Vec2 = x
proc cosh*(x: Vec3): Vec3 = x
proc cosh*(x: Vec4): Vec4 = x
proc tanh*(x: Vec2): Vec2 = x
proc tanh*(x: Vec3): Vec3 = x
proc tanh*(x: Vec4): Vec4 = x
proc asinh*(x: Vec2): Vec2 = x
proc asinh*(x: Vec3): Vec3 = x
proc asinh*(x: Vec4): Vec4 = x
proc acosh*(x: Vec2): Vec2 = x
proc acosh*(x: Vec3): Vec3 = x
proc acosh*(x: Vec4): Vec4 = x
proc atanh*(x: Vec2): Vec2 = x
proc atanh*(x: Vec3): Vec3 = x
proc atanh*(x: Vec4): Vec4 = x
proc asinh*(x: float32): float32 = x
proc acosh*(x: float32): float32 = x
proc atanh*(x: float32): float32 = x
proc `mod`*(x, y: Vec2): Vec2 = x
proc `mod`*(x, y: Vec3): Vec3 = x
proc `mod`*(x, y: Vec4): Vec4 = x
proc `mod`*(x: Vec2, y: float32): Vec2 = x
proc `mod`*(x: Vec3, y: float32): Vec3 = x
proc `mod`*(x: Vec4, y: float32): Vec4 = x

proc transpose*(m: Mat2): Mat2 = m
proc transpose*(m: Mat3): Mat3 = m
proc transpose*(m: Mat4): Mat4 = m

proc inverse*(m: Mat2): Mat2 = m
proc inverse*(m: Mat3): Mat3 = m
proc inverse*(m: Mat4): Mat4 = m
proc determinant*(m: Mat2): float32 = 1.0f
proc determinant*(m: Mat3): float32 = 1.0f
proc determinant*(m: Mat4): float32 = 1.0f
proc matrixCompMult*(a, b: Mat2): Mat2 = a
proc matrixCompMult*(a, b: Mat3): Mat3 = a
proc matrixCompMult*(a, b: Mat4): Mat4 = a

proc newVec2f*(x, y: float32): Vec2 = Vec2(x: x, y: y)

proc newVec3f*(x, y, z: float32): Vec3 = Vec3(x: x, y: y, z: z)
proc newVec3f*(v: Vec2, z: float32): Vec3 = Vec3(x: v.x, y: v.y, z: z)
proc newVec3f*(v: Vec4): Vec3 = Vec3(x: v.x, y: v.y, z: v.z)

proc newVec4f*(x, y, z, w: float32): Vec4 = Vec4(x: x, y: y, z: z, w: w)
proc newVec4f*(v: Vec3, w: float32): Vec4 = Vec4(x: v.x, y: v.y, z: v.z, w: w)
proc newVec4f*(v: Vec2, z, w: float32): Vec4 = Vec4(x: v.x, y: v.y, z: z, w: w)
