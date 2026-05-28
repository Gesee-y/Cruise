

type
  DenseHandle* = object
    ## A safe, public handle to a Dense Entity.
    ##
    ## This handle acts as a safe reference, allowing the system to detect if the entity
    ## has been deleted (stale handle).
    world*: ECSWorld
    widx : uint32
    gen {.align: 4.} : uint16

type
  SparseHandle* = object
    ## A safe, public handle to a Sparse Entity.
    ##
    ## Sparse entities are stored using blocks of 64 (32 depending on the system) elements that don't care about order.
    ## This allows for flexible addition/removal of components at the cost of a bit of iteration speed.
    id*   : uint32
    gen  : uint16

# ################################################################################################################################################## #
# ################################################################### ACCESSORS #################################################################### #
# ################################################################################################################################################## #

template obj*(d: DenseHandle): ptr Entity = addr d.world.entities[d.widx]

template `[]`*[N,P,T,S,B](f: FragmentArray[N,P,T,S,B], d: DenseHandle):untyped = 
  ## Retrieves component data from a `FragmentArray` using a raw `Entity`.
  f[d.world.entities[d.widx]]

template `[]=`*[N,P,T,S,B](f:var FragmentArray[N,P,T,S,B], d: DenseHandle, v:B) = 
  ## Sets component data in a `FragmentArray` for a raw `Entity`.
  f[d.id] = v

template `[]`*[N,P,T,S,B](f: FragmentArray[N,P,T,S,B], d:SparseHandle):untyped = 
  ## Retrieves component data from a `FragmentArray` using a `SparseHandle`.
  ## Sparse storage maps an Entity ID to a component value.
  let S = sizeof(uint)*8 # Size of the bucket range (e.g., 64 bits).
  
  # Calculate the bucket index via toSparse indirection.
  # Calculate the offset: `id and (S-1)` gets the index within that page (modulo 64).
  f.sparse[f.toSparse[d.id shr BIT_DIVIDER.uint]-1][d.id and BIT_REMAINDER.uint]

proc `[]=`*[N,P,T,S,B](f: var FragmentArray[N,P,T,S,B], d:SparseHandle, v:B) = 
  ## Sets component data in a `FragmentArray` for a `SparseHandle`.
  let S = sizeof(uint)*8
  when P: setChangedSparse(f, d.id)
  f.sparse[f.toSparse[d.id shr BIT_DIVIDER.uint]-1][d.id and BIT_REMAINDER.uint] = v

template `==`*(d1,d2:DenseHandle):bool = 
  ## Equality operator for `DenseHandle`.
  ##
  ## Two handles are equal only if they point to the exact same underlying Entity
  ## **AND** the generation counters match (ensuring neither handle is stale).
  (d1.widx == d2.widx) and (d1.gen == d2.gen)

template `==`*(d1,d2:SparseHandle):bool = 
  ## Equality operator for `SparseHandle`.
  ##
  ## Checks if the sparse IDs and generation counters match.
  (d1.id == d2.id) and (d1.gen == d2.gen)

proc wid*(d:DenseHandle): uint32 = d.widx
template id*(d:DenseHandle): uint32 = d.world.entities[d.widx].id