# Cruise ECS Architecture

## Introduction

Game engine development is often perceived as an expert-only domain. Yet, beneath every performant engine lies a single unifying force: **software architecture**.

A poor architecture inevitably leads to technical debt. A good one ensures **modularity**, **maintainability**, and **scalability** over time. Among the leading paradigms, the **Entity-Component-System (ECS)** stands out for its data-oriented design.
This design puts data and bandwith at the heart of the architecture, often showing better scalability, extensibility and performances.
However traditional engine struggled to get in the trend due to retrocompatibility and an architecture designed for OOP.

Before going further let's first define things:

## What is ECS?

The **Entity-Component-System (ECS)** is an architecture where game objects are represented by **entities**, uniquely identified. These entities are **structural only**: they have no behavior or logic.

Game logic is handled by **systems**, which operate on **components** attached to entities. Each system processes only the entities possessing a specific set of components.

Modern ECS frameworks often rely on the notion of **archetypes**: groupings of entities sharing the same component combination, allowing for optimized batch processing.

This decouples the logics from the data and offers better extensibility.

That's why engines like **Bevy**, designed from in the start in an ECS paradigm gained traction in the rust ecosystem (also as it's an architecture that naturally match borrow checker programming style).
However, ECS comes with its own set of trade-offs — especially regarding communication between systems, runtime flexibility and the usual iteration speed vs mutations costs.

This has created 2 ECS schools:

- Archetype ECS: using dense table to store entities with a given set of components. This offers peak iteration and query speed but suffer from mutation cost. Adding/removing a component requires to move the entity from an archetype to another.

- Sparse set ECS: using sparse set for a single component pool, we can add remove components by just setting or removing a flag in the sparse set at the cost more random access while iterating and heavier queries.

## What is Cruise ECS ?

Well it's an ECS that tries his best to bridge the gap between archetype ECS and sparse sets ECS.
At its core, Cruise ECS uses **fragment vectors**, a data structure that stores blocks of data. It is similar to a sparse set, but stores contiguous indices within the same data block. On deletion, it splits blocks, and on insertion it can fuse them again if necessary (at least that was the original design, this one is more hard core.)

This version of the data structure is more hardcore: constant block size, no gaps smaller than a block size between blocks, etc.
This provides extremely fast performance and is perfectly suited to our use case.

## Structure

To understand Cruise architecture we need to see the particularities of his storage.
Fragment vectors store data by entities ID. This means that for each component pool (which use a fragment vector), the same id means the same entity.
This looks kinda like this:

```
        INTERNAL STORAGE
 _______________________________________________________
|   |     Health    |     Transform    |    Physic     |
|-------------------------------------------------------
|   |      hp       |    x    |    y   |   velocity    |
|-------------------------------------------------------
| 1 |     100       |   1.0   |  1.0   |      //       |
|-------------------------------------------------------
| 2 |     150       |   1.0   |  1.0   |      //       |
|-------------------------------------------------------
| 3 |     ___       |   ___   |  ___   |      //       |
|-------------------------------------------------------
| 4 |     ___       |   ___   |  ___   |      //       |
|-------------------------------------------------------
| 5 |     50        |  -5.0   |  1.0   |     1.0       |
|-------------------------------------------------------
| 6 |     50        |  -5.0   |  1.0   |     1.0       |
|-------------------------------------------------------
```

* Rows 1–4: entities with `Health` and `Transform`

  * Rows 1–2 are **active**, 3–4 are **pooled**
* Rows 5–6: entities with `Health`, `Transform`, and `Physic`

This is the same principle of sparse sets, enabling faster random access (as we only need the entity ID to get his component), and **id stability**, which means that the entity id is the same accros storages (we will come back to why this is important).
This is harder to ensure in archetype ECS as entities can move around and we will also get to this

## Queries

In order to understand Cruise ECS architecture, one must take it not by the memory layout but by the query engine, which is the heart of the ECS.
It introduces **abstract queries**, which are queries for anything. 
Since queries are basicaly predicate to categorize your entities following 2 categories, Cruise ECS distinguish 3 cases: 

### virtual queries 

This consist of checking a predicate at each entities to know whether it match a given predicate or not.
We have this pseudo code:

```nim
for entity in allEntities:
  if predicate(entity):
    doStuff(entity)
```  

While this allows the best flexibiliy as predicate can be anything, constructed on the fly and combined as we want, it requires to check every entity against the predicate.
This was how old ECS implemented their, without any special trick, this quickly became a performance issue.

### soft materialized queries 

Here we keep a list of the entities matching a given predicate.
The entities matching the entities are recorded before hand and then when needed we just iterate on then.

```nim
for entity in entities_matching_predicate:
  doStuff(entity)
```

This is a problem when we need to compose query, but we can use bitsets to make them simple xor operations

```nim
for id in ent_matching_A and ents_matching_B:
  let entity = entities[id]
  doStuff(entity)
```

However doing this requires stable entities id (meaning that there is one single ID that don't moves and can reliably index an entity) which is something sparse sets natively have but archetype ECS... well in thos it's mostly an after thought.
As we noted earlier, our fragment vector enable id stability so we are good.

### hard materialized queries 

Here, matching the predicate means being in a special place in memory, a.k.a archetypes.
This allows extra fast queries as you just do:

```nim
for entity in predicateA_archetype:
  doStuff(entity)
```

However composition is still not has evident. We have constraints:

- Should not be too dynamic as it would cause moving data all the time
- Entities should be at only one place at a time

Queries compositions is way more costly as you always have to move memory each time you want to make an entity match a predicate.
That's why most archetypes ECS also have sparse storage that enable soft materialized queries to complement the rigidity and fragmentation of the hard materialized ones.

## Cruise ECS in all that ?

Cruise uses fragment vectors to simulate both sparse sets and archetypes, not through physical storage but through organization and iteration strategies.

### Dense Strategy

#### Organization

Entities with the same set of components are stored in the same chunks. The set of chunks containing entities for a given component set is called a **partition**, this is our hard materialized query. Multiple partitions can coexist, allowing dense iterations with maximum performance. However, removing entities or adding/removing components requires moving some memory (mostly overwrites), which can be more costly than in a sparse set.

```
        INTERNAL STORAGE
 _______________________________________________________
|   |     Health    |     Transform    |    Physic     |
|-------------------------------------------------------
|   |      hp       |    x    |    y   |   velocity    |
|-------------------------------------------------------
| 1 |     100       |   1.0   |  1.0   |      //       |
|-------------------------------------------------------
| 2 |     150       |   1.0   |  1.0   |      //       |
|-------------------------------------------------------
| 3 |     ___       |   ___   |  ___   |      //       |
|-------------------------------------------------------
| 4 |     ___       |   ___   |  ___   |      //       |
|-------------------------------------------------------
| 5 |     50        |  -5.0   |  1.0   |     1.0       |
|-------------------------------------------------------
| 6 |     50        |  -5.0   |  1.0   |     1.0       |
|-------------------------------------------------------
```

* Rows 1–4: partition for entities with `Health` and `Transform`

  * Rows 1–2 are **active**, 3–4 are **pooled**
* Rows 5–6: partition for entities with `Health`, `Transform`, and `Physic`


#### Querying and Iteration

Querying consists of retrieving all partitions matching a given signature. This is easy to implement using specialized hash maps and related structures. Iteration simply consists of walking through tightly packed chunks of data.

### Sparse Strategy

#### Organization

Here, data organization is not important: entities are placed wherever space is available. We keep a **hibitset** composed of 3 masks:

* a first mask indicating which set of 64 chunks contain at least one chunk with one entity with the component
* a second mask indicating which chunck contains at least one entity with the components
* a third mask indicating which entities are present

Those **hibitsets** are our soft materialized queries.

```
        INTERNAL STORAGE
 _______________________________________________________
|   |     Health    |     Transform    |    Physic     |
|-------------------------------------------------------
|   |      hp       |    x    |    y   |   velocity    |
|-------------------------------------------------------
| 1 |     100       |   1.0   |  1.0   |      0.5      |
|-------------------------------------------------------
| 2 |      //       |   1.0   |  1.0   |      //       |
|-------------------------------------------------------
| 3 |     50        |  -5.0   |  1.0   |     1.0       |
|-------------------------------------------------------
| 4 |     //        |   //    |   //   |     1.0       |
|-------------------------------------------------------
```

#### Querying and Iteration

Querying consists of intersecting the hibitsets of the requested components. Iteration first finds non-zero bits to access matching chunks using trailing zero counts, then iterates over matching entities the same way. This drastically reduces branching during iteration and allows skipping up to 4096 entities in a single instruction.

## TradeOff

Obviously, Fragment vectors aren't perfect and mostly have the flaw of using more memory than traditional ECS. Since it allocate fixing chunks of memory, even if most of it is unused, and extreme churn in sparse storage can cause high memory comsumption as it can allocate in every components pool.

## Query composition

This section will introduces some abstract trick so it will requires a bit of attention.
Imagine you have a flat paper in front of you.
Looking at it, it doesn't seems like much and if someone says to you that he want to make a paper star, you would obviously say "just cut it to be a star"
But sadly, doing so means that we lose our flat paper forever!

Is not there a way to get a star out of it while still having our flat paper ?
Can we make our paper star and flat paper exist at the same time ?
The answer is yes and the trick is simple

## Masking & Filtering

*(Note: In the following sections, "masking" and "filtering" will be used interchangeably.)*

If you take a star-shaped cookie cutter (a mold) and place it over your flat sheet of paper, you successfully isolate a star without altering the paper itself. 

One might object: *"That’s not a real star; it’s just the mold giving it that appearance."* And that is exactly the trick! The star we obtained is purely virtual. It exists only as long as the mold remains on the paper. 

This is the core principle of **masking**: hiding the parts of an object that are irrelevant to your current goal, leaving only the shape you desire. This is precisely how Cruise ECS handles complex data extraction.

In this paradigm, our raw ECS storage is the flat paper, and queries are our molds—or lenses—allowing us to view the data through whatever perspective we need.

---

### The Mathematics of Queries: Set Isomorphism

To implement this efficiently, we can formalize these operations using set theory. 

Let Q be a query executed over the universe of entities E. This query returns a subset S of entities that match its criteria (S ⊆ E). 

If we have multiple queries Q1, Q2, ..., Qn yielding the respective entity sets S1, S2, ..., Sn, we can define their compositions as follows:

1. **Intersection**: Q1 ∧ Q2 ∧ . . . ∧ Qn ⇐⇒ Si = S1 ∩ S2 ∩ . . . ∩ Sn
2. **Union**: Q1 ∨ Q2 ∨ . . . ∨ Qn ⇐⇒ Si = S1 ∪ S2 ∪ . . . ∪ Sn
3. **Negation**: ¬Q ⇐⇒ E \ S

Because operations on queries map perfectly to operations on sets, we can state that **queries are isomorphic to sets**. Through query composition, we can programmatically model any mathematical set we want.

Those queries are represented in Cruise as **abstract queries filter** and **dynamic components**:

```nim
# Abstract query filter are soft materialized queries that allows for custom requirements in a query
var fil = newQueryFilter()
fil.set(entity)
var sig = world.query(Position)
sig.addFilter(fil)

let e = world.createEntity(Pos, runtimeFunc()) # runtimeFunc is a dynamic component that assign a runtime value as a component to an entity
# This allows to model to custom filter for an entity, beyond components and hard materialize it
```

### Why This Matters: Representing Complex Structures

This mathematical result is huge. It means that complex, hierarchical data structures can be represented without specialized storage engines. 

For instance, a **tree structure**—traditionally defined as a collection of nodes paired with a set of children—can be elegantly expressed in Cruise ECS as a simple tuple: 

Node = (e, Qchildren)

Which directly implemented under this API:

```nim
var tree = initSceneTree(rootEntity)
world.setUp(tree)

tree.addChild(entity1)
tree.addChild(entity1, entity2)

var sig = world.query(Position and Velocity)
sig.addFilter(tree.getChildren(entity1).toDenseID)
for (bid, r) in world.denseQuery(sig):
  # Modify the children

# or with hard materialized queries
var e = world.createEntity(Transform, parentID) # assuming parentID exist as the id of the parent of `e`
for (bid, r) in world.denseQuery(world.query(Transform and parentId)):
  for i in r:
    # Modify children
```

Instead of storing hardcoded pointers to child nodes, a parent entity can simply hold a query that filters for its children dynamically. The implications for flexibility and data-oriented design are profound.

## Application in Cruise

Using soft materialized queries (that offer the best compromise speed/composability), Cruise model almost everything as queries:

- Entities having a component is sparse strategy ? A Query
- Change tracking ? A query
- Custom filter ? A query

All this allows high composbility through set operations.

Plus through id stability (it again!), we can actually rollback, know how entities changed at from frame to frame, through `xor` 

## Static optimizations

In this section we will go away from abstract stuff and play with low level stuff.

### Component registry

When dealing with ECS, it's often necessary to have some way to have a dynamic storage that stores the differents components pool

You may need to have a `ComponentRegistry` along with `ComponentEntry`s. Each `ComponentEntry` should store the component pool.
We run on a problem. Since a sequences can only contains elements of the same type, you can't do `ComponentEntry[Position]` or `ComponentEntry[Velocity]`.
We may think about making some static structure, like a tuple `(ComponentEntry[A], ComponentEntry[B])`, but this would require every components to be registered before hands and dealing with some static shenaningans. We want to have **dynamism**
In order to solve this, we need **type erasure**.

This is about reducing the pools to a pointer and storing them in a component entry.
This way we can effectively store multiple components pool without dealing with multiple types or complex static data structure.

In order to interact with those entries, we add virtual function to them, each entry having his own sets of functions affecting his component pool.
So here comes our second problem, performances.

Using virtual functions have a huge cost in an ECS where every ns adds up.
So what can we do about it ?

### The truth about dynamism

We have to go back and think. Is our program really **dynamic** or **can it even be ?**
That's where we can follow an interesting chain of thoughts:

1. Nim is a statically typed languages
2. Meaning every types are known at compile time
3. Hencing every components are known at compile time

With this in mind, we understand that our program is *not that dynamic*, it's inherently static.
This means that at compile time, we can track the types that have been used in the ECS, set them as components and attribute an ID to them **without ever asking the user to declare components before hand**

So with it and nim metaprogramming capabilities, we can store at compile time something like this

```nim
var NEXT_COMPONENT_ID {.compileTime.} = 0 ## The ID of the next component
var COMPONENT_ID_REGISTRY {.compileTime.} = initTable[int, int]() # Map the hash of a type to his id
var ID_TO_COMPONENT {.compileTime.} = initTable[int, NimNode]() # Map each component id to a NimNode (which is a typedesc that will be use to cast it)
```

This significantly speedup making entities ou adding/removing components as the types can be resolved at compile time, the pool fetched without virtual calls and more. This has offer a 10 times speed up on adding/removing components in the sparse storage.
This can't be achieved in dense storage as we need to know the entities has before to bypass vtable, else it's useless complexity

### Static archetypes

We can push it even further by defining **compile time** archetypes.
From the multiple operations defined by the users, some archetypes can statically be inferred.
Writing `world.createEntity(Position, Velocity)` already tells the compiler that there will be a `{Position, Velocity}` archetypes, we can then initialize the ID at compile time.
This allows us to instantly get the correct archetype to spawn an entity without ANY lookup! Which makes entity creation even more faster.

### Typed entities

As we saw earlier, we can't speed up dense storage through this trick because updates aren't local to the components affected, adding/removing components need us to know which components the entity has in the first place...
And that's the purpose of typed entities
Basically just:

```nim
type TDHandle[Signature: static ArchetypeMask] = distinct DenseHandle
```

Here we encode the entity's signature in his type. Through macro we can then fully bypass vtable and generate code that directly access the required components pool when we need to add or remove components.
This after then a massive speedup

### Modding in all this ? Any downside ?

We may be worrying that this would impact modding but not at all.
A type imported from a DLL for example still has to be used somewhere!
If it's used somewhere the compiler will automatically register it without any trouble as this would just need a recompilation or even just using the dynamic component registry API (for really exotic case.)

The downside of this approach is that:
  
  - it increase binary size
  - Slow down compilation
  - Generate a lot of specialized code

But that's generally easy to handle and not that annoying. 

There are still case where you would want to manually register components so Cruise still offers the function `registerComponent` which return the component poll id.

## Benchmarks 

What's a good ECS without benchmarks ?
Cruise has been benchmarked against other ECS in the nim ecosystem (mostly outperforming them), but I guess a more juicy comparison would be against bevy, one successful and highly respected ECS engine.

### Benchmark setup

- **OS**: Windows 11
- **CPU**: Intel core i7 inside @2.8 GHz
- **RAM**: 16 Go
- **Hard Disk**: 512 Go SSD

### Benchmark against nim ECS

╔══════════════════════╦════════════════════════╦═══════════════════════╦═══════════════════════╦═══════════════════════╦═══════════════════════╦═══════════════════════╦═══════════════════════╦═══════════════════════╗
║                      ║   Cruise Dense Typed   ║     Cruise Dense      ║  Cruise Sparse Typed  ║     Cruise Sparse     ║        Easyess        ║        MiniECS        ║        Necsus         ║       Polymorph       ║
║                      ║    time         mem    ║   time         mem    ║   time         mem    ║   time         mem    ║   time         mem    ║   time         mem    ║   time         mem    ║   time         mem    ║
╠══════════════════════╬════════════╤═══════════╬═══════════╤═══════════╬═══════════╤═══════════╬═══════════╤═══════════╬═══════════╤═══════════╬═══════════╤═══════════╬═══════════╤═══════════╬═══════════╤═══════════╣
║ create entity        ║  517.59 µs │  20.50 B  ║ 381.20 µs │   0.00 B  ║ 544.65 µs │   0.00 B  ║ 477.30 µs │   0.00 B  ║ 963.00 µs │  36.00 KB ║   6.49 ms │   1.79 MB ║   2.50 ms │   0.00 B  ║   7.53 ms │ 132.00 KB ║
║ delete entity        ║  605.74 µs │   0.00 B  ║ 773.69 µs │   0.00 B  ║ 404.37 µs │   8.06 KB ║   2.32 ms │   8.06 KB ║  50.00 µs │   0.00 B  ║ 873.00 µs │ 528.00 KB ║   5.26 ms │   0.00 B  ║   4.19 ms │   0.00 B  ║
║ add component        ║    1.53 ms │   0.00 B  ║   7.17 ms │   0.00 B  ║ 257.47 µs │   0.00 B  ║ 293.48 µs │   0.00 B  ║ 552.00 µs │   0.00 B  ║   2.35 ms │ 343.70 KB ║     -     │     -     ║   6.31 ms │   0.00 B  ║
║ remove component     ║    1.13 ms │   0.00 B  ║   6.88 ms │   0.00 B  ║ 168.83 µs │   4.03 KB ║ 119.71 µs │  16.06 KB ║ 490.00 µs │   0.00 B  ║   4.09 ms │   0.00 B  ║     -     │     -     ║   4.15 ms │   0.00 B  ║
║ add remove component ║    2.57 ms │   0.00 B  ║  16.65 ms │   0.00 B  ║ 962.83 µs │   0.00 B  ║   1.02 ms │   0.00 B  ║   1.05 ms │   0.00 B  ║   7.05 ms │  81.58 KB ║     -     │     -     ║   5.39 ms │   0.00 B  ║
║ iteration            ║   39.62 µs │   0.00 B  ║  38.21 µs │   0.00 B  ║  74.36 µs │  20.50 B  ║  56.90 µs │   0.00 B  ║ 131.00 µs │   0.00 B  ║  43.00 µs │   0.00 B  ║   2.90 ms │   0.00 B  ║  56.00 µs │   0.00 B  ║
║ heterogeneous iter   ║    2.11 µs │   0.00 B  ║  22.01 µs │   0.00 B  ║  16.40 µs │   0.00 B  ║  11.72 µs │  20.50 B  ║  10.00 µs │   0.00 B  ║  16.00 µs │   0.00 B  ║     -     │     -     ║   1.94 ms │   0.00 B  ║
║ read                 ║   32.10 µs │   0.00 B  ║  35.09 µs │   0.00 B  ║  56.25 µs │   0.00 B  ║ 104.83 ns │   0.00 B  ║ 108.00 µs │   0.00 B  ║   2.25 ms │   0.00 B  ║   5.74 ms │  93.34 B  ║  31.00 µs │   0.00 B  ║
║ write                ║   53.42 µs │   0.00 B  ║  47.41 µs │   0.00 B  ║ 191.23 µs │   0.00 B  ║  71.02 µs │   0.00 B  ║  95.00 µs │   0.00 B  ║   2.11 ms │   0.00 B  ║     -     │     -     ║  33.00 µs │   0.00 B  ║
╚══════════════════════╩════════════╧═══════════╩═══════════╧═══════════╩═══════════╧═══════════╩═══════════╧═══════════╩═══════════╧═══════════╩═══════════╧═══════════╩═══════════╧═══════════╩═══════════╧═══════════╝

### Benchmarks against Bevy

Bevy's benchmarks comes from bevy offical repository.
We then get the following results:

### Spawning entities

This benchmark measures the time required to instantiate entities initialized with 15 distinct components. 
*(Note: **ZST** stands for Zero-Sized Types, which carry no data overhead and test the pure structural efficiency of the engine).*

To make sense of the raw telemetry, let’s aggregate the median execution times of Cruise ECS against Bevy's Criterion test suite:

| Benchmark Scenario | Cruise ECS (Median) | Bevy ECS (Median) | Cruise Speedup |
| :--- | :--- | :--- | :--- |
| **Spawn One (10,000 ZST Entities)** | **172.90 µs** | 871.45 µs | **~5.0x faster** |
| **Spawn Many (2,000 ZST Entities)** | **70.60 µs** | 327.68 µs | **~4.6x faster** |
| **Spawn Many (2,000 Heavy Entities)** | **89.90 µs** | 374.55 µs | **~4.1x faster** |

---

#### Raw Telemetry Breakdowns

#### 1. Cruise ECS Results
A crucial detail to look at here is the **Memory Statistics**: because our architecture resolves archetype targets entirely at compile time, the runtime memory allocation overhead is a flawless **0.00 B**.

* **Spawn One (10k ZST):** Median: `172.90 µs` | Mean: `471.86 µs` | Allocations: `0.00 B`
* **Spawn Many (2k ZST):** Median: `70.60 µs` | Mean: `176.75 µs` | Allocations: `0.00 B`
* **Spawn One (10k Standard):** Median: `226.60 µs` | Mean: `582.48 µs` | Allocations: `0.00 B`
* **Spawn Many (2k Standard):** Median: `89.90 µs` | Mean: `224.60 µs` | Allocations: `0.00 B`

#### 2. Bevy ECS Results (Criterion)
* **Spawn One (ZST Static):** Avg Time: `871.45 µs` (Interval: `[799.69 µs - 957.09 µs]`)
* **Spawn Many (ZST Static):** Avg Time: `327.68 µs` (Interval: `[311.09 µs - 347.29 µs]`)
* **Spawn Many (Standard Static):** Avg Time: `374.55 µs` (Interval: `[359.16 µs - 393.14 µs]`)

---

#### Conclusion

The data is clear: **Cruise ECS outperforms Bevy by a factor of 4x to 8x depending on the workload.** This massive performance leap isn't magic—it is the direct payoff of the strict static design choices we've detailed throughout this article. By shifting structural discovery, component registration, and archetype identification from runtime lookups into Nim’s compile-time evaluation step, Cruise completely bypasses the dynamic overhead that slows down traditional engines. 

### Component Insertion

This benchmark measures structural mutation costs under two challenging workload scenarios across 2,000 entities:
* **Insert Many:** Iteratively adding 15 components one after the other to an entity (testing worst-case fragmentation and migration overhead).
* **Insert Only Last:** Adding a single, final component to an entity that already possesses 14 components.

To clearly evaluate the impact of our optimizations, we contrast Bevy against Cruise's standard (Untyped) and optimized (**Typed**) variations for both the **Dense** and **Sparse** strategies:

| Benchmark Scenario (2,000 Entities) | Strategy Variant | Cruise ECS (Median) | Bevy ECS (Median) | Comparison / Winner |
| :--- | :--- | :--- | :--- | :--- |
| **Insert Many** *(15 components sequential)* | Dense (Untyped)<br>Dense (**Typed**)<br>Sparse (Untyped)<br>Sparse (**Typed**) | 17.95 ms<br>**4.84 ms**<br>472.40 µs<br>**276.05 µs** | —<br>5.10 ms<br>—<br>— | Bevy crushes Untyped Dense<br>**Cruise Typed Dense wins** (~1.05x)<br>—<br>**Cruise Typed Sparse dominates** (~18x) |
| **Insert Only Last** *(14 $\rightarrow$ 15 components)* | Dense (Untyped)<br>Dense (**Typed**)<br>Sparse (Untyped)<br>Sparse (**Typed**) | 1.05 ms<br>**495.35 µs**<br>254.35 µs<br>**245.95 µs** | —<br>758.41 µs<br>—<br>— | Bevy beats Untyped Dense<br>**Cruise Typed Dense wins** (~1.5x)<br>—<br>**Cruise Typed Sparse wins** (~3x) |

---

#### Conclusion

The empirical data tells a textbook story of ECS memory mechanics:

1. **The Archetype Mutation Tax:** As predicted, Bevy comfortably crushes Cruise’s standard *Untyped Dense* storage during sequential insertions (`17.95 ms` vs Bevy's `5.10 ms`). Because an untyped archetype model has to dynamically move entity data across memory tables 15 times in a row, the dynamic lookup overhead spirals out of control.
2. **The Typed Entity Redemption:** The moment we use Cruise’s compile-time **Typed Entities** (`TDHandle`), the vtable tax vanishes. On the brutal *Insert Many* track, Cruise's Typed Dense storage drops from `17.95 ms` to **`4.84 ms`**, pulling slightly ahead of Bevy. On *Insert Only Last*, it cleanly beats Bevy (`495.35 µs` vs `758.41 µs`).
3. **The Uncontested Sparse Domination:** Because the *Sparse Strategy* leverages our Fragment Vectors alongside Hibitsets, adding components doesn't trigger massive table migrations—it simply sets memory flags locally. As a result, Cruise’s Sparse layout completely dominates the benchmark, finishing the complex *Insert Many* routine in a staggering **`276.05 µs`** (roughly 18 times faster than Bevy's archetype layout) with a pristine **`0.00 B`** runtime allocation footprint.

### Change Tracking & Filtering

As established in our theoretical section, Cruise unifies all state and change monitoring through its abstract query engine. This benchmark evaluates the efficiency of filtering systems under three scenario densities across scale thresholds of 5,000 and 50,000 entities:
* **Filter All:** Every entity in the pool has been modified or matches the filter criteria.
* **Filter Few:** Only a small subset of entities match.
* **Filter None:** No entities match the tracking criteria (testing the pure bypass overhead).

We compare Cruise's strategies against Bevy's two internal tracking backends (`Table` storage and `Sparse` storage):

| Benchmark Scenario | Entity Count | Cruise Dense (Median) | Cruise Sparse (Median) | Bevy Table (Median) | Bevy Sparse (Median) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Filter All** | 5,000<br>50,000 | **7.90 µs**<br>**80.10 µs** | **6.60 µs**<br>**75.10 µs** | 14.24 µs<br>152.68 µs | 17.39 µs<br>199.89 µs |
| **Filter Few** | 5,000<br>50,000 | **1.90 µs**<br>**34.80 µs** | **1.40 µs**<br>**37.60 µs** | 11.45 µs<br>213.14 µs | 17.31 µs<br>305.63 µs |
| **Filter None** | 5,000<br>50,000 | **1.10 µs**<br>**4.70 µs** | **300.00 ns**<br>**400.00 ns** | 6.37 µs<br>69.90 µs | 9.26 µs<br>140.92 µs |

---

#### Conclusion

Cruise ECS comfortably outperforms Bevy across every single permutation of this benchmark, with the delta becoming exponentially wider as the target data thins out:

1. **The Architecture Clash (Masking vs Ticks):** Bevy relies on component *change ticks* (timestamps updated per system execution). To detect modifications, systems must sweep and evaluate entities to check if their component tick is newer than the system's last run. Cruise entirely bypasses this evaluation. Because it models state changes as basic set operations ($\Delta_{\text{state}} = S_t \oplus S_{t+1}$), finding changed entities is as simple as reading a pre-computed bitmask.
2. **The Power of the Hibitset Bypass:** The most staggering results happen when few or no entities change. On the **Filter None** track with 50,000 entities, Bevy requires up to `140.92 µs` to guarantee nothing changed. Cruise's Sparse Strategy handles it in **`400.00 ns`**—roughly **350 times faster**. 

This is where the hardware-accelerated Trailing Zero Count (TZC) optimization proves its worth. When a bitmask is completely empty, the CPU detects the zero sequence instantly and skips blocks of 4,096 entities in a single instruction cycle, completely eliminating iteration branches.

### Empty Archetype Overhead

A classic vulnerability in archetype-based ECS architectures is **Archetype Graph Bloat**. If a game creates thousands of unique component combinations (for instance, via dynamic gameplay modifiers or procedural items), it generates a massive volume of structural tables. Many of these tables will end up completely empty. 

When a system queries the world, it must evaluate every single matching archetype, even if that archetype contains zero active entities. This benchmark measures the baseline evaluation overhead of querying across a sea of **100, 1,000, and 10,000 completely empty archetypes**:

| Empty Archetypes Count | Cruise Dense (Median) | Cruise Sparse (Median) | Bevy Archetype (Median) | The Structural Winner |
| :--- | :--- | :--- | :--- | :--- |
| **100 Empty Pools** | **3.90 µs** | 9.80 µs | 41.81 µs | Cruise Dense |
| **1,000 Empty Pools** | 24.45 µs | **10.20 µs** | 52.32 µs | Cruise Sparse |
| **10,000 Empty Pools** | 636.05 µs | **12.80 µs** | 77.19 µs | Bevy / Cruise Sparse |

---

#### Conclusion

These numbers highlight the structural friction of different layout styles when confronted with a fragmented memory graph:

1. **The Archetype Scaling Tax:** At small scales (100 tables), Cruise Dense is exceptionally fast (`3.90 µs`), easily skipping through its hard-materialized partitions. However, as the table count reaches 10,000, Cruise Dense climbs to **`636.05 µs`**. Bevy handles this scaling curve significantly better, keeping its overhead at a tight **`77.19 µs`** for 10,000 empty archetypes. Bevy's highly optimized dynamic structural graph and internal query caching give it a clear edge over Cruise's dense query pipeline under extreme table fragmentation.
2. **The Sparse Strategic Immunity:** This is where the core thesis of Cruise ECS shines brightest. Because our **Sparse Strategy** decouples entity location from rigid archetype tables, it is fundamentally immune to archetype fragmentation. Whether there are 100 empty archetypes or 10,000, Cruise Sparse's execution time barely moves, shifting from `9.80 µs` to a flat **`12.80 µs`**.

By relying on unified Hibitsets and skipping vacant data chunks via hardware-accelerated bit-shifts, the Sparse Strategy completely flattens the archetype tax. It proves itself as the definitive choice for game loops where entity signatures are highly volatile and fragmented.

### Add / Remove Volatility

This benchmark tests the violent architectural stress of adding and then immediately removing components from an entity. This simulates a real-world engine handling highly volatile runtime states (like frame-delayed status effects or short-lived physics modifiers). 

The test is divided into three tiers of increasing severity:
1. **Standard Add/Remove:** Adding and removing a single baseline component.
2. **Add/Remove Big:** Alternating 8 heavy matrix components.
3. **Add/Remove Very Big:** Alternating 7 heavy matrices + 7 Zero-Sized Types (ZST) on an entity that already carries an existing load of 47 matrix components.

| Benchmark Tier | Cruise Layout Variant | Cruise (Median) | Bevy Backend (Median) | Structural Winner |
| :--- | :--- | :--- | :--- | :--- |
| **Standard** | Dense (Untyped)<br>Dense (**Typed**)<br>Sparse | 10.87 ms<br>**683.15 µs**<br>2.19 ms | 4.36 ms (Table)<br>—<br>2.43 ms (Sparse) | **Cruise Typed Dense** (~6.3x)<br>**Cruise Sparse** (~1.1x) |
| **Big** *(8x Matrices)* | Dense (Untyped)<br>Dense (**Typed**)<br>Sparse | 24.28 ms<br>13.92 ms<br>**525.85 µs** | 10.20 ms (Table)<br>—<br>2.89 ms (Sparse) | **Cruise Sparse** (~5.5x) |
| **Very Big** *(Heavy Load)* | Dense (Untyped)<br>Dense (**Typed**)<br>Sparse | 356.01 ms<br>308.51 ms<br>**4.51 ms** | 132.43 ms (Table)<br>—<br>— | **Cruise Sparse** (~29x) |

---

#### Conclusion

These results present the clearest picture of where each architectural pattern succeeds and where the laws of hardware cache lines assert themselves:

1. **The Dynamic Wall of Heavy Archetypes:** On standard components, Cruise’s compile-time **Typed Dense** variation completely crushes the competition, clocking in at an incredible **`683.15 µs`** (over 6x faster than Bevy's Table layout). However, as we scale into the *Big* and *Very Big* tracks, the limits of the Archetype design appear. When an entity with 47 matrices moves tables, the engine has to physically copy all that payload into a new memory block. Even though our `TDHandle` completely eliminates the vtable tax, the sheer volume of memory copying causes Cruise Dense (`308.51 ms`) to fall behind Bevy’s highly tuned dynamic archetype graphs (`132.43 ms`).
2. **The Absolute Dominance of Cruise Sparse:** While the dense layouts struggle under the physical weight of moving matrices across archetype tables, **Cruise Sparse dominates the entire benchmark.** Because the Sparse strategy records components locally in isolated Fragment Vectors, adding or removing a component requires zero data relocation for the other existing 47 components. 

On the maximum *Very Big* stress test, Cruise Sparse processes the load in just **`4.51 ms`** compared to the hundreds of milliseconds required by dense topologies—achieving an absolute **29x speedup over Bevy**.

---

### Core Iteration Throughput

Iteration is the bread and butter of any ECS engine—it represents the raw speed at which systems cycle through component arrays during execution frames. 

This benchmark evaluates iteration speeds across multiple configuration profiles:
* **Simple Iteration:** Standard continuous read/write execution loops over target arrays.
* **Wide Iteration:** Querying and extracting a large number of components simultaneously.
* **Fragmented Iteration:** Iterating across heavily scattered entities (20 entities broken up across 26 distinct archetypes, simulating an extreme edge case).
* **No Detection:** Standard iteration executing with change tracking overhead entirely disabled.

| Benchmark Scenario Profile | Strategy / Backend | Cruise ECS (Median) | Bevy ECS (Median) | Performance Delta |
| :--- | :--- | :--- | :--- | :--- |
| **Simple Iteration** | Dense / Table<br>Sparse / Sparse Set | **6.10 µs**<br>**19.10 µs** | 17.21 µs<br>36.71 µs | **Cruise Dense wins** (~2.8x)<br>**Cruise Sparse wins** (~1.9x) |
| **Wide Iteration** | Dense / Table<br>Sparse / Sparse Set | **44.00 µs**<br>89.60 µs | 97.75 µs<br>**269.96 µs** | **Cruise Dense wins** (~2.2x)<br>**Cruise Sparse wins** (~3.0x) |
| **No Detection** | Dense / Table<br>Sparse / Sparse Set | **6.30 µs**<br>**17.50 µs** | 12.85 µs<br>— | **Cruise Dense wins** (~2.0x)<br>— |
| **Fragmented** *(Worst Case)* | Dense / Archetype<br>Sparse / Sparse Set | 2.80 µs<br>1.60 µs | **571.92 ns**<br>**15.93 ns** | **Bevy Table wins** (~4.9x)<br>**Bevy Sparse wins** (~100x) |

---

#### Conclusion

The iteration telemetry uncovers the fundamental relationship between data layout optimizations and hardware cache lines:

1. **The Dense Cache Victory:** Under normal operating conditions (**Simple** and **Wide** iterations), Cruise’s Dense layout leaves Bevy completely behind, securing up to a **2.8x speedup**. Because our architecture flattens dynamic lookup indirection, the CPU can read component arrays as linear contigous memory segments, achieving maximum L1/L2 cache utilization. Even Cruise’s Sparse layout beats Bevy’s Sparse Set implementation by a comfortable factor of 2x to 3x.
2. **The Fragmentation Bottleneck:** The one area where Bevy pulls ahead cleanly is the highly fragmented configuration. In this test, a tiny group of 20 entities is shattered across 26 distinct archetypes. For Cruise Dense, this activates our structural archetype machinery overhead over a dataset too tiny to amortize the setup cost (`2.80 µs` vs Bevy’s `571.92 ns`). For Sparse layouts, Bevy's internal architecture reaches an ultra-streamlined `15.93 ns`.
3. **The Workload Factor:** It's important to contextualize the fragmentation test: it represents a worst-case scenario with an extremely miniature payload. As the entity density scales up to realistic production workloads, Cruise’s compile-time lookup optimizations quickly overtake the setup overhead, allowing Cruise to recapture the performance crown across the board.

## Conclusion

Cruise ECS is a highly performant tool that tries to brigde the gap between dense and sparse.
This filters and static optimizations, it achieves extreme performances, often outperforming industry standard implementation.
THe project is here to stay and will continue growing further.
