# A Perfect Game Engine

Game engines are tools or sets of tools, designed to build games. In theory, they are meant to let developers create as many kinds of games as they want.
Bulding worlds, making games where your imaginations is the only limits. Where only your skills and creativity matters.
But in practice, they often suffer from the same recurring problems:

* Technical debt
* Performance bottlenecks
* Rigidity
* Tight coupling
* Opaque abstractions

Because of this, developers frequently decide to build their own engine to fix what they see as inefficiencies in existing ones. It's easy to think: "Those custom engines are just shallow reimplementations of existing solutions and will eventually be abandoned"
But the reality is different. While custom engines trend drastically declined these days, some studios still use custom game engines (Minecrast, rockstar, Capcom, etc).
So why is building his own engine now a marginal idea that most people just frame as "for learning purpose" and not as "to build a game" ?

The answer is actually pretty simple. Building a game engine is a incredibly difficult and time consuming project. Devs usually take more time on the engine than on the game they want to build.
Commercial engines like Unity, Unreal, Godot have decades of optimization, refactor, updates with an immense community.
This make it hard to sell any custom game engine to anyone.

But those game engines have their flaws, as we saw earlier, and some games may requires highly custom features that the engine just don't have but building an alternative is too expensive so it's usually easier to find workaround around the engine problem rather thant building your own one.

So in this article, I actually ask myself if we can't get around this. If rather than always having to endure the current engines bottlenecks, we could have one last perfect game engine, here to fix everything from start. An engine that match every possible game and adapt perfectly to your project.
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

These tensions are exactly why the “perfect engine” remains a dream.
It's like a tool kit. you can't make a tool that can to every work perfectly in the same manner like a tool perfectly built for that task.
But what if that was actually the mistake.
What if we were just too focused on the task and not on the tools.
What if we just didn't see the problem from the right angle ?

---

## How Do We Get There?

Simple.
Stop focusing on tools to make games.
Focus on tools to make engines.

That idea is not new. Libraries like SDL or SFML already exist for this reason. The challenge is to strike a balance: high-level enough to reduce friction and avoid dealing with low-level details, yet low-level enough to remain fully configurable.

These goals appear contradictory. If we are not low-level enough, we lose flexibility. If we are too low-level, usability collapses. At first glance, this looks like a dead end.
So should we stop complaining about game engines and simply accept the trade-offs?
Obviously not. Otherwise, this text would not exist.

There is one massively underestimated force behind successful engines—especially one that hobby engines often forget:
Community.
Not to build the engine itself, but to build the high-level layers on top of it.
When you start making a game, you do not begin by learning how a renderer works internally. You pick a tool that lets you move fast.
Our framework should work the same way. Instead of guessing how low-level users want to go, we provide ready-made tools that can be used immediately while still allowing low level dev find their pleasure in hacking everything.
This naturally leads to the concept of plugins, now common in most engines.
So that’s it, right? Just add plugins and everything becomes possible. A 2D plateformer plugin, text game plugin, rpg plugin, thos are common things.
So have we found the solution ?

Not quite.


---

## Why Plugins Are Not Enough

Plugins are still coupled to the engine’s architecture. They are hosted by the engine and constrained by it. Often, they lack real power. For example, Bevy plugins cannot bypass the ECS.
So to put it simply, regular engines host plugins, our framework should be **built** by plugins.

If we want true flexibility, plugins must be able to ignore or at least not be constrained by the engine’s internal architecture.
At the same time, plugins must integrate seamlessly.
Another contradiction.

---

## The Architecture Is the Engine

One viable solution is to define the plugin architecture itself: how plugins communicate, interact, and depend on each other.
This architecture does not dictate how plugins are internally implemented. It only defines the minimal contract they must respect.

Bevy uses ECS as this contract. Godot uses extension interfaces. These approaches work, but they still introduce coupling because plugins remain separate from the engine.

What we want instead is for the architecture itself to be the engine.
That gives us the following requirements:

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
- The architecture is the engine
- Features are added as nodes in the graph
- All systems are on equal footing
- No imposed internal architecture: systems can use ECS, OOP, or anything else internally

Problem solved?
No.

In a platformer, for example, gravity or physics constraints may need to be modified dynamically. More generally, dependent systems sometimes need to feed data back into their dependencies.

In a multithreaded environment, this is dangerous.
So what do we do?

---

## Interfaces and Capabilities

Systems can only access their dependencies, but they should not be allowed to do anything with them.
Each system exposes an interface, the only thing other systems can see. Access is further restricted using capabilities, primarily:

- Read
- Write

Some data is read-only, some can be modified.

This raise 2 problems:
- Thread safety. A borrow-checker-like mechanism would help, but this is impractical outside of Rust. Locks or FIFO queues are viable alternatives.
So what can we do about it ?
- Where is our data ? Plugin will have to share data between them, where will they be stored ? who owns them ?

This is our last rampage and the solution seems clear.

---

## Dual DAG Architecture

We now have a global resource registry where shared data will now be stored.
In order to make access to it thread safe, we not only use a DAG to organize task, but define a second DAG on the same set of vertices (game systems), that define their access on data.
Each system specify what he needs to run, what it reads and it modifies and through topological sorting, the engine can compute a thread safe order to execute all the systems

So here we are. We have our holy grail.
A double DAG architecture.
Each systems are isolated.
Dependecies are declared.
Access are secured.
This seems perfect one the papers but yield an big problem that just can't be ignored.

---

## Spatial coherency

Let's take a simple case. Assume we have a system in in how magnificient DAG that for some reason (lock, condtion, etc) stop it's execution until resumed.
Whethever the system that should resume it is before or after it, we are unable to continue executing the DAG because we are softlocked until it's unlocked.
We may just say "we just ignore it and continue" but now it create this **temporal coherency problem**.
We are unable to know when the system will resume, so unable to guarantee it will not cause deadlock.

This may seems like an impossible problem to solve yet... is incredibly easy in reality to slove with our dual DAG.

---

### Execution condition

The solution is something that will make architectural purists scream, and it might sound completely contradictory to our Dual DAG philosophy, but here it is: we need locks.

Woah, wait! Don’t close the tab yet! Let me explain!

What we actually need are Execution Conditions for our systems. When a condition isn't met, it acts like a non-blocking spinlock. The plugin is simply put into a NotReady status, and this status is immediately propagated down to its dependencies.

Objection: Won't spinning like this waste massive amounts of CPU power?

And that is the beauty of the trick: absolutely not.

While a system's execution conditions are not met, the scheduler doesn't freeze. It simply bypasses that node and continues executing other independent branches of the graph. The rest of the engine moves on as if nothing ever happened. Only the direct dependencies of the locked system have to react (by skipping their own execution, using cached data from the previous frame, etc.).

This completely resolves our temporal coherency issue. Resuming a paused system becomes perfectly safe, all while leveraging the full power of our Dual DAG.

- A system waiting for an async network callback? It just reports NotReady until the data arrives.

- A system waiting for a heavy asset to load? NotReady.

Now, it is still a well-known rule in game development that in a multithreaded environment, achieving 100% thread safety is practically impossible—nothing stops a rogue developer from launching a background task that mutates data out of order.
But in our case, we actually can guarantee it. By applying one subtle trick.

---

### Resources Borrow checking

The rule is absurdly simple.

Any task, whether it is a standard system, a rogue background thread, or a duplicate execution, can borrow multiple resources to read them. Furthermore, it cannot borrow a resource for reading if another system is currently writing to it, nor for writing if another one is already writing or reading.

This runtime borrow-checking mechanism (inspired by Rust’s notoriously annoying yet brilliant compiler) makes our engine 100% thread-safe. Even if a paused system suddenly and dramatically resumes at the worst possible moment, the registry will simply return nil if the requested resource cannot be safely acquired.

How to handle that nil fallback is up to the developer, but it allows the engine to maintain absolute, bulletproof thread safety without relying on heavy OS-level locks.

---

## Continuous System Execution

I don't know if you noticed, but our graph has an interesting property: it's continuous. The graph executes itself indefinitely in a tight game loop, without relying on traditional OS-level sleep() calls.

This may seem weird. "If we no longer sleep the thread, how do we ensure a consistent framerate?"

The answer lies within our architecture: Execution Conditions. Systems can use time-based conditions to dictate their update rate. A renderer might say, "I will only execute if 16ms have elapsed since my last run," while a physics system might require a 5ms tick.

Using their last execution timestamp as an anchor, systems simply report NotReady if their time hasn't elapsed. But here is the magic: because the scheduler just bypasses NotReady nodes, the rest of the engine continues to run. While the renderer waits for its 16ms, an input system can run at staggering speeds, seamlessly capturing precise clicks that would otherwise fall between traditional frames. The CPU doesn't busy-wait in a blocked loop; it continuously does useful work across the graph, simply checking if timed systems are ready to fire.

You might ask, "Why go through this instead of just sleeping at the end of each frame?"

Because sleeping is OS-dependent. An OS sleep() guarantees you sleep at least the requested duration, but the actual wake-up time varies based on the OS thread scheduler. This introduces unpredictable latency.

In our framework, timing relies on high-resolution CPU clocks rather than the OS scheduler. We get local pacing for systems instead of a global timer that dictate the pace of the whole engine pipeline.

And just like that, as a byproduct of our architecture, we inadvertently allowed mutiple systems to run at custom pace.
While this seems incredible, it raise another issue.
Fixed timestep

---

### Fixing timestep in a Dual DAG

In our current architecture, since we don't rely on OS sleep, we have no way to guarantee a perfectly consistent pace for a system. Nothing guarantees that the local dt will exactly match the desired interval when the physics system is next allowed to run. Real time is messy and continuous.

So, how can we solve this?

Using **Discrete Event Simulation**.

Yeah, I know. I just gave a big speech about how "wow, our graph is continuous, extra!" and now I'm talking about making it discrete. Calm down, I haven't lost my mind yet. Only a part of the DAG is discrete. Let me explain.

The architecture introduces Logical Time for fixed-timestep systems. In our graph, logical time advances in discrete increments—a system's execution acts as a discrete event that ticks time forward. This logical time is local to the system and depends on its real-time constraints, which are enforced during the readiness test.

Let's take a concrete example: a physics system that needs to run every X ms. If the renderer takes too long and 2X ms pass in real time before the physics system executes again, logical time dictates that it must execute twice in a row to catch up to where the simulation should logically be.

In case the system falls too far behind and cannot catch up (preventing the infamous "spiral of death"), it can set an OVERRUN status, letting its dependencies know that the timeline has been compromised.

Because of this, the set of all logical times across the systems in the graph forms the true state of our DAG. Since time is now discrete and deterministic, we can travel through it. We can snapshot the state. We can rollback whenever we need to.

This is the power of our logical graph: deterministic system execution while still seamlessly matching real time.

## Traceability and debuggability

That's one clear win of our architecture. With the multiple plugin status, the propagations, the borrow checking, the timing.
We made a system that is easy to debug (as we can trace the exact flow of data). Easy to profile and rollback.
This may just be some sidenote but come in handy when working on complex multithreaded architecture.

---

## The Perfect Void

We set out to build the perfect game engine, and what did we end up with? A void.

Our architecture is fundamentally empty. It has no built-in renderer, no physics loop, no player controller. If you boot it up, it does nothing. It is a blank canvas.

Yet, this void is immensely structured. The Dual DAG, the Read/Write capabilities, the Runtime Borrow Checking, the Execution Conditions—these are not just features; they are absolute, unbending laws of physics within our engine.

This is the ultimate paradox: True flexibility requires absolute structure.

Traditional engines try to give you freedom by giving you tools. But those tools always come with assumptions, hidden constraints, and rigid internal architectures that eventually fight against your vision. They build the house for you, but you can only move the furniture.

Our framework takes the opposite approach. It doesn't build the house. It provides the laws of physics—the gravity, the thermodynamics, the rules of matter. By strictly governing how systems communicate and share data, we guarantee that they will never conflict. And because they can never conflict, you are free to build whatever you want on top of it. ECS, OOP, Data-Oriented, a 2D platformer, or a massive MMO—everything is possible because the foundation doesn't care what you build, only that it stands safe.

The perfect game engine is not a toolbox. It is a perfectly regulated vacuum, waiting for your imagination to fill it.

## Epilogue: It Works.

This might sound like an engineering fever dream. A theoretical framework so abstract that it would collapse under its own weight the moment it hits a real CPU.

I wouldn't have written this if I hadn't seen it work with my own eyes.

Every mechanism described in this article—the Dual DAG, the runtime borrow checking, the NotReady propagation, the continuous loop—has been implemented. It compiles. It runs. It is bulletproof.

Building a game engine is hard. Building an engine that builds engines is harder. But stepping into the void and finding out that the structure holds? That is what makes the struggle worth it.

---

## Performance

A common argument is that ECS is unbeatable for performance.
Performance is not the real reason ECS exists. Its real strength lies in composability, reuse, and architectural clarity. Our approach aims to provide the same benefits at a higher abstraction level.
We do not need perfect performance only correct performance.

Parallelism comes naturally with a DAG. Topological sorting is trivial and easily cacheable. It is not a bottleneck.
In the worst case, a fully connected DAG would serialize execution, making parallelism useless. But such a graph would already be a sign of terrible design.
Performance-critical systems can still use an ECS internally, tailored specifically to their needs.

The Dual DAG archtecture doesn't enforce intra-plugin architecture, allowing them to implement whethever they want to maximize performances.


---

## Conclusion

What we have described is not a traditional game engine, but the kernel of one.
Like an operating system kernel, it is designed for extensibility from the start. It is not meant to make games directly, but to make building engines easier.

A meta-engine. A tool to build tools.

This is the most realistic compromise to the “perfect engine” problem. We cannot build one engine for every game but we can make it easy to build the right engine for each game.

This kernel is my current project. It is written in Nim for several reasons:

* Fast compilation
* Small binaries
* High portability
* C and C++ interoperability
* Powerful macro system
* Good performance
* Simple and expressive syntax
* Multi-paradigm support
* Memory safety

The list goes on.

The project is available here:

https://github.com/Gesee-y/Cruise

Consider giving a star if you liked the project or donate to support the development