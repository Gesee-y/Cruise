####################################################################################################################################################
################################################################## ECS ENTITY ######################################################################
####################################################################################################################################################

const
  SHIFT16 = 16
  MASK16 = (1 shl SHIFT16) - 1

## Internal representation of an Entity within the Dense storage.
##
## This struct is the low-level metadata stored in the world's entity list.
## It contains the raw IDs required to locate the entity's component data in memory.
type
  Entity* = object
    id:uint32             ## The packed entity ID. This usually combines the Block ID and the local index
    archetypeId* {.align: 4.}:uint16  ## Identifies which Archetype (table of components) this entity currently belongs to.

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

## Sets component data in a `SoAFragmentArray` for a raw `Entity`.
proc `[]=`[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], e:SomeEntity, v:B) = 
  f[e.id] = v

####################################################################################################################################################
################################################################# OPERATORS #######################################################################
####################################################################################################################################################

## Equality operator for raw Entity types.
##
## Checks if the packed IDs are identical.
template `==`(e1,e2:SomeEntity):bool = (e1.id == e2.id)

## String representation operator for `Entity`.
##
## Useful for debugging and logging. Displays the Entity ID and its current Archetype ID.
proc `$`*(e:SomeEntity):string = "e" & $e.id & " arch " & $e.archetypeId
