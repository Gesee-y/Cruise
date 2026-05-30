# UT Engine Example

Here we will build step by step a functional undertale engine to illustrate the plugin architecture.
So what do we need for an undertale engine.

Let's start with a simple part, the window.
We need to open a window and be able to access it (for inputs or other stuffs.)

It's a resource.
Let start with this

```nim
import ../../src/windows/windows
import ../../stdplugin/sdlwin/sdlwin

var UTPlugin = newPlugin()
var app = initSDL3App()
var win = SDL3Window()
app.initWindow(win, "Example 1 — Simple Window", width=800, height=600)

discard UTPlugin.addResource(app)
discard UTPlugin.addResource(win)
```

New we can start easy with inputs.
We will start with a system that will poll inputs this frame and let us take it.

```nim
newSystem(UTPlugin, InputSystem[var CApp])
method update(p: InputSystem) =
  let appopt = p.getWriteResource[:CApp]()
  if appopt.isNone:
    p.setStatus(PLUGIN_WAITING)
    return

  let app = winopt.get
  app.eventLoop(SDLEventRouter)
UTPlugin.addSystem(InputSystem())
```

Next we can work on player inputs, it need to happen after inputs and access the window and the player.
We can use an ECS here and define a player component.

```nim
newSystem(UTPlugin, PlayerControllerSystem[ECSWorld, SDL3Window, var Motor2D, var UPlayer])
method update(p: PlayerControllerSystem) =
  let winopt = p.getReadResource[:SDL3Window]()
  var wopt = p.getReadResource[:ECSWorld]()
  if winopt.isNone or wopt.isNone:
    p.setStatus(PLUGIN_WAITING)
    return

  let win = winopt.get()
  var world = wopt.get()
  var moves = world.get(UMove)

  for (bid, r) in world.denseQuery(world.query(UPlayer and UMove)):
    var directions = moves.getdenseField(bid, position)

    for i in r:
      directions[i] = point2d(win.isKeyPressed(CKey_RIGHT) - win.isKeyPressed(CKey_LEFT), win.isKeyPressed(CKey_DOWN) - win.isKeyPressed(CKey_UP))
```

Now we can add our dependencies to make it start after that:

```nim
let pcID = UTPlugin.addSystem(PlayerControllerSystem())
UTPlugin.addDependencies(inpID, pcID)
```

