#############################################################################################################################
####################################################### RAYS ################################################################
#############################################################################################################################

type
  MRay2D* = concept r
    r.start is CVec2
    r.dir is CVec2

  MRay3D* = concept r
    r.start is CVec3
    r.dir is CVec3

  MRay4D* = concept r
    r.start is CVec4
    r.dir is CVec4

  MRay* = MRay2D | MRay3D | MRay4D

template `$`(r: MRay): string =
  "Ray<" & $r.start & " toward " & $r.dir & ">"

template rayAt(r: MRay, t): untyped =
  r.start + (r.dir)*t

template closestPoint(ray: MRay2D, pos: CVec2, min_t: float32 = 0'f32, max_t: float = float32.high): untyped =
  let pa = pos - ray.start
  let ba = ray.dir

  var h = dot(pa, ba) / dot(ba, ba)
  h = clamp(h, min_t, max_t)

  length(pa - (ba * h))

template closestPoint(ray: MRay3D, pos: CVec3, min_t: float32 = 0'f32, max_t: float = float32.high): untyped =
  let pa = pos - ray.start
  let ba = ray.dir

  var h = dot(pa, ba) / dot(ba, ba)
  h = clamp(h, min_t, max_t)

  length(pa - (ba * h))

template closestPoint(ray: MRay4D, pos: CVec4, min_t: float32 = 0'f32, max_t: float = float32.high): untyped =
  let pa = pos - ray.start
  let ba = ray.dir

  var h = dot(pa, ba) / dot(ba, ba)
  h = clamp(h, min_t, max_t)

  length(pa - (ba * h))