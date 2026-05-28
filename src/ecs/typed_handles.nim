####################################################################################################################################################
################################################################# TYPED HANDLES ####################################################################
####################################################################################################################################################

type
  # Self Explanatory
  TDHandle*[S: static ArchetypeMask] = distinct DenseHandle
  TSHandle*[S: static ArchetypeMask] = distinct SparseHandle

template staticMask*[S: static ArchetypeMask](h: TDHandle[S] | TSHandle[S]): ArchetypeMask = 
  ## Return the `ArchetypeMask` encoded in a `TDHandle` or `TSHandle` type
  ## parameter at compile time.  The mask is the `static ArchetypeMask` `S`.
  S

template staticArchId*[S: static ArchetypeMask](
    _: typedesc[TDHandle[S]] | typedesc[TSHandle[S]]): uint16 =
  ## Resolve the runtime archetype node ID for a typed handle's mask.
  ## Because `S` is statically known, `toArchetypeIDC` (compile-time proc) gives
  ## us the integer without any hash-table lookup at runtime.
  const (_, id) = toArchetypeIDC(S.getComponents())
  id.uint16

macro maskOf*(ids: static openArray[int]): ArchetypeMask =
  ## Compute the `ArchetypeMask` for a list of component IDs known at compile time.
  ## Required components (declared via `requireComponent`) are folded in
  ## automatically by consulting `REQUIRED_COMPS`.
  var m: ArchetypeMask
  for id in ids:
    m.withComponentInPlace(id)
    for req in getRequiredComps(id):
      m.withComponentInPlace(req)
  return quote do : `m`

macro maskOf*(comps: varargs[untyped]): ArchetypeMask =
  var m: ArchetypeMask
  for c in comps:
    let id = getComponentIdFromRegistry(c)
    m.withComponentInPlace(id)
    for req in getRequiredComps(id):
      m.withComponentInPlace(req)

  return quote do : `m`

macro toTyped*(d: DenseHandle, comps: varargs[typed]): untyped =
  ## Convert a dense handle to a typed dense handle (but you have to specify all the components the entity have, else it will crash)
  var newMask: ArchetypeMask
  for c in comps:
    let id = getComponentIdFromRegistry(c)
    newMask = newMask.withComponent(id)
    for rc in getRequiredComps(id):
      newMask.withoutComponentInPlace(rc)

  return quote do: cast[TDHandle[`newMask`]](`d`)

macro toTyped*(s: SparseHandle, comps: varargs[typed]): untyped =
  ## Convert a sparse handle to a typed sparse handle (but you have to specify all the components the entity have, else it will crash)
  var newMask: ArchetypeMask
  for c in comps:
    let id = getComponentIdFromRegistry(c)
    newMask = newMask.withComponent(id)
    for rc in getRequiredComps(id):
      newMask.withoutComponentInPlace(rc)

  return quote do: cast[TSHandle[`newMask`]](`s`)

template obj*(d: TDHandle): ptr Entity = addr DenseHandle(d).world.entities[DenseHandle(d).widx]

template world*(d:TDHandle): uint32 = DenseHandle(d).world
template gen(d:TDHandle): uint16 = DenseHandle(d).gen
template widx(d:TDHandle): uint32 = DenseHandle(d).widx
template wid*(d:TDHandle): uint32 = DenseHandle(d).wid
template id*(d:TDHandle): uint32 = DenseHandle(d).id

template gen*(s: TSHandle): uint16 = (s.meta and MASK16).uint16
template `gen=`*(s: TSHandle, v: untyped) = 
  SparseHandle(s).meta = (SparseHandle(s).meta and not MASK16) or v

template archID*(s: TSHandle): uint16 = (SparseHandle(s).meta shr SHIFT16).uint16
template `archID=`(s: TSHandle, v: untyped) = 
  SparseHandle(s).meta = (SparseHandle(s).meta and MASK16) or (v.uint32 shl SHIFT16)

template id*(d:TSHandle): uint32 = SparseHandle(d).id
template meta*(d:TSHandle): uint32 = SparseHandle(d).meta

template `[]`*[N,P,T,S,B](f: FragmentArray[N,P,T,S,B], d: TDHandle):untyped = 
  ## Retrieves component data from a `FragmentArray` using a raw `Entity`.
  f[d.DenseHandle]

template `[]=`*[N,P,T,S,B](f:var FragmentArray[N,P,T,S,B], d: TDHandle, v:B) = 
  ## Sets component data in a `FragmentArray` for a raw `Entity`.
  f[d.DenseHandle] = v

template `[]`*[N,P,T,S,B](f: FragmentArray[N,P,T,S,B], d: TSHandle):untyped = 
  ## Retrieves component data from a `FragmentArray` using a raw `Entity`.
  f[d.SparseHandle]

template `[]=`*[N,P,T,S,B](f:var FragmentArray[N,P,T,S,B], d: TSHandle, v:B) = 
  ## Sets component data in a `FragmentArray` for a raw `Entity`.
  f[d.SparseHandle] = v
