# Cruise : Game engine kernel in Nim

Once upon a time, making a game was long, tremendous and insane task. People would often need to build their own game engine before being able to make their game logics. But nowadays, the rise of game engines has allowed peoples to focus on creativity rather than fighting with low level details.
While being an extreme time saver, regular game engines often have their limitations which may be **cost**, **technical debt**, **performances**, etc.
So here is **Cruise**, not a game engine in the regular sense (you can't have a full game JUST by using Cruise) but a **kernel**. This means it offers all the core functionnality ones need for their engine or game.

## Why Cruise

So, why bother using Cruise ? What does it offer the plethora of game engines out there doesn't offer ? It's simple.
A flexible, extensible, performant, and simple core architecture.
All that through a **DAG** (Direct Acyclic Graph) architecture.
A DAG architecture is a model where the game systems are modelled as vertex in the DAG and and edges are dependencies between them.
DAG:
  - **Direct**: Ensure data and dependencies flows in one direction.
  - **Acyclic**: Ensure there are no circular dependencies and impossible execution order.
  - **Graph**: Ensure we can find an optimal execution order through topological sort.

This allows people to easily build **plugins**. A plugin is simply a subgraph of the DAG. People can create their own plugins and just fuse it with the main graph and automatically, it will be able to run.

This architecture offers several advantages:
  - **Architectural liberty**: Each plugin encapsulate his own way to work, game developers aren't constricted by any given architecture.
  - **Optimal parallelism**: Topological order ensure game systems run in the best possible way.
  - **Easy to extend**: Plugins are just a small chunk of code that should performs specific task well.

## Features

- **Secure and flexible plugin system**: Built around a DAG (Direct Acyclic Graph), it allows you to extend Cruise, share your own plugin and collaborate without too much hassle. Each system of the plugin have his own inteface to safely interact with his dependencies.

- **Optimal system scheduling**: Through topological sort, Cruise ensure your systems are executed in the most efficient way.

- **Game logics as first class citizens**: Your customs systems have as much power as the core ones. They are easy to define, are automatically scheduled.

- **CLI tool**: To manage plugins, get them, solve dependencies, etc. ![Cruise CLI overview](https://github.com/Gesee-y/Cruise/blob/main/assets%2Fcruise_cli.PNG)

- **Event System**: Cruise provides you 2 event system, a lightweight synchronous one that can be use for simple cases, and a complex one leveraging the full powers of reactive programming such as merging, filtering, delays, throttling,  etc.

- ~~**Temporary storage**: To easily share data among your systems, it also support TTL (Time To Live) for data and provides events and serialization support~~

- ~~**Multiple clear interfaces**: [ECS](https://github.com/Gesee-y/ECSInterface), SceneTree, [Rendering](https://github.com/Gesee-y/Horizons) , [windowing and events](https://github.com/Gesee-y/Outdoors). All clear and set for you to overload with bunch of premade implementations available.~~

- **Make your own structure**: Cruise doesn't enforce any architecture, build your game as you feel

- **Build your own engine**: Since Cruise is just a minimal core, you can just choose the set of plugins (or build your own) that perfectly match your use case.

## Donations

If you want to support the dev behind this project you can make donations. But because of geographic restrictions, donations can't be made through regular platforms loke "buy me a coffee" since Stripe and PayPal aren't supported. So the alternatives are:

- [Binance](
https://s.binance.com/KvfmIsbC): Use the link or this [QR code](https://github.com/Gesee-y/Cruise/blob/main/assets/qr-image-1767409833813.png)

- Payoneer: You can write at gesee37@gmail.com for this process

## License

This package is licenced under the MIT License, you are free to use it as you wish.
