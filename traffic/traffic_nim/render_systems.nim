import ../../src/plugins/plugins
import ../../src/la/La
import tables
import math
import ../../src/render/render
import ../../stdplugin/sdlrender/sdlrender
import components
import ../../externalLibs/sdl3_nim/src/sdl3_nim

type TrafficRenderSystem* = ref object of PluginNode
  manager*: ptr PResourceManager
  ren*: ptr CSDLRenderer
  camX*, camY*: float32
  camZoom*: float32

method update*(self: TrafficRenderSystem) =
  var laneSt = getResource[Storage[Lane]](self.manager[], idLane)
  var carsSt = getResource[Storage[LaneCars]](self.manager[], idLaneCars)

  # Clear background
  ClearTarget(self.ren[], self.ren[].data.screenKey, rgba(30, 30, 40, 255))

  let screenW = 800.0f32
  let screenH = 600.0f32
  let zoom = self.camZoom
  let cx = self.camX
  let cy = self.camY
  
  let worldLeft = cx
  let worldTop = cy
  let worldRight = cx + screenW / zoom
  let worldBottom = cy + screenH / zoom

  var drawnLanes = 0
  var drawnCars = 0

  for id, lane in laneSt.data:
    # 1. Frustum Culling
    let minX = min(lane.startX, lane.endX)
    let maxX = max(lane.startX, lane.endX)
    let minY = min(lane.startY, lane.endY)
    let maxY = max(lane.startY, lane.endY)
    
    if maxX < worldLeft or minX > worldRight or maxY < worldTop or minY > worldBottom:
      continue # Outside viewport, clip!

    drawnLanes += 1

    # 2. Geometry calculations
    let dx = lane.endX - lane.startX
    let dy = lane.endY - lane.startY
    let len = sqrt(dx*dx + dy*dy)
    if len <= 0.001f32: continue
    
    let ux = dx / len
    let uy = dy / len
    
    let laneWidth = 6.0f32 # scale thickness
    let perpX = -uy * laneWidth / 2.0f32
    let perpY = ux * laneWidth / 2.0f32
    
    # 3. Draw Lane Polygon
    let p1 = fpoint((lane.startX + perpX - cx)*zoom, (lane.startY + perpY - cy)*zoom)
    let p2 = fpoint((lane.startX - perpX - cx)*zoom, (lane.startY - perpY - cy)*zoom)
    let p3 = fpoint((lane.endX - perpX - cx)*zoom, (lane.endY - perpY - cy)*zoom)
    let p4 = fpoint((lane.endX + perpX - cx)*zoom, (lane.endY + perpY - cy)*zoom)
    
    DrawPolygon(self.ren[], @[p1, p2, p3, p4], rgba(80, 80, 80, 255), true)
    
    # 3b. Draw Traffic Light (Offset significantly to the right and back)
    let lightOffsetDist = 18.0f32
    let lightBackDist = 12.0f32
    let lightWorldX = lane.endX + perpX*lightOffsetDist/float32(laneWidth/2.0) - ux*lightBackDist
    let lightWorldY = lane.endY + perpY*lightOffsetDist/float32(laneWidth/2.0) - uy*lightBackDist
    
    let lightPos = fpoint((lightWorldX - cx)*zoom, (lightWorldY - cy)*zoom)
    let lightColor = case lane.lightState:
      of 1: rgba(255, 50, 50, 255)  # Red
      of 2: rgba(255, 180, 50, 255) # Yellow/Orange
      else: rgba(50, 255, 50, 255) # Green
    DrawCircleAdv(self.ren[], lightPos, 6.0f32 * zoom, lightColor, true)
    
    # 4. Draw Cars
    if carsSt.has(id):
      let c = addr carsSt.data[id]
      for i in 0..<c.count:
        drawnCars += 1
        let carPos = c.cars[i].position
        let carWorldX = lane.startX + ux * carPos
        let carWorldY = lane.startY + uy * carPos
        let carLen = c.cars[i].length
        
        let hw = 2.0f32 # half width
        let hl = float32(carLen) / 2.0f32 # half length
        
        let cp1 = fpoint((carWorldX + ux*hl + perpX/laneWidth*hw*2.0 - cx)*zoom, (carWorldY + uy*hl + perpY/laneWidth*hw*2.0 - cy)*zoom)
        let cp2 = fpoint((carWorldX + ux*hl - perpX/laneWidth*hw*2.0 - cx)*zoom, (carWorldY + uy*hl - perpY/laneWidth*hw*2.0 - cy)*zoom)
        let cp3 = fpoint((carWorldX - ux*hl - perpX/laneWidth*hw*2.0 - cx)*zoom, (carWorldY - uy*hl - perpY/laneWidth*hw*2.0 - cy)*zoom)
        let cp4 = fpoint((carWorldX - ux*hl + perpX/laneWidth*hw*2.0 - cx)*zoom, (carWorldY - uy*hl + perpY/laneWidth*hw*2.0 - cy)*zoom)
        
        DrawPolygon(self.ren[], @[cp1, cp2, cp3, cp4], rgba(220, 200, 50, 255), true)
        
        # 4b. Draw Brake Lights if car is stopped or slowing
        if c.cars[i].targetSpeed < 1.0f or c.cars[i].speed < 0.2f:
          let blSize = 1.2f32 * zoom
          let bl1 = fpoint((carWorldX - ux*hl + perpX/laneWidth*hw*1.2 - cx)*zoom, (carWorldY - uy*hl + perpY/laneWidth*hw*1.2 - cy)*zoom)
          let bl2 = fpoint((carWorldX - ux*hl - perpX/laneWidth*hw*1.2 - cx)*zoom, (carWorldY - uy*hl - perpY/laneWidth*hw*1.2 - cy)*zoom)
          DrawCircleAdv(self.ren[], bl1, blSize, rgba(255, 0, 0, 255), true)
          DrawCircleAdv(self.ren[], bl2, blSize, rgba(255, 0, 0, 255), true)

  # Draw stats
  drawDebugStats(self.ren[], 10.0f32, 10.0f32)
  
  # Calculate total cars across all instances
  var totalCarsCount = 0
  for id, cars_val in carsSt.data:
    totalCarsCount += int(cars_val.count)

  let line = "Rendered: " & $drawnCars & " Cars, " & $drawnLanes & " Lanes. Total Sim: " & $totalCarsCount & " Cars"
  discard SDL_RenderDebugText(self.ren[].data.renderer, 10.0f32, 110.0f32, line.cstring)
