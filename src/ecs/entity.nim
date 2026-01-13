####################################################################################################################################################
################################################################## ECS ENTITY ######################################################################
####################################################################################################################################################

type
  Entity = object
    id:uint
    archetypeId:uint16
    widx:int

  DenseHandle = object
    obj:ptr Entity
    gen:uint32

  SparseHandle = object
    id:uint
    mask:ArchetypeMask

  SomeEntity = ptr Entity | Entity | var Entity

template newEntity():untyped =
  var result:Entity
  result

template `[]`[N,T,S,B](f: SoAFragmentArray[N,T,S,B], e:SomeEntity):untyped = f[e.id]
template `[]`[N,T,S,B](f: SoAFragmentArray[N,T,S,B], e:DenseHandle):untyped = f[d.obj.id]
template `[]=`[N,T,S,B](f:var SoAFragmentArray[N,T,S,B], e:SomeEntity, v:B) = 
  f[e.id] = v
template `[]=`[N,T,S,B](f:var SoAFragmentArray[N,T,S,B], d:DenseHandle, v:B) = 
  f[d.obj.id] = v
template `==`(e1,e2:SomeEntity):bool = (e1.id == e2.id)
template `==`(d1,d2:DenseHandle):bool = (d1.obj == d2.obj)

proc `$`(e:SomeEntity):string = "e" & $e.id & " arch " & $e.archetypeId
