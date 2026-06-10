# ################################################################################################################################################## #
# ############################################################## ENTITY WRAPPERS ################################################################### #
# ################################################################################################################################################## #

type
  DWEntity* = object
    ## A dense handle that can be used without passing the world around
    handle*:DenseHandle
    w*:ECSWorld

  SWEntity* = object
    ## A sparse handle that can be used without passing the world around
    handle*:SparseHandle
    w*:ECSWorld

proc link*(w: ECSWorld, d:DenseHandle): DWEntity =
  ## Transform a dense handle into a `DWEntity` that can be use for ops without passing the world around
  DWEntity(handle:d, w:w)

proc link*(w: ECSWorld, d:SparseHandle): SWEntity =
  ## Transform a sparse handle into a `SWEntity` that can be use for ops without passing the world around
  SWEntity(handle:d, w:w)

# ################################################################################################################################################## #
# ################################################################### ACCESSORS #################################################################### #
# ################################################################################################################################################## #

template `[]`*[N,P,T,S,B](f: FragmentArray[N,P,T,S,B], dw:DWEntity):untyped = 
  ## Retrieves component data from a `FragmentArray` using a `DWEntity`.
  f[dw.handle]

template `[]`*[N,P,T,S,B](f: FragmentArray[N,P,T,S,B], sw:SWEntity):untyped = 
  ## Retrieves component data from a `FragmentArray` using a `SWEntity`.
  f[sw.handle]

template `[]=`*[N,P,T,S,B](f:var FragmentArray[N,P,T,S,B], dw:DWEntity, v:B) = 
  ## Sets component data in a `FragmentArray` for a `DWEntity`.
  f[dw.handle] = v

template `[]=`*[N,P,T,S,B](f: var FragmentArray[N,P,T,S,B], sw:SWEntity, v:B) = 
  ## Sets component data in a `FragmentArray` for a `SWEntity`.
  f[sw.handle] = v

# ################################################################################################################################################## #
# ################################################################# OPERATORS ###################################################################### #
# ################################################################################################################################################## #

template `==`*(d1,d2:DWEntity):bool = 
  ## Equality operator for `DWEntity`.
  (d1.handle == d2.handle)

template `==`*(d1,d2:SWEntity):bool = 
  ## Equality operator for `SWEntity`.
  (d1.handle == d2.handle)

proc `$`*(dw:DWEntity):string = 
  ## String representation operator for `DWEntity`.
  "dw:" & $dw.handle.obj.id & " g:" & $dw.handle.gen

proc `$`*(sw:SWEntity):string = "sw:" & $sw.handle.id & " g:" & $sw.handle.gen

# ################################################################################################################################################## #
# ################################################################ UTILITIES ####################################################################### #
# ################################################################################################################################################## #

proc hasComponent*(dw: DWEntity, comp: ComponentId | int): bool =
  return dw.w.archGraph.nodes[dw.handle.obj.archetypeId].mask.hasComponent(comp)

proc hasComponent*(sw: SWEntity, comp: ComponentId | int): bool =
  return sw.w.archGraph.nodes[sw.handle.archID].mask.hasComponent(comp)

proc hasComponent*[T](dw: DWEntity): bool =
  return dw.hasComponent(dw.w.getComponentId(T))

proc hasComponent*[T](sw: SWEntity): bool =
  return sw.hasComponent(sw.w.getComponentId(T))

proc hasComponent*[T](hw: DWEntity | SWEntity, t:typedesc[T]): bool =
  return hw.hasComponent(hw.w.getComponentId(T))

proc wid*(d:DWEntity): uint32 = d.handle.wid
proc id*(d:DWEntity): uint32 = d.handle.obj.id
