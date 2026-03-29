
include "core.nim"
# ===========================================================================
# EXAMPLE USAGE
# (remove or move to a separate file in your project)
# ===========================================================================

when isMainModule:

  # -------------------------------------------------------------------------
  # 1. Fake renderer + command types (stand-ins for your real backend)
  # -------------------------------------------------------------------------

  type
    MyRenderer* = ref object
      name*: string

    DrawMeshCmd* = object
      meshId*: uint32

    FullscreenCmd* = object
      shaderId*: uint32

  commandAction(DrawMeshCmd)
  commandAction(FullscreenCmd)

  proc executeCommand*(ren: var MyRenderer, batch: RenderBatch[DrawMeshCmd]) =
    echo "  [", ren.name, "] DrawMesh x", batch.commands.len

  proc executeCommand*(ren: var MyRenderer, batch: RenderBatch[FullscreenCmd]) =
    echo "  [", ren.name, "] Fullscreen shader=", batch.commands[0].shaderId

  proc passOrder*(ren: MyRenderer): seq[string] =
    @["render", "postprocess"]

  # -------------------------------------------------------------------------
  # 2. Backend callbacks
  # -------------------------------------------------------------------------

  proc myAllocate(res: var RenderResource) =
    echo "  [alloc]  ", res.name, " (", res.desc.width, "x", 
      res.desc.height, ")  size=", byteSize(res.desc) div 1024, " KB"
    res.backingPtr = cast[pointer](0xDEAD_BEEF)   # pretend GPU allocation

  proc myRelease(res: var RenderResource) =
    echo "  [free]   ", res.name
    res.backingPtr = nil

  proc myTransition(res: var RenderResource,
                    fromState, toState: RenderResourceState) =
    echo "  [barrier] ", res.name, " : ", fromState, " → ", toState
  
  proc myAlias(canonical: var RenderResource, alias: var RenderResource) =
    ## Backend reuses canonical's memory for alias.
    ## In a real Vulkan backend this would create an aliased VkImage.
    alias.backingPtr = canonical.backingPtr
    echo "  [alias]  ", alias.name, " reuses ", canonical.name,
         " (", byteSize(canonical.desc) div 1024, " KB available,",
         " ", byteSize(alias.desc) div 1024, " KB needed)"

  # -------------------------------------------------------------------------
  # 3. Build the render graph
  # -------------------------------------------------------------------------

  var rg = initRenderGraph(
    onAllocate   = myAllocate,
    onRelease    = myRelease,
    onTransition = myTransition,
    onAlias      = myAlias      # enable aliasing
  )

  # -- Register transient resources
  let gbufColorId = rg.addRenderResource RenderResource(
    name: "GBuffer_Color",
    desc: TextureDesc(width: 1920, height: 1080, format: fmtRGBA8, mips: 1),
    transient: true
  )
  let gbufDepthId = rg.addRenderResource RenderResource(
    name: "GBuffer_Depth",
    desc: TextureDesc(width: 1920, height: 1080, format: fmtDepth32, mips: 1),
    transient: true
  )
  let shadowMapId = rg.addRenderResource RenderResource(
    name: "ShadowMap",
    desc: TextureDesc(width: 2048, height: 2048, format: fmtDepth32, mips: 1),
    transient: true
  )
  let hdrId = rg.addRenderResource RenderResource(
    name: "HDR",
    desc: TextureDesc(width: 1920, height: 1080, format: fmtRGBA16F, mips: 1),
    transient: true
  )
  let bloomId = rg.addRenderResource RenderResource(
    name: "Bloom",
    desc: TextureDesc(width: 1920, height: 1080, format: fmtRGBA8, mips: 1),
    transient: true
  )
  let backbufferId = rg.addRenderResource RenderResource(
    name: "Backbuffer",
    desc: TextureDesc(width: 1920, height: 1080, format: fmtRGBA8, mips: 1),
    transient: false   # owned by the swap chain
  )
  rg.setBackbuffer(backbufferId)

  # -- Register passes

  # ShadowPass: writes ShadowMap  (no reads from other passes)
  var shadowPass = RenderPassNode(id:0, enabled: true, execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
    addCommand[DrawMeshCmd, MyRenderer](cb,
      target = pass.id.uint32, priority = 50, caller = 0,
      cmd = DrawMeshCmd(meshId: 99), pass = "render"
    )
  )
  let shadowId = rg.addRenderPass(shadowPass,
    reads  = @[],
    writes = @[shadowMapId]
  )

  # GBufferPass: writes Color + Depth
  var gbufPass = RenderPassNode(id:1, enabled: true, execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
    addCommand[DrawMeshCmd, MyRenderer](cb,
      target = pass.id.uint32, priority = 100, caller = 0,
      cmd = DrawMeshCmd(meshId: 1), pass = "render"
    )
  )
  let gbufId = rg.addRenderPass(gbufPass,
    reads  = @[],
    writes = @[gbufColorId, gbufDepthId]
  )

  # LightingPass: reads Color + Depth + Shadow, writes HDR
  # depends on both ShadowPass and GBufferPass
  var lightPass = RenderPassNode(id:2, enabled: true, execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
    addCommand[FullscreenCmd, MyRenderer](cb,
      target = pass.id.uint32, priority = 200, caller = 0,
      cmd = FullscreenCmd(shaderId: 42), pass = "render"
    )
  )
  let lightId = rg.addRenderPass(lightPass,
    reads  = @[gbufColorId, gbufDepthId, shadowMapId],
    writes = @[hdrId],
    deps   = @[shadowId, gbufId]
  )

  # BloomPass: reads HDR, writes Bloom  (level 2)
  # Bloom aliases ShadowMap's backing — same level as Tonemap but ShadowMap
  # is already free after LightingPass.
  var bloomPass = RenderPassNode(id:3, enabled: true, execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
    addCommand[FullscreenCmd, MyRenderer](cb,
      target = pass.id.uint32, priority = 250, caller = 0,
      cmd = FullscreenCmd(shaderId: 13), pass = "render"
    )
  )
  let bloomId2 = rg.addRenderPass(bloomPass,
    reads  = @[hdrId],
    writes = @[bloomId],
    deps   = @[lightId]
  )

  # TonemapPass: reads HDR, writes Backbuffer
  var tonemapPass = RenderPassNode(id:4, enabled: true, execute: proc(pass: RenderPassNode, cb: var CommandBuffer) =
    addCommand[FullscreenCmd, MyRenderer](cb,
      target = pass.id.uint32, priority = 300, caller = 0,
      cmd = FullscreenCmd(shaderId: 7), pass = "postprocess"
    )
  )
  discard rg.addRenderPass(tonemapPass,
    reads  = @[hdrId, bloomId],
    writes = @[backbufferId],
    deps   = @[lightId, bloomId2]
  )

  # -------------------------------------------------------------------------
  # 4. Run two frames
  # -------------------------------------------------------------------------

  var renderer = MyRenderer(name: "MyBackend")

  for frame in 1..2:
    echo "\n=== Frame ", frame, " ==="
    rg.executeFrame(renderer)

  rg.teardown()