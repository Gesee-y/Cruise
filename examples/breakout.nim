import breakout/common
import breakout/bench_sizes
import breakout/runtime
import ../src/ecs/table
import ../src/windows/windows
import ../stdplugin/sdlrender/sdlrender
import ../src/la/LA
import ../stdplugin/sdlwin/sdlwin

proc initGame(): Game =
  result = Game(
    world: newECSWorld(),
    isRunning: true,
    windowWidth: WindowWidth,
    windowHeight: WindowHeight,
    clearColor: [0'u8, 0, 0, 255],
    alive: newQueryFilter(5000),
  )

  discard result.world.registerComponent(Dead)

proc applyInput(game: var Game) =
  if game.app.isKeyJustPressed(CKey_Escape):
      game.isRunning = false
  
  game.inputState[Left] = game.app.isKeyPressed(CKey_Left)
  game.inputState[Right] = game.app.isKeyPressed(CKey_Right)

proc update(game: var Game) =
  sysControlBall(game)
  sysControlBrick(game)
  sysControlPaddle(game)
  sysShake(game)
  sysFade(game)
  sysMove(game)
  sysTransform2d(game)
  sysCollide(game)
  sysDraw(game)
  inc game.tickId

when isMainModule:
  var game = initGame()

  game.app = initSDL3App()
  new(game.window)
  game.app.initWindow(game.window, "Breakout", posX=0, posY=0, width=game.windowWidth, height=game.windowHeight)
  game.renderer = initSDLRenderer(game.window.handle)

  game.createScene(findBenchscale("small"))

  while game.isRunning:
    game.renderer.beginFrame
    game.app.eventLoop(SDLEventRouter)
    game.applyInput()
    update(game)
    game.renderer.endFrame()