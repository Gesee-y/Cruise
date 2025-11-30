#################################################################################################################################################
########################################################## STATE OPERATIONS #####################################################################
#################################################################################################################################################

proc delay*[T,L](n: var Notifier[T,L], dur:int, first:bool=false) =
  let d = Delay(first, dur)
  n.state.delay = d

proc delayFirst*[T,L](n: var Notifier[T,L], first:bool=false) =
  var d = n.state.delay
  doAssert d is Delay

  d.first = first

proc noDelay*[T,L](n: var Notifier[T,L], dur:int, first:bool=false) =
  let d = Delay(first, dur)
  n.state.delay = NoDelay()

proc syncNotif*[T,L](n: var Notifier[T,L], consumes:bool=false, priorities:bool=false) =
  n.state.emission = SyncState(consumes:consumes, priorities:priorities)

proc parrallelNotif*[T,L](n: var Notifier[T,L], wait:bool=false) =
  n.state.emission = ParallelState(wait:wait, mode:SingleTask())

proc singleTask*[T,L](n: var Notifier[T,L]) =
  var em = n.state.emission
  doAssert em is ParralleState

  em.mode = SingleTask()

proc multipleTask*[T,L](n: var Notifier[T,L]) =
  var em = n.state.emission
  doAssert em is ParralleState

  em.mode = MultipleTask()

proc enableValue*[T,L](n: var Notifier[T,L], ignore_eqv=false) =
  n.state.mode = ValState(ignore_eqvalue:ignore_eqv)

proc disableValue*[T,L](n: var Notifier[T,L]) =
  n.state.mode = EmitState()

proc ignoreEqValue*[T,L](n: var Notifier[T,L], ignore_eqv=true) =
  var m = n.state.mode
  doAssert m is ValState

  m.ignore_eqvalue = ignore_eqv

proc execAll*[T,L](n: var Notifier[T,L]) =
  n.state.exec = ExecAll()

proc execLatest*[T,L](n: var Notifier[T,L], count:int=1) =
  n.state.exec = ExecLatest(count:count)

proc execOldest*[T,L](n: var Notifier[T,L], count:int=1) =
  n.state.exec = ExecOldest(count:count)