## =============================================================
##  SDL3 Backend — event pump & input handling
##
##  Uses the sdl3_nim package (dinau/sdl3_nim, futhark-generated).
##  Naming conventions from that package:
##    - struct fields named `type` → `type_field`
##    - struct fields named `mod`  → `mod_field`
##    - SDLK_a … SDLK_z           → SDLK_a_const … SDLK_z_const
##
##  All methods take SDL3Window directly — no internal casting.
##
##  Fixes vs previous version:
##    1. Proper method dispatch on SDL3Window (no CWindow + cast).
##    2. sdl3_nim types used throughout — no manual importc / copyMem.
##    3. detectModifiers called AFTER key insertion (modifier sees itself).
##    4. CMouseAxis_X and CMouseAxis_Y stored separately.
##    5. Signals fired BEFORE updateInputState (just_* flags still live).
##    6. SDL_EVENT_TEXT_INPUT handled; text appended to win.textInput.
##    7. SDL_MOUSEWHEEL_FLIPPED handled correctly and documented.
##    8. eventLoop runs the pump once per CApp, not once per CWindow.
## =============================================================

import sdl3_nim

# ---------------------------------------------------------------------------
# convertKey — SDL_Keycode → KeyInput
# sdl3_nim renames SDLK_a..z to SDLK_a_const..SDLK_z_const (futhark rule).
# ---------------------------------------------------------------------------

method convertKey*(win: SDL3Window, rawKey: SDL_Keycode): KeyInput =
  ## Translate an SDL3 SDL_Keycode to our KeyInput enum.
  ## Returns CKey_None for any unmapped key.
  case rawKey
  # Letters (futhark renames SDLK_a → SDLK_a_const, etc.)
  of SDLK_a_const: CKey_A    
  of SDLK_b_const: CKey_B
  of SDLK_c_const: CKey_C    
  of SDLK_d_const: CKey_D
  of SDLK_e_const: CKey_E    
  of SDLK_f_const: CKey_F
  of SDLK_g_const: CKey_G    
  of SDLK_h_const: CKey_H
  of SDLK_i_const: CKey_I    
  of SDLK_j_const: CKey_J
  of SDLK_k_const: CKey_K    
  of SDLK_l_const: CKey_L
  of SDLK_m_const: CKey_M    
  of SDLK_n_const: CKey_N
  of SDLK_o_const: CKey_O    
  of SDLK_p_const: CKey_P
  of SDLK_q_const: CKey_Q    
  of SDLK_r_const: CKey_R
  of SDLK_s_const: CKey_S    
  of SDLK_t_const: CKey_T
  of SDLK_u_const: CKey_U    
  of SDLK_v_const: CKey_V
  of SDLK_w_const: CKey_W    
  of SDLK_x_const: CKey_X
  of SDLK_y_const: CKey_Y    
  of SDLK_z_const: CKey_Z
  # Digits
  of SDLK_0: CKey_0   
  of SDLK_1: CKey_1   
  of SDLK_2: CKey_2
  of SDLK_3: CKey_3   
  of SDLK_4: CKey_4   
  of SDLK_5: CKey_5
  of SDLK_6: CKey_6   
  of SDLK_7: CKey_7   
  of SDLK_8: CKey_8
  of SDLK_9: CKey_9
  # Whitespace / control
  of SDLK_SPACE:     CKey_Space
  of SDLK_RETURN:    CKey_Enter
  of SDLK_ESCAPE:    CKey_Escape
  of SDLK_TAB:       CKey_Tab
  of SDLK_BACKSPACE: CKey_Backspace
  of SDLK_DELETE:    CKey_Delete
  of SDLK_INSERT:    CKey_Insert
  of SDLK_HOME:      CKey_Home
  of SDLK_END:       CKey_End
  of SDLK_PAGEUP:    CKey_PageUp
  of SDLK_PAGEDOWN:  CKey_PageDown
  # Arrows
  of SDLK_UP:    CKey_Up
  of SDLK_DOWN:  CKey_Down
  of SDLK_LEFT:  CKey_Left
  of SDLK_RIGHT: CKey_Right
  # Function keys
  of SDLK_F1:  CKey_F1
  of SDLK_F2:  CKey_F2
  of SDLK_F3:  CKey_F3
  of SDLK_F4:  CKey_F4
  of SDLK_F5:  CKey_F5
  of SDLK_F6:  CKey_F6
  of SDLK_F7:  CKey_F7
  of SDLK_F8:  CKey_F8
  of SDLK_F9:  CKey_F9
  of SDLK_F10: CKey_F10
  of SDLK_F11: CKey_F11   
  of SDLK_F12: CKey_F12
  # Modifiers
  of SDLK_LSHIFT: CKey_LShift   
  of SDLK_RSHIFT: CKey_RShift
  of SDLK_LCTRL:  CKey_LCtrl    
  of SDLK_RCTRL:  CKey_RCtrl
  of SDLK_LALT:   CKey_LAlt     
  of SDLK_RALT:   CKey_RAlt
  of SDLK_LGUI:   CKey_LSuper   
  of SDLK_RGUI:   CKey_RSuper
  # Lock / system keys
  of SDLK_CAPSLOCK:     CKey_CapsLock
  of SDLK_NUMLOCKCLEAR: CKey_NumLock
  of SDLK_SCROLLLOCK:   CKey_ScrollLock
  of SDLK_PRINTSCREEN:  CKey_PrintScreen
  of SDLK_PAUSE:        CKey_Pause
  # Numpad
  of SDLK_KP_0: CKey_Num0   
  of SDLK_KP_1: CKey_Num1
  of SDLK_KP_2: CKey_Num2   
  of SDLK_KP_3: CKey_Num3
  of SDLK_KP_4: CKey_Num4   
  of SDLK_KP_5: CKey_Num5
  of SDLK_KP_6: CKey_Num6   
  of SDLK_KP_7: CKey_Num7
  of SDLK_KP_8: CKey_Num8   
  of SDLK_KP_9: CKey_Num9
  of SDLK_KP_PLUS:     CKey_NumAdd
  of SDLK_KP_MINUS:    CKey_NumSub
  of SDLK_KP_MULTIPLY: CKey_NumMul
  of SDLK_KP_DIVIDE:   CKey_NumDiv
  of SDLK_KP_ENTER:    CKey_NumEnter
  of SDLK_KP_PERIOD:   CKey_NumDecimal
  # Punctuation
  of SDLK_COMMA:        CKey_Comma
  of SDLK_PERIOD:       CKey_Period
  of SDLK_SLASH:        CKey_Slash
  of SDLK_BACKSLASH:    CKey_Backslash
  of SDLK_SEMICOLON:    CKey_Semicolon
  of SDLK_APOSTROPHE:   CKey_Apostrophe
  of SDLK_LEFTBRACKET:  CKey_LBracket
  of SDLK_RIGHTBRACKET: CKey_RBracket
  of SDLK_MINUS:        CKey_Minus
  of SDLK_EQUALS:       CKey_Equal
  of SDLK_GRAVE:        CKey_Grave
  else: CKey_None

# ---------------------------------------------------------------------------
# SDL mouse button index → MouseButton
# ---------------------------------------------------------------------------

proc toMouseButton(sdlBtn: uint8): MouseButton {.inline.} =
  ## SDL3: 1=Left 2=Middle 3=Right 4=X1 5=X2
  case sdlBtn
  of 1: CMouseBtn_Left
  of 2: CMouseBtn_Middle
  of 3: CMouseBtn_Right
  of 4: CMouseBtn_X1
  of 5: CMouseBtn_X2
  else: CMouseBtn_None

# ---------------------------------------------------------------------------
# detectModifiers
# Must be called AFTER the new key event is already in the sparse-set,
# so that a freshly-pressed modifier sees itself in mkey/pkey.
# ---------------------------------------------------------------------------

proc detectModifiers(win: SDL3Window): tuple[mkey, pkey: KeyInput] =
  const modKeys = [CKey_LShift, CKey_RShift, CKey_LCtrl,  CKey_RCtrl,
                   CKey_LAlt,   CKey_RAlt,   CKey_LSuper, CKey_RSuper]
  var res: array[2, KeyInput] = [CKey_None, CKey_None]
  var n = 0
  let kb = win.inputs.data.keyboard
  for mk in modKeys:
    if n >= 2: break
    if kb.contains(mk) and kb[mk].pressed:
      res[n] = mk
      inc n
  (res[0], res[1])

# ---------------------------------------------------------------------------
# handleWindowEvent
# ---------------------------------------------------------------------------

method handleWindowEvent*(win: SDL3Window, ev: SDL_WindowEvent) =
  ## Translate an SDL3 SDL_WindowEvent into a WindowEvent and emit
  ## NOTIF_WINDOW_EVENT.  Also keeps SDL3Window metadata in sync.
  ##
  ## sdl3_nim: the `type` field is renamed `type_field` by futhark.
  let kind = ev.type_field

  let wev: WindowEvent =
    if   kind == SDL_EVENT_WINDOW_RESIZED:
      WindowEvent(kind: WINDOW_RESIZED,
                  width:  ev.data1.int, height: ev.data2.int)
    elif kind == SDL_EVENT_WINDOW_MOVED:
      WindowEvent(kind: WINDOW_MOVED,
                  x_pos: ev.data1.int, y_pos: ev.data2.int)
    elif kind == SDL_EVENT_WINDOW_MAXIMIZED:    WindowEvent(kind: WINDOW_MAXIMIZED)
    elif kind == SDL_EVENT_WINDOW_MINIMIZED:    WindowEvent(kind: WINDOW_MINIMIZED)
    elif kind == SDL_EVENT_WINDOW_RESTORED:     WindowEvent(kind: WINDOW_RESTORED)
    elif kind == SDL_EVENT_WINDOW_SHOWN:        WindowEvent(kind: WINDOW_SHOWN)
    elif kind == SDL_EVENT_WINDOW_HIDDEN:       WindowEvent(kind: WINDOW_HIDDEN)
    elif kind == SDL_EVENT_WINDOW_FOCUS_GAINED: WindowEvent(kind: WINDOW_HAVE_FOCUS)
    elif kind == SDL_EVENT_WINDOW_FOCUS_LOST:   WindowEvent(kind: WINDOW_LOSE_FOCUS)
    elif kind == SDL_EVENT_WINDOW_CLOSE_REQUESTED: WindowEvent(kind: WINDOW_CLOSE)
    else: return  # unrecognised window sub-event

  # Sync cached metadata
  case wev.kind
  of WINDOW_RESIZED:   win.width  = wev.width;  win.height = wev.height
  of WINDOW_MOVED:     win.x      = wev.x_pos;  win.y      = wev.y_pos
  of WINDOW_HIDDEN:    win.visible = false
  of WINDOW_SHOWN:     win.visible = true
  else: discard

  NOTIF_WINDOW_EVENT.emit((win, wev))

# ---------------------------------------------------------------------------
# handleKeyboardInputs
# ---------------------------------------------------------------------------

method handleKeyboardInputs*(win: SDL3Window) =
  ## Emit NOTIF_KEYBOARD_INPUT for every key in a non-idle state.
  ## Call BEFORE updateInputState so just_pressed/just_released are still set.
  let kb = win.inputs.data.keyboard
  for ev in kb.dense:
    if ev.just_pressed or ev.just_released or ev.pressed:
      NOTIF_KEYBOARD_INPUT.emit((win, ev))

# ---------------------------------------------------------------------------
# handleMouseEvents
# ---------------------------------------------------------------------------

method handleMouseEvents*(win: SDL3Window) =
  ## Emit NOTIF_MOUSE_MOTION / NOTIF_MOUSE_WHEEL / NOTIF_MOUSE_BUTTON.
  ## Call BEFORE updateInputState so just_* flags are still live.
  let axes = win.inputs.data.axes

  # Motion — emit only when there was actual relative movement
  if axes.contains(CMouseAxis_X):
    let ae = axes[CMouseAxis_X]
    if ae.kind == AxisMotion and
       (ae.motion.xrel != 0 or ae.motion.yrel != 0):
      NOTIF_MOUSE_MOTION.emit((win, ae.motion))

  # Wheel — emit only when the wheel actually moved
  if axes.contains(CMouseAxis_WheelY):
    let ae = axes[CMouseAxis_WheelY]
    if ae.kind == AxisWheel and
       (ae.wheel.xwheel != 0 or ae.wheel.ywheel != 0):
      NOTIF_MOUSE_WHEEL.emit((win, ae.wheel))

  # Buttons
  let mb = win.inputs.data.mouseButtons
  for ev in mb.dense:
    if ev.just_pressed or ev.just_released or ev.pressed:
      NOTIF_MOUSE_BUTTON.emit((win, ev))

# ---------------------------------------------------------------------------
# routeEvent — dispatch a single SDL_Event to the right SDL3Window
# ---------------------------------------------------------------------------

proc findWindow(app: CApp, id: SDL_WindowID): SDL3Window =
  ## Return the SDL3Window whose SDL handle matches `id`, or nil.
  for w in app.windows:
    let sw = SDL3Window(w)
    if SDL_GetWindowID(sw.handle) == id:
      return sw
  nil

proc routeEvent(app: CApp, ev: SDL_Event) =
  ## Translate one raw SDL_Event and update the matching SDL3Window.
  ## sdl3_nim: the union field `type` is renamed `type_field`.
  let kind = ev.type_field

  NOTIF_EVENT_RECEIVED.emit((unsafeAddr ev, kind.int))

  # ---- Quit -------------------------------------------------------------
  if kind == SDL_EVENT_QUIT:
    NOTIF_QUIT_EVENT.emit(())
    return

  # ---- Window events ----------------------------------------------------
  if kind >= SDL_EVENT_WINDOW_SHOWN and
     kind <= SDL_EVENT_WINDOW_CLOSE_REQUESTED:
    let win = app.findWindow(ev.window.windowID)
    if win != nil:
      win.handleWindowEvent(ev.window)
    return

  # ---- Keyboard ---------------------------------------------------------
  if kind == SDL_EVENT_KEY_DOWN or kind == SDL_EVENT_KEY_UP:
    let win = app.findWindow(ev.key.windowID)
    if win == nil: return

    # sdl3_nim: SDL_KeyboardEvent.key holds the SDL_Keycode
    let key = win.convertKey(ev.key.key)
    if key == CKey_None: return

    win.inputs.updateKeyboardCount()

    # Preserve existing state or create a fresh event
    var kev: KeyboardEvent
    let kb = win.inputs.data.keyboard
    kev = if kb.contains(key): kb[key]
          else: KeyboardEvent(id: win.id, key: key)

    let isDown   = ev.key.down
    # sdl3_nim: SDL_KeyboardEvent has no `repeat` field name conflict →
    # futhark keeps it as `repeat` (not a Nim keyword).
    let isRepeat = ev.key.repeat

    if isDown and not isRepeat:
      kev.just_pressed  = true
      kev.pressed       = true
      kev.just_released = false
    elif isDown and isRepeat:
      # Auto-repeat: still held, no edge transition
      kev.just_pressed  = false
      kev.pressed       = true
    else:
      # Key released
      kev.just_pressed  = false
      kev.pressed       = false
      kev.just_released = true

    # Insert FIRST so detectModifiers sees the key if it is itself a modifier
    win.inputs.setKeyEvent(kev)

    # Attach modifier context from the now-updated sparse-set
    let (mkey, pkey) = win.detectModifiers()
    win.inputs.data.keyboard[key].mkey = mkey
    win.inputs.data.keyboard[key].pkey = pkey
    return

  # ---- Text input -------------------------------------------------------
  if kind == SDL_EVENT_TEXT_INPUT:
    let win = app.findWindow(ev.text.windowID)
    if win == nil: return
    # sdl3_nim: SDL_TextInputEvent.text is array[32, char]
    var s = ""
    for ch in ev.text.text:
      if ch == '\0': break
      s.add(ch)
    win.textInput.add(s)
    return

  # ---- Mouse motion -----------------------------------------------------
  if kind == SDL_EVENT_MOUSE_MOTION:
    let win = app.findWindow(ev.motion.windowID)
    if win == nil: return
    win.inputs.updateMouseMotionCount()

    let mev = MouseMotionEvent(
      x    : ev.motion.x.int,
      y    : ev.motion.y.int,
      xrel : ev.motion.xrel.int,
      yrel : ev.motion.yrel.int)

    # Store under both CMouseAxis_X and CMouseAxis_Y so both are queryable
    # independently, while sharing the same underlying MouseMotionEvent.
    win.inputs.data.axes.insert(CMouseAxis_X,
        AxisEvent(kind: AxisMotion, motion: mev))
    win.inputs.data.axes.insert(CMouseAxis_Y,
        AxisEvent(kind: AxisMotion, motion: mev))
    return

  # ---- Mouse wheel ------------------------------------------------------
  if kind == SDL_EVENT_MOUSE_WHEEL:
    let win = app.findWindow(ev.wheel.windowID)
    if win == nil: return
    win.inputs.updateMouseWheelCount()

    ## SDL_MOUSEWHEEL_FLIPPED: the platform uses "natural scroll" (content
    ## follows the finger direction), so x/y are already inverted relative
    ## to the conventional axes.  We flip them back to get consistent
    ## "positive Y = scroll up / away from user" semantics.
    let flip: float32 =
      if ev.wheel.direction == SDL_MOUSEWHEEL_FLIPPED: -1.0'f32
      else: 1.0'f32

    let wev = MouseWheelEvent(
      xwheel: (ev.wheel.x * flip).int,
      ywheel: (ev.wheel.y * flip).int)

    # Store under both wheel axes
    win.inputs.data.axes.insert(CMouseAxis_WheelX,
        AxisEvent(kind: AxisWheel, wheel: wev))
    win.inputs.data.axes.insert(CMouseAxis_WheelY,
        AxisEvent(kind: AxisWheel, wheel: wev))
    return

  # ---- Mouse buttons ----------------------------------------------------
  if kind == SDL_EVENT_MOUSE_BUTTON_DOWN or
     kind == SDL_EVENT_MOUSE_BUTTON_UP:
    let win = app.findWindow(ev.button.windowID)
    if win == nil: return
    win.inputs.updateMouseButtonCount()

    let btn = ev.button.button.toMouseButton()
    if btn == CMouseBtn_None: return

    var mev: MouseClickEvent
    let mb = win.inputs.data.mouseButtons
    mev = if mb.contains(btn): mb[btn]
          else: MouseClickEvent(button: btn)

    mev.clicks = ev.button.clicks.int
    if ev.button.down:
      mev.just_pressed  = true
      mev.pressed       = true
      mev.just_released = false
    else:
      mev.just_pressed  = false
      mev.pressed       = false
      mev.just_released = true

    win.inputs.setMouseButtonEvent(mev)
    return

# ---------------------------------------------------------------------------
# eventLoop — one complete frame of event processing
# ---------------------------------------------------------------------------

proc eventLoop*(app: CApp) =
  ## SDL3-aware eventLoop.  Call once per game-loop iteration.
  ##
  ## Order of operations:
  ##   1. Clear textInput buffers and per-frame counters on every window.
  ##   2. Drain the SDL3 event queue via SDL_PollEvent.
  ##   3. Fire NOTIF_* signals (BEFORE clearing edge flags).
  ##   4. Advance the input state machine (clears just_pressed/just_released).
  ##
  ## Usage example:
  ##   let app = initSDL3App()
  ##   # ... create windows ...
  ##   while running:
  ##     app.eventLoop()
  ##     if app.isKeyJustPressed(CKey_Escape): running = false

  # Step 1 — reset per-frame state
  for win in app.windows:
    let sw = SDL3Window(win)
    sw.clearFrameState()
    sw.inputs.resetCounts()

  # Step 2 — drain the SDL3 event queue
  var ev: SDL_Event
  while SDL_PollEvent(addr ev):
    app.routeEvent(ev)

  # Step 3 — fire per-window NOTIF_* signals (edges still set)
  for win in app.windows:
    let sw = SDL3Window(win)
    sw.handleKeyboardInputs()
    sw.handleMouseEvents()

  # Step 4 — advance state machine (clear just_pressed / just_released)
  for win in app.windows:
    SDL3Window(win).inputs.updateInputState()