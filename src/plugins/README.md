# Cruise: Plugins

Plugins are at the heart of Cruise’s architecture. They define how systems are executed, which can run in parallel, and which must run sequentially.
In Cruise, plugins are modeled as a DAG: each vertex represents a system, and each edge represents a dependency.

Using Kahn's algorithm, Cruise computes **topological levels** (groups of systems whose dependencies have all been satisfied in previous levels). This allows safe parallel execution of systems.

## Systems

A system is a subtype of `PluginNode` and provides:

* **Status:** error, OK, uninitialized
* **Error handling**
* **Options** like enabling/disabling the system or forcing it to run on the main thread (some tools require this)

Systems are built around the `EffectivePluginNode` concept, which requires implementations for:

* `awake`: Initialize the system
* `update`: Run the system every frame
* `shutdown`: Stop the system and release resources
* `getObject`: Return the system’s object
* `getCapability`: Provide an interface for dependent systems

## Capability

A capability is the interface a system exposes to its dependencies. For example:

```nim
type
  MySys = object of PluginNode
    count: int
    value: int

method update(s: var MySys, dt: float) =
  s.count += s.value

## In a dependent system

var dep = node.getDependency[MySys]()
dep.value = 1
dep.count = 0  # Modifying count here can break MySys unexpectedly
```

Using capabilities makes this safer:

```nim
type
  Incrementer = ref object
    value: int

  MySys = object of PluginNode
    count: int
    cap: Incrementer

method getCapability(s: MySys): Incrementer = s.cap
method update(s: var MySys, dt: float) =
  s.count += s.cap.value

## In a dependent system

var inc = node.getDependency[MySys]() # Only access the interface provided
inc[].value = 1
```

With this approach, multiple independent plugins can interact safely, without risking corruption of internal state.

## Game logics

Game logics can easily be created as systems in the graph. They are as important as any other system.
Since no one probably want to write to much boilerplate just for a logic so we provide the `gameLogic` macro:

```nim
gameLogic MyLogic:
  var deps = getDependency[SomeDepsType](self)

  ## Some code

var logic:MyLogic
```

## World data

Now that we have talked about plugin's logic and dependencies between them the concern now would be about data races.
What if 2 plugin access some data at the same time ?
If we just use this we would have to use costly locks.

so in order to solve that Cruise plugin system introduce **Resources** and a **Resources DAG**.

So a resource is some global data that a system may request in order to use it.
It can be anything that is typed.

```nim
myPlugin.addResource(myResource)
```

So now for a given plugin node `MySys` we now have:

```nim
myPlugin.addWriteRequest(MySys, MyResource)

gameLogic myLogic Read[Res1, Res2], Write[Res3]:
  var res = getResource[Res1](self)
  # My logics
```

Once it's done a resource DAG is etablished to make safe resources access.

An example that may help grasping this is assuming resource are components in an ECS.
we will then have

```nim
myPlugin.addReadRequest(MySys, Transform, Velocity)
```

Except that you're not limited to components, you can for example use it for safe access to a SceneTree. 

Then the dependency DAG and resource DAG are used to compute the final execution order of the systems.
Both graphs are dynamic. You can change dependencies between systems at runtime and the data they access but it's recommended to do it in one phase then at the next call to `update` the graph will detect the changes and recompute the correct order.