# Observer pattern: Why your callbacks aren't thread-safe

The observer pattern is one of the most popular design patterns in the world. Anyone who has encountered Javascript events knows what they are.
Listed amongs the mighty patterns of the GoF book *Design patterns: Elements of Reusable Object-Oriented Software*, his purpose is to part of a program to react to changes without having to poll everytime to know if anything happened.

## Overview

Conceptually the pattern just look like this:

We have an **Observer** object, which, as his name suggest it, *observe* a **Subject** object, and when the subject decide to emit a notification, the observers receive it and execute accordingly.

This is the same as when you subscribe to a newsletter, you, whethever you like it or not, observe the newsletter and each time they notify you something, you act accordingly (maybe by reading it or ignoring it)

So we end up with something like this:

```nim
type
  Subject = object
    observers: seq[Observer]

  Observer = proc()

proc notify(s: Subject) =
  for observer in s.observers:
    observer()
```

Looking at this the pattern seems simple and with multiple benefits, you can add observers to the subject without tight coupling between them, easily add behaviors and more.
So on paper this looks perfect, right ?

## Observer pattern is still coupling

Conceptually, the observer patterns purpose to allows us to decouple how core (the subject) from behaviors (observers) but still miss something.
Let's take a simple example.

Assume you have some simple command app like this:

```nim
type
  CommandService = object
    commands: int
```

Now you want that each time the user do a given action, a commands should be added (incrementing the internal `commands` field).
So you would have something like

```nim
var onAction = Subject()
onAction.observer.add(proc() = inc cmdService.command)
```

Wait wait wait, did you just saw what happened ?
We added an observer to our subject and that observer is a simple function that keeps a  **closure** to our command services.

This may seem innocent, as that's how most people uses observer but this introduces coupling to the command services.
Every observer that read or write on that service are now bounded by that closure, if that object happens to diseappear, then it would be a cascading failure (but GCed language already save us from such case.)

But it may just be my implementation, reactive libs aren't that naive and let you pass arguments to the observer.
So we have this instead:

```nim
var onAction = Subject[CommandService]()
onAction.observer.add(proc(cmd: var CommandService) = inc cmd.command)
```

So this may seems like the solutions but this is even more flawed than the previous version as it reduce the whole purpose of this pattern, **decoupling**:

- We coupled the Subject to the Observer by CommandService, now both should know it in order for everything to works
- For language that distinguish immutable and mutable references (like rust or nim), this won't compile as our proc ask for a mutable reference where the subject only accept observer if they ask immutable references.
- This couple the observer to the subject callback signature.

So the closure version clearly wins this round and, by deduction, this pattern encourage the use of closure for observers, and that is the problem in multithreaded context.

## Thread safety

We define thread safety at 3 level for this pattern:

- **Intra thread safety**: This is ensuring the internal operations of the Subject are thread safe (adding an observer, notifying, etc). That's the most discussed part while implementing this pattern and most stop here.
- **Inter thread safety**: That's safety between multiple notifications of the same subject. If thread A and thread B both emit at the same time, they will execute the callbacks at the same time and corrupt data
- **Extra thread safety**: That's ensuring the Observers can't be source of data race with the rest of the application. This is harder to ensure and the implementer can't make assumptions about the Observers internal's

### Observers aren't thread safe

While most implementations guarantee safety with some efforts like using locks, monitors mutex, etc, the 2 others are much harder to ensure.

Especially because there seems to be 2 core assumptions about this pattern:

  - The observers execution is sequential, meaning they happens one after the other (else it would already be an extremely thread unsafe pattern)
  - One Subject can't notify 2 times at the same time.

The first assumptions hold and helps with inter safety, but not the second one. Two threads could easily notify the same subject at the same time, resulting in immediate corruption.

What I'm trying to show here is that the Observer patterns was inherently thought for an asynchronous single threaded environment, not a multithreaded one. That's why it's so used in JS for example which is single threaded and manage callbacks through his event loop.

We can inspire ourselves from that and add some sort of event loop to our observer implementation, this way notifying is like registering an event in queue, and there is only one call site, the thread currently holding the Subject (for example by holding his lock) or a thread dedicated to execute those, that empty the queue.

This solves our inter thread safety issue but the extra thread safety issue is still there.
But this one can't actually be solved from just the implementer perspective as he can't deduce all the interactions the Observers may have have on things outside of his scope.

## Conclusion

That's why we conclude that the Observer pattern is inherently thread unsafe, thought for single threaded applications, it doesn't scale for large programs where it would just be a source for bugs and corruptions.
That's why approach like **message passing**, **pub/sub** are prefered over this approach in multithreaded apps.
