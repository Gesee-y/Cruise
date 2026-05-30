# UT Engine Example

Here we will build step by step a functional Undertale-like engine to illustrate how our plugin architecture works in practice. So, what do we need for an Undertale engine?

Let's start with a simple part: the window.
We need to open a window and be able to access it (for inputs or other stuff). In our architecture, a window is a **Resource**.

```nim
import ../../src/windows/windows
import ../../stdplugin/sdlwin/sdlwin

var UTPlugin = newPlugin()
var app = initSDL3App()
var win = SDL3Window()
app.initWindow(win, "Undertale Engine", width=800, height=600)

discard UTPlugin.addResource(app)
discard UTPlugin.addResource(win)
```

Now we can start with inputs. We will create a system that polls inputs this frame and makes them available to the rest of the engine.

```nim
newSystem(UTPlugin, InputSystem[var CApp])
method update(p: InputSystem) =
  let appopt = p.getWriteResource[:CApp]()
  if appopt.isNone:
    # Runtime Borrow Checker: the resource is busy, we wait
    p.setStatus(PLUGIN_WAITING)
    return

  let app = appopt.get()
  app.eventLoop(SDLEventRouter)

let inpID = UTPlugin.addSystem(InputSystem())
```

Next, we can work on player inputs. This system needs to happen *after* the input polling, and it needs to access the window and the player. We can use an ECS here and define a player component. 

Notice how we request a `WriteResource` for the `ECSWorld` because we are going to modify the player's position.

```nim
newSystem(UTPlugin, PlayerControllerSystem[ECSWorld, SDL3Window, var UPlayer])
method update(p: PlayerControllerSystem) =
  let winopt = p.getReadResource[:SDL3Window]()
  var wopt = p.getReadResource[:ECSWorld]() # Write because we mutate positions
  
  if winopt.isNone or wopt.isNone:
    p.setStatus(PLUGIN_WAITING)
    return

  let win = winopt.get()
  var world = wopt.get()
  var moves = world.get(UMove)

  for (bid, r) in world.denseQuery(world.query(UPlayer and UMove)):
    var directions = moves.getdenseField(bid, position)

    for i in r:
      directions[i] = point2d(
        win.isKeyPressed(CKey_RIGHT) - win.isKeyPressed(CKey_LEFT), 
        win.isKeyPressed(CKey_DOWN) - win.isKeyPressed(CKey_UP)
      )
```

Now we can add our dependencies to build our execution DAG. The Player Controller must run after the Input System, otherwise, it might read stale input data.

```nim
let pcID = UTPlugin.addSystem(PlayerControllerSystem())
UTPlugin.addDependencies(pcID, inpID) # pcID depends on inpID
```
