# Server Client space example

For networked games, it's often necessary to attribute a specific space to entities coming from the server and those made by the client.
This means for example that in an online fighting game, we want to distinguish synchronized entities (the battlers for example) from local entities (the UI, etc).

## Hashmap 
So one simple way this has been using a hashmap or sparse set, IDs coming from the server where mapped to entities on the client side and vice versa.

```nim
var map: Table[NetworkID, Entity]
var reverseMap: Table[Entity, NetworkID]
for ents in world.query(...):
  if ents in reverseMap:
    # Do stuff with server obj
  else:
    # Regular local obj
```

This is obviously inefficient, we could think of another solutions using components but we ends up duplicating a lot of logic between distant and local objects.

## Entity ranges

Another better way popularized by Flecs is to use **Entity range**, this means that entities will only have ids within that range. This allows us to send ids to the clients and it would be instantly able to retrieve it.

```c
// Generate entities between 5000 and 6000
world.set_entity_range(5000, 6000);
```

So while this seems like the ultimate solution, Cruise ECS goes even further.

## Sparse storage

Cruise has one concepts that enable more reliable networking, which is **ids are memory slots**. This means for example that the id you recieved from a server map directly without indirection to a slot in memory.
This means that Cruise has **stable entities ID**.

This way making a rearrange basically map to preallocation entities in the sparse storage (as in the dense storage, entities moves make it more complicated.)

You may say "This will eat up memory", but no, preallocating entities without components doesn't allocate anything in any components pools.
So now both entities from the server and client benefits from change tracking, bitset operations, serialization, rollback and more as they manipulate the native bitsets of Cruise.

```nim
var entityPool = world.createSparseEntities(ENTITIES_COUNT)
var entitiesInUse = newQueryFilter()

# When a server ID is received, we retrieve the entity from the pool 
# via simple arithmetic and activate it in the filter.
# Now, we can query distant entities as if they were local.
```