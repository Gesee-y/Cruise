#############################################################################################################################
####################################################### EVENT LOOP ##########################################################
#############################################################################################################################

## Fired whenever any event is received, carrying the raw event kind.
notifier NOTIF_EVENT_RECEIVED(event: pointer, kind: int)

## Fired when a window-level event occurs (resize, move, focus, …).
## d1 and d2 carry optional integer payload (e.g. new width/height).
notifier NOTIF_WINDOW_EVENT(win: CWindow, ev: WindowEvent)

## Fired when one or more keyboard keys have been processed for a window.
notifier NOTIF_KEYBOARD_INPUT(win: CWindow, ev: KeyboardEvent)

## Fired when the mouse cursor has moved.
notifier NOTIF_MOUSE_MOTION(win: CWindow, ev: MouseMotionEvent)

## Fired when the mouse wheel has scrolled.
notifier NOTIF_MOUSE_WHEEL(win: CWindow, ev: MouseWheelEvent)

## Fired when a mouse button state changes.
notifier NOTIF_MOUSE_BUTTON(win: CWindow, ev: MouseClickEvent)

## Fired when the user requests to quit the application.
notifier NOTIF_QUIT_EVENT()


## ============================================================
##  Abstract backend interface
##  Concrete backends (SDL, GLFW, …) override these procs.
## ============================================================

method getEvents*(app: CWindow) {.base.} = discard

## ## Poll and dispatch all pending OS events for the given app.
## Implementations should emit the appropriate NOTIF_* signals
## and update the InputState of each CWindow.
proc getEvents*(app: CApp) = 
  for win in app.windows:
    win.getEvents()

## Handle a single window-level OS event.
## Override per backend to translate native events into WindowEvent
## and emit NOTIF_WINDOW_EVENT.
method handleWindowEvent*(win: CWindow, event: pointer) {.base.} = discard

## Translate and store keyboard input for a window.
## Override per backend. Emit NOTIF_KEYBOARD_INPUT when inputs are found.
method handleKeyboardInputs*(win: CWindow) {.base.} =
  NOTIF_KEYBOARD_INPUT.emit((win, KeyboardEvent()))

## Translate and store mouse events (motion, wheel, buttons) for a window.
## Override per backend. Emit the relevant NOTIF_MOUSE_* signal.
method handleMouseEvents*(win: CWindow) {.base.} =
  NOTIF_MOUSE_MOTION.emit((win, MouseMotionEvent()))

## Return the current mouse cursor position for the given window.
## Override per backend.
method getMousePosition*(win: CWindow): tuple[x, y: int] {.base.} = (0, 0)

## Translate a raw backend key value into a KeyInput enum value.
## Override per backend (e.g. "SDLK_a" → CKey_A, "KEY_A" → CKey_A).
method convertKey*(win: CWindow, rawKey: int): KeyInput {.base.} = CKey_None


## ============================================================
##  InputState accessors
## ============================================================

proc getInputsState*(win: CWindow): var InputState =
  ## Return a mutable reference to the window's InputState.
  win.inputs

proc getInputsData*(win: CWindow): var InputData =
  ## Return a mutable reference to the window's InputData.
  win.inputs.data

proc getKeyboardData*(win: CWindow): var SparseSet[KeyInput, KeyboardEvent] =
  ## Return the keyboard sparse set for direct inspection.
  win.inputs.data.keyboard

proc getMouseButtonData*(win: CWindow): var SparseSet[MouseButton, MouseClickEvent] =
  ## Return the mouse-button sparse set for direct inspection.
  win.inputs.data.mouseButtons

proc getAxesData*(win: CWindow): var SparseSet[MouseAxis, AxisEvent] =
  ## Return the axes sparse set for direct inspection.
  win.inputs.data.axes


## ============================================================
##  Keyboard query helpers
## ============================================================

proc isKeyJustPressed*(win: CWindow, key: KeyInput): bool =
  ## Return true if `key` was pressed this frame (rising edge only).
  let kb = win.inputs.data.keyboard
  if not kb.contains(key): return false
  kb[key].just_pressed

proc isKeyPressed*(win: CWindow, key: KeyInput): bool =
  ## Return true while `key` is held down.
  let kb = win.inputs.data.keyboard
  if not kb.contains(key): return false
  kb[key].pressed

proc isKeyJustReleased*(win: CWindow, key: KeyInput): bool =
  ## Return true if `key` was released this frame (falling edge only).
  let kb = win.inputs.data.keyboard
  if not kb.contains(key): return false
  kb[key].just_released

proc isKeyReleased*(win: CWindow, key: KeyInput): bool =
  ## Return true while `key` is not held down.
  not win.isKeyPressed(key)

## App-wide variants: true if ANY window satisfies the condition.

proc isKeyJustPressed*(app: CApp, key: KeyInput): bool =
  for win in app.windows:
    if win.isKeyJustPressed(key): return true

proc isKeyPressed*(app: CApp, key: KeyInput): bool =
  for win in app.windows:
    if win.isKeyPressed(key): return true

proc isKeyJustReleased*(app: CApp, key: KeyInput): bool =
  for win in app.windows:
    if win.isKeyJustReleased(key): return true

proc isKeyReleased*(app: CApp, key: KeyInput): bool =
  for win in app.windows:
    if win.isKeyReleased(key): return true


## ============================================================
##  Mouse button query helpers
## ============================================================

proc isMouseButtonJustPressed*(win: CWindow, btn: MouseButton): bool =
  ## Return true if `btn` was pressed this frame (rising edge only).
  let mb = win.inputs.data.mouseButtons
  if not mb.contains(btn): return false
  mb[btn].just_pressed

proc isMouseButtonPressed*(win: CWindow, btn: MouseButton): bool =
  ## Return true while `btn` is held down.
  let mb = win.inputs.data.mouseButtons
  if not mb.contains(btn): return false
  mb[btn].pressed

proc isMouseButtonJustReleased*(win: CWindow, btn: MouseButton): bool =
  ## Return true if `btn` was released this frame (falling edge only).
  let mb = win.inputs.data.mouseButtons
  if not mb.contains(btn): return false
  mb[btn].just_released

proc isMouseButtonReleased*(win: CWindow, btn: MouseButton): bool =
  ## Return true while `btn` is not held down.
  not win.isMouseButtonPressed(btn)


## ============================================================
##  Axis query helpers
## ============================================================

proc getAxis*(win: CWindow, axis: MouseAxis): AxisEvent =
  ## Return the current AxisEvent for `axis`.
  ## Falls back to a zeroed event if the axis has never been seen.
  let axes = win.inputs.data.axes
  if axes.contains(axis):
    return axes[axis]
  # Default fallback depending on the requested axis
  case axis
  of CMouseAxis_WheelX, CMouseAxis_WheelY:
    result = AxisEvent(kind: AxisWheel,  wheel:  MouseWheelEvent())
  else:
    result = AxisEvent(kind: AxisMotion, motion: MouseMotionEvent())


## ============================================================
##  Main event loop
##
##  Usage:
##    let app = CApp(windows: @[myWin])
##    while running:
##      eventLoop(app)
##      if myWin.isKeyJustPressed(CKey_Escape): running = false
## ============================================================

proc eventLoop*(app: CApp) =
  ## One iteration of the event loop:
  ##   1. Reset per-frame counters for every window.
  ##   2. Poll OS events (backend-specific via getEvents).
  ##   3. Advance the input state machine for every window.
  for win in app.windows:
    win.inputs.resetCounts()

  app.getEvents()

  for win in app.windows:
    win.inputs.updateInputState()