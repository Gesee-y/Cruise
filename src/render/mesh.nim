## mesh.nim
##
## Generic mesh abstraction — backend-agnostic.
##
## Design rules:
##   - Vertex types are defined by concepts only. The moteur knows nothing
##     about the concrete layout — only the capabilities (position, normal…).
##   - `CMesh[V, I, M]` is the universal mesh container. `M` holds any
##     backend-specific GPU data (VBOs, VAOs, descriptor sets…).
##   - Mesh creation and `DrawMesh` are the backend's responsibility.
##     The moteur only defines the concepts and the resource wrapper.
##   - Tuples are used for geometric data instead of named vector types
##     so the moteur stays independent of any math library.

# ---------------------------------------------------------------------------
# Index concept
# ---------------------------------------------------------------------------

type CIndex* = concept type I
  ## Any unsigned integer type suitable as a mesh index.
  ## Typically `uint16` (up to 65 535 vertices) or `uint32`.
  var i: I
  uint32(i) is uint32   ## Must be convertible to uint32 for generic code.

# ---------------------------------------------------------------------------
# CVertex2D concept
##
## A 2D vertex must expose at minimum a position in the XY plane.
## Additional attributes (UV, color, normal…) are optional — backend types
## may satisfy additional concepts defined below.
# ---------------------------------------------------------------------------

type CVertex2D* = concept v, var mv, type V
  ## Minimum requirement: readable and writable 2D position.
  position2D(v)     is tuple[x, y: float32]
  setPosition2D(mv, tuple[x, y: float32])

# ---------------------------------------------------------------------------
# CVertex3D concept
##
## A 3D vertex must expose a position in XYZ space.
# ---------------------------------------------------------------------------

type CVertex3D* = concept v, var mv, type V
  ## Minimum requirement: readable and writable 3D position.
  position3D(v)     is tuple[x, y, z: float32]
  setPosition3D(mv, tuple[x, y, z: float32])

# ---------------------------------------------------------------------------
# Optional vertex attribute concepts
##
## Backend vertex types opt into additional attributes by satisfying these
## concepts. Generic procs can then be constrained on them.
# ---------------------------------------------------------------------------

type CVertexUV* = concept v, var mv
  ## Vertex carries a texture coordinate.
  uv(v)     is tuple[u, v: float32]
  setUv(mv, tuple[u, v: float32])

type CVertexColor* = concept v, var mv
  ## Vertex carries a per-vertex RGBA colour.
  color(v)     is tuple[r, g, b, a: float32]
  setColor(mv, tuple[r, g, b, a: float32])

type CVertexNormal* = concept v, var mv
  ## Vertex carries a surface normal (3D only in practice).
  normal(v)     is tuple[x, y, z: float32]
  setNormal(mv, tuple[x, y, z: float32])

type CVertexTangent* = concept v, var mv
  ## Vertex carries a tangent vector (for normal mapping).
  tangent(v)     is tuple[x, y, z: float32]
  setTangent(mv, tuple[x, y, z: float32])

# ---------------------------------------------------------------------------
# CMeshData concept
##
## Backend-specific GPU data attached to a mesh (VBOs, VAOs, buffer handles,
## descriptor sets…).  The moteur only requires that it exists as a type.
## Use `EmptyMeshData` when no GPU data is needed (e.g. CPU-only meshes).
# ---------------------------------------------------------------------------

type CMeshData* = concept type M
  ## Any type can serve as mesh data — no required procs.
  ## This concept exists purely as a constraint marker.
  discard

type EmptyMeshData* = object
  ## Placeholder for backends that keep all GPU state outside the mesh.

# ---------------------------------------------------------------------------
# Bounding volumes
##
## Derived from the vertex concept so the moteur can compute them generically
## without knowing the concrete vertex layout.
# ---------------------------------------------------------------------------

type
  Bounds2D* = object
    ## Axis-aligned bounding box in 2D space.
    min*: tuple[x, y: float32]
    max*: tuple[x, y: float32]

  Bounds3D* = object
    ## Axis-aligned bounding box in 3D space.
    min*: tuple[x, y, z: float32]
    max*: tuple[x, y, z: float32]

template computeBounds2D*[V: CVertex2D](vertices: openArray[V]): Bounds2D =
  ## Compute the AABB of a 2D vertex array.
  if vertices.len == 0:
     Bounds2D()
  else:
    let first = position2D(vertices[0])
    var result = Bounds2D(min: first, max: first)
    for v in vertices:
      let p = position2D(v)
      if p.x < result.min.x: result.min.x = p.x
      if p.y < result.min.y: result.min.y = p.y
      if p.x > result.max.x: result.max.x = p.x
      if p.y > result.max.y: result.max.y = p.y

    result

template computeBounds3D*[V: CVertex3D](vertices: openArray[V]): Bounds3D =
  ## Compute the AABB of a 3D vertex array.
  if vertices.len == 0:
     Bounds3D()
  else:
    let first = position3D(vertices[0])
    var result = Bounds3D(min: first, max: first)
    for v in vertices:
      let p = position3D(v)
      if p.x < result.min.x: result.min.x = p.x
      if p.y < result.min.y: result.min.y = p.y
      if p.z < result.min.z: result.min.z = p.z
      if p.x > result.max.x: result.max.x = p.x
      if p.y > result.max.y: result.max.y = p.y
      if p.z > result.max.z: result.max.z = p.z

    result

# ---------------------------------------------------------------------------
# CMesh2D[V, I, M]
##
## Generic 2D mesh resource. `V` must satisfy `CVertex2D`, `I` must satisfy
## `CIndex`, `M` must satisfy `CMeshData`.
##
## `meshData` is the backend's GPU representation — it is written by the
## backend's `createMesh` overload and read inside `executeCommand`.
# ---------------------------------------------------------------------------

type CMesh2D*[V: CVertex2D; I: CIndex; M: CMeshData] = object
  ## Generic 2D mesh.
  vertices*:  seq[V]       ## CPU-side vertex buffer.
  indices*:   seq[I]       ## CPU-side index buffer.
  bounds*:    Bounds2D     ## Precomputed AABB (updated on upload).
  meshData*:  M            ## Backend-specific GPU data (VBO, VAO…).

# ---------------------------------------------------------------------------
# CMesh3D[V, I, M]
##
## Generic 3D mesh resource. `V` must satisfy `CVertex3D`.
# ---------------------------------------------------------------------------

type CMesh3D*[V: CVertex3D; I: CIndex; M: CMeshData] = object
  ## Generic 3D mesh.
  vertices*:  seq[V]
  indices*:   seq[I]
  bounds*:    Bounds3D
  meshData*:  M

# ---------------------------------------------------------------------------
# Generic mesh construction helpers
##
## These are moteur-level utilities. The backend's `createMesh` calls them
## to initialise the CPU side, then fills in `meshData` itself.
# ---------------------------------------------------------------------------

proc initMesh2D*[V: CVertex2D; I: CIndex; M: CMeshData](
    vertices: sink seq[V],
    indices:  sink seq[I],
    meshData: sink M
): CMesh2D[V, I, M] =
  ## Build a `CMesh2D` from pre-built vertex/index data and backend GPU data.
  ## Computes the bounding box automatically.
  result = CMesh2D[V, I, M](
    vertices: vertices,
    indices:  indices,
    meshData: meshData,
  )
  result.bounds = computeBounds2D(result.vertices)

proc initMesh3D*[V: CVertex3D; I: CIndex; M: CMeshData](
    vertices: sink seq[V],
    indices:  sink seq[I],
    meshData: sink M
): CMesh3D[V, I, M] =
  ## Build a `CMesh3D` from pre-built vertex/index data and backend GPU data.
  result = CMesh3D[V, I, M](
    vertices: vertices,
    indices:  indices,
    meshData: meshData,
  )
  result.bounds = computeBounds3D(result.vertices)

# ---------------------------------------------------------------------------
# DrawMesh — backend-overloaded push helper
##
## The moteur defines only the stub. Each backend overloads `DrawMesh` for
## its concrete `(HRenderer[R], CMesh2D[V,I,M])` or `(…, CMesh3D[V,I,M])`.
##
## The backend is free to define its own `DrawMeshCmd` command type and push
## it into the command buffer however it sees fit.  The only contract is that
## `DrawMesh` must end up pushing at least one command into `ren.commandBuffer`.
# ---------------------------------------------------------------------------

proc DrawMesh*[R; V: CVertex2D; I: CIndex; M: CMeshData](
    ren:      var R,
    mesh:     CResource[CMesh2D[V, I, M]],
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a 2D mesh draw command.
  ## **Must be overloaded by the backend** — the default raises at compile time.
  {.error: "DrawMesh (2D) not implemented for this renderer. " &
           "Override DrawMesh for your concrete (R, V, I, M) combination.".}

proc DrawMesh*[R; V: CVertex3D; I: CIndex; M: CMeshData](
    ren:      var R,
    mesh:     CResource[CMesh3D[V, I, M]],
    priority: uint32 = 0,
    pass:     string  = "render"
) =
  ## Push a 3D mesh draw command.
  ## **Must be overloaded by the backend.**
  {.error: "DrawMesh (3D) not implemented for this renderer. " &
           "Override DrawMesh for your concrete (R, V, I, M) combination.".}