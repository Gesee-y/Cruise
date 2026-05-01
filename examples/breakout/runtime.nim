import std/math
from typetraits import supportsCopyMem
import ./bench_random
import ./bench_sizes
import headless_raylib, vmath
import ../../src/ecs/table
import ../../src/ecs/plugins/scenetree
import ../../src/la/LA
import ../../src/windows/windows
import ../../src/render/render
import ../../stdplugin/rendergraph/core
import ../../stdplugin/sdlwin/sdlwin
import ../../stdplugin/sdlrender/sdlrender
import std/[math, random]
# ---- cruise ecs runtime ----

const
  BALL_RADIUS = 10
  PADDLE_SPEED = 0.5'f32

type
  Input* = enum
    Right, Left

  CollisionFlag* = enum
    Hit

  TransformFlag* = enum
    Dirty, Fresh, HasPrevious

  BallTag* = object
  PaddleTag* = object
  Dead* = object

  Collision* = object
    flags*: set[CollisionFlag]
    hit*: Vec2

  Collide* = object
    size*: Vec2
    min*, max*: Point2
    center*: Point2
    collision*: Collision

  Draw2d* = object
    width*, height*: int32
    color*: array[4, uint8]

  Fade* = object
    step*: float32

  Move* = object
    direction*: Vec2
    speed*: float32

  Transform2d* = object
    world*: Mat2d
    translation*: Vec2
    rotation*: Rad
    scale*: Vec2
    flags*: set[TransformFlag]

  Previous* = object
    position*: Point2
    rotation*: Rad
    scale*: Vec2

  Shake* = object
    duration*: float32
    strength*: float32

  Game* = ref object
    world*: ECSWorld
    root*: DenseHandle
    camera*: DenseHandle
    paddle*: DenseHandle
    tree*: SceneTree
    alive*: QueryFilter

    inputState*: array[Input, bool]
    clearColor*: array[4, uint8]

    isRunning*: bool
    windowWidth*, windowHeight*: int32
    tickId*: int

    raylib*: RaylibContext
    app*: CApp
    renderer*: CSDLRenderer
    window*: SDL3Window

proc markDirty*(game: var Game; entity: DenseHandle) =
  var t = game.world.get(Transform2D, entity)
  t.flags.incl(Dirty)
  game.world.set(entity, t)

func intersects*[K: enum](a, b: set[K]): bool {.inline.} =
  (a * b) != {}

proc initTransform(translation: Vec2): Transform2d =
  Transform2d(
    world: mat2d(),
    translation: translation,
    rotation: 0.Rad,
    scale: vec2(1, 1),
    flags: {Dirty, Fresh}
  )

proc initPrevious(): Previous =
  Previous(position: point2(0, 0), rotation: 0.Rad, scale: vec2(1, 1))

proc addCamera(game: var Game; translation: Vec2): DenseHandle =
  result = game.world.createEntity(Transform2d, Shake, Previous)
  game.world.set(result, initTransform(translation))
  game.world.set(result, Shake(duration: 0, strength: 10))
  game.world.set(result, initPrevious())

proc addPaddleEntity(game: var Game; translation: Vec2): DenseHandle =
  result = game.world.createEntity(Transform2d, Move, Collide, Draw2d, Previous, PaddleTag)
  game.world.set(result, initTransform(translation))
  game.world.set(result, initPrevious())
  game.world.set(result, Collide(
    size: vec2(100, 20),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  ))
  game.world.set(result, Draw2d(
    width: 100,
    height: 20,
    color: [255'u8, 0, 0, 255]
  ))
  game.world.set(result, Move(direction: vec2(0, 0), speed: 20))
  game.tree.addChild(game.camera, result)

proc createBall*(game: var Game; x, y: float32; seed: uint32) =
  let angle = angleFromSeed(seed)
  let entity = game.world.createEntity(Transform2d, Collide, Draw2d, Move, Previous, BallTag)
  game.world.set(entity, initTransform(vec2(x, y)))
  game.world.set(entity, initPrevious())
  game.world.set(entity, Collide(
    size: vec2(20, 20),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  ))
  game.world.set(entity, Draw2d(
    width: 20,
    height: 20,
    color: [0'u8, 255, 0, 255]
  ))
  game.world.set(entity, Move(
    direction: Vec2(x: cos(angle), y: sin(angle)),
    speed: 14
  ))
  game.tree.addChild(entity)
  
proc createBrick*(game: var Game; x, y: float32; width, height: int32) =
  let entity = game.world.createEntity(Transform2d, Collide, Draw2d, Fade, Previous)
  game.world.set(entity, initTransform(vec2(x, y)))
  game.world.set(entity, initPrevious())
  game.world.set(entity, Collide(
    size: vec2(width.float32, height.float32),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  ))
  game.world.set(entity, Draw2d(
    width: width,
    height: height,
    color: [255'u8, 255, 0, 255]
  ))
  game.world.set(entity, Fade(step: 0))
  game.tree.addChild(entity)

proc createExplosion*(game: var Game; x, y: float32) =
  let explosions = 32
  let step = TAU / explosions.float
  let fadeStep = 0.05
  for i in 0..<explosions:
    let entity = game.world.createEntity(Transform2d, Previous, Draw2d, Fade, Move)
    game.world.set(entity, initTransform(vec2(x, y)))
    game.world.set(entity, initPrevious())
    game.world.set(entity, Draw2d(
      width: 20,
      height: 20,
      color: [255'u8, 255, 255, 255]
    ))
    game.world.set(entity, Fade(step: fadeStep))
    game.world.set(entity, Move(
      direction: Vec2(x: sin(step * i.float32), y: cos(step * i.float32)),
      speed: 20
    ))
    game.tree.addChild(entity)

proc createTrail*(game: var Game; x, y: float32) =
  let entity = game.world.createEntity(Transform2d, Previous, Draw2d, Fade)
  game.world.set(entity, initTransform(vec2(x, y)))
  game.world.set(entity, initPrevious())
  game.world.set(entity, Draw2d(
    width: 20,
    height: 20,
    color: [0'u8, 255, 0, 255]
  ))
  game.world.set(entity, Fade(step: 0.05))
  game.tree.addChild(entity)

proc createPaddle*(game: var Game; x, y: float32) =
  game.paddle = game.addPaddleEntity(vec2(x, y))

proc createScene*(game: var Game; scale: BenchScale) =
  let columnCount = scale.columns
  let rowCount = scale.rows
  let brickWidth = 50
  let brickHeight = 15
  let margin = 5

  let gridWidth = brickWidth * columnCount + margin * (columnCount - 1)
  let startingX = (game.windowWidth - gridWidth) div 2
  let startingY = 50

  game.camera = game.addCamera(vec2(0, 0))
  var tree = initSceneTree(game.camera)
  var world = game.world
  world.setUp(tree)
  game.tree = tree

  for row in 0..<rowCount:
    let y = startingY + row * (brickHeight + margin) + brickHeight div 2
    for col in 0..<columnCount:
      let x = startingX + col * (brickWidth + margin) + brickWidth div 2
      game.createBrick(x.float32, y.float32, brickWidth.int32, brickHeight.int32)

  game.createBall(
    float32(game.windowWidth / 2),
    float32(game.windowHeight - 60),
    eventSeed(1'u32, 0, float32(game.windowWidth / 2), float32(game.windowHeight - 60))
  )
  game.createPaddle(float32(game.windowWidth / 2), float32(game.windowHeight - 30))

template updateTransformWorld(game: var Game; entity: DenseHandle) =
  var transforms = game.world.get(Transform2d)
  var prevs = game.world.get(Previous)

  var transform = transforms[entity]
  var previous = prevs[entity]

  if Fresh in transform.flags:
    transform.flags.excl(Fresh)
  else:
    previous.position = transform.world.origin
    previous.rotation = transform.world.rotation
    previous.scale = transform.world.scale
    transform.flags.incl(HasPrevious)
    transform.flags.excl(Dirty)

  let local = compose(transform.scale, transform.rotation, transform.translation)
  let parentNode = game.tree.getParent(entity)
  
  if parentNode != nil:
    let parent = game.world.entities[parentNode.id.id].id
    transform.world = transforms[parent].world * local
  else:
    transform.world = local

  transforms[entity] = transform
  prevs[entity] = previous

proc sysTransform2d*(game: var Game, root: DenseHandle = game.camera) =
  var stack: seq[DenseHandle] = @[root]
  
  let transforms = game.world.get(Transform2d)

  while stack.len > 0:
    let current = stack.pop()

    if transforms[current].flags.intersects({Dirty, Fresh}):
      game.updateTransformWorld(current)

    let children = game.tree.getChildren(current)

    if children != nil:
      for i in children.dLayer:
        let handle = game.world.getDHandle(i)
        stack.add(handle)

template computeAabb(transform: Transform2d; collide: var Collide) =
  collide.center = transform.world.origin
  collide.min = collide.center - collide.size / 2
  collide.max = collide.center + collide.size / 2

template intersectAabb(a, b: Collide): bool =
  a.min.x < b.max.x and a.min.y < b.max.y and
    a.max.x > b.min.x and a.max.y > b.min.y

template penetrateAabb(a, b: Collide): Vec2 =
  let distanceX = a.center.x - b.center.x
  let penetrationX = a.size.x / 2 + b.size.x / 2 - abs(distanceX)
  let distanceY = a.center.y - b.center.y
  let penetrationY = a.size.y / 2 + b.size.y / 2 - abs(distanceY)

  if penetrationX < penetrationY:
    vec2(penetrationX * sgn(distanceX).float32, 0)
  else:
    vec2(0, penetrationY * sgn(distanceY).float32)

template prepareCollider(game: var Game; entity: uint) =
  var colliders = game.world.get(Collide)
  var collider = colliders[entity]
  let trans = game.world.get(Transform2d, entity)

  collider.collision = Collision(flags: {}, hit: vec2(0, 0))
  computeAabb(trans, collider)
  colliders[entity] = collider

proc updateCollision(game: var Game; aEntity, bEntity: uint) =
  var colliders = game.world.get(Collide)
  var a = colliders[aEntity]
  var b = colliders[bEntity]
  if intersectAabb(a, b):
    let hit = penetrateAabb(a, b)
    
    let (abid, aid) = aEntity.getDenseMeta
    let (bbid, bid) = bEntity.getDenseMeta

    a.collision = Collision(flags: {Hit}, hit: hit)
    b.collision = Collision(flags: {Hit}, hit: -hit)

    colliders[aEntity] = a
    colliders[bEntity] = b 

proc sysCollide*(game: var Game) =
  var sig = game.world.query(Collide and not BallTag and not Dead)
  var cached = game.world.denseQueryCache(sig)

  for (bid, r) in game.world.denseQuery(game.world.query(Collide)):
    for i in r:
      var eid = makeId(bid, i)
      game.prepareCollider(eid)

  for (bid, r) in game.world.denseQuery(game.world.query(BallTag)):
    for i in r:
      var eid = makeId(bid, i)

      for (bid2, r2) in cached:
        for j in r2:
          var eid2 = makeId(bid2, j)
          game.updateCollision(eid, eid2)

proc sysControlPaddle*(game: var Game) =
  var moves = game.world.get(Move)
  var move = moves[game.paddle]
  
  move.direction.x = 0
  if game.inputState[Left]:
    move.direction.x -= PADDLE_SPEED
  if game.inputState[Right]:
    move.direction.x += PADDLE_SPEED

  moves[game.paddle] = move

proc sysControlBall*(game: var Game) =
  var moves = game.world.get(Move)
  var transforms = game.world.get(Transform2d)
  var colliders = game.world.get(Collide)
  
  for (bid, r) in game.world.denseQuery(game.world.query(BallTag)):
    for i in r:
      var eid = makeId(bid, i)
      let ball = game.world.getDHandleFromID(eid)

      var collide = colliders[eid]
      var move = moves[eid]
      var transform = transforms[eid]

      if collide.min.x < 0:
        transform.translation.x = collide.size.x / 2
        move.direction.x *= -1

      if collide.max.x > game.windowWidth.float32:
        transform.translation.x = game.windowWidth.float32 - collide.size.x / 2
        move.direction.x *= -1

      if collide.min.y < 0:
        transform.translation.y = collide.size.y / 2
        move.direction.y *= -1

      if collide.max.y > game.windowHeight.float32:
        transform.translation.y = game.windowHeight.float32 - collide.size.y / 2
        move.direction.y *= -1

      if Hit in collide.collision.flags:
        var shake = game.world.get(Shake, game.camera)
        shake.duration = 0.1
        game.world.set(game.camera, shake)

        if collide.collision.hit.x != 0:
          transform.translation.x += collide.collision.hit.x
          move.direction.x *= -1

        if collide.collision.hit.y != 0:
          transform.translation.y += collide.collision.hit.y
          move.direction.y *= -1

        game.createExplosion(transform.translation.x, transform.translation.y)

      transform.flags.incl(Dirty)
      game.createTrail(transform.translation.x, transform.translation.y)

      colliders[eid] = collide
      moves[eid] = move
      transforms[eid] = transform

proc sysControlBrick*(game: var Game) =
  var colliders = game.world.get(Collide)
  var fades = game.world.get(Fade)
  var to_kill: seq[DenseHandle]
  
  for (bid, r) in game.world.denseQuery(game.world.query(Transform2d and Fade and Collide and not Move and not Dead)):
    for i in r:
      var brick = makeId(bid, i)
      var collide = colliders[brick]
      var fade = fades[brick]

      if Hit in collide.collision.flags:
        #game.alive.dLayer.set(brick.toIdx)
        to_kill.add(game.world.getDHandleFromID(brick))
        fade.step = 0.05
        let position = game.world.get(Transform2D, brick).translation
        let spawnSeed = eventSeed(2'u32, game.tickId, position.x, position.y)
        if chanceFromSeed(spawnSeed) > 0.98:
          game.createBall(
            float32(game.windowWidth / 2),
            float32(game.windowHeight / 2),
            spawnSeed
          )

        fades[brick] = fade

  for brick in to_kill:
    game.world.addComponent(brick, Dead.toComponentID)

proc sysShake*(game: var Game) =
  var transform = game.world.get(Transform2D, game.camera)
  var shake = game.world.get(Shake, game.camera)

  if shake.duration > 0:
    shake.duration -= 0.01
    transform.translation.x = shakeOffsetFromTick(game.tickId, 0, shake.strength)
    transform.translation.y = shakeOffsetFromTick(game.tickId, 1, shake.strength)

    game.clearColor[0] = shakeColorFromTick(game.tickId, 0)
    game.clearColor[1] = shakeColorFromTick(game.tickId, 1)
    game.clearColor[2] = shakeColorFromTick(game.tickId, 2)
    transform.flags.incl(Dirty)

    if shake.duration <= 0:
      shake.duration = 0
      transform.translation.x = 0
      transform.translation.y = 0
      game.clearColor[0] = 0
      game.clearColor[1] = 0
      game.clearColor[2] = 0
      transform.flags.incl(Dirty)

  game.world.set(game.camera, transform)
  game.world.set(game.camera, shake)

proc updateFading(game: var Game; actor: DenseHandle): bool =
  var transforms = game.world.get(Transform2d)
  var draws = game.world.get(Draw2d)
  var fades = game.world.get(Fade)

  var transform = transforms[actor]
  var draw = draws[actor]
  let fade = fades[actor]
  var flag = false

  if draw.color[3] > 0:
    let step = 255 * fade.step
    draw.color[3] = draw.color[3] - step.uint8
    transform.scale.x -= fade.step
    transform.scale.y -= fade.step
    transform.flags.incl(Dirty)

    transforms[actor] = transform
    draws[actor] = draw

    if transform.scale.x <= 0:
      return true

  return false

proc sysFade*(game: var Game) =
  var to_delete: seq[DenseHandle]
  for (bid, r) in game.world.denseQuery(game.world.query(Fade)):
    for i in r:
      var eid = makeId(bid, i)
      let actor = game.world.getDHandleFromID(eid)
      if game.updateFading(actor):
        to_delete.add(actor)

  for i in countdown(to_delete.high, 0):
    var d = to_delete[i]
    game.world.deleteEntity(d)


proc updateTransform(game: var Game; entity: DenseHandle) =
  let move = game.world.get(Move, entity)
  var transforms = game.world.get(Transform2d)
  
  if move.direction.x != 0 or move.direction.y != 0:
    var transform = transforms[entity]
    
    transform.translation.x += move.direction.x * move.speed
    transform.translation.y += move.direction.y * move.speed
    transform.flags.incl(Dirty)
    transforms[entity] = transform


proc sysMove*(game: var Game) =
  let move = game.world.get(Move)
  var transforms = game.world.get(Transform2d)
  for (bid, r) in game.world.denseQuery(game.world.query(Transform2d and Move)):
    let mb = addr move.blocks[bid].data
    let tb = addr transforms.blocks[bid].data
    for i in r:
      if mb.direction[i].x != 0 or mb.direction[i].y != 0:
        tb.translation[i].x += mb.direction[i].x * mb.speed[i]
        tb.translation[i].y += mb.direction[i].y * mb.speed[i]
        tb.flags[i].incl(Dirty)

proc sysDraw*(game: var Game) =
  let draws = game.world.get(Draw2D)
  let transforms = game.world.get(Transform2d)

  for (bid, r) in game.world.denseQuery(game.world.query(Draw2D and Transform2D and not BallTag and not PaddleTag)):
    let db = draws.blocks[bid]
    let wb = addr transforms.blocks[bid].data.world
    for i in r:
      let draw = db[i]
      let world = wb[i]
      let p = world.origin
      let s = world.scale
      let (x, y) = (p.x, p.y)

      game.renderer.DrawRect2D(rgba(draw.color[0], draw.color[1], draw.color[2], draw.color[3]).toVec, 
        (x1: x-draw.width.float32*s.x/2, y1: y-draw.height.float32*s.y/2, x2: x+draw.width.float32*s.x/2, y2: y+draw.height.float32*s.y/2), filled=true)
 
  for (bid, r) in game.world.denseQuery(game.world.query(PaddleTag)):
    let db = draws.blocks[bid]
    let wb = addr transforms.blocks[bid].data.world
    for i in r:
      let draw = db[i]
      let world = wb[i]
      let p = world.origin
      let s = world.scale
      let (x, y) = (p.x, p.y)

      game.renderer.DrawRect2D(rgba(draw.color[0], draw.color[1], draw.color[2], draw.color[3]).toVec, 
        (x1: x-draw.width.float32*s.x/2, y1: y-draw.height.float32*s.y/2, x2: x+draw.width.float32*s.x/2, y2: y+draw.height.float32*s.y/2), filled=true)
 

  for (bid, r) in game.world.denseQuery(game.world.query(BallTag)):
    let db = draws.blocks[bid]
    let wb = addr transforms.blocks[bid].data.world
    for i in r:
      let draw = db[i]
      let world = wb[i]
      let p = world.origin

      game.renderer.DrawCircleAdv(fpoint(p.x, p.y), BALL_RADIUS,
                        rgba(draw.color[0], draw.color[1], draw.color[2], draw.color[3]), filled=true)