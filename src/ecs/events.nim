import tables

type
  DenseEntityCreatedEvent* = object
    entity*: DenseHandle
    
  DenseEntityDestroyedEvent* = object
    entity*: DenseHandle
    last*: uint
    
  DenseComponentAddedEvent* = object
    entity*: DenseHandle
    componentIds*: seq[int]
    
  DenseComponentRemovedEvent* = object
    entity*: DenseHandle
    componentIds*: seq[int]
    
  DenseEntityMigratedEvent* = object
    entity*: DenseHandle
    oldId*:uint
    lastId*:uint
    oldArchetype*: uint16
    newArchetype*: uint16

  SparseEntityCreatedEvent* = object
    entity*: SparseHandle
    
  SparseEntityDestroyedEvent* = object
    entity*: SparseHandle
    
  SparseComponentAddedEvent* = object
    entity*: SparseHandle
    componentIds*: seq[int]
    
  SparseComponentRemovedEvent* = object
    entity*: SparseHandle
    componentIds*: seq[int]

  DensifiedEvent* = object
    oldSparse*: SparseHandle
    newDense*: DenseHandle
    
  SparsifiedEvent* = object
    oldDense*: DenseHandle
    newSparse*: SparseHandle

  CommandBufferFlushedEvent* = object
    bufferId*: int
    entitiesProcessed*: int
    operationCount*: int
    
  ArchetypeCreatedEvent* = object
    archetypeId*: int
    mask*: ArchetypeMask
    componentIds*: seq[int]

  EventCallback*[T] = proc(event: T) {.closure.}
  
  EventPool*[T] = object
    callbacks: seq[EventCallback[T]]
    freeSlots: seq[int]
  
  EventManager* = object
    denseEntityCreated: EventPool[DenseEntityCreatedEvent]
    denseEntityDestroyed: EventPool[DenseEntityDestroyedEvent]
    denseComponentAdded: EventPool[DenseComponentAddedEvent]
    denseComponentRemoved: EventPool[DenseComponentRemovedEvent]
    denseEntityMigrated: EventPool[DenseEntityMigratedEvent]
    
    sparseEntityCreated: EventPool[SparseEntityCreatedEvent]
    sparseEntityDestroyed: EventPool[SparseEntityDestroyedEvent]
    sparseComponentAdded: EventPool[SparseComponentAddedEvent]
    sparseComponentRemoved: EventPool[SparseComponentRemovedEvent]
    
    densifiedEvent: EventPool[DensifiedEvent]
    sparsifiedEvent: EventPool[SparsifiedEvent]
    
    commandBufferFlushed: EventPool[CommandBufferFlushedEvent]
    archetypeCreated: EventPool[ArchetypeCreatedEvent]

proc initEventPool*[T](): EventPool[T] =
  result.callbacks = @[]
  result.freeSlots = @[]

proc subscribe*[T](pool: var EventPool[T], callback: EventCallback[T]): int =
  if pool.freeSlots.len > 0:
    result = pool.freeSlots.pop()
    pool.callbacks[result] = callback
  else:
    result = pool.callbacks.len
    pool.callbacks.add(callback)

proc unsubscribe*[T](pool: var EventPool[T], id: int) =
  if id >= 0 and id < pool.callbacks.len:
    pool.callbacks[id] = nil
    pool.freeSlots.add(id)

proc trigger*[T](pool: var EventPool[T], event: T) =
  for callback in pool.callbacks:
    if callback != nil:
      callback(event)

proc clear*[T](pool: var EventPool[T]) =
  pool.callbacks.setLen(0)
  pool.freeSlots.setLen(0)

proc initEventManager*(): EventManager =
  result.denseEntityCreated = initEventPool[DenseEntityCreatedEvent]()
  result.denseEntityDestroyed = initEventPool[DenseEntityDestroyedEvent]()
  result.denseComponentAdded = initEventPool[DenseComponentAddedEvent]()
  result.denseComponentRemoved = initEventPool[DenseComponentRemovedEvent]()
  result.denseEntityMigrated = initEventPool[DenseEntityMigratedEvent]()
  
  result.sparseEntityCreated = initEventPool[SparseEntityCreatedEvent]()
  result.sparseEntityDestroyed = initEventPool[SparseEntityDestroyedEvent]()
  result.sparseComponentAdded = initEventPool[SparseComponentAddedEvent]()
  result.sparseComponentRemoved = initEventPool[SparseComponentRemovedEvent]()
  
  result.densifiedEvent = initEventPool[DensifiedEvent]()
  result.sparsifiedEvent = initEventPool[SparsifiedEvent]()
  
  result.commandBufferFlushed = initEventPool[CommandBufferFlushedEvent]()
  result.archetypeCreated = initEventPool[ArchetypeCreatedEvent]()

proc onDenseEntityCreated*(em: var EventManager, cb: EventCallback[DenseEntityCreatedEvent]): int =
  em.denseEntityCreated.subscribe(cb)

proc onDenseEntityDestroyed*(em: var EventManager, cb: EventCallback[DenseEntityDestroyedEvent]): int =
  em.denseEntityDestroyed.subscribe(cb)

proc onDenseComponentAdded*(em: var EventManager, cb: EventCallback[DenseComponentAddedEvent]): int =
  em.denseComponentAdded.subscribe(cb)

proc onDenseComponentRemoved*(em: var EventManager, cb: EventCallback[DenseComponentRemovedEvent]): int =
  em.denseComponentRemoved.subscribe(cb)

proc onDenseEntityMigrated*(em: var EventManager, cb: EventCallback[DenseEntityMigratedEvent]): int =
  em.denseEntityMigrated.subscribe(cb)

proc onSparseEntityCreated*(em: var EventManager, cb: EventCallback[SparseEntityCreatedEvent]): int =
  em.sparseEntityCreated.subscribe(cb)

proc onSparseEntityDestroyed*(em: var EventManager, cb: EventCallback[SparseEntityDestroyedEvent]): int =
  em.sparseEntityDestroyed.subscribe(cb)

proc onSparseComponentAdded*(em: var EventManager, cb: EventCallback[SparseComponentAddedEvent]): int =
  em.sparseComponentAdded.subscribe(cb)

proc onSparseComponentRemoved*(em: var EventManager, cb: EventCallback[SparseComponentRemovedEvent]): int =
  em.sparseComponentRemoved.subscribe(cb)

proc onDensified*(em: var EventManager, cb: EventCallback[DensifiedEvent]): int =
  em.densifiedEvent.subscribe(cb)

proc onSparsified*(em: var EventManager, cb: EventCallback[SparsifiedEvent]): int =
  em.sparsifiedEvent.subscribe(cb)

proc onCommandBufferFlushed*(em: var EventManager, cb: EventCallback[CommandBufferFlushedEvent]): int =
  em.commandBufferFlushed.subscribe(cb)

proc onArchetypeCreated*(em: var EventManager, cb: EventCallback[ArchetypeCreatedEvent]): int =
  em.archetypeCreated.subscribe(cb)

proc offDenseEntityCreated*(em: var EventManager, id: int) =
  em.denseEntityCreated.unsubscribe(id)

proc offDenseEntityDestroyed*(em: var EventManager, id: int) =
  em.denseEntityDestroyed.unsubscribe(id)

proc offDenseComponentAdded*(em: var EventManager, id: int) =
  em.denseComponentAdded.unsubscribe(id)

proc offDenseComponentRemoved*(em: var EventManager, id: int) =
  em.denseComponentRemoved.unsubscribe(id)

proc offDenseEntityMigrated*(em: var EventManager, id: int) =
  em.denseEntityMigrated.unsubscribe(id)

proc offSparseEntityCreated*(em: var EventManager, id: int) =
  em.sparseEntityCreated.unsubscribe(id)

proc offSparseEntityDestroyed*(em: var EventManager, id: int) =
  em.sparseEntityDestroyed.unsubscribe(id)

proc offSparseComponentAdded*(em: var EventManager, id: int) =
  em.sparseComponentAdded.unsubscribe(id)

proc offSparseComponentRemoved*(em: var EventManager, id: int) =
  em.sparseComponentRemoved.unsubscribe(id)

proc offDensified*(em: var EventManager, id: int) =
  em.densifiedEvent.unsubscribe(id)

proc offSparsified*(em: var EventManager, id: int) =
  em.sparsifiedEvent.unsubscribe(id)

proc offCommandBufferFlushed*(em: var EventManager, id: int) =
  em.commandBufferFlushed.unsubscribe(id)

proc offArchetypeCreated*(em: var EventManager, id: int) =
  em.archetypeCreated.unsubscribe(id)

proc emitDenseEntityCreated*(em: var EventManager, entity: DenseHandle) =
  em.denseEntityCreated.trigger(DenseEntityCreatedEvent(
    entity: entity,
  ))

proc emitDenseEntityDestroyed*(em: var EventManager, entity: DenseHandle, last:uint) =
  em.denseEntityDestroyed.trigger(DenseEntityDestroyedEvent(
    entity: entity,
    last: last
  ))

proc emitDenseComponentAdded*(em: var EventManager, entity: DenseHandle, componentIds: openArray[int]) =
  em.denseComponentAdded.trigger(DenseComponentAddedEvent(
    entity: entity,
    componentIds: componentIds.toSeq
  ))

proc emitDenseComponentRemoved*(em: var EventManager, entity: DenseHandle, componentIds: openArray[int]) =
  em.denseComponentRemoved.trigger(DenseComponentRemovedEvent(
    entity: entity,
    componentIds: componentIds.toSeq
  ))

proc emitDenseEntityMigrated*(em: var EventManager, entity: DenseHandle, old,lst:uint, 
                             oldArchetype, newArchetype: uint16) =
  em.denseEntityMigrated.trigger(DenseEntityMigratedEvent(
    entity: entity,
    oldId: old,
    lastId: lst,
    oldArchetype: oldArchetype,
    newArchetype: newArchetype
  ))

proc emitSparseEntityCreated*(em: var EventManager, entity: SparseHandle) =
  em.sparseEntityCreated.trigger(SparseEntityCreatedEvent(
    entity: entity,
  ))

proc emitSparseEntityDestroyed*(em: var EventManager, entity: SparseHandle) =
  em.sparseEntityDestroyed.trigger(SparseEntityDestroyedEvent(
    entity: entity,
  ))

proc emitSparseComponentAdded*(em: var EventManager, entity: SparseHandle, componentIds: openArray[int]) =
  em.sparseComponentAdded.trigger(SparseComponentAddedEvent(
    entity: entity,
    componentIds: componentIds.toSeq
  ))

proc emitSparseComponentRemoved*(em: var EventManager, entity: SparseHandle, componentIds: openArray[int]) =
  em.sparseComponentRemoved.trigger(SparseComponentRemovedEvent(
    entity: entity,
    componentIds: componentIds.toSeq
  ))

proc emitDensified*(em: var EventManager, oldSparse: SparseHandle, 
                   newDense: DenseHandle) =
  em.densifiedEvent.trigger(DensifiedEvent(
    oldSparse: oldSparse,
    newDense: newDense,
  ))

proc emitSparsified*(em: var EventManager, oldDense: DenseHandle, 
                    newSparse: SparseHandle) =
  em.sparsifiedEvent.trigger(SparsifiedEvent(
    oldDense: oldDense,
    newSparse: newSparse,
  ))

proc emitCommandBufferFlushed*(em: var EventManager, bufferId, entitiesProcessed, operationCount: int) =
  em.commandBufferFlushed.trigger(CommandBufferFlushedEvent(
    bufferId: bufferId,
    entitiesProcessed: entitiesProcessed,
    operationCount: operationCount
  ))

proc emitArchetypeCreated*(em: var EventManager, archetypeId: int, 
                          mask: ArchetypeMask, componentIds: seq[int]) =
  em.archetypeCreated.trigger(ArchetypeCreatedEvent(
    archetypeId: archetypeId,
    mask: mask,
    componentIds: componentIds
  ))