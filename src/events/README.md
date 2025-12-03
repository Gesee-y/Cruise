# Cruise Events

Events are an essential part of any game engine. They allow different parts of your project to work together without tight coupling. In a game engine, events are important not only from an architectural perspective (making core components interact seamlessly) but also for developer experience.

Game developers often need different parts of their game to communicate. For example, the player’s health display should update when the player collides with an enemy, when a bullet hits a monster, or when the score changes. Tracking these changes and notifying the HUD of collisions is critical in any game.

Most game engines implement the **observer pattern**, the most common way to allow a program to react to changes.

One great example is Godot with its [signals](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html). The syntax is simple and clear:

```gdscript
signal my_signal(param, another_param)

func foo(x1, x2):
    print(x1)
    print(x2)

my_signal.connect(foo)

## Bunch of code

my_signal.emit(1, 2.0)
```

Here, we attached the function `foo` to a signal that emits two parameters. `foo` will be called only when `my_signal` is emitted. `foo` is called a **Listener** because it listens for changes emitted by the signal.

This is particularly useful for UI, where we need to update the HUD when internal data changes, instead of repeatedly polling values manually. This approach makes games simpler, more maintainable, and often more performant.

## Cruise’s Approach

Inspired by Godot signals, Cruise provides `Notifier`s, an implementation of the observer pattern built around a **pipeline**. When a value is emitted, multiple processes take the `Notifier` as input and modify its internal state. These processes can include:

* Removing recent calls
* Adding delays
* Calling listeners asynchronously
* And more

![Emission pipeline](assets/pipeline.png)

Cruise's notifiers have a similar syntax to Godot:

```nim
notifier my_notifier(param:int, another_param:float)

proc foo(param:int, another_param:float) =
  echo param
  echo another_param

my_notifier.connect(foo)
my_notifier.emit((1, 2.0))
```

## How It Works

`Notifier`s are built around a pipeline divided into phases:

* `NotifierState`: Defines what the Notifier should track about its calls
* `ExecMode`: Preprocesses the Notifier’s stream and removes unnecessary calls
* `EmissionMode`: Determines how listeners are called (synchronously, asynchronously, etc.)

This provides flexibility: users aren’t locked into static event behaviors. Modifying pipeline components allows runtime changes in the Notifier’s behavior.

## States

A **state** is any combination of pipeline components. For example, `Value + ExecAllEmission + Synchronous` is one state for a `Notifier`. Switching to `Value + Exec3LatestEmission + Synchronous` is as simple as changing a pipeline component. Dedicated functions exist to modify pipeline states easily.

## Reactive Features

`Notifier`s also provide reactive functions familiar to users of Rx-style libraries, including:

* Delays: `notif.delay(duration, first)`. duration is in millinsecond and first is wheter there should be a delay before the first listener call
* Map: `notif.map(fn, Return_type)`. Map the fonction fn to each change of `notif`.
* Fold: `notif.fold(fn, Return_type)`. Accumulate value via the function `fn`.
* Filtering: `notif.filter(fn)`. Filter only some change following the function `fn`

## Why Notifier?

While there are many standard implementations of the observer pattern and reactive systems, `Notifier`s offer a new perspective: an event processing pipeline that allows great runtime flexibility through composition rather than schedulers.

Additionally, the Nim ecosystem lacks mature libraries for reactive programming, making `Notifier`s a valuable addition.

## Conclusion

`Notifier`s are a clean, extensible solution for handling reactivity in Nim. Their pipeline architecture allows runtime modifications, such as switching a `Notifier` from synchronous to parallel execution on the fly.
