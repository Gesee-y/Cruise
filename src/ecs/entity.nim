####################################################################################################################################################
################################################################## ECS ENTITY ######################################################################
####################################################################################################################################################
##
## Entity types and accessors for the Cruise ECS.
##
## Defines the internal ``Entity`` metadata record, the public ``DenseHandle``
## and ``SparseHandle`` reference types, and the index/access operators needed
## to read and write component data from SoA-backed fragment arrays.
##
## Usage example
## =============
##
## .. code-block:: nim
##   import cruise/ecs/entity
##
##   # DenseHandle is obtained from world.createEntity(...)
##   let d: DenseHandle = world.createEntity(Position, Velocity)
##   assert world.isAlive(d)
##
##   # Direct SoA access
##   positions[d]  # read component
##   positions[d] = Position(x: 10.0, y: 20.0)  # write component
##
##   # SparseHandle works similarly
##   let s: SparseHandle = world.createSparse(Health)
##   health[s] = Health(hp: 100)

import ./types
export types

# ──── NOTE ─────────────────────────────────────────────────────────────── #
# The type definitions for Entity, DenseHandle, SparseHandle, SomeEntity   #
# live in types.nim.  This file only contains the accessor / operator procs #
# that operate on those types together with SoAFragmentArray.              #
# ─────────────────────────────────────────────────────────────────────── #

####################################################################################################################################################
################################################################### ACCESSORS #####################################################################
####################################################################################################################################################

## Retrieves component data from a ``SoAFragmentArray`` using a raw ``Entity``.
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], e: SomeEntity): untyped = f[e.id]

## Retrieves component data from a ``SoAFragmentArray`` using a ``DenseHandle``.
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], d: DenseHandle): untyped = f[d.obj.id]

## Retrieves component data from a ``SoAFragmentArray`` using a ``SparseHandle``.
##
## Sparse storage maps entity IDs to component values via an indirection
## table (``toSparse``).
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], d: SparseHandle): untyped =
  let S_bits = sizeof(uint)*8
  f.sparse[f.toSparse[d.id shr 6]-1][d.id and (S_bits-1).uint]

## Sets component data in a ``SoAFragmentArray`` for a raw ``Entity``.
proc `[]=`*[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], e: SomeEntity, v: B) =
  f[e.id] = v

## Sets component data in a ``SoAFragmentArray`` for a ``DenseHandle``.
proc `[]=`*[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], d: DenseHandle, v: B) =
  f[d.obj.id] = v

## Sets component data in a ``SoAFragmentArray`` for a ``SparseHandle``.
proc `[]=`*[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], d: SparseHandle, v: B) =
  let S_bits = sizeof(uint)*8
  when P: setChangedSparse(f, d.id)
  f.sparse[f.toSparse[d.id shr 6]-1][d.id and (S_bits-1).uint] = v

####################################################################################################################################################
################################################################# OPERATORS #######################################################################
####################################################################################################################################################

## Equality operator for raw ``Entity`` types.
## Compares packed IDs only.
template `==`*(e1, e2: SomeEntity): bool = (e1.id == e2.id)

## Equality operator for ``DenseHandle``.
## Two handles are equal only if they point to the same ``Entity`` **and**
## their generation counters match (ensuring neither is stale).
template `==`*(d1, d2: DenseHandle): bool = (d1.obj == d2.obj) and (d1.gen == d2.gen)

## Equality operator for ``SparseHandle``.
template `==`*(d1, d2: SparseHandle): bool = (d1.id == d2.id) and (d1.gen == d2.gen)

## String representation for ``Entity``.
proc `$`*(e: SomeEntity): string = "e" & $e.id & " arch " & $e.archetypeId