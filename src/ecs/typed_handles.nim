####################################################################################################################################################
################################################################# TYPED HANDLES ####################################################################
####################################################################################################################################################

type
  TDHandle[S: static ArchetypeMask] = DenseHandle
  TSHandle[S: static ArchetypeMask] = SparseHandle

## Return the `ArchetypeMask` encoded in a `TDHandle` or `TSHandle` type
## parameter at compile time.  The mask is the `static ArchetypeMask` `S`.
template staticMask*[S: static ArchetypeMask](h: TDHandle[S] | TSHandle[S]): ArchetypeMask = S

## Resolve the runtime archetype node ID for a typed handle's mask.
## Because `S` is statically known, `toArchetypeIDC` (compile-time proc) gives
## us the integer without any hash-table lookup at runtime.
template staticArchId*[S: static ArchetypeMask](
    _: typedesc[TDHandle[S]] | typedesc[TSHandle[S]]): uint16 =
  const (_, id) = toArchetypeIDC(S.getComponents())
  id.uint16

## Compute the `ArchetypeMask` for a list of component IDs known at compile time.
## Required components (declared via `requireComponent`) are folded in
## automatically by consulting `REQUIRED_COMPS`.
macro maskOf(ids: static openArray[int]): ArchetypeMask =
  var m: ArchetypeMask
  for id in ids:
    m.withComponentInPlace(id)
    for req in getRequiredComps(id):
      m.withComponentInPlace(req)
  return quote do : `m`

