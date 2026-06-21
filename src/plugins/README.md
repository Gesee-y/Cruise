# Cruise: Plugins

Plugins are at the heart of Cruise’s architecture. They define how systems are executed, which can run in parallel, and which must run sequentially.
In Cruise, plugins are modeled as a **Dependency DAG**: each vertex represents a system, and each edge represents a dependency.

## Systems

A system is a subtype of `PluginNode` and provides:

* **Status:** error, OK, uninitialized
* **Error handling**
* **Options** like enabling/disabling the system or forcing it to run on the main thread (some tools require this)

Systems are built around the `EffectivePluginNode` concept, which requires implementations for:

* `awake`: Initialize the system
* `update`: Run the system every frame
* `shutdown`: Stop the system and release resources

## Capability

A capability is the interface a system exposes to its dependencies.
This is simply done through exported field.

```nim
type
  MySys = object of PluginNode
    count: int
    value*: int # Can only access `value`

method update(s: var MySys, dt: float) =
  s.count += s.value

## In a dependent system

var dep = node.getDependency[MySys]()
dep.value = 1 # Ok
dep.count = 0 # Error: Can't access `count`
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

so in order to solve that Cruise plugin system introduce **Resources** and an **Access DAG** that shows Cruise's dual DAG architecture.

So a resource is some global data that a system may request in order to use it. Resources here are global objects that will be used for the whole runtime of the program so they should not be volatile objects but singletons (preferably).
It can be anything that is typed.

```nim
myPlugin.addResource(myResource)
```

So now for a given plugin node `MySys` we now have:

```nim
myPlugin.addWriteRequest(mySysId, myResourceId)

newSystem myPlugin, mySystem[Res1, var Res2]:
  field0:T1
  # ...
  # mySystem fields
```

Once it's done a resource DAG is etablished to make safe resources access.

An example that may help grasping this is assuming resource are components in an ECS.
we will then have

```nim
myPlugin.attachSystem MySys[Transform, var Velocity]
```

Except that you're not limited to components, you can for example use it for safe access to a SceneTree, a global mesh manager or any object requiring thread safe access. 

Then the dependency DAG and resource DAG are used to compute the final execution order of the systems.
Both graphs are dynamic. You can change dependencies between systems at runtime and the data they access but it's recommended to do it in one phase then at the next call to `update` the graph will detect the changes and recompute the correct order.

## Race security

Let's assume you have a system that emit callbacks.
Since those callbacks aren't handled by the DAG, our current model can't ensure they don't conflit and create data race.
That's why Cruise plugin introduce a **runtime borrow checker** similar to rust. 
It ensure that multiple reader can have a resources but there should be only one writer even if those reader/writer aren't systems in the DAG.

```nim
var res = sys.getWriteResource[:MyResource] # Or getReadResource for read access
if not res.isSome:
  sys.setStatus(PLUGIN_WAITING)
```

The status is to notify depedent systems about what happened

## Temporal coherency

In order to make a simulation coherent, events should happen in a given order, that's temporal coherency. 
Given a point in real time, the simulation should be at a given state.
That state is the logical time.
The point where the simulation should **logically** be given the real time.

That's the principle of **discrete event simulation**
And Cruise plugin allows you to do that through **execution amounts** (how many time a system should execute to be in sync with the logical time) and **execution condition** that allows you to define when your system should execute

```nim
method isReady(sys: PhysiscSystem): bool =
  let ticks = getMonoTime().ticks
  let elapsed = (ticks - sys.lastTicks).float * 1e-9
  if elapsed > 0.005:
    sys.setExecAmount((elapsed div 0.005))
    return true

  return false
``` 

Through this we ensure the physic simulation is always in sync with the current point in logical time while giving the power to the developers to control how that time should be treated.
