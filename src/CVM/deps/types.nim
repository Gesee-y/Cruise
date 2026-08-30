  ########################################################################################################
 ############################################# TYPE INFORMATIONS ########################################
########################################################################################################

#
# Here we implement a cache for type declared in the current module scope.
# Types declared outside are marked as `UnknownType` and may ends up rejected during generation
# Whether a type is accepted or not by a backend is at the discretion fo the backend generation
# 
# Typically in a GPU kernel, Ref types and string types will get rejected
#

import std/tables, std/strutils, std/assertions

type
  # Describe which kind of type we are dealing with
  TypeKind* = enum
    RefType # Not yet supported
    ObjectType
    PrimitiveType
    EnumType
    ProcType
    UnknownType # Not yet supported

  # Annotation currently seen on the type
  TypeFlag* = enum
    NilF # Not allowed in GPU kernels
    NotNilF
    VarF
    LentF
    SinkF
    OutF

  # Describe field of a type
  TypeField* = object
    name*: string
    ty*: string
    raw*: NifCursor
    subinfo*: set[TypeFlag]

  # An instance of a type.
  # It's obtained from a type declaration
  TypeInst* = object
    name*: string
    associated*: seq[string] # Store generics informations
    kind*: TypeKind
    raw*: NifCursor
    nameToId*: Table[string, int]
    fields*: seq[TypeField]
    scopeId: int

  # Type cache, a global structure bookeeping informations about types
  TypeCache* = object
    nameToId*: Table[string, int]
    instances*: seq[TypeInst]

# ######################################################################################################### #
# ############################################# CONSTRUCTORS ############################################## #
# ######################################################################################################### #

# Instantiate a new `TypeCache` with primitive types already registered
proc newTypeCache(): TypeCache =
  result = TypeCache()
  result.nameToId["int"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int")
  result.nameToId["int8"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int8")
  result.nameToId["int16"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int16")
  result.nameToId["int32"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int32")
  result.nameToId["int64"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int64")

  result.nameToId["uint"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint")
  result.nameToId["uint8"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint8")
  result.nameToId["uint16"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint16")
  result.nameToId["uint32"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint32")
  result.nameToId["uint64"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint64")

  result.nameToId["float"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "float")
  result.nameToId["float32"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "float32")
  result.nameToId["float64"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "float64")

  result.nameToId["bool"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "bool")

  # Not allowed in GPU kernel
  # But here as a placeholder for an hypothetic time with a JIT support
  result.nameToId["char"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "char")

  result.nameToId["string"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "string")

# ######################################################################################################### #
# ################################################# UTILS ################################################# #
# ######################################################################################################### #

# Pass through all wrappers around a function parameter
proc stripTypeWrappers*(t: NifCursor): NifCursor =
  result = t
  while result.typeKind in {SinkT, MutT, LentT, OutT}:
    inc result

# Record type wrappers in a set
# Used to construct types `subinfo`
proc recordTypeWrappers*(t: NifCursor, flags: var set[TypeFlag]) =
  var n = t
  while n.typeKind in {SinkT, MutT, LentT, OutT}:
    case n.typeKind:
    of SinkT:
      flags.incl SinkF
    of MutT:
      flags.incl VarF
    of LentT:
      flags.incl LentF
    of OutT:
      flags.incl OutF
    else: discard
    inc n

# Translate a Nif `TypeKind` directly to CVM `TypeKind`
proc getRawTypeKind*(t: NifCursor): TypeKind =
  var n = stripTypeWrappers(t)

  case n.typeKind:
  of RefT:
   result = RefType
  of EnumT:
   result = EnumType
  of ProcT, TemplateT, MethodT, IteratorT:
    result = ProcType
  of IT, FT, CT, UT, BoolT:
    result = PrimitiveType
  of UntypedT, TypedT, AutoT:
    result = UnknownType
  of NoType:
    assert false, "Unable to get raw type."
    return UnknownType
  else:
    result = ObjectType

# Fetch the name of type from a NifCursor designing that type
proc getTypeName(ty: NifCursor): string =
  result = ""
  var n = stripTypeWrappers(ty)

  let k = n.typeKind
  case k:
  of IT:
    result = "int" & $(n.firstChild.intValue)
  of BoolT:
    result = $k
  of RefT:
    # For field who uses ref types
    # We need to infer the ref type name from the object one
    # They are ina the form `typeName.Obj.version.otherStuff`
    # We just need to remove the `Obj`
    inc n
    var txt = n.symText.split(".")
    result = txt[0]
    for i in 2..txt.high:
      result = result & "." & txt[i]
  of NoType:
    assert false, "Unable to get type name."
    return ""
  else:
    if n.kind == TagLit: inc n
    result = n.symText

# Quickly check if the current cursor point to a Ref Type
proc isRefType*(n: NifCursor): bool =
  n.getRawTypeKind == RefType

# Fetch sub type information
proc getSubTypeInfo*(n: NifCursor): set[TypeFlag] =
  # Assume modifiers have already been stripped away
  result = default(set[TypeFlag])
  if n.kind == TagLit:
    var marker = firstChild(n)
    skip marker

    if marker.hasMore and marker.otherKind in {NotnilU, NilU}:
      case marker.otherKind:
      of NotnilU:
        result.incl NotNilF
      of NilU:
        result.incl NilF
      else: discard
  else:
    assert false, "Unable to get sub type information."
    return default(set[TypeFlag])

# Add a type instance to the cache
proc addInstance(c: var TypeCache, instance: TypeInst) =
  let id = c.instances.len
  c.nameToId[instance.name] = id
  c.instances.add(instance)

# And a field instance to a type
proc addField(t: var TypeInst, field: TypeField) =
  let id = t.fields.len
  t.nameToId[field.name] = id
  t.fields.add(field)

# Fetch the body of a type declaration
proc declaredTypeBody(n: NifCursor): NifCursor =
  result = n
  skip result # export marker
  skip result # pragmas
  skip result # typevars/body prefix
  skip result

# Create a new type instance from a type definition
proc addTypeInstance*(tyDef: NifCursor): TypeInst =
  result = TypeInst()
  result.raw = tyDef

  let symNode = firstChild(tyDef) # Definition of the type
  if symNode.kind == SymbolDef:
    let name = symNode.symText # Text is preferred to symID as it allows more control
    var node = symNode
    skip node
    skip node
    skip node
    skip node

    let body = declaredTypeBody(symNode)
    let tyKind = getRawTypeKind(body) # We get the raw body kind from the type

    result.name = name
    result.kind = tyKind

    case tyKind
    of ObjectType:
      var fieldCursor = firstChild(body)
      skip fieldCursor # parent type / inheritance slot, skip for now
      while fieldCursor.hasMore:
        if fieldCursor.kind == TagLit and fieldCursor.otherKind == FldU:
          var f = TypeField()
          var field = firstChild(fieldCursor)
          let fieldName = field.symText
          let fieldSym = field.symId
          skip field # export marker
          skip field # pragmas
          skip field
          let fieldType = field
          let fieldTyName = fieldType.getTypeName

          f.ty = fieldTyName
          f.raw = fieldType
          f.name = fieldName
          result.addField f
        skip fieldCursor
    of RefType:
      let associated = body.firstChild.getTypeName
      result.associated = @[associated]
    else: discard

# Directly get informations about procs
proc addProcTypeInstance*(pDef: NifCursor): TypeInst =
  result = TypeInst()
  result.raw = pDef
  result.kind = ProcType

  var symNode = firstChild(pDef) # Definition of the proc
  if symNode.kind == SymbolDef:
    let name = symNode.symText
    result.name = name

    # Skip directly to parameters
    skip symNode
    skip symNode
    skip symNode
    skip symNode

    let body = symNode
    if body.otherKind == ParamsU:
      var fieldCursor = firstChild(body)

      while fieldCursor.hasMore:
        if fieldCursor.exprKind != DotX:
          var f = TypeField()
          var field = firstChild(fieldCursor)
          let fieldName = field.symText
          let fieldSym = field.symId
          skip field
          skip field # export marker
          skip field # pragmas
          let fieldType = field
          let fieldTyName = fieldType.getTypeName
          recordTypeWrappers(fieldType, f.subinfo)

          f.ty = fieldTyName
          f.raw = fieldType
          f.name = fieldName
          result.addField f
        skip fieldCursor

# Collect type declaration and fill the type cache
proc collectTypeDecls*(c: var TypeCache, root: NifCursor) =
  var n = root
  if n.kind != TagLit:
    return
  n.loopInto:
    case n.stmtKind
    of TypeS:
      let tyDef = n
      let instance = addTypeInstance(tyDef)
      c.addInstance(instance)
    of ProcS, FuncS:
      let pDef = n
      let instance = addProcTypeInstance(pDef)
      c.addInstance(instance)
    of CommentS:
      return
    else:
      discard
    collectTypeDecls(c, n)
    n.skip()

# Recursively goes through the type cache to mark types with `ref` fields as `ref` types
proc updateRef(t: var TypeCache, ty: string, visited: var Table[string, bool]): bool =
  var id = t.nameToId.getOrDefault(ty)

  # If we have already seen the type, just return it
  if ty in visited:
    return visited.getOrDefault(ty)

  # Primitive types and procs are always not refs
  if t.instances[id].kind in {PrimitiveType, ProcType}:
    visited[ty] = false
    return false

  # We recursively check the fields
  for field in t.instances[id].fields:
    if updateRef(t, field.ty, visited):
      var id = t.nameToId.getOrDefault(ty)
      t.instances[id].kind = RefType
      visited[ty] = true
      return true

  visited[ty] = false
  return false

proc propagateRefs(t: var TypeCache) =
  var visited = initTable[string, bool]()
  for inst in t.nameToId.keys:
    if inst notin visited:
      discard updateRef(t, inst, visited)

# ########################################################################################################################################## #
# ################################################################### Query API ############################################################ #
# ########################################################################################################################################## #

proc getType*(c: TypeCache, root: TypeInst, additional: seq[string]): TypeInst =
  # Fetch the concrete type following a given path
  var inst = root

  for f in additional:
    if inst.associated.len > 0:
      let id = c.nameToId.getOrDefault(inst.associated[0], -1)
      inst = c.instances[id]
    let fid = inst.nameToId.getOrDefault(f, -1)
    if fid == -1: return TypeInst(kind: UnknownType)
    let field = inst.fields[fid]

    var ty = c.nameToId.getOrDefault(field.ty, -1)
    if ty == -1: return TypeInst(kind: UnknownType)
    inst = c.instances[ty]

  return inst

proc getType*(c: TypeCache, root: TypeInst, idx: int): TypeInst =
  # Fetch the concrete type following a given position
  # Useful for function the `idx`-th parameter
  var inst = root
  if inst.associated.len > 0:
    let id = c.nameToId.getOrDefault(inst.associated[0], -1)
    inst = c.instances[id]
  if idx < inst.fields.len:
    let field = inst.fields[idx]

    var ty = c.nameToId.getOrDefault(field.ty, -1)
    if ty == -1: return TypeInst(kind: UnknownType)
    inst = c.instances[ty]

  return inst

proc getType*(c: TypeCache, root: string): TypeInst =
  # Fetch the concrete type following a given path
  var ty = c.nameToId.getOrDefault(root, -1)
  if ty == -1: return TypeInst(kind: UnknownType)

  return c.instances[ty]

proc getType*(c: TypeCache, root: string, additional: seq[string]): TypeInst =
  # Fetch the concrete type following a given path
  var ty = c.nameToId.getOrDefault(root, -1)
  if ty == -1: return TypeInst(kind: UnknownType)

  var inst = c.instances[ty]
  return c.getType(inst, additional)

proc getType*(c: TypeCache, root: string, idx: int): TypeInst =
  # Fetch the concrete type following a given position
  # Useful for function the `idx`-th parameter
  var ty = c.nameToId.getOrDefault(root, -1)
  if ty == -1: return TypeInst(kind: UnknownType)

  var inst = c.instances[ty]
  return c.getType(inst, idx)
