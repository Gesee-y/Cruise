
import ../la/La

## Crenderer.nim
##
## Generic renderer wrapper — backend-agnostic.
##
## `CRenderer[R]` owns the command buffer and resource registry.
## `R` is the concrete backend data type supplied by the backend developer.
##
## The backend developer is responsible for:
##   - Defining their concrete data type (e.g. `SDLData`, `GLData`).
##   - Registering their resource types via `registry.registerType[T]()`.
##   - Implementing `executeCommand` overloads for their command types.
##   - Exposing `commandBuffer` and `screenTarget` so the push helpers work.
##
## The end user only ever touches `CRenderer[R]` through the push helpers
## defined in `render_commands.nim` — they never see `R` directly.

include "commandBuf.nim"
include "resource.nim"

# ---------------------------------------------------------------------------
# CRenderer[R]
# ---------------------------------------------------------------------------

type
  CRenderer*[R] = object
    ## Generic renderer handle.
    ## `R` is the backend-specific data type (e.g. SDLData, GLData).
    data*:          R                ## Backend-owned state (GPU context, etc.)
    commandBuffer: CommandBuffer    ## Frame command queue.
    registry:      ResourceRegistry ## All registered resource stores.

# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

proc initCRenderer*[R](data: R): CRenderer[R] =
  ## Create a renderer wrapping `data`.
  ## The backend should call `registry.registerType` immediately after.
  CRenderer[R](
    data:          data,
    commandBuffer: initCommandBuffer(),
    registry:      initResourceRegistry(),
  )

# ---------------------------------------------------------------------------
# Core accessors
##
## These are the procs that `render_commands.nim` expects on any renderer `R`.
## Backend types that embed `CRenderer` should forward these, or user code
## can pass `CRenderer[R]` directly.
# ---------------------------------------------------------------------------

proc `.commandBuffer`*[R](ren: var CRenderer[R]): var CommandBuffer {.inline.} =
  ## Return the mutable command buffer — used by all push helpers.
  ren.commandBuffer

proc `.registry`*[R](ren: var CRenderer[R]): var ResourceRegistry {.inline.} =
  ## Return the mutable resource registry.
  ren.registry

# ---------------------------------------------------------------------------
# Resource helpers
# ---------------------------------------------------------------------------

proc registerType*[R, T](ren: var CRenderer[R]): TypeId =
  ## Register resource type `T` with this renderer's registry.
  ## Returns the stable `TypeId` to be stored by the backend.
  ren.registry.registerType[T]()

proc createResource*[R, T](ren: var CRenderer[R],
                            typeId: TypeId,
                            value:  T): CResource[T] =
  ## Allocate a new resource of type `T` in the registry.
  ren.registry.create(typeId, value)

proc getResource*[R, T](ren: var CRenderer[R],
                         h: CResource[T]): ptr T =
  ## Retrieve a pointer to the resource data.
  ## Asserts that the handle is valid.
  ren.registry.get(h)

proc getResource*[R, T](ren: var CRenderer[R],
                         h: ResourceHandle): ptr T =
  ## Opaque-handle overload — used inside `executeCommand` implementations.
  ren.registry.get[T](h)

proc destroyResource*[R, T](ren: var CRenderer[R], h: CResource[T]) =
  ## Release the resource slot and invalidate the handle.
  ren.registry.destroy(h)

proc isValidResource*[R, T](ren: CRenderer[R], h: CResource[T]): bool =
  ## Return true if `h` refers to a live resource.
  ren.registry.isValid(h)

proc isValidResource*[R](ren: CRenderer[R], h: ResourceHandle): bool =
  ## Opaque-handle overload.
  ren.registry.isValid(h)

# ---------------------------------------------------------------------------
# Frame lifecycle
# ---------------------------------------------------------------------------

proc beginFrame*[R](ren: var CRenderer[R]) =
  ## Reset command lists for the next frame.
  ## Call at the start of each frame before pushing new commands.
  for passName in ren.commandBuffer.passes.keys:
    ren.commandBuffer.clearPass(passName)

proc endFrame*[R](ren: var CRenderer[R]) =
  ## Execute all queued commands then clear the buffer.
  ## The backend must have `executeCommand` overloads defined for all command
  ## types it expects to receive.
  ren.data.executeAll(ren.commandBuffer)

proc teardown*[R](ren: var CRenderer[R]) =
  ## Release all resources and destroy all command batches.
  ## Call when the window / backend shuts down.
  ren.commandBuffer.destroyAllPasses()
  ren.registry.teardown()

include "commands.nim"
include "mesh.nim"
