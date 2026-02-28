## render_commands.nim
##
## 2D rendering command definitions and push helpers.
##
## Commands are plain objects declared via `commandAction` — no inheritance.
## Push helpers come in two flavours:
##   - explicit target : DrawPoint2D(ren, target, color, pos)
##   - implicit target : DrawPoint2D(ren, color, pos)  → uses viewport screen
##
## Handle compression:
##   ResourceHandle is 64 bits (typeId 10 | generation 22 | index 32).
##   The command buffer encodes target/caller as 32-bit fields, so we strip
##   the generation and pack typeId (10 bits) + index (22 bits) into uint32.
##   This is safe for single-frame commands — dangling detection is the
##   caller's responsibility.

# ---------------------------------------------------------------------------
# Handle compression helpers
##
## CompressedHandle fits in the 32-bit target/caller slot of a Signature.
## Layout:
##   bits 31-22 : typeId  (10 bits)
##   bits 21- 0 : index   (22 bits — lower 22 of the full 32-bit index)
##
## NOTE: resources with index >= 2^22 (~4M) will alias. In practice a single
## resource type rarely exceeds this limit; add an assert in `compress` if
## you want an early warning.
# ---------------------------------------------------------------------------

const
  CompressedTypeBits  = 10
  CompressedIndexBits = 22
  CompressedTypeShift = CompressedIndexBits
  CompressedIndexMask = uint32((1 shl CompressedIndexBits) - 1)
  CompressedTypeMask  = uint32((1 shl CompressedTypeBits)  - 1)

proc compress*(h: ResourceHandle): uint32 {.inline.} =
  ## Strip the generation field and pack typeId + low index bits into uint32.
  let tid = uint32(h.handleTypeId) and CompressedTypeMask
  let idx = h.handleIndex         and CompressedIndexMask
  (tid shl CompressedTypeShift) or idx

proc compress*[T](h: CResource[T]): uint32 {.inline.} =
  ## Typed overload — delegates to the opaque version.
  compress(h.toHandle)

proc decompressTypeId*(c: uint32): TypeId {.inline.} =
  ## Recover the TypeId from a compressed handle.
  TypeId((c shr CompressedTypeShift) and CompressedTypeMask)

proc decompressIndex*(c: uint32): uint32 {.inline.} =
  ## Recover the resource index from a compressed handle.
  c and CompressedIndexMask

# ---------------------------------------------------------------------------
# Abstract facade types
##
## These are phantom types — they carry no data.  User code always works with
## `CResource[Texture]`, never with any backend-specific concrete type.
## Backend code maps these to its own concrete types via `registerType`.
# ---------------------------------------------------------------------------

type
  Texture* = object   ## Abstract 2D texture resource.
  Screen*  = object   ## Abstract render-target / screen surface.

# ---------------------------------------------------------------------------
# Command types
# ---------------------------------------------------------------------------

type DrawPoint2DCmd* = object
  ## Draw a single point at `pos` with the given `color`.
  color*: tuple[r,g,b,a:uint8]     ## iRGBA packed as four int components.
  pos*:   tuple[x,y:float32]
commandAction DrawPoint2DCmd

type DrawLine2DCmd* = object
  ## Draw a line segment from `start` to `stop`.
  color*: tuple[r,g,b,a:uint8]
  start*: tuple[x,y:float32]
  stop*:  tuple[x,y:float32]

commandAction DrawLine2DCmd

type DrawRect2DCmd* = object
  ## Draw an axis-aligned rectangle.
  color*:  tuple[r,g,b,a:uint8]
  rect*:   tuple[x1,x2,y1,y2:float32]   ## Rect2Df equivalent.
  filled*: bool
commandAction DrawRect2DCmd

type DrawCircle2DCmd* = object
  ## Draw a circle centered at `center` with the given `radius`.
  color*:  tuple[r,g,b,a:uint8]
  center*: tuple[x,y:float32]
  radius*: float32
  filled*: bool
commandAction DrawCircle2DCmd

type DrawTexture2DCmd* = object
  ## Blit a texture onto a target surface.
  ## The source texture is encoded in the command's `caller` field (compressed
  ## handle) so the backend can recover it without an extra field here.
  rect*:   tuple[x1,x2,x3,x4:float32]   ## Destination rectangle on the target surface.
  center*: tuple[x,y:float32]    ## Rotation pivot in local space.
  angle*:  float32  ## Rotation in radians.
  flipH*:  bool
  flipV*:  bool
commandAction DrawTexture2DCmd

# ---------------------------------------------------------------------------
# Renderer concept
##
## Any renderer passed to the push helpers must provide:
##   - a `commandBuffer` field / proc returning `var CommandBuffer`
##   - a `screenTarget` proc returning `CResource[Screen]`
##     (the default render target when no explicit target is given)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# DrawPoint2D
# ---------------------------------------------------------------------------

proc DrawPoint2D*[R; C: Vec4i; V: Vec2f](
    ren:      var R,
    target:   CResource[Screen],
    color:    C,
    pos:      V,
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a point-draw command onto `target`.
  ren.commandBuffer.addCommand[DrawPoint2DCmd, R](
    compress(target), priority, 0u32,
    DrawPoint2DCmd(color: (color.x.uint8, color.y.uint8, color.z.uint8, color.w.uint8), pos: (pos.x, pos.y)),
    pass
  )

proc DrawPoint2D*[R; C: Vec4i; V: Vec2f](
    ren:      var R,
    color:    C,
    pos:      V,
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a point-draw command onto the renderer's default screen target.
  DrawPoint2D(ren, ren.screenTarget, color, pos, priority, pass)

# ---------------------------------------------------------------------------
# DrawLine2D
# ---------------------------------------------------------------------------

proc DrawLine2D*[R; C: Vec4i; V: Vec2f](
    ren:      var R,
    target:   CResource[Screen],
    color:    C,
    start:    V,
    stop:     V,
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a line-draw command onto `target`.
  ren.commandBuffer.addCommand[DrawLine2DCmd, R](
    compress(target), priority, 0u32,
    DrawLine2DCmd(color: (color.x.uint8, color.y.uint8, color.z.uint8, color.w.uint8), 
      start: (start.x, start.y), stop: (stop.x, stop.y)),
    pass
  )

proc DrawLine2D*[R; C: Vec4i; V: Vec2f](
    ren:      var R,
    color:    C,
    start:    V,
    stop:     V,
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a line-draw command onto the renderer's default screen target.
  DrawLine2D(ren, ren.screenTarget, color, start, stop, priority, pass)

# ---------------------------------------------------------------------------
# DrawRect2D
# ---------------------------------------------------------------------------

proc DrawRect2D*[R; C: Vec4i; B: Box2Df](
    ren:      var R,
    target:   CResource[Screen],
    color:    C,
    rect:     B,
    filled:   bool   = true,
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a rectangle-draw command onto `target`.
  ren.commandBuffer.addCommand[DrawRect2DCmd, R](
    compress(target), priority, 0u32,
    DrawRect2DCmd(color: (color.x.uint8, color.y.uint8, color.z.uint8, color.w.uint8), 
      rect: (rect.x1, rect.x2, rect.y1, rect.y2), filled: filled),
    pass
  )

proc DrawRect2D*[R; C: Vec4i; B: Box2Df](
    ren:      var R,
    color:    C,
    rect:     B,
    filled:   bool   = true,
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a rectangle-draw command onto the renderer's default screen target.
  DrawRect2D(ren, ren.screenTarget, color, rect, filled, priority, pass)

# ---------------------------------------------------------------------------
# DrawCircle2D
# ---------------------------------------------------------------------------

proc DrawCircle2D*[R; C: Vec4i; V: Vec2f](
    ren:      var R,
    target:   CResource[Screen],
    color:    C,
    center:   V,
    radius:   float32,
    filled:   bool   = false,
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a circle-draw command onto `target`.
  ren.commandBuffer.addCommand[DrawCircle2DCmd, R](
    compress(target), priority, 0u32,
    DrawCircle2DCmd(
      color:  (color.x.uint8, color.y.uint8, color.z.uint8, color.w.uint8),
      center: (center.x, center.y),
      radius: radius,
      filled: filled
    ),
    pass
  )

proc DrawCircle2D*[R; C: Vec4i; V: Vec2f](
    ren:      var R,
    color:    C,
    center:   V,
    radius:   float32,
    filled:   bool   = false,
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a circle-draw command onto the renderer's default screen target.
  DrawCircle2D(ren, ren.screenTarget, color, center, radius, filled, priority, pass)

# ---------------------------------------------------------------------------
# DrawTexture2D
##
## The source texture is encoded as the `caller` field (compressed handle).
## The backend recovers it in `executeCommand` via `decompressIndex` /
## `decompressTypeId` on the batch's `caller` value.
# ---------------------------------------------------------------------------

proc DrawTexture2D*[R; B: Box2Df; V: Vec2f](
    ren:      var R,
    texture:  CResource[Texture],
    target:   CResource[Screen],
    rect:     B,
    center:   V,
    angle:    float32 = 0,
    flipH:    bool    = false,
    flipV:    bool    = false,
    priority: uint32  = 0,
    pass:     string   = "render"
) =
  ## Push a texture-blit command.
  ## `texture` travels as the compressed `caller`; `target` as the compressed
  ## `target` field — both fit in 32 bits after generation stripping.
  ren.commandBuffer.addCommand[DrawTexture2DCmd, R](
    compress(target),
    priority,
    compress(texture),   ## caller encodes the source texture
    DrawTexture2DCmd(
      rect:   Box2Df(rect),
      center: Vec2f(center),
      angle:  angle,
      flipH:  flipH,
      flipV:  flipV,
    ),
    pass
  )

proc DrawTexture2D*[R; B: Box2Df; V: Vec2f](
    ren:      var R,
    texture:  CResource[Texture],
    rect:     B,
    center:   V,
    angle:    float32 = 0,
    flipH:    bool    = false,
    flipV:    bool    = false,
    priority: uint32  = 0,
    pass:     string   = "render"
) =
  ## Push a texture-blit command onto the renderer's default screen target.
  DrawTexture2D(ren, texture, ren.screenTarget,
    rect, center, angle, flipH, flipV, priority, pass)