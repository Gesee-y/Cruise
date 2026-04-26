# Cruise static optimization

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

We can push it even further by defining **compile time** archetypes.
From the multiple operations defined by the users, some archetypes can statically be inferred.
Writing `world.createEntity(Position, Velocity)` already tells the compiler that there will be a `{Position, Velocity}` archetypes, we can then initialize the ID at compile time.
This allows us to instantly get the correct archetype to spawn an entity without ANY lookup! Which makes entity creation even more faster.

We may be worrying that this would impact modding but not at all.
A type imported from a DLL for example still has to be used somewhere!
If it's used somewhere the compiler will automatically register it without any trouble as this would just need a recompilation or even just using the dynamic component registry API (for really exotic case.)

The downside of this approach is that:
  
  - it increase binary size
  - Slow down compilation
  - Generate a lot of specialized code

But that's generally easy to handle and not that annoying. 

There are still case where you would want to manually register components so Cruise still offers the function `registerComponent` which return the component poll id.