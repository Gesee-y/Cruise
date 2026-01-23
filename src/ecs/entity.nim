####################################################################################################################################################
################################################################## ECS ENTITY ######################################################################
####################################################################################################################################################

## Internal representation of an Entity within the Dense storage.
##
## This struct is the low-level metadata stored in the world's entity list.
## It contains the raw IDs required to locate the entity's component data in memory.
type
  Entity* = object
    id:uint             ## The packed entity ID. This usually combines the Block ID and the local index
                        ## within that block to form a unique memory address for the entity's row.
    archetypeId:uint16  ## Identifies which Archetype (table of components) this entity currently belongs to.
    widx:int            ## The "World Index". A stable ID referencing this entity's slot in the main entities list,
                        ## used for handle lookup and recycling.

## A safe, public handle to a Dense Entity.
##
## Dense entities are stored contiguously in memory blocks (SoA - Structure of Arrays)
## for optimal cache performance during iteration.
## This handle acts as a safe reference, allowing the system to detect if the entity
## has been deleted (stale handle).
type
  DenseHandle* = object
    obj : ptr Entity  ## Pointer to the underlying `Entity` metadata structure.
    gen : uint32      ## The generation counter. Used to verify that the entity is still alive.
                      ## If `gen` does not match the world's stored generation for this entity,
                      ## the handle is considered stale.

## A safe, public handle to a Sparse Entity.
##
## Sparse entities are stored using a hash map or set-like structure.
## This allows for flexible addition/removal of components at the cost of iteration speed.
type
  SparseHandle* = object
    id   : uint       ## The unique identifier of the entity in sparse storage.
    gen  : uint32     ## The generation counter for validity checks.
    mask : ArchetypeMask ## A bitmask representing the set of components currently owned by this entity.

  ## A type class (concept-like alias) encompassing various raw Entity forms.
  ##
  ## This allows generic procedures to accept either a pointer to an Entity,
  ## a value Entity, or a mutable reference to an Entity.
  SomeEntity = ptr Entity | Entity | var Entity

####################################################################################################################################################
################################################################### ACCESSORS #####################################################################
####################################################################################################################################################

## Retrieves component data from a `SoAFragmentArray` using a raw `Entity`.
template `[]`[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], e:SomeEntity):untyped = f[e.id]

## Retrieves component data from a `SoAFragmentArray` using a `DenseHandle`.
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], d:DenseHandle):untyped = f[d.obj.id]

## Retrieves component data from a `SoAFragmentArray` using a `SparseHandle`.
##
## Sparse storage typically maps an Entity ID to a component value.
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], d:SparseHandle):untyped = 
  let S = sizeof(uint)*8 # Size of the bucket range (e.g., 64 bits).
  
  # Calculate the bucket index: `id shr 6` divides the ID by 64 to find the page.
  # Calculate the offset: `id and (S-1)` gets the index within that page (modulo 64).
  f.sparse[d.id shr 6][d.id and (S-1).uint]

## Sets component data in a `SoAFragmentArray` for a raw `Entity`.
proc `[]=`[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], e:SomeEntity, v:B) = 
  f[e.id] = v

## Sets component data in a `SoAFragmentArray` for a `DenseHandle`.
proc `[]=`*[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], d:DenseHandle, v:B) = 
  f[d.obj.id] = v

## Sets component data in a `SoAFragmentArray` for a `SparseHandle`.
proc `[]=`*[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], d:SparseHandle, v:B) = 
  let S = sizeof(uint)*8
  when P: setChangedSparse(f, d.id)
  f.sparse[d.id shr 6][d.id and (S-1).uint] = v

proc get*(qf: QueryFilter, d: DenseHandle): bool =
  ## Dense handle membership check
  qf.dGet(d.obj.id) != 0

proc get*(qf: QueryFilter, s: SparseHandle): bool =
  ## Sparse handle membership check
  qf.sGet(s.id)

proc set*(qf: var QueryFilter, d: DenseHandle) =
  ## Insert dense handle into query filter
  qf.dSet(d.obj.id)

proc set*(qf: var QueryFilter, s: SparseHandle) =
  ## Insert sparse handle into query filter
  qf.sSet(s.id)

proc unset*(qf: var QueryFilter, d: DenseHandle) =
  ## Remove dense handle from query filter
  qf.dUnset(d.obj.id)

proc unset*(qf: var QueryFilter, s: SparseHandle) =
  ## Remove sparse handle from query filter
  qf.sUnset(s.id)

####################################################################################################################################################
################################################################# OPERATORS #######################################################################
####################################################################################################################################################

## Equality operator for raw Entity types.
##
## Checks if the packed IDs are identical.
template `==`(e1,e2:SomeEntity):bool = (e1.id == e2.id)

## Equality operator for `DenseHandle`.
##
## Two handles are equal only if they point to the exact same underlying Entity
## **AND** the generation counters match (ensuring neither handle is stale).
template `==`*(d1,d2:DenseHandle):bool = (d1.obj == d2.obj) and (d1.gen == d2.gen)

## Equality operator for `SparseHandle`.
##
## Checks if the sparse IDs and generation counters match.
template `==`*(d1,d2:SparseHandle):bool = (d1.id == d2.id) and (d1.gen == d2.gen)

## String representation operator for `Entity`.
##
## Useful for debugging and logging. Displays the Entity ID and its current Archetype ID.
proc `$`*(e:SomeEntity):string = "e" & $e.id & " arch " & $e.archetypeId