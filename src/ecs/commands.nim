########################################################################################################################################################
################################################################### ECS COMMAND BUFFERS ################################################################
########################################################################################################################################################

const
  ECENTITY_KIND_POS = 5
  ECBASE_POS = 7
  ECDEST_POS = 23
  ECCUSTOM_POS = 39

type
  # Describe which kind of command we are dealing with.
  # eckAddComponent and eckRemComponent are specific to the sparse storage
  # eckMigrate is specific to the dense storage
  ECommandKind = enum
    eckAddEntity
    eckRemEntity
    eckAddComponent
    eckRemComponent
    eckMigrate

  # Allows to distinguish (for a command that deal with both dense and sparse entities) which entities we are dealing with 
  ECommandEntityKind = enum
    ecekDense, ecekSparse

  # Command id are of the forms 5 bits -> CommandKind, 2 bits -> EntityKind, 16 bits -> base archetype id
  # 16 bits -> destination archetype, 19 bits ->  Custom 
  ECommand = object
    custom: int 
    kind: ECommandKind
    destArch: uint16
    baseArch: uint16
    case entityKind: ECommandEntityKind
    of ecekDense:
      dEntities: seq[DenseHandle]
    of ecekSparse:
      sEntities: seq[SparseHandle]

  ECommandBuffer = object
    denseEntityAdded: CSparseSet[ECommand] # Only indexed through `destArch`
    sparseEntityAdded: CSparseSet[ECommand] # Only indexed through `destArch`
    denseEntityRemoved: CSparseSet[ECommand] # Only indexed through `baseArch`
    sparseEntityRemoved: CSparseSet[ECommand] # Only indexed through `baseArch`
    denseEntityMigrate: CSparseSet[CSparseSet[ECommand]] # Only indexed through `destArch + baseArch`
    sparseComponentsAdded: CSparseSet[ECommand] # Only indexed through `custom`
    sparseComponentsRemoved: CSparseSet[ECommand] # Only indexed through `custom`
    
########################################################################################################################################################
##################################################################### UTILITIES ########################################################################
########################################################################################################################################################

template getKind(_: DenseHandle): ECommandEntityKind = ecekDense
template getKind(_: SparseHandle): ECommandEntityKind = ecekSparse

proc newCommand(h: DenseHandle | SparseHandle, kind: static ECommandKind, destArch: uint16, custom: int = 0) =
  var cmd = ECommand(custom: custom, kind: kind, entityKind: h.getKind, baseArch: h.archID, destArch: destArch)
  cmd

proc clear(eb: var ECommandBuffer) =
  eb.denseEntityAdded.clear()
  eb.sparseEntityAdded.clear()
  eb.denseEntityRemoved.clear()
  eb.sparseEntityRemoved.clear()
  eb.denseEntityMigrate.clear()  
  eb.sparseComponentsAdded.clear()
  eb.sparseComponentsRemoved.clear()

proc addEntity(c: var ECommand, h: DenseHandle | SparseHandle) =
  case h.kind:
    of ecekDense:
      c.dEntities.add(h)
    of ecekSparse:
      c.sEntities.add(h)

template addOrNew(cmds, i, newKind: untyped) =
  if i in cmds:
    cmds[i].addEntity(h)
  else:
    cmds[i] = newCommand(h, eckAddEntity, i)

proc addCommand(eb: var ECommandBuffer, kind: ECommandKind, h: DenseHandle | SparseHandle, destArch: uint16 = 0, comp: int = 0) =
  case kind:
    of eckAddEntity:
      let i = destArch.int
      eb.denseEntityAdded.addOrNew(i, eckAddEntity)
    of eckRemEntity:
      let i = h.archID.int
      eb.denseEntityRemoved.addOrNew(i, eckRemEntity)
    of eckMigrate:
      let i = h.archID.int
      let j = destArch.int

      if i notin eb.denseEntityMigrate:
        eb.denseEntityMigrate[i] = CSparseSet()

      eb.denseEntityMigrate[i].addOrNew(j, eckMigrate)
    of eckAddComponent:
      if comp notin eb.sparseComponentAdded:
        eb.sparseComponentAdded[comp] = newCommand(h, eckAddComponent, destArch, comp)
      else:
        eb.sparseComponentAdded[comp].addEntity(h)
    of eckRemComponent:
      if comp notin eb.sparseComponentRemoved:
        eb.sparseComponentRemoved[comp] = newCommand(h, eckRemoveComponent, destArch, comp)
      else:
        eb.sparseComponentRemoved[comp].addEntity(h)


  