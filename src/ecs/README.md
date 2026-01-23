# Cruise ECS

Actually, Cruise isn't an ECS based game engine kernel, so why am I making this ?
Because we need to exploit the plugin architecture.
Cruise ECS is there to give a solid base to anyone trying to build his engine while being completely optional (as we say, Cruis is not based on an ECS) and offers enough material to explore the Data store graph (a graph of layout, some being views into other layouts and other being combinations of layouts).

## Quick Start

```nim
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

for (bid, r, _) in w.denseQuery(query(w, Pos)):
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

## Features

- **Really Fast**: Performance is one of the main aspect of any ECS and Cruise doesn't belittle that. Using an SoA + Fragment Vector layout, it allows for extra fast dense iterations and fast sparse iterations.

- **Choose your layout**: Cruise ECS allows you to use dense or sparse entities as you wish or even make entities transitions between them:

```nim
var w = newECSWorld()
var d = w.createEntity()
var s = w.createSparseEntity()

let e = w.makeDense(s)
let t = w.makeSparse(d)
```

- **Flexible components**: No need to tell Cruise ECS the components you need before hand, you can add components at any points in your code.

```nim
world.registerComponent(Position)
world.registerComponent(Tag)
world.registerComponent(Inventory[Sword])
```

- **Setter/getters**: Cruise allows you to have setters and getter for you components. This way you can easily track change and make using components easier

```nim
proc newPosition(x,y:float32):Position =
  echo "Fetching position"
  return Position(x:x*2, y:y/2)

proc setComponent[T](blk: ptr T, i:uint, v:Position) =
  echo "Setting position"
  blk.data.x = v.x/2
  blk.data.y = v.y*2

var positions = world.get(Position, true) # Enable set get access

discard position[entity] # Call the getter `newPosition` defined by the user
position[entity] = Position() # Call the setter `setComponent` which can be overloaded by the user
```

- **Abstract query filter**: Cruise ECS allows yser to define their own queries constraint through query filter. Then they can be incrementally maintained to get all entities matching a filter. Theybsupport all bitwise operations.

```nim
var fil = newQueryFilter()
fil.set(entity)
var sig = world.query(Position)
sig.addFilter(fil)
```

- **Pluggable views**: Cruise ECS allows you to make multiple views or projections of the world through hooks and filter. These are *plugins**. Allowing people to share views of the ECS and work as they like.

```nim
var tree = initSceneTree()
world.setUp(tree)

tree.addChild(entity)
tree.addChild(entity1, entity2)

for (bid, m) in tree.getChildren(entity1):
  # Modify the childrens
```

- **Change tracking**: Cruise ECS allows you to queries only entities that changed for a given component via the syntax `Modified[Type]`. You can also query components that didn't changed with `not Modified[Type]`

- **Integrated Event System**: Cruise ECS allows you to watch for events like entity creation or more:

```nim
world.events.onDenseComponentAdded do _:
  echo "New component added there!"
```

- **Powerful query system**: Cruise ECS allows you to create powerful queries with an agreable syntax

```nim
let sig = world.query(Modified[Position] and Velocity and not Tag)
# The signature can then be used for sparse or dense queries
```

- **Command buffers**: Cruise ECS allows you to defers some structural changes to avoid corrupting your iterations.

```nim
var id = world.newCommandBuffer() # Can initialize one per thread if necessary
world.deleteEntityDefer(entity, id) # We register the deletion command
world.flush() # We execute all the commands
```

- **Stable once the peak entity count is reached**: No more allocations will happens and the ECS will reuse his own slots

- **Ease of use**: Heavily relying on Nim's macro to get the best performances without sacrificing simplicity:

- **Rollback friendly**: Cruise ECS use hibitsets to track changes, this allow to track changes for a components just by diffing 2 hibitset (which is basically a `xor`)

- **Granular concurrency**: Using `LockTree` using TRWLocks that allows to locks specific fields of an object for Read/Write 

```nim
var positions = world.get(Position)
positions.locks.withWriteLock("x"): # We only lock write access to the `x` field
  # Do stuffs
``` 

- **0 external dependency**: Cruise ECS doesn't rely on any third party lib to work.