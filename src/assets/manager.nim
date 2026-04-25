import tables, streams, times, locks

##########################################################################################################################################################
############################################################ BASE ASSET ##############################################################################
##########################################################################################################################################################

type
  CBaseAsset* = ref object of RootObj
    ## Root type for every managed asset.
    ##
    ## Fields are populated by the manager before any pipeline method is called;
    ## subtype implementations should treat them as read-only.
    ##
    ## `lock` is managed exclusively by the asset manager — never acquire or
    ## release it manually from asset code.
    id*:        int         ## Unique monotonic identifier assigned at first load
    timestamp*: int64       ## Unix timestamp of the most recent load or reload
    path*:      string      ## Source path passed to `loadAsset`
    meta*:      seq[string] ## Optional user-defined metadata tags
    lock:       Lock        ## Per-asset lock, held during any pipeline operation

var gNextId {.global.}: int = 0
proc allocId(): int = (inc gNextId; gNextId)

proc initAsset(asset: CBaseAsset, id: int, path: string) =
  ## Internal: stamp common fields and initialise the per-asset lock.
  asset.id        = id
  asset.timestamp = getTime().toUnix()
  asset.path      = path
  initLock(asset.lock)

##########################################################################################################################################################
############################################################ VIRTUAL PIPELINE INTERFACE ##############################################################
##########################################################################################################################################################

method signature*(asset: CBaseAsset): uint64 {.base.} =
  ## **[override recommended]**
  ## Return a unique hardcoded constant written into and checked against the
  ## binary header on reload. This is the asset's own type guard.
  ##
  ## Rules:
  ##   - Use a hardcoded literal, never derive it from the type name.
  ##   - Must be unique across all asset types in the project.
  ##   - Must be stable across renames and refactors.
  ##
  ## Special value:
  ##   0 (default) means no guard — any file is accepted regardless of type.
  ##   Override with a non-zero constant to opt into type checking.
  result = 0

method load*(asset: CBaseAsset, path: string) {.base.} =
  ## **[override required]**
  ## Populate `asset` from the resource located at `path`.
  ## Step 1 of the import pipeline.
  raise newException(CatchableError,
    "load() not implemented for " & $asset.type)

method process*(asset: CBaseAsset) {.base.} =
  ## **[override optional]**
  ## Apply any in-place transformation after loading (mip-map generation,
  ## atlas packing, audio normalisation, etc.).
  ## Default: no-op.
  discard

method serialize*(asset: CBaseAsset): seq[byte] {.base.} =
  ## **[override required for export / reload-from-disk]**
  ## Convert the live asset to a flat byte sequence.
  ## Called as step 1 of the export pipeline, before `compress`.
  ## Default: empty sequence.
  result = @[]

method deserialize*(asset: CBaseAsset, data: seq[byte]) {.base.} =
  ## **[override required for reload-from-disk]**
  ## Reconstruct asset state from bytes produced by `serialize`.
  ## Receives already-decompressed bytes — `decompress` has already run.
  ## Default: no-op.
  discard

method compress*(asset: CBaseAsset, data: seq[byte]): seq[byte] {.base.} =
  ## **[override optional]**
  ## Compress `data` (the serialised payload) before writing to disk.
  ## The asset is free to use any algorithm or format it wishes.
  ## Default: identity — data is stored as-is.
  result = data

method decompress*(asset: CBaseAsset, data: seq[byte]): seq[byte] {.base.} =
  ## **[override optional]**
  ## Decompress `data` read from disk before passing it to `deserialize`.
  ## Must be the exact inverse of `compress`.
  ## Default: identity — passes data through unchanged.
  result = data

method reload*(asset: CBaseAsset, next: pointer) {.base.} =
  ## **[override optional]**
  ## Called on the *old* cached asset instance when a reload produces a fresh
  ## one. `next` points to the newly loaded asset (cast to your concrete type).
  ##
  ## Use this to transfer runtime state that should survive a reload:
  ## active callbacks, GPU handles that can be reused, in-flight references, etc.
  ##
  ## Example:
  ##   method reload(asset: CMyAsset, next: pointer) =
  ##     cast[CMyAsset](next).gpuHandle = asset.gpuHandle
  ##
  ## Default: no-op — the new asset fully replaces the old one as-is.
  discard

method destroy*(asset: CBaseAsset) {.base.} =
  ## **[override optional]**
  ## Release any external resources (GPU buffers, file handles, native memory).
  ## The GC reclaims the Nim object itself; this hook covers everything else.
  ## Default: no-op.
  discard

##########################################################################################################################################################
############################################################ BINARY FILE FORMAT ######################################################################
##########################################################################################################################################################
##
##  Offset  Size  Type    Field
##  ──────  ────  ──────  ─────────────────────────────────────────────────────
##       0     8  uint64  signature  = asset.signature() — 0 means accept-all
##       8     2  uint16  version    = 1
##      10     8  int64   dataSize   = stored payload length in bytes
##      18     4  int32   metaCount  = number of meta strings
##      22     ·  …       meta[]     = metaCount × (int32 length + UTF-8 bytes)
##       ·     ·  …       payload    = dataSize raw bytes (possibly compressed)
##
##  Whether the payload is compressed and in what format is entirely up to the
##  asset subtype — the file format itself is agnostic.
##
##########################################################################################################################################################

const kVersion*: uint16 = 1

type
  AssetHeader* = object
    ## In-memory representation of the binary file header.
    signature*:  uint64
    version*:    uint16
    dataSize*:   int64
    metaCount*:  int32

proc writeAssetFile(fs: FileStream, asset: CBaseAsset, payload: seq[byte]) =
  fs.write(asset.signature())
  fs.write(kVersion)
  fs.write(int64(payload.len))
  fs.write(int32(asset.meta.len))
  for m in asset.meta:
    fs.write(int32(m.len))
    if m.len > 0: fs.writeData(unsafeAddr m[0], m.len)
  if payload.len > 0: fs.writeData(unsafeAddr payload[0], payload.len)

proc readHeader*(path: string): AssetHeader =
  ## Parse and validate the binary header of an exported asset file without
  ## touching the payload. Useful for inspection before a full reload.
  var fs = newFileStream(path, fmRead)
  if fs == nil:
    raise newException(IOError, "Cannot open for reading: " & path)
  defer: fs.close()
  let sig  = fs.readUint64()
  let ver  = fs.readUint16()
  if ver > kVersion:
    raise newException(IOError,
      "Unsupported asset version " & $ver & " in: " & path)
  result = AssetHeader(
    signature:  sig,
    version:    ver,
    dataSize:   fs.readInt64(),
    metaCount:  fs.readInt32(),
  )

proc readAssetFile(path: string): tuple[sig: uint64, meta: seq[string], data: seq[byte]] =
  ## Internal: read signature, meta strings, and raw payload from an exported
  ## asset file. Decompression is the caller's responsibility.
  var fs = newFileStream(path, fmRead)
  if fs == nil:
    raise newException(IOError, "Cannot open for reading: " & path)
  defer: fs.close()
  let sig       = fs.readUint64()
  discard fs.readUint16()
  let dataSize  = fs.readInt64()
  let metaCount = fs.readInt32()
  var metas: seq[string]
  for _ in 0 ..< metaCount:
    let mlen = fs.readInt32()
    var s    = newString(mlen)
    if mlen > 0: discard fs.readData(addr s[0], mlen)
    metas.add(s)
  var payload = newSeq[byte](dataSize)
  if dataSize > 0: discard fs.readData(addr payload[0], int(dataSize))
  result = (sig, metas, payload)

##########################################################################################################################################################
############################################################ ASSET MANAGER ###########################################################################
##########################################################################################################################################################

type
  CAssetManager* = ref object
    ## Central registry that owns every loaded asset, keyed by source path.
    ##
    ## Locking discipline:
    ##   - `lock` guards the `resources` table itself (insert / delete / lookup).
    ##     It is a RwLock: concurrent reads are allowed, writes are exclusive.
    ##     It is held for the shortest possible time — never across I/O.
    ##   - Each `CBaseAsset` carries its own `Lock` acquired for the full
    ##     duration of any pipeline operation on that asset.
    resources: Table[string, CBaseAsset]
    lock:      Lock

proc newAssetManager*(): CAssetManager =
  ## Create a new, empty asset manager.
  result = CAssetManager(resources: initTable[string, CBaseAsset]())
  initLock(result.lock)

# ── table helpers (lock must be held by caller) ───────────────────────────────

proc unsafeGet(man: CAssetManager, path: string): CBaseAsset =
  man.resources.getOrDefault(path, nil)

proc unsafeSet(man: CAssetManager, path: string, asset: CBaseAsset) =
  man.resources[path] = asset

proc unsafeDel(man: CAssetManager, path: string) =
  man.resources.del(path)

##########################################################################################################################################################
## assetExists
##########################################################################################################################################################

proc assetExists*(man: CAssetManager, path: string): bool =
  ## Return true if an asset is currently cached at `path`.
  ## Safe to call from any thread — acquires a read lock on the table.
  ##
  ## Typical use: check whether a dependency is loaded before requesting it.
  ##   if not man.assetExists(albedoPath):
  ##     man.loadAsset[CTextureAsset](albedoPath)
  acquire(man.lock)
  result = path in man.resources
  release(man.lock)

##########################################################################################################################################################
## loadAsset
##########################################################################################################################################################

proc loadAsset*[T: CBaseAsset](man: CAssetManager, path: string): T =
  ## Load an asset of type `T` from `path` through the import pipeline and
  ## cache the result. Returns the cached value immediately on subsequent calls.
  ## Safe to call from any thread.
  ##
  ## Pipeline:
  ##   1. `load(asset, path)` – populate the asset from the source file
  ##   2. `process(asset)`    – optional in-place transformation
  ##
  ## If two threads race on the same path, one will find the asset already
  ## cached after acquiring the write lock and return the existing instance.

  # Fast path: asset already cached — read lock only.
  acquire(man.lock)
  let cached = man.unsafeGet(path)
  release(man.lock)
  if cached != nil:
    return T(cached)

  # Slow path: build the asset outside any table lock so other threads can
  # concurrently load different assets.
  var asset = T()
  initAsset(asset, allocId(), path)

  acquire(asset.lock)
  try:
    asset.load(path)   # step 1 – import
    asset.process()    # step 2 – process
  finally:
    release(asset.lock)

  # Insert into the table — re-check for a race winner.
  acquire(man.lock)
  let winner = man.unsafeGet(path)
  if winner != nil:
    # Another thread beat us; discard our copy and return theirs.
    release(man.lock)
    asset.destroy()
    return T(winner)
  man.unsafeSet(path, asset)
  release(man.lock)

  result = asset

##########################################################################################################################################################
## reloadAsset
##########################################################################################################################################################

proc reloadAsset*[T: CBaseAsset](man: CAssetManager, path: string): T =
  ## Force a fresh import of the asset at `path`.
  ## Safe to call from any thread. Blocks until the asset lock is available,
  ## so concurrent operations on the same asset are serialised.
  ##
  ## Pipeline:
  ##   1. Run the full import pipeline to produce a new asset instance
  ##   2. Call `old.reload(next)` so the old instance can transfer runtime state
  ##   3. Destroy the old instance and replace it in the cache

  # Build the new asset without holding the table lock.
  var next = T()
  initAsset(next, allocId(), path)

  acquire(next.lock)
  try:
    next.load(path)
    next.process()
  finally:
    release(next.lock)

  # Swap into the table and notify the old instance.
  acquire(man.lock)
  let old = man.unsafeGet(path)
  man.unsafeSet(path, next)
  release(man.lock)

  if old != nil:
    acquire(old.lock)
    try:
      old.reload(cast[pointer](next))  # let old instance transfer runtime state
      old.destroy()
    finally:
      release(old.lock)

  result = next

##########################################################################################################################################################
## exportAsset
##########################################################################################################################################################

proc exportAsset*(man: CAssetManager, path: string, outPath: string) =
  ## Serialize and write the cached asset at `path` to `outPath`.
  ## Acquires the asset lock for the full duration of the export.
  ## Raises `KeyError` if `path` is not currently in the cache.
  ##
  ## Export pipeline:
  ##   1. `serialize(asset)`       – convert to bytes
  ##   2. `compress(asset, bytes)` – asset decides whether/how to compress
  ##   3. write header + payload to `outPath`

  acquire(man.lock)
  let asset = man.unsafeGet(path)
  release(man.lock)

  if asset == nil:
    raise newException(KeyError, "Asset not loaded: " & path)

  acquire(asset.lock)
  try:
    let raw     = asset.serialize()
    let payload = asset.compress(raw)
    var fs = newFileStream(outPath, fmWrite)
    if fs == nil:
      raise newException(IOError, "Cannot open for writing: " & outPath)
    defer: fs.close()
    fs.writeAssetFile(asset, payload)
  finally:
    release(asset.lock)

##########################################################################################################################################################
## reloadFromDisk
##########################################################################################################################################################

proc reloadFromDisk*[T: CBaseAsset](man: CAssetManager, binPath: string): T =
  ## Load a previously exported binary asset file back into the manager.
  ## Safe to call from any thread.
  ##
  ## Reload pipeline:
  ##   1. Read signature, meta, and raw payload from `binPath`
  ##   2. Check signature: if the file's signature != 0 and != asset.signature(),
  ##      abort — the file belongs to a different asset type
  ##   3. `decompress(asset, data)` – mirror of `compress`
  ##   4. `deserialize(asset, data)` – reconstruct asset state
  ##   5. Call `old.reload(next)` if a previous version is cached, then destroy it

  # I/O happens outside all locks.
  let (fileSig, metas, raw) = readAssetFile(binPath)

  var next = T()
  initAsset(next, allocId(), binPath)
  next.meta = metas

  # Signature check: 0 on either side means accept-all.
  let assetSig = next.signature()
  if fileSig != 0 and assetSig != 0 and fileSig != assetSig:
    raise newException(IOError,
      "Signature mismatch in \"" & binPath & "\": " &
      "file has 0x" & fileSig.toHex() & ", expected 0x" & assetSig.toHex())

  acquire(next.lock)
  try:
    let data = next.decompress(raw)
    next.deserialize(data)
  finally:
    release(next.lock)

  # Swap into the table and notify the old instance.
  acquire(man.lock)
  let old = man.unsafeGet(binPath)
  man.unsafeSet(binPath, next)
  release(man.lock)

  if old != nil:
    acquire(old.lock)
    try:
      old.reload(cast[pointer](next))
      old.destroy()
    finally:
      release(old.lock)

  result = next

##########################################################################################################################################################
## destroyAsset / destroyAllAssets
##########################################################################################################################################################

proc destroyAsset*(man: CAssetManager, path: string) =
  ## Call `destroy` on the cached asset at `path` and remove it from the registry.
  ## Acquires the asset lock before calling `destroy`.
  acquire(man.lock)
  let asset = man.unsafeGet(path)
  if asset != nil: man.unsafeDel(path)
  release(man.lock)

  if asset != nil:
    acquire(asset.lock)
    try:    asset.destroy()
    finally: release(asset.lock)

proc destroyAllAssets*(man: CAssetManager) =
  ## Call `destroy` on every cached asset and clear the registry.
  ## No new assets can be inserted while this runs (write lock held on table).
  acquire(man.lock)
  var snapshot: seq[CBaseAsset]
  for a in man.resources.values: snapshot.add(a)
  man.resources.clear()
  release(man.lock)

  for asset in snapshot:
    acquire(asset.lock)
    try:    asset.destroy()
    finally: release(asset.lock)

