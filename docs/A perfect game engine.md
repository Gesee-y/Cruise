# A Perfect Game Engine

Game engines are tools, or sets of tools, designed to build games. In theory, they are meant to let developers create as many kinds of games as they want — building worlds, making games where imagination is the only limit, where only skill and creativity matter.

But in practice, they often suffer from the same recurring problems:

* Technical debt
* Performance bottlenecks
* Rigidity
* Tight coupling
* Opaque abstractions

Because of this, developers frequently decide to build their own engine to fix what they see as inefficiencies in existing ones. It's easy to think: "Those custom engines are just shallow reimplementations of existing solutions and will eventually be abandoned."

But the reality is different. While the trend toward custom engines has drastically declined these days, some studios still use them (Minecraft, Rockstar, Capcom, etc.).

So why is building your own engine now a marginal idea that most people frame as "for learning purposes" rather than "to build a game"?

The answer is actually pretty simple. Building a game engine is an incredibly difficult and time-consuming project. Developers usually spend more time on the engine than on the game they want to build. Commercial engines like Unity, Unreal, and Godot have decades of optimization, refactoring, and updates behind them, backed by an immense community. This makes it hard to compete with any custom game engine.

But those engines have their flaws, as we saw earlier, and some games may require highly custom features that the engine simply doesn't have. Since building an alternative is too expensive, it's usually easier to find workarounds rather than rolling your own engine.

So in this article, I ask myself whether we can get around this. Rather than always having to endure current engine bottlenecks, could we have one final, perfect game engine — one that fixes everything from the start? An engine that matches every possible game and adapts perfectly to your project.

Could this ideal actually exist?

* An engine that is efficient and extensible
* An engine that lets everyone choose their own style without descending into anarchy
* An engine that provides freedom with structure
* An engine free of technical debt and resistant to accumulating it
* An engine that supports every platform without extra work
* An engine capable of handling any game

This is the ideal every engine developer aims for, but reality always pulls us back. Trade-offs are unavoidable.

* Freedom or structure
* Coupling or complexity
* Extensibility or control
* Performance or ease of use

These tensions are exactly why the "perfect engine" remains a dream. It's like a toolkit: you can't make a single tool that does every job as well as a tool specifically built for that task. But what if that was actually the mistake? What if we were too focused on the tasks and not enough on the tools? What if we just weren't looking at the problem from the right angle?

---

## How Do We Get There?

Simple. Stop focusing on tools to make games. Focus on tools to make engines.

That idea is not new. Libraries like SDL or SFML already exist for this reason. The challenge is to strike a balance: high-level enough to reduce friction and avoid dealing with low-level details, yet low-level enough to remain fully configurable.

These goals appear contradictory. If we're not low-level enough, we lose flexibility. If we're too low-level, usability collapses. At first glance, this looks like a dead end.

So should we stop complaining about game engines and simply accept the trade-offs? Obviously not. Otherwise, this text wouldn't exist.

There is one massively underestimated force behind successful engines — especially one that hobby engines often forget: **community**. Not to build the engine itself, but to build the high-level layers on top of it.

When you start making a game, you don't begin by learning how a renderer works internally. You pick a tool that lets you move fast. Our framework should work the same way. Instead of guessing how low-level users want to go, we provide ready-made tools that can be used immediately, while still allowing low-level developers to find pleasure in hacking everything.

This naturally leads to the concept of plugins, now common in most engines. So that's it, right? Just add plugins and everything becomes possible — a 2D platformer plugin, a text game plugin, an RPG plugin. These are common things. So have we found the solution?

Not quite.

---

## Why Plugins Are Not Enough

Plugins are still coupled to the engine's architecture. They are hosted by the engine and constrained by it. They often lack real power. For example, Bevy plugins cannot bypass the ECS.

To put it simply: regular engines *host* plugins; our framework should be *built* by plugins.

If we want true flexibility, plugins must be able to ignore — or at least not be constrained by — the engine's internal architecture. At the same time, plugins must integrate seamlessly. Another contradiction.

---

## The Architecture Is the Engine

One viable solution is to define the plugin architecture itself: how plugins communicate, interact, and depend on each other. This architecture does not dictate how plugins are internally implemented. It only defines the minimal contract they must respect.

Bevy uses ECS as this contract. Godot uses extension interfaces. These approaches work, but they still introduce coupling because plugins remain separate from the engine.

What we want instead is for the architecture itself to *be* the engine. That gives us the following requirements:

- An architecture that does not undermine other architectures
- A clear and structured way for plugins to communicate
- Protection against anarchy
- Ease of use

This is the missing piece.

---

## A Short Detour

Apache Airflow is a platform for building services composed of workflows. It is scalable, dynamic, has no runtime locks, and enforces clean, decoupled tasks.

The analogy should already be obvious.

We need a DAG, or workflow-based, architecture.

---

## DAG Architecture

We model the engine as a graph of systems (nodes) connected by dependencies (edges). Each system declares zero or more dependencies. A scheduler can then parallelize execution using a simple topological sort.

The benefits are clear:
- The architecture *is* the engine
- Features are added as nodes in the graph
- All systems are on equal footing
- No imposed internal architecture: systems can use ECS, OOP, or anything else internally

Problem solved? No.

In a platformer, for example, gravity or physics constraints may need to be modified dynamically. More generally, dependent systems sometimes need to feed data back into their dependencies. In a multithreaded environment, this is dangerous. So what do we do?

---

## Message Passing

Systems can only access their dependencies, but if we let them modify those dependencies to solve our feedback problem, we end up with two issues:

* This can cause race conditions if multiple systems try to modify the same dependency simultaneously.
* We still can't access systems that aren't in the current node's graph.

A way to solve both of these is to use **message passing**, a concept from **Event-Driven Architecture**. This allows any system to have an impact on another by simply passing a message onto the bus. Wherever the target system is, it will catch the message at some point — on the next run if it's earlier in the graph, or the current run if it's later — and act accordingly.

But aren't we just inheriting all the problems of event-driven architecture?

* Unknown ordering
* Traceability hell
* Unstable system ordering
* Copies and no mechanism to handle shared data

...

Wait — haven't we already solved the first three issues with our DAG? That's the magic. We get the best of EDA without its pain points. But we still have the shared data issue.

---

## Dual DAG Architecture

We now have a global resource registry where shared data will be stored. In order to make access to it thread-safe, we not only use a DAG to organize tasks, but define a second DAG on the same set of vertices (game systems) that defines their access to data. Each system specifies what it needs to run, what it reads, and what it modifies. Through topological sorting, the engine can compute a thread-safe execution order for all systems.

So here we are. We have our holy grail: a double DAG architecture.

- Each system is isolated.
- Dependencies are declared.
- Access is secured.

This seems perfect on paper, but it yields a significant problem that can't be ignored.

---

## Temporal Coherency

Let's take a simple case. Assume we have a system in our magnificent DAG that, for some reason (a lock, a condition, etc.), halts its execution until resumed. Whether the system that should resume it comes before or after it in the graph, we are unable to continue executing the DAG because we are soft-locked until it unlocks.

We might say "just skip it and continue," but that creates a **temporal coherency problem**: a system is at a point in the graph where it shouldn't be, holding data it shouldn't possess at that moment. We have no way of knowing when the system will resume, so we can't guarantee it won't cause data races, especially if we end up with multiple instances of the same systems running at the same time.

This may seem like an impossible problem to solve, yet the solution is incredibly simple with our dual DAG.

---

### Execution Conditions

The solution is something that will make architectural purists scream, and it might sound completely contradictory to our Dual DAG philosophy — but here it is: we need locks.

Woah, wait! Don't close the tab yet! Let me explain.

What we actually need are **Execution Conditions** for our systems. When a condition isn't met, it acts like a spinlock (just a way to say it, because technically we spin, just that we do work instead of asking again and again). The plugin is simply put into a `NotReady` status, and this status is immediately propagated down to its dependents.

*Objection: Won't spinning like this waste massive amounts of CPU power?*

And that is the beauty of the trick: absolutely not.

While a system's execution conditions are not met, the scheduler doesn't freeze. It simply bypasses that node and continues executing other independent branches of the graph. The rest of the engine moves on as if nothing happened. Only the direct dependents of the locked system need to react — by skipping their own execution, using cached data from the previous frame, etc.

This completely resolves our spatial coherency issue. Resuming a paused system becomes perfectly safe, all while leveraging the full power of our Dual DAG.

- A system waiting for an async network callback? It just reports `NotReady` until the data arrives.
- A system waiting for a heavy asset to load? `NotReady`.

Now, it is a well-known rule in game development that achieving 100% thread safety in a multithreaded environment is practically impossible — nothing stops a rogue developer from launching a background task that mutates data out of order. But in our case, we actually *can* guarantee it. Through one subtle trick.

---

### Resource Borrow Checking

The rule is absurdly simple.

Any task — whether it is a standard system, a rogue background thread, or a duplicate execution — can borrow multiple resources to read them. Furthermore, it cannot borrow a resource for reading if another system is currently writing to it, nor for writing if another one is already writing or reading.

This runtime borrow-checking mechanism (inspired by Rust's notoriously annoying yet brilliant compiler) makes our engine 100% thread-safe. Even if a paused system suddenly resumes at the worst possible moment, the registry will simply return `nil`/`None` if the requested resource cannot be safely acquired.

How to handle that `nil`/`None` fallback is up to the developer, but it allows the engine to maintain absolute, bulletproof thread safety without relying on heavy OS-level locks.

---

## Continuous System Execution

You may have noticed that our graph has an interesting property: it's continuous. The graph executes itself indefinitely in a tight game loop, without relying on traditional OS-level `sleep()` calls, or atleast without enforcing one.

This may seem strange. "If we no longer sleep the thread, how do we ensure a consistent framerate?"

The answer lies within our architecture: Execution Conditions. Systems can use time-based conditions to dictate their update rate. A renderer might say "I will only execute if 16ms have elapsed since my last run," while a physics system might require a 5ms tick.

Using their last execution timestamp as an anchor, systems simply report `NotReady` if their time hasn't elapsed. And because the scheduler bypasses `NotReady` nodes, the rest of the engine continues to run. While the renderer waits for its 16ms, an input system can run at staggering speeds, seamlessly capturing precise clicks that would otherwise fall between traditional frames. The CPU doesn't busy-wait in a blocked loop; it continuously does useful work across the graph, simply checking whether timed systems are ready to fire.

You might ask: "Why go through this instead of just sleeping at the end of each frame?"

Because sleeping is OS-dependent. An OS `sleep()` guarantees you sleep *at least* the requested duration, but the actual wake-up time varies based on the OS thread scheduler. This introduces unpredictable latency.

In our framework, timing relies on high-resolution CPU clocks rather than the OS scheduler. We get local pacing for each system instead of a global timer that dictates the pace of the entire engine pipeline.

And just like that, as a byproduct of our architecture, we've inadvertently allowed multiple systems to run at custom paces. While this seems incredible, it raises another issue: fixed timestep.

---

### Fixing Timestep in a Dual DAG

In our current architecture, since we don't rely on OS sleep, we have no way to guarantee a perfectly consistent pace for a system. Nothing guarantees that the local `dt` will exactly match the desired interval when the physics system is next allowed to run. Real time is messy and continuous.

So, how can we solve this? Using **Discrete Event Simulation**.

I know — I just gave a speech about how our graph is wonderfully continuous, and now I'm talking about making it discrete. Bear with me; I haven't lost my mind. Only part of the DAG is discrete. Let me explain.

The architecture introduces **Logical Time** for fixed-timestep systems. In our graph, logical time advances in discrete increments — a system's execution acts as a discrete event that ticks time forward. This logical time is local to the system and depends on its real-time constraints, which are enforced during the readiness test.

Let's take a concrete example: a physics system that needs to run every X ms. If the renderer takes too long and 2X ms pass in real time before the physics system executes again, logical time dictates that it must execute twice in a row to catch up to where the simulation should logically be.

If the system falls too far behind and cannot catch up — preventing the infamous "spiral of death" — it can set an `OVERRUN` status, letting its dependents know that the timeline has been compromised.

Because of this, the set of all logical times across the systems in the graph forms the true state of our DAG. Since time is now discrete and deterministic, it's now easier to travel through it. We more easily snapshot the state. We more easily roll back whenever we need to.

This is the power of our logical graph: deterministic system execution while still seamlessly matching real time.

---

## Traceability and Debuggability

This is one clear win of our architecture. With the multiple plugin statuses, the propagations, the borrow checking, and the timing, we've built a system that is easy to debug (since we can trace the exact flow of data), easy to profile, and easy to roll back.

This may seem like a footnote, but it comes in very handy when working on complex multithreaded architectures.

---

## So What Do We Have?

We spent a long time talking about perfection, but if we look concretely at what we have, we can see that we got... nothing. No renderer, no physics, no pathfinding.

Throughout this whole article, we defined our engine not as a set of features, but as the architecture that structures them while offering as much freedom as possible to developers.

So we don't leave empty-handed. We leave with an architecture that ensures the engine can last long and grow with the community. This is the architecture of **Cruise** — my engine for game engines, a framework to build engines.

Why don't we look at what this whole architecture looks like in practice?

---

## Timer Plugin

We will demonstrate a simple timer plugin. Let's think through what we need. We need to define a `Timer` type:

```nim
type Timer = object
  duration: float32
  signal: Cond
```

We use Nim's `sysCond` as a signal.

In order to be able to pause or resume our timer system, we will use messages. Let's define them:

```nim
type
  PauseTimer = object
  ResumeTimer = object
```

Now we can create our timer pool, which will be the resource containing all the timers:

```nim
type TimerPool = ref object
  timers: seq[Timer]
```

We use `ref` types because we want a global resource (and to avoid Nim's implicit copies).

So now we can set up our plugin:

```nim
# We create a new plugin
var TMPlugin* = newPlugin()

# Initialize our global pool
var TM = TimerPool()

# Utility functions for this timer functionality
proc addTimer(tp: var TimerPool, timer: Timer) =
  tp.timers.add(timer)

proc addTimer(tp: var TimerPool, dur: float): Timer =
  var c: Cond
  c.initCond()
  let timer = Timer(duration: dur, signal: c)
  tp.addTimer(timer)
  timer

proc addTimer(dur: float): Timer = addTimer(TM, dur)
template waitTimeout(t: Timer) = t.signal.wait()
```

Then we register our resource in the plugin:

```nim
let tmID = TMPlugin.res_manager.addResource(TM)
```

Let's now create our timer system:

```nim
# This returns the system ID in the plugin
discard newSystem(TMPlugin, TimerSystem[var TimerPool]):
  paused: bool
  lastResumed: int
```

We now just have to define our system update function:

```nim
method update(p: var TimerSystem) =
  # We access our timer pool.
  # If the resource is already borrowed by another system (which normally shouldn't happen,
  # as we discussed above), this returns None.
  var res = p.getWriteResource[:TimerPool]
  if res.isNone:
    p.setStatus(PLUGIN_WAITING)
    return

  # We set our system to an "ok" status, as it's functioning correctly
  p.setStatus(PLUGIN_OK)

  # If the system is paused, we check for a resume message
  let resume = p.bus.getMessage[:ResumeTimer]() # Returns an Option[CInstance[ResumeTimer]]

  if resume.isNone:
    if p.paused: return
  else:
    p.lastResumed = resume.timestamps[^1] # We get the timestamp of the latest resume message
    p.paused = false

  # Now we check for a pause message
  let paused = p.bus.getMessage[:PauseTimer]()
  if paused.isSome:
    # If the pause event happened after the latest resume,
    # it means the pause occurred more recently
    if paused.timestamps[^1] > p.lastResumed:
      p.paused = true
      return

  # We get our resource
  var tm = res.get()

  # Our timer update logic — nothing fancy
  var (start, stop) = (0, tm.timers.len-1)

  # The system's last execution time is automatically tracked
  let dt = (getMonoTime().ticks - p.lastTick).float * 1e-9 # We move per second

  while start <= stop:
    tm.timers[start].duration -= dt

    if tm.timers[start].duration <= 0:
      tm.timers[start].signal.signal()
      (tm.timers[start], tm.timers[stop]) = (tm.timers[stop], tm.timers[start])
      stop -= 1
    else:
      start += 1

  tm.timers.setLen(stop)
```

Finally, we just have to define our system shutdown function:

```nim
method shutdown(p: TimerSystem) =
  p.setStatus(PLUGIN_OFF)
  var tm = p.getWriteResource[:TimerPool]
  tm.get().timers.setLen(0)
```

And that is it. We built a functional, extensible, thread-safe, decoupled timer plugin. That's the magic of our architecture.

---

## So is that all ?

Well it would not be that cool if I just offered that in my project.
You can stop there if you just wanted to explore the main engine architecture.
But if you wanna see all the other niceties, just continue the journey :)


---
