  # ###################################################################################################### #
 # ############################################ TYPE INFORMATIONS ####################################### #
# ###################################################################################################### #

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
    UnknownType # Not yet supported
    RefType # Not yet supported
    ObjectType
    PrimitiveType
    EnumType
    ProcType
    GenericContainerType
    ContainerType
    
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
    offset*: int
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
    returnType*: string
    ## Size in virtual-memory words. Primitive shader values occupy one word.
    size*: int
    scopeId: int

  ProcOverloadNode* = object
    id: int = -1
    tid: int
    children: Table[string, int]
  
  ProcOverload* = object
    name: string
    nodes: seq[ProcOverloadNode]

  CLiveness* = object
    birth*: LineInfo
    dead*: LineInfo

  ShaderUniform* = object
    tid: int

  ShaderSSBO* = object
    tid: int

  ShaderParameters* = object
    uniforms: seq[ShaderUniform]
    ssbos: seq[ShaderSSBO]
    uniformToId: Table[string, int]
    ssboToId: Table[string, int]
    globalIndex: tuple[name: string, tid: int]

  # Type cache, a global structure bookeeping informations about types
  TypeCache* = object
    nameToId*: Table[string, int]
    instances*: seq[TypeInst]
    variables*: Table[string, int]
    functions*: Table[string, ProcOverload]
    liveness*: Table[string, CLiveness]
    shaderParams: ShaderParameters 

# ######################################################################################################### #
# ############################################# CONSTRUCTORS ############################################## #
# ######################################################################################################### #

proc newProcOverloadNode(id: int, tid = -1): ProcOverloadNode =
  result = ProcOverloadNode(id: id, tid: tid, children: initTable[string, int]())
proc newProcOverload(name: string): ProcOverload =
  result = ProcOverload(name: name, nodes: @[newProcOverloadNode(0, -1)])
proc addOverloadNode(p: var ProcOverload, n: int, t: TypeInst, fid, tid: int) =
  if fid >= t.fields.len:
    p.nodes[n].tid = tid
    return

  let ftype = t.fields[fid].ty
  var cid = p.nodes[n].children.getOrDefault(ftype, -1)
  if cid < 0:
    cid = p.nodes.len
    p.nodes.add(newProcOverloadNode(cid))
    p.nodes[n].children[ftype] = cid

  p.addOverloadNode(cid, t, fid + 1, tid)

proc addOverload(p: var ProcOverload, t: TypeInst, tid: int) =
  addOverloadNode(p, 0, t, 0, tid)

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
  if n.kind == DotToken: return ""

  let k = n.typeKind
  case k
  of IT:
    if n.firstChild.kind == IntLit:
      result = "int" & $(n.firstChild.intValue)
    else:
      result = "int"
  of BoolT:
    result = "bool"
  of RefT:
    inc n
    if n.kind in {Symbol, SymbolDef}:
      var txt = n.symText.split(".")
      result = txt[0]
      for i in 2..txt.high:
        result = result & "." & txt[i]
  of NoType:
    if n.kind in {Symbol, SymbolDef}:
      return n.symText
    return ""
  else:
    if n.kind == TagLit: inc n
    if n.kind in {Symbol, SymbolDef}:
      result = n.symText
    else:
      result = ""

# Quickly check if the current cursor point to a Ref Type
proc isRefType*(n: NifCursor): bool =
  n.getRawTypeKind == RefType

# Fetch sub type information
proc getSubTypeInfo*(n: NifCursor): set[TypeFlag] =
  # Assume modifiers have already been stripped away
  result = {}
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
    return {}

proc addInstance(c: var TypeCache, instance: TypeInst) =
  let id = c.instances.len
  c.nameToId[instance.name] = id
  c.instances.add(instance)

  if instance.kind == ProcType:
    try:
      addOverload(c.functions[instance.name], instance, id)
    except:
      var ov = newProcOverload(instance.name)
      addOverload(ov, instance, id)
      c.functions[instance.name] = ov

proc addUniform(c: var TypeCache, name: string, tid: int) =
  let id = c.shaderParams.uniforms.len
  c.shaderParams.uniformToId[name] = id
  c.shaderParams.uniforms.add(ShaderUniform(tid: tid))

proc addSSBO(c: var TypeCache, name: string, tid: int) =
  let id = c.shaderParams.ssbos.len
  c.shaderParams.ssboToId[name] = id
  c.shaderParams.ssbos.add(ShaderSSBO(tid: tid))

proc addGlobalIndex(c: var TypeCache, name: string, tid: int) =
  c.shaderParams.globalIndex = (name, tid)

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

proc genContainerType(tyDef: NifCursor): TypeInst =
  result = TypeInst()
  let symNode = firstChild(tyDef) # Definition of the type
  if symNode.kind == SymbolDef:
    let name = symNode.symText # Text is preferred to symID as it allows more control
    var node = symNode
    skip node
    skip node
    if node.kind != DotToken:
      var c = firstChild(node)
      var ty = c
      skip ty
      result = TypeInst(kind: ContainerType, name: name, returnType: ty.getTypeName, size: 1)

# Create a new type instance from a type definition
proc addTypeInstance*(tyDef: NifCursor): TypeInst =
  result = TypeInst()

  let symNode = firstChild(tyDef) # Definition of the type
  if symNode.kind == SymbolDef:
    let name = symNode.symText # Text is preferred to symID as it allows more control
    var node = symNode
    skip node
    skip node
    if node.otherKind == TypevarsU: return
    if node.kind != DotToken:
      # Check to avoid generating IR for system.nim code
      if firstChild(node).symText.split(".")[^1].startsWith(SYSTEM_MODULE): return
        
    result.raw = tyDef
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

  var symNode = firstChild(pDef) # Definition of the proc
  if symNode.kind == SymbolDef:
    let name = symNode.symText
    result.name = name

    # Skip directly to parameters
    skip symNode
    skip symNode
    skip symNode
    if symNode.otherKind == TypevarsU: return
    if symNode.kind != DotToken:
      # Check to avoid generating IR for system.nim code
      if firstChild(symNode).symText.split(".")[^1].startsWith(SYSTEM_MODULE): return
    result.raw = pDef
    result.kind = ProcType

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

    var retNode = symNode
    skip retNode # Skip ParamsU to reach return type slot
    if retNode.hasMore and retNode.kind != DotToken:
      result.returnType = retNode.getTypeName

# Collect type declaration and fill the type cache
proc collectTypeDecls*(c: var TypeCache, root: NifCursor) =
  var n = root
  if n.kind != TagLit:
    return

  n.loopInto:
    case n.stmtKind
    of TypeS:
      let tyDef = n
      let name = firstChild(tyDef).symText
      let instance = if c.isGenericContainerType(name): genContainerType(tyDef) else: addTypeInstance(tyDef)
      if instance.kind != UnknownType: c.addInstance(instance)
    of ProcS, FuncS:
      let pDef = n
      let instance = addProcTypeInstance(pDef)
      if instance.kind != UnknownType: c.addInstance(instance)
    else:
      discard
    collectTypeDecls(c, n)
    n.skip()

# Recursively goes through the type cache to mark types with `ref` fields as `ref` types
proc updateRef(t: var TypeCache, ty: string, visited: var Table[string, bool]): bool =
  var id = t.nameToId.getOrDefault(ty, -1)
  if id < 0: return false

  # If we have already seen the type, just return it
  if ty in visited:
    return visited.getOrDefault(ty, false)

  # Primitive types and procs are always not refs
  if t.instances[id].kind in {PrimitiveType, ProcType}:
    visited[ty] = false
    return false

  # Copy field types so we don't borrow t while recursing
  var fieldTypes: seq[string] = @[]
  for field in t.instances[id].fields:
    fieldTypes.add(field.ty)

  for fieldTy in fieldTypes:
    if updateRef(t, fieldTy, visited):
      var id2 = t.nameToId.getOrDefault(ty, -1)
      if id2 >= 0:
        t.instances[id2].kind = RefType
      visited[ty] = true
      return true

  visited[ty] = false
  return false

proc propagateRefs(t: var TypeCache) =
  var visited = initTable[string, bool]()
  var allKeys: seq[string] = @[]
  for inst in t.nameToId.keys:
    allKeys.add(inst)
  for inst in allKeys:
    if inst notin visited:
      discard updateRef(t, inst, visited)

proc computeInstanceLayout*(t: var TypeCache, index: int) =
  if t.instances[index].kind != ObjectType:
    return
  
  var offset = 0
  for fieldIndex in 0..<t.instances[index].fields.len:
    t.instances[index].fields[fieldIndex].offset = offset
    let fieldType = t.nameToId.getOrDefault(t.instances[index].fields[fieldIndex].ty, -1)
    if fieldType >= 0:
      offset += max(1, t.instances[fieldType].size)
    else:
      inc offset
  t.instances[index].size = max(1, offset)

proc computeLayouts*(t: var TypeCache) =
  ## Assign field offsets after every declaration is known. Unknown fields keep
  ## one word so a backend can still report them without corrupting neighbours.
  for index in 0..<t.instances.len:
    t.computeInstanceLayout(index)

# ########################################################################################################################################## #
# ################################################################### Query API ############################################################ #
# ########################################################################################################################################## #

proc isGenericContainerType*(cache: TypeCache, name: string): bool =
  let n = name.split(".")[0]
  let tid = cache.nameToId.getOrDefault(n, -1)
  if tid < 0: return false
  return cache.instances[tid].kind == GenericContainerType
  
proc getType*(c: TypeCache, root: TypeInst, additional: seq[string]): TypeInst =
  # Fetch the concrete type following a given path
  var inst = root

  for f in additional:
    if inst.associated.len > 0:
      let id = c.nameToId.getOrDefault(inst.associated[0], -1)
      if id < 0: return TypeInst(kind: UnknownType)
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
    if id < 0: return TypeInst(kind: UnknownType)
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

  ########################################################################################################
 ############################################# TYPE CACHE INIT ##########################################
########################################################################################################

include "builtins.nim"

# Instantiate a new `TypeCache` with primitive types already registered
proc newTypeCache(): TypeCache =
  result = TypeCache()
  result.nameToId["auto"] = result.instances.len
  result.instances.add TypeInst(kind: UnknownType, name: "auto", size: 0)
  result.nameToId["int"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int", size: 4)
  result.nameToId["int8"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int8", size: 1)
  result.nameToId["int16"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int16", size: 2)
  result.nameToId["int32"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int32", size: 4)
  result.nameToId["int64"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "int64", size: 8)

  result.nameToId["uint"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint", size: 1)
  result.nameToId["uint8"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint8", size: 1)
  result.nameToId["uint16"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint16", size: 2)
  result.nameToId["uint32"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint32", size: 4)
  result.nameToId["uint64"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "uint64", size: 8)

  result.nameToId["float"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "float", size: 4)
  result.nameToId["float32"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "float32", size: 4)
  result.nameToId["float64"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "float64", size: 8)

  result.nameToId["bool"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "bool", size: 1)

  # Not allowed in GPU kernel
  # But here as a placeholder for an hypothetic time with a JIT support
  result.nameToId["char"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "char", size: 1)

  result.nameToId["string"] = result.instances.len
  result.instances.add TypeInst(kind: PrimitiveType, name: "string", size: 16)

  # Container types that returns a particular element type
  result.nameToId["seq"] = result.instances.len
  result.instances.add TypeInst(kind: GenericContainerType, name: "seq", size:1)

  result.registerBuiltins()
