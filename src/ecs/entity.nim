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
    gen:uint32
    mask:ArchetypeMask

  SomeEntity = ptr Entity | Entity | var Entity

template newEntity():untyped =
  var result:Entity
  result

template `[]`[N,T,S,B](f: SoAFragmentArray[N,T,S,B], e:SomeEntity):untyped = f[e.id]
template `[]`[N,T,S,B](f: SoAFragmentArray[N,T,S,B], d:DenseHandle):untyped = f[d.obj.id]
template `[]`[N,T,S,B](f: SoAFragmentArray[N,T,S,B], d:SparseHandle):untyped = 
  let S = sizeof(uint)*8
  f.sparse[d.id shr 6][d.id and (S-1).uint]
template `[]=`[N,T,S,B](f:var SoAFragmentArray[N,T,S,B], e:SomeEntity, v:B) = 
  f[e.id] = v
template `[]=`[N,T,S,B](f:var SoAFragmentArray[N,T,S,B], d:DenseHandle, v:B) = 
  f[d.obj.id] = v
template `[]=`[N,T,S,B](f: SoAFragmentArray[N,T,S,B], d:SparseHandle, v:B) = 
  let S = sizeof(uint)*8
  f.sparse[d.id shr 6][d.id and (S-1).uint] = v
template `==`(e1,e2:SomeEntity):bool = (e1.id == e2.id)
template `==`(d1,d2:DenseHandle):bool = (d1.obj == d2.obj) and (d1.gen == d2.gen)
template `==`(d1,d2:SparseHandle):bool = (d1.id == d2.id) and (d1.gen == d2.gen)

proc `$`(e:SomeEntity):string = "e" & $e.id & " arch " & $e.archetypeId
  