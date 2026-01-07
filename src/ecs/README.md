# Cruise ECS

Actually, Cruise isn't an ECS based game engine kernel, so why am I making this ?
Because we need to exploit the plugin architecture.
Cruise ECS is there to give a solid base to anyone trying to build his engine while being completely optional (as we say, Cruis is not based on an ECS) and offers enough material to explore the Data store graph (a graph of layout, some being views into other layouts and other being combinations of layouts).

## Core: Fragment Vector

At his core, Cruise ECS use **fragment vector** which is a data structure that store blocks of data. It's actually like a sparse set but that store contiguous index in the same data block. On deletion it split the block and on insertion it can fuse them again if necessary.

But the version of this data structure is a more hardcore version with constant block size, no gap lesser than a block size between blocks, etc.
This gives extra fast performances and is perfectly adapted for our use case.

Here are some benchmarks results:

```
CPU Time [Create blocks 10] 20.0ns with 16.0140625Kb
CPU Time [Get blocks 10k] 9489.9ns with 0.0Kb
CPU Time [Insertion 10k] 27139.9ns with 0.0Kb
CPU Time [Random Access 10k] 25920.0ns with 0.0Kb
CPU Time [Sequential Iter 10k] 15920.0ns with 0.0Kb
```

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

