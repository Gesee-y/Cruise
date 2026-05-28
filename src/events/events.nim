# Event system for Cruise
# This implements a stateful event system. You can change the state of the events to make them behave differently 
import macros
import locks
import threadpool
import asyncdispatch
import os
import algorithm
import sequtils

## Cruise Events is an event system built for game development. Inspired by godot signal, it offers an ergonomic and highly flexible event pipeline.


## Determine how many event can be queued for deletion
const CHANNEL_SIZE = 64

type
  TaskVar = enum
    ## Determine how a group of callbacks should be called in a multithreaded context.
    ## By default, `tsSingle` is used.
    ## - `tsSingle` -> Callback are executed one after the other in a single task
    ## - `tsMulti` -> A task is created for each callback and they all run in parallel
    tsSingle, tsMulti

  EmissionVar = enum
    ## Determine how the callback are called. `emSync` is used by default.
    ## - `emSync` -> Synchronous calls
    ## - `emParallel` -> Asynchronous calls
    emSync, emParallel

  NotifVar = enum
    ## Determine whether the `Notifier` should keep track of the latest emitted value or not.
    ## By default `nEmit` is used.
    ## - `nValue` -> Keep the latest emitted value
    ## - `nEmit` -> Ignore it
    nValue, nEmit

  ExecVar = enum
    ## Determine which callbacks should be called. By default `exAll` is used.
    ## - `exAll`: All the callbacks are executed
    ## - `exOldest`: Only the oldest callbacks are called, and the others are ignored until they finish
    ## - `exLatest`: Only the latest callbacks are called, and the others are ignored until they finish.
    ## > **Note**:
    ## > `exOldest` and `exLatest` are mostly useful in multithreaded context when you don't want to be flooded by useless callbacks 
    exAll, exOldest, exLatest

  DelayVar = enum
    ## Whether there is a delay between emissions or not.
    ## Self explanatory.
    ## `dNone` is used by default.
    dNone, dDelay

  EmissionState = object
    ## Encapsultate how the Notifier can be executed
    ## They define how it should emit signals (synchronously, asynchronously, etc).
    ## They are basically his current state for emission.
    mode:TaskMode
    consumes:bool
    case kind : EmissionVar
    of emSync:
      priorities:bool
    of emParallel:
      wait:bool
  
  NotifierState[T] = ref object
    ## The notifier State, it contains all the necessary information about the state of the notifier.
    ## Influenced by NotifVar.
    case kind: NotifVar
    of nValue:
      value:T
      ignore_eqvalue:bool
    of nEmit:
      discard

  TaskMode = object
    ## TaskMode define how the emission should be done for the asynchronous state.
    kind:TaskVar

  DelayMode = object
    ## Define if there should be a delay between emissions.
    ## if yes, allows you to configure it (if the first emission should be delayed, the duration, etc)
    case kind:DelayVar
    of dNone:
      discard
    of dDelay:
      first:bool
      duration:int

  ExecMode = object
    ## Represent the ways in which Listeners are filtered.
    case kind:ExecVar
    of exAll:
      discard
    of exLatest, exOldest:
      count:int 
        
  StateMismatch* = object of CatchableError
    ##Exception thrown when a function is called on Notifier with the wrong state.

  Listener*[T] = ref object
    ## Concrete Listeners impl.
    ## Where `T` is the callback type
    ## `Consume` is the whether the callback should be remoed after its execution
    ## `priority` define if it will be executed before the other.
    callback:T
    consume:bool
    priority:int
    stop:bool

  EmissionCallback[T,L] = object
    ## Concrete instance of an emission of a notifier. Useful for filtering.
    ## Listener instance for this emission is copied (necessary for it to be a snapshot of the current state of the notifier)
    listeners:seq[Listener[L]]
    data:T

  StateData[T,L] = ref object
    ## Keep all the necessary information about the state of a Notifier
    emission:EmissionState
    mode:NotifierState[T]
    exec:ExecMode
    delay:DelayMode
    stream:Channel[EmissionCallback[T,L]]
    check:bool

  Notifier*[T,L] = ref object
    ## Concrete Notifier object, used for the observer pattern.
    ## It uses a state machine to allow users to modify its behavior at runtime.
    cond:Cond
    lck:Lock
    listeners*:seq[Listener[L]]
    buffer:seq[EmissionCallback[T,L]]
    state*:StateData[T,L]

  Observer[T] = proc(val: T) {.closure.}

  CRSubject*[T] = ref object
    ## Lightweight implementation of the Notifiers
    ## Less overhead, less powers
    value*: T
    observers: seq[Observer[T]]

# ############################################################## ACCESSORS ###############################################################

proc newCRSubject*[T](value: T): CRSubject[T] =
  ## Create a new lightweight subject with value type `T` (the type the new notifier will accept, better enter a value)
  CRSubject[T](value: value, observers: @[])

proc callback*[L](l:Listener[L]): L = 
  ## Return the callback of a lister
  l.callback

template getstate*(n:Notifier): untyped = 
  ## Return the state of a notifier
  return n.state

template getstream(s:StateData): untyped = 
  ## Return the channel storing all the emissions
  ## The `stream`.
  s.stream

# ############################################################ CONSTRUCTORS ##############################################################

# All the names are self-explanatory

proc ExecAll():ExecMode =
  return ExecMode(kind:exAll)

proc ExecLatest(count:int):ExecMode =
  return ExecMode(kind:exLatest,count:count)

proc ExecOldest(count:int):ExecMode =
  return ExecMode(kind:exOldest, count:count)

proc newStateMismatch(msg:string): ref StateMismatch = 
  return newException(StateMismatch, message=msg)

proc SingleTask():TaskMode =
  return TaskMode(kind:tsSingle)

proc MultipleTask():TaskMode =
  return TaskMode(kind:tsMulti)

proc NoDelay():DelayMode =
  return DelayMode(kind: dNone)

proc Delay(first:bool, dur:int): DelayMode =
  return DelayMode(kind: dDelay, first:first, duration:dur)

proc SyncState(priorities=false, consumes:bool=false): EmissionState =
  return EmissionState(mode: SingleTask(), kind: emSync, priorities: priorities, consumes: consumes)

proc ParallelState(w:bool, mode:TaskMode=SingleTask(), consumes:bool=false): EmissionState =
  return EmissionState(mode: mode, kind: emParallel, wait: w, consumes: consumes)

proc ValState[T](ignore_eqvalue:bool): NotifierState[T] =
  return NotifierState[T](kind: nValue, ignore_eqvalue: ignore_eqvalue)

proc EmitState[T](): NotifierState[T] =
  return NotifierState[T](kind: nEmit)

proc newStateData[T,L](): StateData[T,L] = 
  var chan = Channel[EmissionCallback[T,L]]()
  chan.open(CHANNEL_SIZE)
  
  return StateData[T,L](emission: SyncState(), 
    mode: EmitState[T](), 
    exec: ExecAll(), delay: NoDelay, stream: chan, check:false)

proc newNotifier*[T,L](): Notifier[T,L] =
  ## Build a new notifier
  ## `T` is a tuple of the data the notifier accept.
  ## `L` is the type of the proc that are used as callbacks 
  var cond = Cond()
  var lck = Lock()

  lck.initLock()
  cond.initCond()
  
  return Notifier[T,L](cond:cond, lck:lck, listeners:newSeq[Listener[L]](), buffer:newSeq[EmissionCallback[T,L]](), state:newStateData[T,L]())

################################################################ HELPERS ################################################################

macro notifier*(args:untyped) =
  ## Create a typed notifier with named parameters.
  ##   
  ## This macro generates a notifier with a specific signature based on the provided parameters.
  ## It automatically infers the tuple type for data and the procedure type for callbacks.
  ##   
  ## Parameters:
  ##   - `args`: Untyped arguments where first element is the notifier name, followed by name:type pairs
  ##  
  ## Returns:
  ##   A notifier declaration initialized with the appropriate types
  ##  
  ## Example:
  ## ```nim
  ## # Create a notifier for mouse events with x, y coordinates
  ## notifier mouseClick(x: int, y: int)
  ## # Creates: var mouseClick = newNotifier[(x: int, y: int), proc(x: int, y: int)]()
  ##    
  ## # Create a notifier for simple string messages
  ## notifier messageReceived(msg: string)
  ## # Creates: var messageReceived = newNotifier[(msg: string), proc(msg: string)]()
  ##    
  ## # Use the notifier
  ## mouseClick.open()
  ## proc onMouseClick(x: int, y: int) =
  ##  echo "Clicked at: ", x, ", ", y
  ##    
  ## mouseClick.connect(onMouseClick)
  ## mouseClick.emit((10, 20))  # Prints "Clicked at: 10, 20"
  ## ```

  let nname = args[0]
  nname.expectKind(nnkIdent)

  # Build the type signature from the provided arguments
  var names = newNimNode(nnkBracket)
  var types = newNimNode(nnkPar)
  var namedtypes = newNimNode(nnkTupleTy)
  var procty = newNimNode(nnkProcTy)
  var ty = args[1..<args.len]
  
  var params = newNimNode(nnkFormalParams)
  params.add(newNimNode(nnkEmpty))
  procty.add(params)
  procty.add(newNimNode(nnkEmpty))

  if args.len > 1:
    # Process each parameter and build the tuple and proc types
    for col in ty:
      let ident = newNimNode(nnkIdentDefs)
      let id = col[0]
      let t = col[1]
      names.add(id)
      types.add(t)
      ident.add(id)
      ident.add(t)
      ident.add(newNimNode(nnkEmpty))
      params.add(ident)
      namedtypes.add(ident)
  
  return quote do:
    var `nname` = newNotifier[`namedtypes`, `procty`]()

# Call a function with tuple elements as separate arguments.  
# This macro unpacks a tuple and passes each element as an individual argument to the function.
# Allows calling fn(tup[0], tup[1], ..., tup[n]) with cleaner syntax.
macro destructuredCall(fn:untyped, tup:typed) =
  let n = len(getType(tup))-1
  var callex = newNimNode(nnkCall)
  callex.add(fn)
  
  # Unpack each tuple element as a separate argument
  for i in 0..<n:
    callex.add((quote do: `tup`[`i`]))

  return quote do:
   `callex`

# Call a function with tuple elements and capture the return value.
# Similar to destructuredCall but stores the result in a variable.
macro destructuredCallRet(name:untyped, fn:untyped, tup:typed) =
  let n = len(getType(tup))-1
  var callex = newNimNode(nnkCall)
  callex.add(fn)
  
  for i in 0..<n:
    callex.add((quote do: `tup`[`i`]))

  return quote do:
   let `name` = `callex`

# Generate an anonymous function with parameters inferred from a typed object.
# Creates a lambda that accepts individual parameters and bundles them into a tuple
# for processing in the function body.
macro anoFunc(name:untyped, obj:typed, body:untyped) =
  var data = obj.getType()[1]

  var f = newNimNode(nnkLambda)
  f.add(newNimNode(nnkEmpty))
  f.add(newNimNode(nnkEmpty))
  f.add(newNimNode(nnkEmpty))

  var params = newNimNode(nnkFormalParams)
  params.add(newNimNode(nnkEmpty))

  # Bundle all parameters into a tuple for easier handling
  var vs = newNimNode(nnkLetSection)
  var arg_bundle = newNimNode(nnkIdentDefs)
  vs.add(arg_bundle)
  arg_bundle.add(ident("allarg"))
  arg_bundle.add(newNimNode(nnkEmpty))

  var tup = newNimNode(nnkTupleConstr)
  # Use alphabetic names for parameters (up to 25 parameters supported)
  let ids = @["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "w", "y","z"]

  for i in 1..<data.len:
    var ident = newNimNode(nnkIdentDefs)
    let id = ident(ids[i-1])
    ident.add(id)
    tup.add(id)
    ident.add(data[i])
    ident.add(newNimNode(nnkEmpty))

    params.add(ident)

  arg_bundle.add(tup)

  f.add(params)
  f.add(newNimNode(nnkEmpty))
  f.add(newNimNode(nnkEmpty))
  
  var stmt = newNimNode(nnkStmtList)
  stmt.add(vs)

  for i in 0..<body[1].len:
    stmt.add(body[1][i])

  f.add(stmt)

  return quote do:
    var `name` = `f`


include "pipeline.nim"
include "operations.nim"
include "state_operations.nim"
include "val_operations.nim"