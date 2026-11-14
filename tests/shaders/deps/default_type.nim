type
  Vec2* = object
    x, y: float32
  Vec3* = object
    x, y, z: float32
  Vec4* = object
    x, y, z, w: float32
  Sampler2D* = object

proc sample*(s: Sampler2D, v: Vec2): Vec4 = Vec4()