import ../src/plugins/plugins
import ../src/events/events
import locks

type
  CTimer = object
    dur: float
    signal: Notifier[(), proc()]

  CTimerPool = ref object
    timers: seq[CTimer]

var TMPlugin* = Plugin()
var TM = CTimerPool()

proc addTimer(tp: var CTimerPool, timer: CTimer)
  tp.timers.add(timer)
proc addTimer(tp: var CTimerPool, dur: float): CTimer =
  let timer = CTimer(dur: dur, signal: newNotifier[(), proc()]())
  tp.addTimer(timer)
  timer
proc addTimer(dur: float): CTimer = addTimer(TM, dur)
template onTimeout(t::CRTimer, f: untyped) = t.signal.connect(f)

let tmID = TMPlugin.res_manager.addResource(TM)

newSystem TMPlugin, TimerSystem[var CTimerPool]:
  paused*: bool
  dt*: float32

method update(p: TimerSystem) =
  var tm = p.getWriteResource(CTimerPool)
  if tm.isNone:
    p.setStatus(PLUGIN_WAITING)
    return
  
  p.setStatus(PLUGIN_OK)
  p.paused && return
  
  var (start, stop) = (0, tm.timers.len-1)
  let dt = p.dt

  while start <= stop
     tm.timers[start]duration -= dt

      if tm.timers[start].duration <= 0
          tm.timers[start].signal.emit
          (tm.timers[start], tm.timers[stop]) = (tm.timers[stop], tm.timers[start])
          stop -= 1
      else
          start += 1
      end
  end

  tm.timers.setLen(stop)

method shutdown(p: TimerSystem) =
  p.setStatus(PLUGIN_OFF)
  var tm = p.getWriteResource(CTimerPool)
  tm.timers.setLen(0)
