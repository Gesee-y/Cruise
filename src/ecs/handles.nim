

## A safe, public handle to a Dense Entity.
##
## This handle acts as a safe reference, allowing the system to detect if the entity
## has been deleted (stale handle).
type
  DenseHandle* = object
    world*: ECSWorld   ## ECS World being a ref object we just store a pointer to it
    widx : uint32     ## Pointer to the underlying `Entity` metadata structure.
    gen {.align: 4.} : uint16      ## The generation counter. Used to verify that the entity is still alive.

## A safe, public handle to a Sparse Entity.
##
## Sparse entities are stored using blocks of 64 (32 depending on the system) elements that don't care about order.
## This allows for flexible addition/removal of components at the cost of a bit of iteration speed.
type
  SparseHandle* = object
    id*   : uint32       ## The unique identifier of the entity in sparse storage.
    meta  : uint32     ## The generation counter for validity checks on 16 bits and archetype ID on another 16 bits.

####################################################################################################################################################
#################################################################### ACCESSORS #####################################################################
####################################################################################################################################################

template obj*(d: DenseHandle): ptr Entity = addr d.world.entities[d.widx]

template gen*(s: SparseHandle): uint16 = (s.meta and MASK16).uint16
template `gen=`(s: SparseHandle, v: untyped) = 
  s.meta = (s.meta and not MASK16) or v

template archID*(s: SparseHandle): uint16 = (s.meta shr SHIFT16).uint16
template `archID=`(s: SparseHandle, v: untyped) = 
  s.meta = (s.meta and MASK16) or (v.uint32 shl SHIFT16)

## Retrieves component data from a `SoAFragmentArray` using a raw `Entity`.
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], d: DenseHandle):untyped = f[d.world.entities[d.widx]]

## Sets component data in a `SoAFragmentArray` for a raw `Entity`.
template `[]=`*[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], d: DenseHandle, v:B) = 
  f[d.id] = v

## Retrieves component data from a `SoAFragmentArray` using a `SparseHandle`.
##
## Sparse storage typically maps an Entity ID to a component value.
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], d:SparseHandle):untyped = 
  let S = sizeof(uint)*8 # Size of the bucket range (e.g., 64 bits).
  
  # Calculate the bucket index via toSparse indirection.
  # Calculate the offset: `id and (S-1)` gets the index within that page (modulo 64).
  f.sparse[f.toSparse[d.id shr BIT_DIVIDER.uint]-1][d.id and BIT_REMAINDER.uint]

## Sets component data in a `SoAFragmentArray` for a `SparseHandle`.
proc `[]=`*[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], d:SparseHandle, v:B) = 
  let S = sizeof(uint)*8
  when P: setChangedSparse(f, d.id)
  f.sparse[f.toSparse[d.id shr BIT_DIVIDER.uint]-1][d.id and BIT_REMAINDER.uint] = v

## Equality operator for `DenseHandle`.
##
## Two handles are equal only if they point to the exact same underlying Entity
## **AND** the generation counters match (ensuring neither handle is stale).
template `==`*(d1,d2:DenseHandle):bool = (d1.widx == d2.widx) and (d1.gen == d2.gen)

## Equality operator for `SparseHandle`.
##
## Checks if the sparse IDs and generation counters match.
template `==`*(d1,d2:SparseHandle):bool = (d1.id == d2.id) and (d1.gen == d2.gen)

proc wid*(d:DenseHandle): uint32 = d.widx
template id*(d:DenseHandle): uint32 = d.world.entities[d.widx].id