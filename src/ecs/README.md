# Cruise ECS

Actually, Cruise isn't an ECS based game engine kernel, so why am I making this ?
Because we need to exploit the plugin architecture.
Cruise ECS is there to give a solid base to anyone trying to build his engine while being completely optional (as we say, Cruis is not based on an ECS) and offers enough material to explore the Data store graph (a graph of layout, some being views into other layouts and other being combinations of layouts).

## Quick Start

```
import Cruise

type
  Pos = object
    x, y: int

  Vel = object
    vx, vy: int

  Acc = object
    ax, ay: int

var w = newECSWorld()
var posID = w.registerComponent(Pos)
var velID = w.registerComponent(Vel)
var accID = w.registerComponent(Acc)

var poscolumn = w.get(Position)

var e = w.createEntity(posID)
poscolumn[e] = Pos()

for (bid, r) in w.denseQuery(query(w, Pos)):
  var xdata = poscolumn.blocks[bid].data.x
  for i in r:
    xdata[i] += 1
```

## Core: Fragment Vector

At his core, Cruise ECS use **fragment vector** which is a data structure that store blocks of data. It's actually like a sparse set but that store contiguous index in the same data block. On deletion it split the block and on insertion it can fuse them again if necessary.

But the version of this data structure is a more hardcore version with constant block size, no gap lesser than a block size between blocks, etc.
This gives extra fast performances and is perfectly adapted for our use case.

## Structure

Cruise use those fragment vectors in other to simulate both sparse sets and archetypes all that not through physical storage but by organization and iteration strategy.

### Dense strategy

#### Organization

Here we put entities with the same set of components in the same chunks. The set of chunk that contains entities for a given set of components is called a **partition**. Multiple partition can coexist and allows to have dense iterations with maximum performances. However removing entities, adding/removing components requires moving some memory (mostly overrides) which may be more costly than in a sparse set.

### Querying and iteration

Querying is just about getting all the partitions matching a given signature. Easy to do will some specialized hash maps and stuffs. Iterations is just about going through these chunks of tighly packed data.

### Sparse strategy

#### Organization

Here we don't care about data organization, entities are just putted where space is available. We keep a hibitset of the structure constituted of a first mask that indicate us the chunks containing at least 1 entity for that component and a second mask indicating us those entities.

#### Querying and iteration

Querying is about intersecting the hibitsets of the components to match. and iteration get first the non zero bit to access matching chunks using trailing zeros count and iterate through matching entities using trailing zeros count. This drastically reduce branching during iteration, allows to skipping up to 4096 entities in one instruction.
