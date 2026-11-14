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