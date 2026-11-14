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

proc dot*(a, b: Vec2): float32 = 0.0f
proc dot*(a, b: Vec3): float32 = 0.0f
proc dot*(a, b: Vec4): float32 = 0.0f

proc normalize*(v: Vec2): Vec2 = v
proc normalize*(v: Vec3): Vec3 = v
proc normalize*(v: Vec4): Vec4 = v

proc reflect*(i, n: Vec2): Vec2 = i
proc reflect*(i, n: Vec3): Vec3 = i

proc pow*(x: Vec2, y: float32): Vec2 = x
proc pow*(x: Vec3, y: float32): Vec3 = x
proc pow*(x: Vec4, y: float32): Vec4 = x

proc transpose*(m: Mat2): Mat2 = m
proc transpose*(m: Mat3): Mat3 = m
proc transpose*(m: Mat4): Mat4 = m

proc inverse*(m: Mat2): Mat2 = m
proc inverse*(m: Mat3): Mat3 = m
proc inverse*(m: Mat4): Mat4 = m

proc newVec2f*(x, y: float32): Vec2 = Vec2(x: x, y: y)

proc newVec3f*(x, y, z: float32): Vec3 = Vec3(x: x, y: y, z: z)
proc newVec3f*(v: Vec2, z: float32): Vec3 = Vec3(x: v.x, y: v.y, z: z)
proc newVec3f*(v: Vec4): Vec3 = Vec3(x: v.x, y: v.y, z: v.z)

proc newVec4f*(x, y, z, w: float32): Vec4 = Vec4(x: x, y: y, z: z, w: w)
proc newVec4f*(v: Vec3, w: float32): Vec4 = Vec4(x: v.x, y: v.y, z: v.z, w: w)
proc newVec4f*(v: Vec2, z, w: float32): Vec4 = Vec4(x: v.x, y: v.y, z: z, w: w)