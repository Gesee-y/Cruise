# Cruise : Game engine kernel in Nim

Once upon a time, making a game was long, tremendous and insane task. People would often need to build their own game engine before being able to make their game logics. But nowadays, the rise of game engines has allowed peoples to focus on creativity rather than fighting with low level details.
While being an extreme time saver, regular game engines often have their limitations which may be **cost**, **technical debt**, **performances**, etc.
So here is **Cruise**, not a game engine in the regular sense (you can't have a full game JUST by using Cruise) but a **kernel**. This means it offers all the core functionnality ones need for their engine or game.

## Why Cruise

So, why bother using Cruise ? What does it offer the plethora of game engines out there doesn't offer ? It's simple.
A flexible, extensible, performant, and simple core architecture.
All that through a **Dual DAG** (Direct Acyclic Graph) architecture.
First, Dual DAG architecture is a model where game systems are modeled as vertices and bounded by 2 set of contraints:
  - Dependecies between systems which forms the **Dependency DAG**
  - Access to data by systems which forms the **Access DAG**

This is inspired by Apache Airflow's task graph and Bevy's scheduler.  
Also between, DAG:
  - **Direct**: Ensure data and dependencies flows in one direction.
  - **Acyclic**: Ensure there are no circular dependencies and impossible execution order.
  - **Graph**: Ensure we can find an optimal execution order through topological sort.

This allows people to easily build **plugins**, which are simply a subgraph of the dependency DAG + set of resources. People can create their own plugins and just fuse it with the main graph and automatically, it will be able to run.

This architecture offers several advantages:
  - **Architectural liberty**: Each plugin encapsulate his own way to work, game developers aren't constricted by any given architecture.
  - **Optimal parallelism**: Topological order ensure game systems run in the best possible way.
  - **Easy to extend**: Plugins are just a small chunk of code that should performs specific task well.

## Features

- **Secure and flexible plugin system**: Built around a Dual DAG, it allows you to extend Cruise, share your own plugin and collaborate without too much hassle. Each system of the plugin have his own inteface to safely interact with his dependencies.

- **Optimal system scheduling**: Through topological sort, Cruise ensure your systems are executed in the most efficient way.

- **Game logics as first class citizens**: Your customs systems have as much power as the core ones. They are easy to define and scheduled.

- **CLI tool**: To manage plugins, get them, solve dependencies, etc. ![Cruise CLI overview](https://github.com/Gesee-y/Cruise/blob/main/assets%2Fcruise_cli.PNG)

- **Generic math library**: Cruise allows any objects implementing his concept to be fully usable for in the math library. Which for example means that any type with an x,y fields are Vec2, etc. Making Cruise highly compatible almost every existing math library objects:
```nim
type MyVec3 = object
  x, y, z: float32

let a = MyVec3(x: 1, y: 0, z: 0)
let b = MyVec3(x: 0, y: 1, z: 0)
let c = a.cross(b)
``` 

- **Projective Geometrical Algebra**: Being one of the first Nim's engine to provide this, Cruise allows your to use PGA for your games which allows unified 2D and 3D logics, simple collision detection, and more.

- **Event System**: Cruise provides you 2 event system, a lightweight synchronous one that can be use for simple cases, and a complex one leveraging the full powers of reactive programming such as merging, filtering, delays, throttling,  etc.

- **Optional ECS**: Cruise provides a high performances, optional ECS based on a fragmented storage. Allowing to mimick archetypes and sparse sets in the same structure without losing the best of both.

- **Temporary storage**: To easily share data among your systems, it also support TTL (Time To Live) for data and provides events and serialization support

- **API-agnostic windowing**: Using a microkernel architecture, Cruise let you to manage windows and inputs in an unified interface, allowing you to change your windowing API in a breeze.

- **Backend agnostic rendering**: Command buffer based renderer, an everything as resource philosophy, 

- **Standar Plugins**: Cruise offers a set of default plugins like: render graph with multi-pass, aliasing, fully backend-agnostic. A SceneTree, SDL implementation of the abstraction,and more.

- **Make your own structure**: Cruise doesn't enforce any architecture, build your game as you feel

- **Build your own engine**: Since Cruise is just a minimal core, you can just choose the set of plugins (or build your own) that perfectly match your use case.

## Standard Plugins

Cruise provides a set of default plugins and modules to allows you to start building games or tools with it, such as:

- **Render graph**: Provide a functional render graph built directly on top of Cruise plugin system that allows you to control rendering pass and resource management.

- **SDL Windows**: Provide an implementation of the windowing abstraction for SDL3, allowing you to conveniently mange inputs and windows.
```nim
import Cruise/src/windows/windows
import Cruise/stdplugin/sdlwin/sdlwin

# Opens an 800×600 window, runs until the user
# presses Escape or closes the window.

let app = initSDL3App()

var win: SDL3Window
new(win)
app.initWindow(win, "Example 1 — Simple Window", "800", "600")

# Connection to the close notifier: when the close button is clicked
var running = true
NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
  if ev.kind == WINDOW_CLOSE:
    running = false

while running:
  app.eventLoop(SDLEventRouter)

  # Quit on Escape
  if app.isKeyJustPressed(CKey_Escape):
    running = false

  win.updateWindow()

win.quitWindow()
app.quitSDL3App()
```

- **SDL Render**: An implementation of a renderer using the rendering interface, allows you to draw, manage resources and batch draw calls or even integrate it with a render graph.
```nim
import Cruise/src/render/render
import Cruise/stdplugin//rendergraph/core
import Cruise/stdplugin/sdlrender/sdlrender
import Cruise/stdplugin/sdlwin/sdlwin
import math

# Creating the window
let app = initSDL3App()

var win: SDL3Window
new(win)
app.initWindow(win, "SDL Render", "800", "600")

# Connection to the close notifier: when the close button is clicked
var running = true
NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
  if ev.kind == WINDOW_CLOSE:
    running = false

var ren: CSDLRenderer = initSDLRenderer(win.handle, true)
var t = 0.0f

while running:
    app.eventLoop(SDLEventRouter)

    if app.isKeyJustPressed(CKey_Escape):
      running = false

    ren.beginFrame()

    ren.DrawCircleAdv(
      fpoint(float32(W)*0.5 + cos(t)*150, float32(H)*0.5 + sin(t)*150),
      30, rgba(255,100,50,200), filled=true)

    ren.endFrame()
    t += 0.016f

  ren.teardown()
```

## License

This package is licenced under the MIT License, you are free to use it as you wish.
