## Lightweight 3D → 2D helpers for the SDL3 2D renderer.
##
## SDL remains purely 2D (`SDL_RenderGeometry`); this module projects 3D points with
## Cruise LA (`Mat4`, `mat4Perspective`, `transformPoint`) and builds screen-space vertices.
## Suitable for billboards and simple perspective; not a full 3D engine.

import ../../src/la/La

type
  SdlVec3f* = object
    x*, y*, z*: float32
  HVec4* = object
    x*, y*, z*, w*: float32

proc sdlVec3f*(x, y, z: float32): SdlVec3f {.inline.} = SdlVec3f(x: x, y: y, z: z)

proc clipToNdc*(clip: HVec4): tuple[x, y: float32] {.inline.} =
  let w = clip.w
  if abs(w) < 1e-8f:
    return (0f, 0f)
  (clip.x / w, clip.y / w)

proc ndcToScreen*(ndcX, ndcY: float32; viewportW, viewportH: float32): FPoint {.inline.} =
  ## NDC [-1,1] (Y up) to SDL pixel coords (Y down).
  let sx = (ndcX * 0.5f + 0.5f) * viewportW
  let sy = (-ndcY * 0.5f + 0.5f) * viewportH
  fpoint(sx, sy)

proc projectPoint*(mvp: Mat4; p: SdlVec3f; viewportW, viewportH: float32): FPoint =
  let c = mvp * HVec4(x: p.x, y: p.y, z: p.z, w: 1.0f)
  let ndc = clipToNdc(c)
  ndcToScreen(ndc.x, ndc.y, viewportW, viewportH)

proc texturedQuadVertices3d*(
    mvp: Mat4;
    world: array[4, SdlVec3f];
    uv: array[4, FPoint];
    viewportW, viewportH: float32;
    tint: SDLRGBA = rgba(255, 255, 255, 255)
): seq[Vertex] =
  ## Four world corners (e.g. billboard), CCW or CW order matching your UV layout.
  result = newSeqOfCap[Vertex](4)
  for i in 0 ..< 4:
    let sp = projectPoint(mvp, world[i], viewportW, viewportH)
    result.add Vertex(pos: sp, uv: uv[i], color: tint)

proc texturedQuadIndices3d*(): seq[uint32] {.inline.} =
  @[0u32, 1u32, 2u32, 0u32, 2u32, 3u32]

proc scaleAxis*(axis: SdlVec3f; s: float32): SdlVec3f {.inline.} =
  sdlVec3f(axis.x * s, axis.y * s, axis.z * s)

proc add3*(a, b: SdlVec3f): SdlVec3f {.inline.} =
  sdlVec3f(a.x + b.x, a.y + b.y, a.z + b.z)

proc sub3*(a, b: SdlVec3f): SdlVec3f {.inline.} =
  sdlVec3f(a.x - b.x, a.y - b.y, a.z - b.z)

proc quadCornersBillboard*(center: SdlVec3f; halfW, halfH: float32;
    camRight, camUp: SdlVec3f): array[4, SdlVec3f] =
  ## Camera-facing quad: `camRight` / `camUp` should be unit vectors in world space.
  let ru = scaleAxis(camRight, halfW)
  let uu = scaleAxis(camUp, halfH)
  [sub3(sub3(center, ru), uu), add3(sub3(center, ru), uu),
   add3(add3(center, ru), uu), sub3(add3(center, ru), uu)]
