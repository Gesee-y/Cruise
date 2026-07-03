# ECS Formaliztion: ECS Query-centric

## Definition

### Entity

An **entity** is an unique identifier for an object in the universe.
That idea is **unique** across time and space.
This means an identifier always correspond to the same entity.

That's called **identifier stability** and ensure the same id maps to the same memory slots
This is generally achieved through the couple:

*ID = (slot, generation)* which is uique for each entity

### Component

We define a **component** as a plain structure
Let **C** be the ordered set **{ci | i < k}** where *k* is the **total number of components** and *i* is the **component ID**
An entity can be associated to zero or many components

Let the function pc defined from (E, C) to {0, 1} such as: 

pc(e, ci) = 0 if e is not associated with component of id i
pc(e, ci) = 1 if e is associated with component of id i

Now let the function ps defined from E to N such as:

ps(e) = (pc(e, c0)pc(e, c1)...pc(e, ck))2 

The number *(pc(e, c0)pc(e, c1)...pc(e, ck))2* is the signature of the entity *e* in the world

## Query

We define a **query** as an operation that fetch every entities matching a given predicate.
The predicate can be anything, not limited (as seen in most ECS implementaion) to the presence of components.

Let Q be a query executed over the universe of entities E. This query returns a subset S of entities that match its criteria (S ⊆ E). 

If we have multiple queries Q1, Q2, ..., Qn yielding the respective entity sets S1, S2, ..., Sn, we can define their compositions as follows:

1. **Intersection**: Q1 ∧ Q2 ∧ . . . ∧ Qn ⇐⇒ Si = S1 ∩ S2 ∩ . . . ∩ Sn
2. **Union**: Q1 ∨ Q2 ∨ . . . ∨ Qn ⇐⇒ Si = S1 ∪ S2 ∪ . . . ∪ Sn
3. **Negation**: ¬Q ⇐⇒ E \ S

Because operations on queries map perfectly to operations on sets, we can state that **queries are isomorphic to sets**. Through query composition, we can programmatically model any mathematical set we want.

## Systems

We define a **system** as a functions that operates on the result of a query. Each system is associated to only one query.
There is not much to say about this.

# Primitives: Query

We distinguish 3 types of queries:

## virtual queries 

This consist of checking a predicate at each entities to know whether it match a given predicate or not.
We have this pseudo code:

```nim
for entity in allEntities:
  if predicate(entity):
    doStuff(entity)
```  

While this allows the best flexibiliy as predicate can be anything, constructed on the fly and combined as we want, it requires to check every entity against the predicate.
This was how old ECS implemented their, without any special trick, this quickly became a performance issue.

## soft materialized queries 

Here we keep a list of the entities matching a given predicate.
The entities matching the entities are recorded before hand and then when needed we just iterate on then.

```nim
for entity in entities_matching_predicate:
  doStuff(entity)
```

This is a problem when we need to compose query, but we can use bitsets to make them simple bitwise operations

```nim
for id in ent_matching_A and ents_matching_B:
  let entity = allEntities[id]
  doStuff(entity)
```

However doing this requires stable entities id (meaning that there is one single ID that don't moves and can reliably index an entity) which is something sparse sets natively have but archetype ECS... well in thos it's mostly an after thought.
As we noted earlier, our fragment vector enable id stability so we are good.

## hard materialized queries 

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

## Consequences

- Sparse ECS and Archetype ECS differ in their query materialization. They are both optimisations of the virtual case
- Materialization can be used given how much flexibility we want to trade for performances
- The components memory layout becomes irrelevant as long as **id stability is guarantee**, same id = same slot in memory, so grouping ID (with materialization for example) means grouping components.

# Relations

As relations are importants part of any ECS framework, in our query-centric ECS, we can use query compositions.

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

### Why This Matters: Representing Complex Structures

This mathematical result is huge. It means that complex, hierarchical data structures can be represented without specialized storage engines. 

For instance, a **tree structure**—traditionally defined as a collection of nodes paired with a set of children—can be elegantly expressed in Cruise ECS as a simple tuple: 

*Node = (e, Qchildren)*

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

# or with hard materialized queries and dynamic components
var e = world.createEntity(Transform, parentID) # assuming parentID exist as the id of the parent of `e`
for (bid, r) in world.denseQuery(world.query(Transform and parentId)):
  for i in r:
    # Modify children
```

Instead of storing hardcoded pointers to child nodes, a parent entity can simply hold a query that filters for its children dynamically. The implications for flexibility and data-oriented design are profound.

We can state this:

*Any data structure relying on sets can be expressed with queries, implying that they can efficiently be represented under our query-centric ECS model*

This means:

- Entities having a component ? A Query
- Change tracking ? A query
- A graph ? the tuple (entity, QchildsNode)
- A relation ? (entity, Qcompose(relation, target))
- Custom filter ? A query
- Rollback ? xor betweens queries

# Parallelism

This section concerns running multiple systems in parallel without causing data races.

We saw earlier that query are isomorphic to sets, so the result of a query is simply a set of entities. But we also explained earlier ID stability, meaning that an entity perfectly map to one memory slot in a pool.
This means that a query also return a set of memory slot which a system will access.
So for 2 systems intersecting queries means intersecting data access.

Let S be the set of all systems and Q the set of all queries and **qs** a function that map a system to a query.
Here we call **static queries** those who don't relate to the presence of components and **dynamic queries** those who don't.
A query can then be defined as q = qstatic inter qdynamic

Let **ws**, the function that return the set of components a system write and **rs** the set of components a system only read where:

*ws(s) = not rs(s)*

So let (s1, s2) a pair of systems.
They can run in parallel only if:

*(ws(s1) ∧ ws(s2)) ∨ (ws(s1) xor rs(s2)) = ∅* or *qs(s1)_dynamic ∧ qs(s2)_dynamic = ∅*

This offer a simple formula to know when systems can run in parallel.
The write set of a system can easily known so the first part is easy to calculate.
But for the dynamic part when the first part don't hold require more compute powers.

If those dynamic parts are hard materialized queries it's easy to prove as it just means showing they don't access the same memory region.
If they are soft materialized here we just have to compute the intersection (which is fast for bitsets) and see if it's equal to zero
If they are virtual ones, we can't compute the intersection without both on every entities which is obviously too slow except the user himself guarantee the framework that both are disjoint but this don't compose well with the others.
So just relying on the first 2 ones (or requiring the users to specifiy whether virtual queries are overlapping) already offers us more parallelization than most ECS frameworks
