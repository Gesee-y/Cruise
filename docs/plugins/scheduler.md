# When did we broke our scheduler ?

A game scheduler is a structure with the purpose of orchestrating the differents game systems in order to make them safe to run in parallel.
While being a popular practice, it's easy to abuse it and loses the main reason why we built it in the first place.
Cruise plugins acted as the scheduler but while enhancing it, I discovered that I was broking it.
So we will explore the differents evolutions of a scheduler and try to see when it broke:

## Stage 1: Access dependencies

The scheduler being built to secure access to data, here we add dependencies between systems to ensure they can safely run in parallels.
So this is a core invariant to ensure.

## Stage 2: User dependencies

THe user can specify the order in which systems run, from here it's important, as the user may need specific ordering that access relations can't ensure.
But this lower a bit the power of the scheduler making it a bit more inefficient because it's a bit more serialized but that's necessary for this to be usable an understandable.

## Stage 3: Conditional systems

Here we have systems that may or may not run at a given point, it doesn't really affect the scheduling while offering more power to the scheduler, so it's a plus.

## Stage 4: Waiting systems

Allowing systems to pause their thread, doing so paralyze the scheduler as all the others systems with parallel access are also stopped from executing. This greatly impact performances but through some aggressive optimization, we can make so that only the subgraph with the paused node will be impacted, leaving the rest of the graph free to run.

## Stage 5: Message passing

Often, systems need a way to communicate with each others, adding dependencies between them for that would just negatively impact the scheduling, we can just add message passing where a system publish message and another one receive it without caring about where it come from. But this raise questions about the safety of the event bus, but through simple RWLocks, we can ensure the safety of message passing and make it more efficient

## Stage 6: Reactivity

This is the point where I saw that something was going wrong.
Those are function that react on changes, this may seem innocent and useful but is an absolute trap for multithreading.

First because of the immediate trait of reactivity, which implicitly breaks the DAG as it can introduce unsupervised data races.
I wrote about this: [Why observers aren't thread safe](../events/callbacks.md)
