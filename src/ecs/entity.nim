####################################################################################################################################################
################################################################## ECS ENTITY ######################################################################
####################################################################################################################################################

type
  Entity = object
    id:uint
    archetypeId:uint16
    widx:int

  SomeEntity = ptr Entity | Entity | var Entity

template newEntity():untyped =
  var result:Entity
  result

template `[]`[N,T,B](f: SoAFragmentArray[N,T,B], e:SomeEntity):untyped = f[e.id]
template `[]=`[N,T,B](f:var SoAFragmentArray[N,T,B], e:SomeEntity, v:B) = 
  f[e.id] = v
template `==`(e1,e2:SomeEntity):bool = (e1.id == e2.id)

proc `$`(e:SomeEntity):string = "e" & $e.id & " arch " & $e.archetypeId
