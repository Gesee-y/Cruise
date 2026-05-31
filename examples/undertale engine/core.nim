############################################################################################################################
###################################################### UNDETALE ENGINE CORE ################################################
############################################################################################################################

import ../../src/windows/windows
import ../../src/render/render
import ../../src/pga/pga
import ../../src/vspace/vspace
import ../../src/plugins/plugins
import ../../src/ecs/table
import ../../stdplugin/sdlwin/sdlwin
import ../../stdplugin/sdlrender/sdlrender
import options

type
  UVec2 = object
    x, y: float32

  UMove = object
    direction: Point2Df

  UPlayer = object
    name: string
    position: UVec2
    colorScheme: CRGBAi

  USprite = object
    handle: TextureKey
    scale: Point2Df

  CPlayer = ref UPlayer
  CMove = ref UMove
  CMotor = ref Motor2D

var ecs = newECSWorld()
var UTPlugin = newPlugin()
var app = initSDL3App()
var win = SDL3Window()
app.initWindow(win, "UT Engine", width=640, height=480)
discard ecs.registerComponent(UPlayer)
discard ecs.registerComponent(UMove)
discard ecs.registerComponent(Motor2D)

var playerPool = ecs.get(UPlayer)
var upl: CPlayer
new(upl)
var umv: CMove
new(umv)
var mt: CMotor
new(mt)

discard UTPlugin.addResource(app)
discard UTPlugin.addResource(win)
discard UTPlugin.addResource(playerPool)
discard UTPlugin.addResource(ecs)
discard UTPlugin.addResource(upl)
discard UTPlugin.addResource(umv)
discard UTPlugin.addResource(mt)

let inpID = newSystem(UTPlugin, InputSystem[var CApp])
method update(p: InputSystem) =
  let appopt = p.getWriteResource[:CApp]()
  if appopt.isNone:
    p.setStatus(PLUGIN_WAITING)
    return

  let app = appopt.get
  app.eventLoop(SDLEventRouter)

let pcID = newSystem(UTPlugin, PlayerControllerSystem[ECSWorld, SDL3Window, var CMotor, var CPlayer])
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
    var directions = moves.getdenseField(bid, direction)

    for i in r:
      directions[i] = point2f(win.isKeyPressed(CKey_RIGHT).float32 - win.isKeyPressed(CKey_LEFT).float32, win.isKeyPressed(CKey_DOWN).float32 - win.isKeyPressed(CKey_UP).float32)

discard UTPlugin.addDependency(inpID, pcID)

var ren = initSDLRenderer(win.handle)
discard UTPlugin.addResource(ren)

let srID = newSystem(UTPlugin, SpriteRendererSystem[ECSWorld, CSDLRenderer, var CMotor, var CSprite])

var shouldRun = true
NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
  if ev.kind == WINDOW_CLOSE:
    shouldRun = false

awake(UTPlugin)
while shouldRun:
  update(UTPlugin)
shutdown(UTPlugin)