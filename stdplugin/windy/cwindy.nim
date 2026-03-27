##############################################################################################################################
#################################################### WINDY BACKEND ###########################################################
##############################################################################################################################
##
##  Concrete backend implementing the CWindow/CApp abstraction using the Windy library.
##
##  Windy API used:
##    newWindow(title, ivec2(w, h))  → windy.Window
##    pollEvents()                   → processes all pending OS events
##    window.closeRequested          → bool, set by OS when user closes window
##    window.size                    → IVec2
##    window.pos                     → IVec2
##    window.pos=                    → move window
##    window.size=                   → resize window
##    window.title=                  → change title
##    window.fullscreen=             → bool
##    window.visible=                → bool
##    window.minimized=              → bool
##    window.maximized=              → bool  (setter only on some platforms)
##    window.focused                 → bool (read)
##    window.focus()                 → raise / give focus
##    window.close()                 → close and release
##    window.mousePos                → IVec2
##    window.scrollDelta             → Vec2
##    window.buttonDown[]            → set[Button]  held this frame
##    window.buttonPressed[]         → set[Button]  just pressed
##    window.buttonReleased[]        → set[Button]  just released
##    window.onButtonPress           → ButtonCallback  proc(b: Button)
##    window.onButtonRelease         → ButtonCallback  proc(b: Button)
##    window.onMouseMove             → Callback        proc()
##    window.onScroll                → Callback        proc()
##    window.onResize                → Callback        proc()
##    window.onMove                  → Callback        proc()
##    window.onFocusChange           → Callback        proc()
##    window.onCloseRequest          → Callback        proc()
##    window.onFrame                 → Callback        proc()   (optional, not used here)
##
##  How it fits the abstraction
##  ───────────────────────────
##  • CWindyWindow  wraps a windy.Window alongside the CWindow base fields.
##  • initWindow    creates the windy window and wires all callbacks so that
##    every OS event is translated to the CWindow InputState AND the appropriate
##    NOTIF_* notifier is emitted.
##  • getEvents     calls pollEvents() – that triggers the callbacks synchronously.
##  • All other lifecycle methods delegate to the windy window properties/procs.

import windy

# Pull in the abstraction (adjust the path to match your project layout).
include "../window/window"

## ============================================================
##  CWindyWindow — extends CWindow with a windy handle
## ============================================================

type
  CWindyWindow* = ref object of CWindow
    wHandle*: windy.Window   ## the underlying Windy window


## ============================================================
##  Key mapping  Windy Button → KeyInput
## ============================================================

proc windyButtonToKeyInput(b: windy.Button): KeyInput =
  case b
  of KeyA:           CKey_A
  of KeyB:           CKey_B
  of KeyC:           CKey_C
  of KeyD:           CKey_D
  of KeyE:           CKey_E
  of KeyF:           CKey_F
  of KeyG:           CKey_G
  of KeyH:           CKey_H
  of KeyI:           CKey_I
  of KeyJ:           CKey_J
  of KeyK:           CKey_K
  of KeyL:           CKey_L
  of KeyM:           CKey_M
  of KeyN:           CKey_N
  of KeyO:           CKey_O
  of KeyP:           CKey_P
  of KeyQ:           CKey_Q
  of KeyR:           CKey_R
  of KeyS:           CKey_S
  of KeyT:           CKey_T
  of KeyU:           CKey_U
  of KeyV:           CKey_V
  of KeyW:           CKey_W
  of KeyX:           CKey_X
  of KeyY:           CKey_Y
  of KeyZ:           CKey_Z
  of Key0:           CKey_0
  of Key1:           CKey_1
  of Key2:           CKey_2
  of Key3:           CKey_3
  of Key4:           CKey_4
  of Key5:           CKey_5
  of Key6:           CKey_6
  of Key7:           CKey_7
  of Key8:           CKey_8
  of Key9:           CKey_9
  of KeySpace:       CKey_Space
  of KeyEnter:       CKey_Enter
  of KeyEscape:      CKey_Escape
  of KeyTab:         CKey_Tab
  of KeyBackspace:   CKey_Backspace
  of KeyDelete:      CKey_Delete
  of KeyInsert:      CKey_Insert
  of KeyHome:        CKey_Home
  of KeyEnd:         CKey_End
  of KeyPageUp:      CKey_PageUp
  of KeyPageDown:    CKey_PageDown
  of KeyUp:          CKey_Up
  of KeyDown:        CKey_Down
  of KeyLeft:        CKey_Left
  of KeyRight:       CKey_Right
  of KeyF1:          CKey_F1
  of KeyF2:          CKey_F2
  of KeyF3:          CKey_F3
  of KeyF4:          CKey_F4
  of KeyF5:          CKey_F5
  of KeyF6:          CKey_F6
  of KeyF7:          CKey_F7
  of KeyF8:          CKey_F8
  of KeyF9:          CKey_F9
  of KeyF10:         CKey_F10
  of KeyF11:         CKey_F11
  of KeyF12:         CKey_F12
  of KeyLeftShift:   CKey_LShift
  of KeyRightShift:  CKey_RShift
  of KeyLeftControl: CKey_LCtrl
  of KeyRightControl:CKey_RCtrl
  of KeyLeftAlt:     CKey_LAlt
  of KeyRightAlt:    CKey_RAlt
  of KeyLeftSuper:   CKey_LSuper
  of KeyRightSuper:  CKey_RSuper
  of KeyCapsLock:    CKey_CapsLock
  of KeyNumLock:     CKey_NumLock
  of KeyScrollLock:  CKey_ScrollLock
  of KeyPrintScreen: CKey_PrintScreen
  of KeyPause:       CKey_Pause
  of Numpad0:        CKey_Num0
  of Numpad1:        CKey_Num1
  of Numpad2:        CKey_Num2
  of Numpad3:        CKey_Num3
  of Numpad4:        CKey_Num4
  of Numpad5:        CKey_Num5
  of Numpad6:        CKey_Num6
  of Numpad7:        CKey_Num7
  of Numpad8:        CKey_Num8
  of Numpad9:        CKey_Num9
  of KeyComma:       CKey_Comma
  of KeyPeriod:      CKey_Period
  of KeySlash:       CKey_Slash
  of KeyBackslash:   CKey_Backslash
  of KeySemicolon:   CKey_Semicolon
  of KeyApostrophe:  CKey_Apostrophe
  of KeyLeftBracket: CKey_LBracket
  of KeyRightBracket:CKey_RBracket
  of KeyMinus:       CKey_Minus
  of KeyEqual:       CKey_Equal
  of KeyBacktick:    CKey_Grave
  else:              CKey_None


## ============================================================
##  Mouse button mapping  Windy Button → MouseButton
## ============================================================

proc windyButtonToMouseButton(b: windy.Button): MouseButton =
  case b
  of MouseLeft:   CMouseBtn_Left
  of MouseRight:  CMouseBtn_Right
  of MouseMiddle: CMouseBtn_Middle
  of MouseButton4:CMouseBtn_X1
  of MouseButton5:CMouseBtn_X2
  else:           CMouseBtn_None


proc isMouseButton(b: windy.Button): bool =
  b in {MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5}

proc isKeyButton(b: windy.Button): bool =
  not b.isMouseButton() and
  b notin {ButtonUnknown, DoubleClick, TripleClick, QuadrupleClick}


## ============================================================
##  Helper — build a KeyboardEvent from the current Windy state
## ============================================================

proc makeKeyEvent(ww: CWindyWindow, key: KeyInput,
                  justPressed, justReleased: bool): KeyboardEvent =
  ## Detect modifier keys currently held and place them in mkey/pkey.
  var mkey = CKey_None
  var pkey = CKey_None

  template checkMod(wBtn: windy.Button, ck: KeyInput) =
    if ww.wHandle.buttonDown[wBtn]:
      if mkey == CKey_None: mkey = ck
      elif pkey == CKey_None: pkey = ck

  checkMod(KeyLeftShift,   CKey_LShift)
  checkMod(KeyRightShift,  CKey_RShift)
  checkMod(KeyLeftControl, CKey_LCtrl)
  checkMod(KeyRightControl,CKey_RCtrl)
  checkMod(KeyLeftAlt,     CKey_LAlt)
  checkMod(KeyRightAlt,    CKey_RAlt)

  KeyboardEvent(
    id:           ww.id,
    key:          key,
    just_pressed: justPressed,
    pressed:      ww.wHandle.buttonDown[windyButtonToWButton(key)],
    just_released:justReleased,
    mkey:         mkey,
    pkey:         pkey
  )

## We need the reverse map (KeyInput → windy.Button) for the pressed query above.
proc windyButtonToWButton(k: KeyInput): windy.Button =
  ## Reverse of windyButtonToKeyInput – used only internally.
  case k
  of CKey_A: KeyA     of CKey_B: KeyB     of CKey_C: KeyC
  of CKey_D: KeyD     of CKey_E: KeyE     of CKey_F: KeyF
  of CKey_G: KeyG     of CKey_H: KeyH     of CKey_I: KeyI
  of CKey_J: KeyJ     of CKey_K: KeyK     of CKey_L: KeyL
  of CKey_M: KeyM     of CKey_N: KeyN     of CKey_O: KeyO
  of CKey_P: KeyP     of CKey_Q: KeyQ     of CKey_R: KeyR
  of CKey_S: KeyS     of CKey_T: KeyT     of CKey_U: KeyU
  of CKey_V: KeyV     of CKey_W: KeyW     of CKey_X: KeyX
  of CKey_Y: KeyY     of CKey_Z: KeyZ
  of CKey_0: Key0     of CKey_1: Key1     of CKey_2: Key2
  of CKey_3: Key3     of CKey_4: Key4     of CKey_5: Key5
  of CKey_6: Key6     of CKey_7: Key7     of CKey_8: Key8
  of CKey_9: Key9
  of CKey_Space:      KeySpace
  of CKey_Enter:      KeyEnter
  of CKey_Escape:     KeyEscape
  of CKey_Tab:        KeyTab
  of CKey_Backspace:  KeyBackspace
  of CKey_Delete:     KeyDelete
  of CKey_Insert:     KeyInsert
  of CKey_Home:       KeyHome
  of CKey_End:        KeyEnd
  of CKey_PageUp:     KeyPageUp
  of CKey_PageDown:   KeyPageDown
  of CKey_Up:         KeyUp
  of CKey_Down:       KeyDown
  of CKey_Left:       KeyLeft
  of CKey_Right:      KeyRight
  of CKey_F1:  KeyF1  of CKey_F2:  KeyF2  of CKey_F3:  KeyF3
  of CKey_F4:  KeyF4  of CKey_F5:  KeyF5  of CKey_F6:  KeyF6
  of CKey_F7:  KeyF7  of CKey_F8:  KeyF8  of CKey_F9:  KeyF9
  of CKey_F10: KeyF10 of CKey_F11: KeyF11 of CKey_F12: KeyF12
  of CKey_LShift:    KeyLeftShift    of CKey_RShift:    KeyRightShift
  of CKey_LCtrl:     KeyLeftControl  of CKey_RCtrl:     KeyRightControl
  of CKey_LAlt:      KeyLeftAlt      of CKey_RAlt:      KeyRightAlt
  of CKey_LSuper:    KeyLeftSuper    of CKey_RSuper:    KeyRightSuper
  of CKey_CapsLock:  KeyCapsLock
  of CKey_NumLock:   KeyNumLock
  of CKey_ScrollLock:KeyScrollLock
  of CKey_PrintScreen:KeyPrintScreen
  of CKey_Pause:     KeyPause
  of CKey_Num0: Numpad0 of CKey_Num1: Numpad1 of CKey_Num2: Numpad2
  of CKey_Num3: Numpad3 of CKey_Num4: Numpad4 of CKey_Num5: Numpad5
  of CKey_Num6: Numpad6 of CKey_Num7: Numpad7 of CKey_Num8: Numpad8
  of CKey_Num9: Numpad9
  of CKey_Comma:      KeyComma
  of CKey_Period:     KeyPeriod
  of CKey_Slash:      KeySlash
  of CKey_Backslash:  KeyBackslash
  of CKey_Semicolon:  KeySemicolon
  of CKey_Apostrophe: KeyApostrophe
  of CKey_LBracket:   KeyLeftBracket
  of CKey_RBracket:   KeyRightBracket
  of CKey_Minus:      KeyMinus
  of CKey_Equal:      KeyEqual
  of CKey_Grave:      KeyBacktick
  else:               ButtonUnknown


## ============================================================
##  Wire all Windy callbacks for a CWindyWindow
##  Called once during initWindow.
## ============================================================

proc wireCallbacks(ww: CWindyWindow) =
  let w = ww.wHandle   # short alias

  ## ── keyboard & mouse button press ───────────────────────
  w.onButtonPress = proc(btn: windy.Button) =
    if btn.isKeyButton():
      let key = windyButtonToKeyInput(btn)
      if key == CKey_None: return
      var ev = KeyboardEvent(
        id:           ww.id,
        key:          key,
        just_pressed: true,
        pressed:      true,
        just_released:false,
      )
      # detect modifiers
      template setMod(wBtn: windy.Button, ck: KeyInput) =
        if w.buttonDown[wBtn]:
          if ev.mkey == CKey_None: ev.mkey = ck
          elif ev.pkey == CKey_None: ev.pkey = ck
      setMod(KeyLeftShift,    CKey_LShift)
      setMod(KeyRightShift,   CKey_RShift)
      setMod(KeyLeftControl,  CKey_LCtrl)
      setMod(KeyRightControl, CKey_RCtrl)
      setMod(KeyLeftAlt,      CKey_LAlt)
      setMod(KeyRightAlt,     CKey_RAlt)

      ww.inputs.setKeyEvent(ev)
      ww.inputs.updateKeyboardCount()
      NOTIF_KEYBOARD_INPUT.emit((ww, ev))

    elif btn.isMouseButton():
      let mb = windyButtonToMouseButton(btn)
      let ev = MouseClickEvent(
        button:       mb,
        just_pressed: true,
        pressed:      true,
        just_released:false,
        clicks:       1,
      )
      ww.inputs.setMouseButtonEvent(ev)
      ww.inputs.updateMouseButtonCount()
      NOTIF_MOUSE_BUTTON.emit((ww, ev))

  ## ── keyboard & mouse button release ─────────────────────
  w.onButtonRelease = proc(btn: windy.Button) =
    if btn.isKeyButton():
      let key = windyButtonToKeyInput(btn)
      if key == CKey_None: return
      let ev = KeyboardEvent(
        id:           ww.id,
        key:          key,
        just_pressed: false,
        pressed:      false,
        just_released:true,
      )
      ww.inputs.setKeyEvent(ev)
      ww.inputs.updateKeyboardCount()
      NOTIF_KEYBOARD_INPUT.emit((ww, ev))

    elif btn.isMouseButton():
      let mb = windyButtonToMouseButton(btn)
      let ev = MouseClickEvent(
        button:       mb,
        just_pressed: false,
        pressed:      false,
        just_released:true,
        clicks:       0,
      )
      ww.inputs.setMouseButtonEvent(ev)
      ww.inputs.updateMouseButtonCount()
      NOTIF_MOUSE_BUTTON.emit((ww, ev))

  ## ── mouse motion ────────────────────────────────────────
  w.onMouseMove = proc() =
    let pos  = w.mousePos
    let prev = w.mousePrevPos
    let ev = MouseMotionEvent(
      x:    pos.x,
      y:    pos.y,
      xrel: pos.x - prev.x,
      yrel: pos.y - prev.y,
    )
    ww.inputs.setMotionEvent(ev)
    ww.inputs.updateMouseMotionCount()
    NOTIF_MOUSE_MOTION.emit((ww, ev))

  ## ── scroll wheel ────────────────────────────────────────
  w.onScroll = proc() =
    let delta = w.scrollDelta
    let ev = MouseWheelEvent(
      xwheel: delta.x.int,
      ywheel: delta.y.int,
    )
    ww.inputs.setWheelEvent(ev)
    ww.inputs.updateMouseWheelCount()
    NOTIF_MOUSE_WHEEL.emit((ww, ev))

  ## ── window resize ────────────────────────────────────────
  w.onResize = proc() =
    let sz = w.size
    ww.width  = sz.x
    ww.height = sz.y
    let wev = WindowEvent(kind: WINDOW_RESIZED, width: sz.x, height: sz.y)
    NOTIF_WINDOW_EVENT.emit((ww, wev))
    NOTIF_WINDOW_RESIZED.emit((ww, sz.x, sz.y))

  ## ── window move ──────────────────────────────────────────
  w.onMove = proc() =
    let p = w.pos
    ww.x = p.x
    ww.y = p.y
    let wev = WindowEvent(kind: WINDOW_MOVED, x_pos: p.x, y_pos: p.y)
    NOTIF_WINDOW_EVENT.emit((ww, wev))
    NOTIF_WINDOW_REPOSITIONED.emit((ww, p.x, p.y))

  ## ── focus change ─────────────────────────────────────────
  w.onFocusChange = proc() =
    if w.focused:
      let wev = WindowEvent(kind: WINDOW_HAVE_FOCUS)
      NOTIF_WINDOW_EVENT.emit((ww, wev))
    else:
      let wev = WindowEvent(kind: WINDOW_LOSE_FOCUS)
      NOTIF_WINDOW_EVENT.emit((ww, wev))

  ## ── close request ────────────────────────────────────────
  w.onCloseRequest = proc() =
    let wev = WindowEvent(kind: WINDOW_CLOSE)
    NOTIF_WINDOW_EVENT.emit((ww, wev))
    NOTIF_QUIT_EVENT.emit(())


## ============================================================
##  CApp — Windy backend method overrides
## ============================================================

method initWindow*(app: CApp, ww: var CWindyWindow,
                   args: varargs[string]) {.base.} =
  ## Create a Windy window for `win` and register it in the app.
  ##
  ## `win` should be a pre-allocated CWindyWindow with at least
  ## title, width, height set.  The caller can also set x, y
  ## before calling; if both are 0 the OS decides placement.
  ##
  ## args[0] (optional) – "vsync" to enable vsync (not yet exposed
  ##                       by all Windy platforms, reserved for future use).

  # Give it a unique id based on the current window count.
  ww.id = app.windows.len

  # Create the Windy window.
  ww.wHandle = newWindow(ww.title, ivec2(ww.width, ww.height))

  # Sync position if the caller set explicit coordinates.
  if ww.x != 0 or ww.y != 0:
    ww.wHandle.pos = ivec2(ww.x, ww.y)

  # Apply initial visibility.
  ww.wHandle.visible = ww.visible

  # Wire all OS-event callbacks.
  wireCallbacks(ww)

  # Register in the app.
  app.windows.add(ww)

  NOTIF_WINDOW_CREATED.emit((ww,))

method resizeWindow*(ww: CWindyWindow, width, height: int) =
  ww.wHandle.size = ivec2(width, height)
  ww.width  = width
  ww.height = height
  NOTIF_WINDOW_RESIZED.emit((win, width, height))

method repositionWindow*(ww: CWindyWindow, x, y: int) =
  ww.wHandle.pos = ivec2(x, y)
  ww.x = x
  ww.y = y
  NOTIF_WINDOW_REPOSITIONED.emit((win, x, y))

method setWindowTitle*(ww: CWindyWindow, newTitle: string) =
  ww.wHandle.title = newTitle
  ww.title = newTitle
  NOTIF_WINDOW_TITLE_CHANGED.emit((win, newTitle))

method maximizeWindow*(ww: CWindyWindow) =
  ww.wHandle.maximized = true
  NOTIF_WINDOW_MAXIMIZED.emit((win,))

method minimizeWindow*(ww: CWindyWindow) =
  ww.wHandle.minimized = true
  NOTIF_WINDOW_MINIMIZED.emit((win,))

method restoreWindow*(ww: CWindyWindow) =
  ## Windy has no single "restore" call; clearing both flags restores the window.
  ww.wHandle.minimized = false
  ww.wHandle.maximized = false
  NOTIF_WINDOW_RESTORED.emit((win,))


method hideWindow*(ww: CWindyWindow) =
  ww.wHandle.visible = false
  ww.visible = false
  NOTIF_WINDOW_HIDDEN.emit((win,))


method showWindow*(ww: CWindyWindow) =
  ww.wHandle.visible = true
  ww.visible = true
  NOTIF_WINDOW_SHOWN.emit((win,))


method raiseWindow*(ww: CWindyWindow) =
  ww.wHandle.focus()
  NOTIF_WINDOW_RAISED.emit((win,))


method setFullscreen*(ww: CWindyWindow, active: bool,
                      desktopResolution: bool = false) =
  ## Note: Windy does not distinguish between desktop-resolution fullscreen
  ## and custom-resolution fullscreen at the API level; it always uses the
  ## native desktop resolution.  `desktopResolution` is accepted for
  ## interface compatibility but has no additional effect.
  ww.wHandle.fullscreen = active
  ww.fullscreen = active
  NOTIF_WINDOW_FULLSCREEN.emit((win, active, desktopResolution))


method updateWindow*(ww: CWindyWindow) =
  ## For OpenGL-backed windows the caller should call window.swapBuffers()
  ## themselves inside their render loop.  This notifier signals that the
  ## frame is "done" from the abstraction's point of view.
  NOTIF_WINDOW_UPDATED.emit((win,))


method getError*(ww: CWindyWindow): string =
  ## Windy does not expose a per-window error string; errors are raised as
  ## WindyError exceptions instead.  Return empty and emit NOTIF_INFO.
  result = ""
  NOTIF_INFO.emit((win.title, "Windy raises exceptions instead of error strings.", 0))


method getMousePosition*(ww: CWindyWindow): tuple[x, y: int] =
  let p = ww.wHandle.mousePos
  (p.x, p.y)


method convertKey*(ww: CWindyWindow, rawKey: int): KeyInput =
  ## Convert a raw Windy Button ordinal to a KeyInput.
  ## The caller can pass `ord(someWindyButton)` here.
  let btn = windy.Button(rawKey)
  windyButtonToKeyInput(btn)


method quitWindow*(ww: CWindyWindow) =
  ww.wHandle.close()
  NOTIF_WINDOW_EXITTED.emit((win,))
