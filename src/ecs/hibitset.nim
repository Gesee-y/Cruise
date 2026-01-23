########################################################################################################################################
######################################################### CRUISE HIBITSETS #############################################################
########################################################################################################################################

import std/[bitops, times, strformat]

const
  L0_BITS = 64  # Bits par bloc de niveau 0
  L0_SHIFT = 6  # log2(64) pour calculs rapides
  L0_MASK = 63  # Masque pour extraire position dans bloc

type
  HiBitSet* = object
    layer0: seq[uint64]  # Niveau inférieur - bits réels
    layer1: seq[uint64]  # Niveau supérieur - résumé

proc newHiBitSet*(capacity: int = 4096): HiBitSet =
  ## Crée un nouveau HiBitSet avec la capacité spécifiée
  let l0Size = (capacity + L0_BITS - 1) shr L0_SHIFT
  let l1Size = (l0Size + L0_BITS - 1) shr L0_SHIFT
  result.layer0 = newSeq[uint64](l0Size)
  result.layer1 = newSeq[uint64](l1Size)

proc len*(h: HiBitSet): int {.inline.} =
  ## Retourne la capacité totale du bitset
  h.layer0.len * L0_BITS

proc ensureCapacity(h: var HiBitSet, idx: int) =
  ## S'assure que le bitset peut contenir l'index donné
  let neededL0 = (idx shr L0_SHIFT) + 1
  if neededL0 > h.layer0.len:
    h.layer0.setLen(neededL0)
    let neededL1 = (neededL0 + L0_BITS - 1) shr L0_SHIFT
    if neededL1 > h.layer1.len:
      h.layer1.setLen(neededL1)

proc set*(h: var HiBitSet, idx: int) {.inline.} =
  ## Active le bit à l'index spécifié
  h.ensureCapacity(idx)
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  h.layer0[l0Idx] = h.layer0[l0Idx] or (1'u64 shl bitPos)
  h.layer1[l0Idx shr L0_SHIFT] = h.layer1[l0Idx shr L0_SHIFT] or (1'u64 shl (l0Idx and L0_MASK))

proc unset*(h: var HiBitSet, idx: int) {.inline.} =
  ## Désactive le bit à l'index spécifié
  if idx >= h.len: return
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  h.layer0[l0Idx] = h.layer0[l0Idx] and not (1'u64 shl bitPos)
  
  # Mise à jour layer1 seulement si le bloc devient vide
  if h.layer0[l0Idx] == 0:
    let l1Idx = l0Idx shr L0_SHIFT
    let l1Bit = l0Idx and L0_MASK
    h.layer1[l1Idx] = h.layer1[l1Idx] and not (1'u64 shl l1Bit)

proc get*(h: HiBitSet, idx: int): bool {.inline.} =
  ## Vérifie si le bit à l'index est activé
  if idx >= h.len: return false
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  (h.layer0[l0Idx] and (1'u64 shl bitPos)) != 0

proc `[]`*(h: HiBitSet, idx: int): bool {.inline.} =
  ## Alias pour get
  h.get(idx)

proc `[]=`*(h: var HiBitSet, idx: int, value: bool) {.inline.} =
  ## Active ou désactive le bit selon la valeur
  if value: h.set(idx) else: h.unset(idx)

proc clear*(h: var HiBitSet) =
  ## Réinitialise tous les bits à 0
  for i in 0..<h.layer0.len: h.layer0[i] = 0
  for i in 0..<h.layer1.len: h.layer1[i] = 0

proc `and`*(a, b: HiBitSet): HiBitSet =
  ## Opération AND bit à bit
  result = newHiBitSet()
  let minL0 = min(a.layer0.len, b.layer0.len)
  result.layer0.setLen(minL0)
  result.layer1.setLen((minL0 + L0_BITS - 1) shr L0_SHIFT)
  
  for i in 0..<minL0:
    result.layer0[i] = a.layer0[i] and b.layer0[i]
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (1'u64 shl (i and L0_MASK))

proc `or`*(a, b: HiBitSet): HiBitSet =
  ## Opération OR bit à bit
  result = newHiBitSet()
  let maxL0 = max(a.layer0.len, b.layer0.len)
  result.layer0.setLen(maxL0)
  result.layer1.setLen((maxL0 + L0_BITS - 1) shr L0_SHIFT)
  
  for i in 0..<maxL0:
    let aVal = if i < a.layer0.len: a.layer0[i] else: 0'u64
    let bVal = if i < b.layer0.len: b.layer0[i] else: 0'u64
    result.layer0[i] = aVal or bVal
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (1'u64 shl (i and L0_MASK))

proc `xor`*(a, b: HiBitSet): HiBitSet =
  ## Opération XOR bit à bit
  result = newHiBitSet()
  let maxL0 = max(a.layer0.len, b.layer0.len)
  result.layer0.setLen(maxL0)
  result.layer1.setLen((maxL0 + L0_BITS - 1) shr L0_SHIFT)
  
  for i in 0..<maxL0:
    let aVal = if i < a.layer0.len: a.layer0[i] else: 0'u64
    let bVal = if i < b.layer0.len: b.layer0[i] else: 0'u64
    result.layer0[i] = aVal xor bVal
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (1'u64 shl (i and L0_MASK))

proc `not`*(a: HiBitSet): HiBitSet =
  ## Opération NOT bit à bit
  result = newHiBitSet()
  result.layer0.setLen(a.layer0.len)
  result.layer1.setLen(a.layer1.len)
  
  for i in 0..<a.layer0.len:
    result.layer0[i] = not a.layer0[i]
    if result.layer0[i] != 0:
      let l1Idx = i shr L0_SHIFT
      result.layer1[l1Idx] = result.layer1[l1Idx] or (1'u64 shl (i and L0_MASK))

iterator items*(h: HiBitSet): int =
  ## Itère sur tous les indices dont le bit est activé (utilise trailing zeros)
  for l1Idx in 0..<h.layer1.len:
    var l1Block = h.layer1[l1Idx]
    while l1Block != 0:
      let l1Tz = countTrailingZeroBits(l1Block)
      let l0Idx = (l1Idx shl L0_SHIFT) or l1Tz
      
      var l0Block = h.layer0[l0Idx]
      while l0Block != 0:
        let l0Tz = countTrailingZeroBits(l0Block)
        yield (l0Idx shl L0_SHIFT) or l0Tz
        l0Block = l0Block and (l0Block - 1)  # Clear le bit le plus à droite
      
      l1Block = l1Block and (l1Block - 1)

proc card*(h: HiBitSet): int =
  ## Compte le nombre de bits activés
  result = 0
  for blk in h.layer0:
    result += countSetBits(blk)

proc `$`*(h: HiBitSet): string =
  ## Représentation textuelle du bitset
  result = "HiBitSet["
  var first = true
  for idx in h:
    if not first: result.add(", ")
    result.add($idx)
    first = false
  result.add("]")

import std/[bitops, times, strformat, algorithm]

type
  SparseHiBitSet* = object
    # Sparse set pour layer0: dense contient les valeurs, sparse les indices
    layer0Dense: seq[uint64]      # Valeurs des blocs non-zéro
    layer0Sparse: seq[int]         # Map: index bloc -> position dans dense
    layer0DenseIdx: seq[int]       # Map inverse: position dense -> index bloc
    layer0Count: int               # Nombre d'entrées valides dans dense
    
    # Sparse set pour layer1
    layer1Dense: seq[uint64]
    layer1Sparse: seq[int]
    layer1DenseIdx: seq[int]
    layer1Count: int

proc newSparseHiBitSet*(initialCapacity: int = 64): SparseHiBitSet =
  ## Crée un nouveau SparseHiBitSet
  result.layer0Dense = newSeq[uint64](initialCapacity)
  result.layer0Sparse = newSeq[int](initialCapacity)
  result.layer0DenseIdx = newSeq[int](initialCapacity)
  result.layer0Count = 0
  
  let l1Cap = max(8, initialCapacity shr L0_SHIFT)
  result.layer1Dense = newSeq[uint64](l1Cap)
  result.layer1Sparse = newSeq[int](l1Cap)
  result.layer1DenseIdx = newSeq[int](l1Cap)
  result.layer1Count = 0

proc ensureCapacityL0(h: var SparseHiBitSet, idx: int) {.inline.} =
  if idx >= h.layer0Sparse.len:
    let newLen = max(idx + 1, h.layer0Sparse.len * 2)
    h.layer0Sparse.setLen(newLen)
    h.layer0Dense.setLen(newLen)
    h.layer0DenseIdx.setLen(newLen)

proc ensureCapacityL1(h: var SparseHiBitSet, idx: int) {.inline.} =
  if idx >= h.layer1Sparse.len:
    let newLen = max(idx + 1, h.layer1Sparse.len * 2)
    h.layer1Sparse.setLen(newLen)
    h.layer1Dense.setLen(newLen)
    h.layer1DenseIdx.setLen(newLen)

proc hasL0*(h: SparseHiBitSet, l0Idx: int): bool {.inline.} =
  ## Vérifie si un bloc layer0 existe
  if l0Idx >= h.layer0Sparse.len: return false
  let denseIdx = h.layer0Sparse[l0Idx]
  denseIdx < h.layer0Count and h.layer0DenseIdx[denseIdx] == l0Idx

proc getL0*(h: SparseHiBitSet, l0Idx: int): uint64 {.inline.} =
  ## Récupère un bloc layer0 (retourne 0 si inexistant)
  if not h.hasL0(l0Idx): return 0
  h.layer0Dense[h.layer0Sparse[l0Idx]]

proc setL0*(h: var SparseHiBitSet, l0Idx: int, value: uint64) {.inline.} =
  ## Définit la valeur d'un bloc layer0
  h.ensureCapacityL0(l0Idx)
  
  if value == 0:
    # Supprimer le bloc s'il existe
    if h.hasL0(l0Idx):
      let denseIdx = h.layer0Sparse[l0Idx]
      let lastIdx = h.layer0Count - 1
      
      if denseIdx != lastIdx:
        # Swap avec le dernier élément
        h.layer0Dense[denseIdx] = h.layer0Dense[lastIdx]
        h.layer0DenseIdx[denseIdx] = h.layer0DenseIdx[lastIdx]
        h.layer0Sparse[h.layer0DenseIdx[lastIdx]] = denseIdx
      
      h.layer0Count -= 1
  else:
    if h.hasL0(l0Idx):
      # Mettre à jour la valeur existante
      h.layer0Dense[h.layer0Sparse[l0Idx]] = value
    else:
      # Ajouter un nouveau bloc
      h.layer0Sparse[l0Idx] = h.layer0Count
      h.layer0Dense[h.layer0Count] = value
      h.layer0DenseIdx[h.layer0Count] = l0Idx
      h.layer0Count += 1

proc hasL1*(h: SparseHiBitSet, l1Idx: int): bool {.inline.} =
  if l1Idx >= h.layer1Sparse.len: return false
  let denseIdx = h.layer1Sparse[l1Idx]
  denseIdx < h.layer1Count and h.layer1DenseIdx[denseIdx] == l1Idx

proc getL1*(h: SparseHiBitSet, l1Idx: int): uint64 {.inline.} =
  if not h.hasL1(l1Idx): return 0
  h.layer1Dense[h.layer1Sparse[l1Idx]]

proc setL1*(h: var SparseHiBitSet, l1Idx: int, value: uint64) {.inline.} =
  h.ensureCapacityL1(l1Idx)
  
  if value == 0:
    if h.hasL1(l1Idx):
      let denseIdx = h.layer1Sparse[l1Idx]
      let lastIdx = h.layer1Count - 1
      
      if denseIdx != lastIdx:
        h.layer1Dense[denseIdx] = h.layer1Dense[lastIdx]
        h.layer1DenseIdx[denseIdx] = h.layer1DenseIdx[lastIdx]
        h.layer1Sparse[h.layer1DenseIdx[lastIdx]] = denseIdx
      
      h.layer1Count -= 1
  else:
    if h.hasL1(l1Idx):
      h.layer1Dense[h.layer1Sparse[l1Idx]] = value
    else:
      h.layer1Sparse[l1Idx] = h.layer1Count
      h.layer1Dense[h.layer1Count] = value
      h.layer1DenseIdx[h.layer1Count] = l1Idx
      h.layer1Count += 1

proc set*(h: var SparseHiBitSet, idx: int) {.inline.} =
  ## Active le bit à l'index spécifié
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  
  let oldValue = h.getL0(l0Idx)
  let newValue = oldValue or (1'u64 shl bitPos)
  h.setL0(l0Idx, newValue)
  
  # Mettre à jour layer1
  let l1Idx = l0Idx shr L0_SHIFT
  let l1Bit = l0Idx and L0_MASK
  let l1Old = h.getL1(l1Idx)
  h.setL1(l1Idx, l1Old or (1'u64 shl l1Bit))

proc unset*(h: var SparseHiBitSet, idx: int) {.inline.} =
  ## Désactive le bit à l'index spécifié
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  
  if not h.hasL0(l0Idx): return
  
  let oldValue = h.getL0(l0Idx)
  let newValue = oldValue and not (1'u64 shl bitPos)
  h.setL0(l0Idx, newValue)
  
  # Mettre à jour layer1 si le bloc devient vide
  if newValue == 0:
    let l1Idx = l0Idx shr L0_SHIFT
    let l1Bit = l0Idx and L0_MASK
    let l1Old = h.getL1(l1Idx)
    h.setL1(l1Idx, l1Old and not (1'u64 shl l1Bit))

proc get*(h: SparseHiBitSet, idx: int): bool {.inline.} =
  ## Vérifie si le bit à l'index est activé
  let l0Idx = idx shr L0_SHIFT
  let bitPos = idx and L0_MASK
  if not h.hasL0(l0Idx): return false
  (h.getL0(l0Idx) and (1'u64 shl bitPos)) != 0

proc `[]`*(h: SparseHiBitSet, idx: int): bool {.inline.} =
  h.get(idx)

proc `[]=`*(h: var SparseHiBitSet, idx: int, value: bool) {.inline.} =
  if value: h.set(idx) else: h.unset(idx)

proc clear*(h: var SparseHiBitSet) =
  ## Réinitialise tous les bits à 0
  h.layer0Count = 0
  h.layer1Count = 0

proc `and`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## Opération AND bit à bit
  result = newSparseHiBitSet()
  
  # Parcourir les blocs de a qui existent aussi dans b
  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    if b.hasL0(l0Idx):
      let andValue = a.layer0Dense[i] and b.getL0(l0Idx)
      if andValue != 0:
        result.setL0(l0Idx, andValue)
        
        let l1Idx = l0Idx shr L0_SHIFT
        let l1Bit = l0Idx and L0_MASK
        let l1Old = result.getL1(l1Idx)
        result.setL1(l1Idx, l1Old or (1'u64 shl l1Bit))

proc `or`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## Opération OR bit à bit
  result = newSparseHiBitSet()
  
  # Ajouter tous les blocs de a
  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    let orValue = a.layer0Dense[i] or b.getL0(l0Idx)
    result.setL0(l0Idx, orValue)
    
    let l1Idx = l0Idx shr L0_SHIFT
    let l1Bit = l0Idx and L0_MASK
    let l1Old = result.getL1(l1Idx)
    result.setL1(l1Idx, l1Old or (1'u64 shl l1Bit))
  
  # Ajouter les blocs de b qui ne sont pas dans a
  for i in 0..<b.layer0Count:
    let l0Idx = b.layer0DenseIdx[i]
    if not a.hasL0(l0Idx):
      result.setL0(l0Idx, b.layer0Dense[i])
      
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      let l1Old = result.getL1(l1Idx)
      result.setL1(l1Idx, l1Old or (1'u64 shl l1Bit))

proc `xor`*(a, b: SparseHiBitSet): SparseHiBitSet =
  ## Opération XOR bit à bit
  result = newSparseHiBitSet()
  
  # Traiter tous les blocs de a
  for i in 0..<a.layer0Count:
    let l0Idx = a.layer0DenseIdx[i]
    let xorValue = a.layer0Dense[i] xor b.getL0(l0Idx)
    if xorValue != 0:
      result.setL0(l0Idx, xorValue)
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      let l1Old = result.getL1(l1Idx)
      result.setL1(l1Idx, l1Old or (1'u64 shl l1Bit))
  
  # Traiter les blocs de b qui ne sont pas dans a
  for i in 0..<b.layer0Count:
    let l0Idx = b.layer0DenseIdx[i]
    if not a.hasL0(l0Idx):
      result.setL0(l0Idx, b.layer0Dense[i])
      let l1Idx = l0Idx shr L0_SHIFT
      let l1Bit = l0Idx and L0_MASK
      let l1Old = result.getL1(l1Idx)
      result.setL1(l1Idx, l1Old or (1'u64 shl l1Bit))

iterator items*(h: SparseHiBitSet): int =
  ## Itère sur tous les indices dont le bit est activé
  for i in 0..<h.layer1Count:
    let l1Idx = h.layer1DenseIdx[i]
    var l1Block = h.layer1Dense[i]
    
    while l1Block != 0:
      let l1Tz = countTrailingZeroBits(l1Block)
      let l0Idx = (l1Idx shl L0_SHIFT) or l1Tz
      
      if h.hasL0(l0Idx):
        var l0Block = h.getL0(l0Idx)
        while l0Block != 0:
          let l0Tz = countTrailingZeroBits(l0Block)
          yield (l0Idx shl L0_SHIFT) or l0Tz
          l0Block = l0Block and (l0Block - 1)
      
      l1Block = l1Block and (l1Block - 1)

proc card*(h: SparseHiBitSet): int =
  ## Compte le nombre de bits activés
  result = 0
  for i in 0..<h.layer0Count:
    result += countSetBits(h.layer0Dense[i])

proc memoryUsage*(h: SparseHiBitSet): int =
  ## Retourne l'utilisation mémoire approximative en octets
  result = h.layer0Count * sizeof(uint64) * 3  # dense + sparse + denseIdx
  result += h.layer1Count * sizeof(uint64) * 3

proc `$`*(h: SparseHiBitSet): string =
  result = "SparseHiBitSet["
  var first = true
  for idx in h:
    if not first: result.add(", ")
    result.add($idx)
    first = false
  result.add("]")

# ============================================================================
# TESTS
# ============================================================================

proc runTests() =
  echo "=== Tests SparseHiBitSet ==="
  
  # Test 1: Set/Get basique
  block:
    var h = newSparseHiBitSet()
    h.set(5)
    h.set(100)
    h.set(4095)
    h.set(1_000_000)
    assert h[5] == true
    assert h[100] == true
    assert h[4095] == true
    assert h[1_000_000] == true
    assert h[6] == false
    echo "✓ Test Set/Get basique"
  
  # Test 2: Unset
  block:
    var h = newSparseHiBitSet()
    h.set(42)
    assert h[42] == true
    h.unset(42)
    assert h[42] == false
    echo "✓ Test Unset"
  
  # Test 3: Itération
  block:
    var h = newSparseHiBitSet()
    h.set(1)
    h.set(10)
    h.set(100)
    h.set(1000)
    h.set(100_000)
    var indices: seq[int]
    for idx in h:
      indices.add(idx)
    indices.sort()
    assert indices == @[1, 10, 100, 1000, 100_000]
    echo "✓ Test Itération"
  
  # Test 4: AND
  block:
    var a = newSparseHiBitSet()
    var b = newSparseHiBitSet()
    a.set(5); a.set(10); a.set(15); a.set(10_000)
    b.set(5); b.set(15); b.set(20); b.set(10_000)
    let c = a and b
    assert c[5] == true
    assert c[10] == false
    assert c[15] == true
    assert c[20] == false
    assert c[10_000] == true
    echo "✓ Test AND"
  
  # Test 5: OR
  block:
    var a = newSparseHiBitSet()
    var b = newSparseHiBitSet()
    a.set(5); a.set(10)
    b.set(15); b.set(20); b.set(100_000)
    let c = a or b
    assert c[5] == true
    assert c[10] == true
    assert c[15] == true
    assert c[20] == true
    assert c[100_000] == true
    echo "✓ Test OR"
  
  # Test 6: XOR
  block:
    var a = newSparseHiBitSet()
    var b = newSparseHiBitSet()
    a.set(5); a.set(10); a.set(15)
    b.set(5); b.set(15); b.set(20)
    let c = a xor b
    assert c[5] == false
    assert c[10] == true
    assert c[15] == false
    assert c[20] == true
    echo "✓ Test XOR"
  
  # Test 7: Cardinalité
  block:
    var h = newSparseHiBitSet()
    h.set(1); h.set(10); h.set(100); h.set(1000); h.set(100_000)
    assert h.card == 5
    echo "✓ Test Cardinalité"
  
  # Test 8: Clear
  block:
    var h = newSparseHiBitSet()
    h.set(1); h.set(100); h.set(1000); h.set(100_000)
    h.clear()
    assert h.card == 0
    assert h[1] == false
    echo "✓ Test Clear"
  
  # Test 9: Sparse - vérifier que la mémoire n'explose pas
  block:
    var h = newSparseHiBitSet()
    h.set(0)
    h.set(1_000_000)
    h.set(10_000_000)
    # Devrait utiliser très peu de mémoire malgré les grands indices
    assert h.layer0Count <= 3
    assert h.card == 3
    echo "✓ Test Sparse memory"
  
  echo "Tous les tests passés! ✓\n"

# ============================================================================
# BENCHMARKS
# ============================================================================

proc benchmark() =
  echo "=== Benchmarks SparseHiBitSet ==="
  
  # Bench 1: Set sparse
  block:
    var h = newSparseHiBitSet()
    let start = cpuTime()
    for i in 0..<10_000:
      h.set(i * 100)  # Éléments très espacés
    let elapsed = cpuTime() - start
    echo &"Set 10k éléments sparse: {elapsed*1000:.2f}ms ({10_000.float/elapsed/1_000_000:.2f}M ops/s)"
    echo &"  Mémoire utilisée: {h.memoryUsage() div 1024}KB pour {h.card} bits"
  
  # Bench 2: Set dense
  block:
    var h = newSparseHiBitSet()
    let start = cpuTime()
    for i in 0..<100_000:
      h.set(i)
    let elapsed = cpuTime() - start
    echo &"Set 100k éléments denses: {elapsed*1000:.2f}ms ({100_000.float/elapsed/1_000_000:.2f}M ops/s)"
  
  # Bench 3: Get performance
  block:
    var h = newSparseHiBitSet()
    for i in 0..<100_000:
      if i mod 2 == 0: h.set(i)
    var count = 0
    let start = cpuTime()
    for i in 0..<100_000:
      if h[i]: count.inc
    let elapsed = cpuTime() - start
    echo &"Get 100k éléments: {elapsed*1000:.2f}ms ({100_000.float/elapsed/1_000_000:.2f}M ops/s)"
  
  # Bench 4: Iteration sparse
  block:
    var h = newSparseHiBitSet()
    for i in 0..<10_000:
      h.set(i * 1000)  # 10k bits éparpillés
    var count = 0
    let start = cpuTime()
    for idx in h:
      count.inc
    let elapsed = cpuTime() - start
    echo &"Itération ultra-sparse (10k sur 10M): {elapsed*1000:.2f}ms ({count.float/elapsed/1_000_000:.2f}M ops/s)"
  
  # Bench 5: AND operation sparse
  block:
    var a = newSparseHiBitSet()
    var b = newSparseHiBitSet()
    for i in 0..<10_000:
      if i mod 2 == 0: a.set(i * 100)
      if i mod 3 == 0: b.set(i * 100)
    let start = cpuTime()
    let c = a and b
    let elapsed = cpuTime() - start
    echo &"AND sparse: {elapsed*1000:.2f}ms (résultat: {c.card} bits)"
  
  # Bench 6: Comparaison mémoire sparse vs dense théorique
  block:
    var h = newSparseHiBitSet()
    # Simuler un ECS avec 1000 entités sur 1M possibles
    for i in 0..<1000:
      h.set(i * 1000)
    let sparseMemKB = h.memoryUsage() div 1024
    let denseMemKB = (1_000_000 div 8) div 1024  # Bits nécessaires en dense
    echo &"Mémoire sparse: {sparseMemKB}KB vs dense théorique: {denseMemKB}KB"
    echo &"  Ratio: {denseMemKB.float / sparseMemKB.float:.1f}x plus efficace"

when isMainModule:
  runTests()
  echo ""
  benchmark()