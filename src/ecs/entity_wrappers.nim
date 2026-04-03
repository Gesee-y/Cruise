####################################################################################################################################################
############################################################### ENTITY WRAPPERS ####################################################################
####################################################################################################################################################

type
  DWEntity* = object
    handle*:DenseHandle
    w*:ECSWorld

  SWEntity* = object
    handle*:SparseHandle
    w*:ECSWorld

proc link*(w: ECSWorld, d:DenseHandle): DWEntity =
  DWEntity(handle:d, w:w)

proc link*(w: ECSWorld, d:SparseHandle): SWEntity =
  SWEntity(handle:d, w:w)

####################################################################################################################################################
################################################################### ACCESSORS #####################################################################
####################################################################################################################################################

## Retrieves component data from a `SoAFragmentArray` using a `DWEntity`.
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], dw:DWEntity):untyped = f[dw.handle]

## Retrieves component data from a `SoAFragmentArray` using a `SWEntity`.
template `[]`*[N,P,T,S,B](f: SoAFragmentArray[N,P,T,S,B], sw:SWEntity):untyped = f[sw.handle]

## Sets component data in a `SoAFragmentArray` for a `DWEntity`.
template `[]=`*[N,P,T,S,B](f:var SoAFragmentArray[N,P,T,S,B], dw:DWEntity, v:B) = 
  f[dw.handle] = v

## Sets component data in a `SoAFragmentArray` for a `SWEntity`.
template `[]=`*[N,P,T,S,B](f: var SoAFragmentArray[N,P,T,S,B], sw:SWEntity, v:B) = 
  f[sw.handle] = v

####################################################################################################################################################
################################################################# OPERATORS #######################################################################
####################################################################################################################################################

## Equality operator for `DWEntity`.
template `==`*(d1,d2:DWEntity):bool = (d1.handle == d2.handle)

## Equality operator for `SWEntity`.
template `==`*(d1,d2:SWEntity):bool = (d1.handle == d2.handle)

## String representation operator for `DWEntity`.
proc `$`*(dw:DWEntity):string = "dw:" & $dw.handle.obj.id & " g:" & $dw.handle.gen

## String representation operator for `SWEntity`.
proc `$`*(sw:SWEntity):string = "sw:" & $sw.handle.id & " g:" & $sw.handle.gen

####################################################################################################################################################
################################################################# UTILITIES ########################################################################
####################################################################################################################################################

## Checks if a `DWEntity` has a specific component by ID.
proc hasComponent*(dw: DWEntity, comp: ComponentId | int): bool =
  return dw.w.getArchetype(dw.handle).mask.hasComponent(comp)

## Checks if a `SWEntity` has a specific component by ID.
proc hasComponent*(sw: SWEntity, comp: ComponentId | int): bool =
  return sw.w.archGraph.nodes[sw.handle.archID].mask.hasComponent(comp)

## Checks if a `DWEntity` has a specific component type.
proc hasComponent*[T](dw: DWEntity): bool =
  return dw.hasComponent(dw.w.getComponentId(T))

## Checks if a `SWEntity` has a specific component type.
proc hasComponent*[T](sw: SWEntity): bool =
  return sw.hasComponent(sw.w.getComponentId(T))
