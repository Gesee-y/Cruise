####################################################################################################################################################
################################################################## ECS ENTITY ######################################################################
####################################################################################################################################################

type
  Entity = object
    id:uint
    archetype:ArchetypeMask

template newEntity():untyped =
  var result:Entity
  new(result)
  result

template `[]`[N,T,B](f: SoAFragmentArray[N,T,B], e:Entity):untyped = f[e.id]
template `[]=`[N,T,B](f:var SoAFragmentArray[N,T,B], e:Entity, v:B) = 
  f[e.id] = v
template `==`(e1,e2:Entity):bool = e1.id == e2.id
