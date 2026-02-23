# Cruise ECS

Cruise ECS exists to give a solid base to anyone trying to build their own engine, while remaining completely optional.

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

var poscolumn = w.get(Pos)

var e = w.createEntity(posID)
poscolumn[e] = Pos()

for (bid, r) in w.denseQuery(query(w, Pos)):
  var xdata = addr poscolumn.blocks[bid].data.x
  for i in r:
    xdata[i] += 1
```

## Core: Fragment Vector

At its core, Cruise ECS uses **fragment vectors**, a data structure that stores blocks of data. It is similar to a sparse set, but stores contiguous indices within the same data block. On deletion, it splits blocks, and on insertion it can fuse them again if necessary.

This version of the data structure is more hardcore: constant block size, no gaps smaller than a block size between blocks, etc.
This provides extremely fast performance and is perfectly suited to our use case.

## Structure

Cruise uses fragment vectors to simulate both sparse sets and archetypes, not through physical storage but through organization and iteration strategies.

### Dense Strategy

#### Organization

Entities with the same set of components are stored in the same chunks. The set of chunks containing entities for a given component set is called a **partition**. Multiple partitions can coexist, allowing dense iterations with maximum performance. However, removing entities or adding/removing components requires moving some memory (mostly overwrites), which can be more costly than in a sparse set.

#### Querying and Iteration

Querying consists of retrieving all partitions matching a given signature. This is easy to implement using specialized hash maps and related structures. Iteration simply consists of walking through tightly packed chunks of data.

### Sparse Strategy

#### Organization

Here, data organization is not important: entities are placed wherever space is available. We keep a **hibitset** composed of two masks:

* a first mask indicating which chunks contain at least one entity for a component
* a second mask indicating which entities are present

#### Querying and Iteration

Querying consists of intersecting the hibitsets of the requested components. Iteration first finds non-zero bits to access matching chunks using trailing zero counts, then iterates over matching entities the same way. This drastically reduces branching during iteration and allows skipping up to 4096 entities in a single instruction.

## Features

* **Really fast**: Performance is one of the main aspects of any ECS, and Cruise takes this seriously. Using an SoA + Fragment Vector layout, it enables extremely fast dense iterations and efficient sparse iterations.

* **Cross-languages**: Compile the ECS to C, C++ or even JS to integrate it in your project (even if it's a web engine)

* **Choose your layout**: Cruise ECS allows you to use dense or sparse entities as you wish, or even transition entities between them:

```nim
var w = newECSWorld()
var d = w.createEntity()
var s = w.createSparseEntity()

let e = w.makeDense(s)
let t = w.makeSparse(d)
```

* **Flexible components**: There is no need to declare components ahead of time. You can add components at any point in your code.

```nim
world.registerComponent(Position)
world.registerComponent(Tag)
world.registerComponent(Inventory[Sword])
```

* **Setters / getters**: Cruise allows you to define setters and getters for your components. This makes tracking changes easier and simplifies component usage. The compiler ensures they have no side effects.

```nim
func newPosition(x,y:float32):Position =
  return Position(x:x*2, y:y/2)

func setComponent[T](blk: ptr T, i:uint, v:Position) =
  blk.data.x = v.x/2
  blk.data.y = v.y*2

var positions = world.get(Position, true) # Enable setter/getter access

discard position[entity]       # Calls the getter `newPosition`
position[entity] = Position()  # Calls the setter `setComponent`
```

* **Abstract query filters**: Cruise ECS allows users to define custom query constraints through query filters. These filters can be incrementally maintained to retrieve all entities matching them. They support all bitwise operations.

```nim
var fil = newQueryFilter()
fil.set(entity)
var sig = world.query(Position)
sig.addFilter(fil)
```

* **Pluggable views**: Cruise ECS allows multiple views or projections of the world using hooks and filters. These are implemented as **plugins**, allowing users to share ECS views and work in their preferred way.

```nim
var tree = initSceneTree(rootEntity)
world.setUp(tree)

tree.addChild(entity1)
tree.addChild(entity1, entity2)

var sig = world.query(Position and Velocity)
sig.addFilter(tree.getChildren(entity1))
for (bid, r) in world.denseQuery(sig):
  # Modify the children
```

* **Change tracking**: Cruise ECS allows querying only entities that have changed for a given component using the syntax `Modified[Type]`. You can also query components that have not changed using `not Modified[Type]`.

* **Integrated event system**: Cruise ECS allows you to listen for events such as entity creation and more:

```nim
world.events.onDenseComponentAdded do _:
  echo "New component added!"
```

* **Powerful query system**: Cruise ECS provides a powerful and expressive query syntax:

```nim
var sig = world.query(Modified[Position] and Velocity and not Tag)
sig.addFilter(MyCustomQueryFilter)
# The signature can then be used for sparse or dense queries
```

* **Command buffers**: Cruise ECS allows deferring structural changes to avoid corrupting ongoing iterations.

```nim
var id = world.newCommandBuffer() # One per thread if needed
world.deleteEntityDefer(entity, id)
world.flush() # Execute all deferred commands
```

* **Stable after peak entity count**: Once the maximum entity count is reached, no more allocations occur. The ECS reuses its own slots.

* **Ease of use**: Heavily relies on Nim macros to achieve high performance without sacrificing simplicity.

* **Rollback friendly**: Cruise ECS uses hibitsets to track changes. Tracking component changes only requires diffing two hibitsets (essentially an `xor`).

* **Granular concurrency**: Uses a `LockTree` with TRWLocks, allowing fine-grained read/write locking on specific object fields.

```nim
var positions = world.get(Position)
positions.locks.withWriteLock("x"): # Lock write access to the `x` field only
  # Do stuff
```

* **Zero external dependencies**: Cruise ECS does not rely on any third-party libraries.
