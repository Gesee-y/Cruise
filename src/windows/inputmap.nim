

type
  InputMap* = object
    ## A set of keyboard/mouse-button bindings for a single action.
    ## Keys from both devices are stored in separate sets so that
    ## enum-based look-ups remain O(1) via the underlying SparseSets.
    ##
    ## Construct via the `inputMap` template:
    ##   let Shoot = inputMap(CKey_Z, CKey_Space, CMouseBtn_Left, strength = 2.0)
    keyKeys*      : set[KeyInput]     ## bound keyboard keys
    mouseKeys*    : set[MouseButton]  ## bound mouse buttons
    strength*     : float             ## action strength (default 1.0)


## ============================================================
##  Construction template
##
##  inputMap(key1, key2, ..., keyN, strength = 1.0)
##
##  Keys are either KeyInput or MouseButton enum values.
##  The template dispatches each argument to the right set at
##  compile time, so there is no runtime branching.
##
##  Example:
##    let Shoot = inputMap(CKey_Z, CMouseBtn_Left, strength = 0.5)
## ============================================================

template inputMap*(args: varargs[untyped]): InputMap =
  ## Build an InputMap from a mix of KeyInput / MouseButton values
  ## and an optional `strength` named parameter.
  block:
    var m = InputMap(strength: 1.0)
    for a in args:
      when a is KeyInput:
        m.keyKeys.incl(a)
      elif a is MouseButton:
        m.mouseKeys.incl(a)
      elif a is float or a is float64:
        m.strength = a
    m


## ============================================================
##  Key management
## ============================================================

proc addKey*(inp: var InputMap, key: KeyInput) =
  ## Add a keyboard key to the InputMap.
  inp.keyKeys.incl(key)

proc addKey*(inp: var InputMap, btn: MouseButton) =
  ## Add a mouse button to the InputMap.
  inp.mouseKeys.incl(btn)

proc removeKey*(inp: var InputMap, key: KeyInput) =
  ## Remove a keyboard key from the InputMap.
  inp.keyKeys.excl(key)

proc removeKey*(inp: var InputMap, btn: MouseButton) =
  ## Remove a mouse button from the InputMap.
  inp.mouseKeys.excl(btn)

proc replaceKey*(inp: var InputMap, old, new: KeyInput) =
  ## Replace one keyboard key with another.
  inp.keyKeys.excl(old)
  inp.keyKeys.incl(new)

proc replaceKey*(inp: var InputMap, old, new: MouseButton) =
  ## Replace one mouse button with another.
  inp.mouseKeys.excl(old)
  inp.mouseKeys.incl(new)

proc hasKey*(inp: InputMap, key: KeyInput): bool =
  ## Return true if the keyboard key is bound in this InputMap.
  key in inp.keyKeys

proc hasKey*(inp: InputMap, btn: MouseButton): bool =
  ## Return true if the mouse button is bound in this InputMap.
  btn in inp.mouseKeys

proc getKeyKeys*(inp: InputMap): set[KeyInput] =
  ## Return all bound keyboard keys.
  inp.keyKeys

proc getMouseKeys*(inp: InputMap): set[MouseButton] =
  ## Return all bound mouse buttons.
  inp.mouseKeys


## ============================================================
##  Query helpers  (mirror the per-key helpers in event_loop.nim)
## ============================================================

proc isKeyPressed*(win: CWindow, inp: InputMap): bool =
  ## Return true if ANY bound key or button is currently held down.
  for key in inp.keyKeys:
    if win.isKeyPressed(key): return true
  for btn in inp.mouseKeys:
    if win.isMouseButtonPressed(btn): return true
  false

proc isKeyJustPressed*(win: CWindow, inp: InputMap): bool =
  ## Return true if ANY bound key or button was pressed this frame.
  for key in inp.keyKeys:
    if win.isKeyJustPressed(key): return true
  for btn in inp.mouseKeys:
    if win.isMouseButtonJustPressed(btn): return true
  false

proc isKeyReleased*(win: CWindow, inp: InputMap): bool =
  ## Return true when ALL bound keys and buttons are released.
  not win.isKeyPressed(inp)

proc isKeyJustReleased*(win: CWindow, inp: InputMap): bool =
  ## Return true if ANY bound key or button was released this frame.
  for key in inp.keyKeys:
    if win.isKeyJustReleased(key): return true
  for btn in inp.mouseKeys:
    if win.isMouseButtonJustReleased(btn): return true
  false