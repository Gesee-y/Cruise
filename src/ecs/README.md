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
CPU Time [Mass Update 10k] 27320.0ns with 0.0Kb
```