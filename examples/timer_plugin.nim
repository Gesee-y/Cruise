import ../src/plugins/plugins
import ../src/events/events
import options, std/monotimes

type
  CTimer = object
    duration: float
    signal: Notifier[(), proc()]

  CTimerPool = ref object
    timers: seq[CTimer]

  PauseTimer = object
  ResumeTimer = object

var TMPlugin* = Plugin()
var TM = CTimerPool()

proc addTimer(tp: var CTimerPool, timer: CTimer) =
  tp.timers.add(timer)
proc addTimer(tp: var CTimerPool, dur: float): CTimer =
  let timer = CTimer(duration: dur, signal: newNotifier[(), proc()]())
  tp.addTimer(timer)
  timer
proc addTimer(dur: float): CTimer = addTimer(TM, dur)
template onTimeout(t:CTimer, f: untyped) = t.signal.connect(f)

let tmID = TMPlugin.res_manager.addResource(TM)

let id = 
  newSystem(TMPlugin, TimerSystem[var CTimerPool]):
    paused: bool

method update(p: var TimerSystem) =
  if p.paused:
    let resume = p.bus.getMessage[ResumeTimer]()
    if resume.isNone: 
      return

    p.paused = false

  var res = p.getWriteResource[:CTimerPool]
  if not res.isSome:
    p.setStatus(PLUGIN_WAITING)
    return

  let paused = p.bus.getMessage[PauseTimer]()
  if paused.isSome:
    p.paused = true
    return

  var tm = res.get()
  p.setStatus(PLUGIN_OK)
  
  var (start, stop) = (0, tm.timers.len-1)
  let dt = (getMonoTime().ticks - p.lastTick).float * 1e-9 # We move per sec

  while start <= stop:
    tm.timers[start].duration -= dt

    if tm.timers[start].duration <= 0:
      tm.timers[start].signal.emit(())
      (tm.timers[start], tm.timers[stop]) = (tm.timers[stop], tm.timers[start])
      stop -= 1
    else:
      start += 1

  tm.timers.setLen(stop)

method shutdown(p: TimerSystem) =
  p.setStatus(PLUGIN_OFF)
  var tm = p.getWriteResource[:CTimerPool]
  tm.get().timers.setLen(0)
