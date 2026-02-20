######################################################################################################################################
######################################################## TEMPORARY STORAGE ########################################################### 
######################################################################################################################################

import std/[tables, times, locks, json, asyncdispatch, strutils, options, sequtils]

type
  EventKind* = enum
    ekAddKey = "addkey"
    ekDeleteKey = "deletekey"
    ekExpire = "expire"
    ekClear = "clear"
    ekAddNamespace = "addns"
    ekDeleteNamespace = "deletens"

  KVEventCallback* = proc(key: string, value: pointer) {.closure, gcsafe.}
  
  TempEntry = object
    value: pointer
    destructor: proc(p: pointer) {.nimcall, gcsafe.}
    ttl: Option[DateTime]
  
  Namespace* = ref object
    data: Table[string, TempEntry]
    listeners: Table[EventKind, seq[KVEventCallback]]
    namespaces: Table[string, Namespace]
    lock: Lock
  
  TempStorage* = ref object
    namespaces: Table[string, Namespace]
    listeners: Table[EventKind, seq[KVEventCallback]]
    lock: Lock
    cleanupTask: Future[void]
    cleanupActive: bool

proc validateName(name: string) {.inline.} =
  if name.len == 0:
    raise newException(ValueError, "Variable name cannot be empty")
  if '/' in name or '\\' in name:
    raise newException(ValueError, "Name cannot contain '/' or '\\': " & name)

proc validateNamespace(ns: string) {.inline.} =
  if ns.len == 0:
    raise newException(ValueError, "Namespace cannot be empty")
  if '/' in ns or '\\' in ns:
    raise newException(ValueError, "Namespace cannot contain '/' or '\\': " & ns)

proc makeEntry[T](val: T, ttl: Option[DateTime] = none(DateTime)): TempEntry =
  let p = cast[pointer](alloc0(sizeof(T)))
  cast[ptr T](p)[] = val
  
  result = TempEntry(
    value: p,
    destructor: proc(pt: pointer) {.nimcall, gcsafe.} =
      dealloc(pt),
    ttl: ttl
  )

proc destroy(entry: var TempEntry) =
  if entry.value != nil:
    entry.destructor(entry.value)
    entry.value = nil

proc getValue[T](entry: TempEntry): T {.inline.} =
  cast[ptr T](entry.value)[]

proc isExpired(entry: TempEntry): bool {.inline.} =
  if entry.ttl.isSome:
    return now() >= entry.ttl.get
  false

proc newNamespace*(): Namespace =
  result = Namespace(
    data: initTable[string, TempEntry](),
    listeners: initTable[EventKind, seq[KVEventCallback]](),
    namespaces: initTable[string, Namespace]()
  )
  initLock(result.lock)

proc newTempStorage*(): TempStorage =
  result = TempStorage(
    namespaces: initTable[string, Namespace](),
    listeners: initTable[EventKind, seq[KVEventCallback]](),
    cleanupActive: false
  )
  initLock(result.lock)
  result.namespaces[""] = newNamespace()

proc emit(ns:var Namespace, event: EventKind, key: string, value: pointer) =
  var callbacks: seq[KVEventCallback]
  
  withLock ns.lock:
    if event in ns.listeners:
      callbacks = ns.listeners[event]
  
  for cb in callbacks:
    try:
      cb(key, value)
    except:
      discard

proc emit(ts:var TempStorage, event: EventKind, key: string, value: pointer) =
  var callbacks: seq[KVEventCallback]
  
  withLock ts.lock:
    if event in ts.listeners:
      callbacks = ts.listeners[event]
  
  for cb in callbacks:
    try:
      cb(key, value)
    except:
      discard

proc on*(ns:var Namespace, event: EventKind, callback: KVEventCallback) =
  withLock ns.lock:
    if event notin ns.listeners:
      ns.listeners[event] = @[]
    ns.listeners[event].add(callback)

proc on*(ts:var TempStorage, event: EventKind, callback: KVEventCallback) =
  withLock ts.lock:
    if event notin ts.listeners:
      ts.listeners[event] = @[]
    ts.listeners[event].add(callback)

proc off*(ns:var Namespace, event: EventKind, callback: KVEventCallback) =
  withLock ns.lock:
    if event in ns.listeners:
      ns.listeners[event].keepIf(proc(cb: KVEventCallback): bool = 
        (addr cb) != addr (callback))

proc addVar*[T](ns:var Namespace, name: string, value: T, ttl: Option[Duration] = none(Duration)) =
  validateName(name)
  
  let expiryTime = if ttl.isSome:
    some(now() + ttl.get)
  else:
    none(DateTime)
  
  var entry = makeEntry(value, expiryTime)
  
  withLock ns.lock:
    if name in ns.data:
      destroy(ns.data[name])
    ns.data[name] = entry
  
  ns.emit(ekAddKey, name, entry.value)

proc getVar*[T](ns:var Namespace, name: string, default: T): T =
  validateName(name)
  
  withLock ns.lock:
    if name in ns.data:
      let entry = ns.data[name]
      if not entry.isExpired:
        return entry.getValue[:T]()
  
  return default

proc getVar*[T](ns:var Namespace, name: string): Option[T] =
  validateName(name)
  
  withLock ns.lock:
    if name in ns.data:
      let entry = ns.data[name]
      if not entry.isExpired:
        return some(entry.getValue[:T]())
  
  return none(T)

proc hasVar*(ns:var Namespace, name: string): bool =
  validateName(name)
  
  withLock ns.lock:
    if name in ns.data:
      return not ns.data[name].isExpired
  false

proc delVar*(ns:var Namespace, name: string) =
  validateName(name)
  
  var entry: TempEntry
  var existed = false
  
  withLock ns.lock:
    if name in ns.data:
      entry = ns.data[name]
      ns.data.del(name)
      existed = true
  
  if existed:
    ns.emit(ekDeleteKey, name, entry.value)
    destroy(entry)

proc clear*(ns:var Namespace) =
  var entries: seq[TempEntry]
  
  withLock ns.lock:
    for entry in ns.data.mvalues:
      entries.add(entry)
    ns.data.clear()
    ns.namespaces.clear()
  
  ns.emit(ekClear, "", nil)
  
  for entry in entries.mitems:
    destroy(entry)

proc cleanup*(ns:var Namespace) =
  let nowTime = now()
  var expired: seq[(string, TempEntry)]
  
  withLock ns.lock:
    for key, entry in ns.data.pairs:
      if entry.ttl.isSome and entry.ttl.get <= nowTime:
        expired.add((key, entry))
    
    for (key, _) in expired:
      ns.data.del(key)
  
  for (key, entry) in expired:
    ns.emit(ekExpire, key, entry.value)
    var e = entry
    destroy(e)
  
  for subNs in ns.namespaces.mvalues:
    subNs.cleanup()

proc listVars*(ns:var Namespace): seq[string] =
  withLock ns.lock:
    for key in ns.data.keys:
      if not ns.data[key].isExpired:
        result.add(key)

proc getOrCreateNamespace(ts:var TempStorage, ns: string): Namespace =
  if ns.len > 0:
    validateNamespace(ns)
  
  withLock ts.lock:
    if ns notin ts.namespaces:
      ts.namespaces[ns] = newNamespace()
      ts.emit(ekAddNamespace, ns, nil)
    return ts.namespaces[ns]

proc addVar*[T](ts:var TempStorage, name: string, value: T, 
                ns: string = "", ttl: Option[Duration] = none(Duration)) =
  var namespace = ts.getOrCreateNamespace(ns)
  namespace.addVar(name, value, ttl)

proc getVar*[T](ts:var TempStorage, name: string, default: T, ns: string = ""): T =
  var namespace = ts.getOrCreateNamespace(ns)
  namespace.getVar(name, default)

proc getVar*[T](ts:var TempStorage, name: string, ns: string = ""): Option[T] =
  var namespace = ts.getOrCreateNamespace(ns)
  namespace.getVar[:T](name)

proc hasVar*(ts:var TempStorage, name: string, ns: string = ""): bool =
  var namespace = ts.getOrCreateNamespace(ns)
  namespace.hasVar(name)

proc delVar*(ts:var TempStorage, name: string, ns: string = "") =
  var namespace = ts.getOrCreateNamespace(ns)
  namespace.delVar(name)

proc clear*(ts:var TempStorage, ns: string = "") =
  if ns.len == 0:
    withLock ts.lock:
      for namespace in ts.namespaces.mvalues:
        namespace.clear()
      ts.namespaces.clear()
      ts.namespaces[""] = newNamespace()
    ts.emit(ekClear, "", nil)
  else:
    var namespace = ts.getOrCreateNamespace(ns)
    namespace.clear()

proc cleanup*(ts:var TempStorage) =
  ## Nettoie toutes les variables expirées
  withLock ts.lock:
    for namespace in ts.namespaces.mvalues:
      namespace.cleanup()

proc createNamespace*(ts:var TempStorage, name: string) =
  ## Crée explicitement un namespace
  discard ts.getOrCreateNamespace(name)

proc deleteNamespace*(ts:var TempStorage, name: string) =
  ## Supprime un namespace
  validateNamespace(name)
  
  var ns: Namespace
  withLock ts.lock:
    if name in ts.namespaces:
      ns = ts.namespaces[name]
      ts.namespaces.del(name)
  
  if ns != nil:
    ns.clear()
    ts.emit(ekDeleteNamespace, name, nil)

proc listNamespaces*(ts:var TempStorage): seq[string] =
  withLock ts.lock:
    for key in ts.namespaces.keys:
      result.add(key)

proc listVars*(ts:var TempStorage, ns: string = ""): seq[string] =
  var namespace = ts.getOrCreateNamespace(ns)
  namespace.listVars()

proc autoCleanupLoop(ts:var TempStorage, interval: Duration) {.async.} =
  while ts.cleanupActive:
    await sleepAsync(interval.inMilliseconds.int)
    if ts.cleanupActive:
      ts.cleanup()

proc startAutoCleanup*(ts:var TempStorage, interval: Duration = initDuration(seconds = 60)) =
  ## Démarre le nettoyage automatique
  if ts.cleanupActive:
    return
  
  ts.cleanupActive = true
  ts.cleanupTask = autoCleanupLoop(ts, interval)

proc stopAutoCleanup*(ts:var TempStorage) =
  if not ts.cleanupActive:
    return
  
  ts.cleanupActive = false

proc toJson*(ts:var TempStorage): JsonNode =
  result = newJObject()
  
  withLock ts.lock:
    var nsNode = newJObject()
    for nsName, namespace in ts.namespaces.pairs:
      var dataNode = newJObject()
      withLock namespace.lock:
        for key, entry in namespace.data.pairs:
          if not entry.isExpired:
            # Note: Sérialisation limitée aux types JSON natifs
            var entryNode = newJObject()
            if entry.ttl.isSome:
              entryNode["ttl"] = %($entry.ttl.get)
            dataNode[key] = entryNode
      nsNode[nsName] = dataNode
    result["namespaces"] = nsNode
    result["saved_at"] = %($now())

proc saveToFile*(ts:var TempStorage, filepath: string) =
  ## Sauvegarde dans un fichier JSON
  let jsonData = ts.toJson()
  writeFile(filepath, jsonData.pretty)

# ============================================================================
# Destructeur
# ============================================================================

#[proc `=destroy`*(ns: var Namespace) =
  ## Nettoyage automatique du namespace
  if ns.data.len > 0:
    for entry in ns.data.mvalues:
      destroy(entry)
  deinitLock(ns.lock)

proc `=destroy`*(ts: var TempStorage) =
  ## Nettoyage automatique du storage
  if ts.cleanupActive:
    ts.cleanupActive = false
  deinitLock(ts.lock)
]#
