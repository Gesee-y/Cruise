## =============================================================
##  SDL3 Windowing Framework — Full Examples
##
##  Covers:
##     1. Simple window with game loop
##     2. Keyboard inputs (just_pressed / pressed / just_released)
##     3. Mouse inputs (movement, wheel, buttons)
##     4. Text input (SDL_EVENT_TEXT_INPUT)
##     5. Multi-windowing
##     6. Fullscreen (borderless and exclusive)
##     7. Notifications (NOTIF_*)
##     8. Key combinations (modifiers)
##     9. Dynamic resizing / repositioning
##    10. Clean shutdown management
## =============================================================

import ../../src/windows/windows
import core

# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 1 — Minimal window with game loop
# ═══════════════════════════════════════════════════════════════════

proc example1_fenetre_simple() =
  ## Opens an 800×600 window, runs until the user
  ## presses Escape or closes the window.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 1 — Simple Window", "800", "600")

  # Connection to the close notifier: when the close button is clicked
  var running = true
  NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
    if ev.kind == WINDOW_CLOSE:
      running = false

  while running:
    app.eventLoop(SDLEventRouter)

    # Quit on Escape
    if app.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 2 — Keyboard: just_pressed / pressed / just_released
# ═══════════════════════════════════════════════════════════════════

proc example2_clavier() =
  ## Demonstrates the three states of a key.
  ##
  ## just_pressed  → triggers ONCE the first frame where the
  ##                  key goes from released to pressed.
  ## pressed       → true as long as the key is held (including
  ##                  the just_pressed frame).
  ## just_released → triggers ONCE the frame where the key
  ##                  is released.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 2 — Keyboard")

  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Rising edge detection (single frame) ──────────────────────────
    if win.isKeyJustPressed(CKey_Space):
      echo "[ SPACE ] was just PRESSED"

    # ── Continuous hold ─────────────────────────────────────────────
    if win.isKeyPressed(CKey_W):
      echo "[ W ] held — moving up"

    if win.isKeyPressed(CKey_S):
      echo "[ S ] held — moving down"

    if win.isKeyPressed(CKey_A):
      echo "[ A ] held — moving left"

    if win.isKeyPressed(CKey_D):
      echo "[ D ] held — moving right"

    # ── Falling edge (single frame) ────────────────────────────
    if win.isKeyJustReleased(CKey_Space):
      echo "[ SPACE ] was just RELEASED"

    # ── Quit ──────────────────────────────────────────────────────
    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 3 — Mouse: movement, wheel, buttons
# ═══════════════════════════════════════════════════════════════════

proc example3_souris() =
  ## Displays mouse events in the console in real-time.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 3 — Mouse")

  # ── Connections to mouse notifiers ──────────────────────────────

  NOTIF_MOUSE_MOTION.connect do(w: CWindow, ev: MouseMotionEvent):
    echo "Motion  pos=(", ev.x, ",", ev.y, ")  rel=(", ev.xrel, ",", ev.yrel, ")"

  NOTIF_MOUSE_WHEEL.connect do(w: CWindow, ev: MouseWheelEvent):
    echo "Wheel  x=", ev.xwheel, "  y=", ev.ywheel

  NOTIF_MOUSE_BUTTON.connect do(w: CWindow, ev: MouseClickEvent):
    let state = if ev.just_pressed: "PRESSED" elif ev.just_released: "RELEASED" else: "held"
    echo "Button ", ev.button, " → ", state, "  (multiple clicks: ", ev.clicks, ")"

  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Direct axis reading ──────────────────────────────────
    let axX = win.getAxis(CMouseAxis_X)
    if axX.kind == AxisMotion and (axX.motion.xrel != 0 or axX.motion.yrel != 0):
      # Already displayed by the notifier above, but shows direct access.
      discard

    # ── Direct button reading ───────────────────────────────
    if win.isMouseButtonJustPressed(CMouseBtn_Left):
      let (mx, my) = win.getMousePosition()
      echo "Left click at (", mx, ",", my, ")"

    if win.isMouseButtonPressed(CMouseBtn_Right):
      echo "Right button held"

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 4 — Text input (SDL_EVENT_TEXT_INPUT)
# ═══════════════════════════════════════════════════════════════════

proc example4_texte() =
  ## Accumulates UTF-8 input from the user.
  ## win.textInput is reset every frame by clearFrameState()
  ## (called in eventLoop), so we concatenate into `buffer` ourselves.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 4 — Text Input (type then Enter)")

  var buffer = ""
  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    # win.textInput contains characters typed THIS frame
    if win.textInput.len > 0:
      buffer.add(win.textInput)
      echo "Buffer : [", buffer, "]"

    # Validate with Enter
    if win.isKeyJustPressed(CKey_Enter):
      echo "==> Validated: \"", buffer, "\""
      buffer = ""

    # Backspace: erase last UTF-8 character
    if win.isKeyJustPressed(CKey_Backspace) and buffer.len > 0:
      # Step back one UTF-8 code point (safe thanks to Nim's string)
      var i = buffer.len - 1
      while i > 0 and (buffer[i].ord and 0xC0) == 0x80:
        dec i
      buffer = buffer[0 ..< i]
      echo "Buffer : [", buffer, "]"

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 5 — Key Modifiers (Shift, Ctrl, Alt)
# ═══════════════════════════════════════════════════════════════════

proc example5_modificateurs() =
  ## Shows how to read modifiers attached to each KeyboardEvent.
  ## mkey / pkey fields are filled by detectModifiers() in
  ## sdl3_events.nim right after insertion into the sparse-set.

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 5 — Modifiers")

  NOTIF_KEYBOARD_INPUT.connect do(w: CWindow, ev: KeyboardEvent):
    if not ev.just_pressed: return
    let mod1 = if ev.mkey != CKey_None: $ev.mkey else: "—"
    let mod2 = if ev.pkey != CKey_None: $ev.pkey else: "—"
    echo "Key=", ev.key, "  mod1=", mod1, "  mod2=", mod2

  # Classic shortcuts built manually
  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    # Ctrl+S → save
    if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_S):
      echo "Ctrl+S — Saving!"

    # Ctrl+Z → undo
    if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_Z):
      echo "Ctrl+Z — Undoing!"

    # Shift+F5 → reload
    if (win.isKeyPressed(CKey_LShift) or win.isKeyPressed(CKey_RShift)) and
       win.isKeyJustPressed(CKey_F5):
      echo "Shift+F5 — Forced Reload!"

    # Alt+F4 → quit
    if win.isKeyPressed(CKey_LAlt) and win.isKeyJustPressed(CKey_F4):
      running = false

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 6 — Fullscreen (borderless and exclusive)
# ═══════════════════════════════════════════════════════════════════

proc example6_fullscreen() =
  ## F11 → toggle desktop fullscreen (borderless)
  ## F10 → toggle exclusive fullscreen
  ## Escape → return to windowed or quit

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 6 — Fullscreen (F11 desktop | F10 exclusive)")

  NOTIF_ERROR.connect do(mes, error: string):
    echo "[ERROR] ", mes, " — ", error

  NOTIF_WINDOW_FULLSCREEN.connect do(w: CWindow, active: bool, desktop: bool):
    echo "Fullscreen → active=", active, "  desktop=", desktop

  var running  = true
  var isFullsc = false

  while running:
    app.eventLoop(SDLEventRouter)

    # ── F11 : borderless fullscreen ─────────────────────────────
    if win.isKeyJustPressed(CKey_F11):
      isFullsc = not isFullsc
      win.setFullscreen(isFullsc, desktopResolution = true)

    # ── F10 : exclusive fullscreen ───────────────────────────────
    if win.isKeyJustPressed(CKey_F10):
      isFullsc = not isFullsc
      win.setFullscreen(isFullsc, desktopResolution = false)

    # ── Escape : quit fullscreen or application ──────────
    if win.isKeyJustPressed(CKey_Escape):
      if isFullsc:
        win.setFullscreen(false)
        isFullsc = false
      else:
        running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 7 — Dynamic Resizing and Repositioning
# ═══════════════════════════════════════════════════════════════════

proc example7_resize_reposition() =
  ## Real-time control keys for size and position.
  ##
  ##  +/- (numpad)  → grow / shrink
  ##  Arrows        → move window
  ##  M             → maximize
  ##  N             → minimize
  ##  R             → restore
  ##  H             → hide   (reappears after 2s)
  ##  T             → change title

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 7 — Resize/Reposition", "640", "480",
                 "400", "200")

  NOTIF_WINDOW_RESIZED.connect do(w: CWindow, width, height: int):
    echo "Resized → ", width, "×", height

  NOTIF_WINDOW_REPOSITIONED.connect do(w: CWindow, x, y: int):
    echo "Repositioned → (", x, ",", y, ")"

  const STEP_PX  = 20
  const STEP_SZ  = 50
  var titleIdx   = 0
  let titles     = ["Example 7", "Hello SDL3!", "Nim ♥ SDL", "Greetings!"]
  var running    = true

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Resizing ─────────────────────────────────────────
    if win.isKeyJustPressed(CKey_NumAdd):
      win.resizeWindow(win.width + STEP_SZ, win.height + STEP_SZ)

    if win.isKeyJustPressed(CKey_NumSub):
      let w = max(200, win.width  - STEP_SZ)
      let h = max(150, win.height - STEP_SZ)
      win.resizeWindow(w, h)

    # ── Movement ───────────────────────────────────────────────
    if win.isKeyPressed(CKey_Left):
      win.repositionWindow(win.x - STEP_PX, win.y)

    if win.isKeyPressed(CKey_Right):
      win.repositionWindow(win.x + STEP_PX, win.y)

    if win.isKeyPressed(CKey_Up):
      win.repositionWindow(win.x, win.y - STEP_PX)

    if win.isKeyPressed(CKey_Down):
      win.repositionWindow(win.x, win.y + STEP_PX)

    # ── Window States ───────────────────────────────────────
    if win.isKeyJustPressed(CKey_M): win.maximizeWindow()
    if win.isKeyJustPressed(CKey_N): win.minimizeWindow()
    if win.isKeyJustPressed(CKey_R): win.restoreWindow()

    if win.isKeyJustPressed(CKey_H):
      win.hideWindow()
      SDL_Delay(2000)   # waits 2 seconds (SDL3 delay)
      win.showWindow()

    # ── Title ─────────────────────────────────────────────────────
    if win.isKeyJustPressed(CKey_T):
      titleIdx = (titleIdx + 1) mod titles.len
      win.setWindowTitle(titles[titleIdx])

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 8 — Multi-windowing
# ═══════════════════════════════════════════════════════════════════

proc example8_multi_fenetres() =
  ## Two independent windows managed by the same CApp.
  ## Each window receives its own events via routing by
  ## SDL_WindowID in routeEvent().
  ##
  ## W1: main window (symbolic red)
  ## W2: secondary window (symbolic blue)
  ##
  ## Closing W2 or pressing F2: destroys only W2.
  ## Escape or closing W1: quits application.

  let app = initSDL3App()

  var w1, w2: SDL3Window
  new(w1); new(w2)

  app.initWindow(w1, "Main Window",  "800", "600", "100", "100")
  app.initWindow(w2, "Secondary Window",  "400", "300", "950", "100")

  var w2Alive = true
  var running  = true

  # Generic notifier — the `win` parameter identifies the event source
  NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
    if ev.kind == WINDOW_CLOSE:
      if win.id == w1.id:
        running = false
      elif win.id == w2.id and w2Alive:
        w2.quitWindow()
        w2Alive = false

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Controls on W1 ─────────────────────────────────────────
    if w1.isKeyJustPressed(CKey_Escape):
      running = false

    # ── Create/destroy W2 with F2 ────────────────────────────────
    if w1.isKeyJustPressed(CKey_F2):
      if w2Alive:
        w2.quitWindow()
        w2Alive = false
        echo "W2 destroyed"
      else:
        new(w2)
        app.initWindow(w2, "Secondary Window (recreated)", "400", "300",
                       "950", "100")
        w2Alive = true
        echo "W2 recreated, id=", w2.id

    # ── W2 specific interactions ─────────────────────────────────
    if w2Alive and w2.isKeyJustPressed(CKey_Space):
      echo "[ SPACE ] in W2!"

    w1.updateWindow()
    if w2Alive: w2.updateWindow()

  if w2Alive: w2.quitWindow()
  w1.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 9 — Connecting/Disconnecting Notifiers
# ═══════════════════════════════════════════════════════════════════

proc example9_notifiers() =
  ## Demonstrates how to dynamically connect and disconnect handlers.
  ## P → pauses keyboard event reception (disconnects the handler)
  ## P (again) → resumes

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Example 9 — Dynamic Notifiers")

  var paused = false

  # Store connection ID to allow disconnection
  var kbHandlerID: int

  proc kbHandler(w: CWindow, ev: KeyboardEvent) =
    if ev.just_pressed:
      echo "Key: ", ev.key

  NOTIF_KEYBOARD_INPUT.connect(kbHandler)

  NOTIF_ERROR.connect do(mes, error: string):
    echo "[ERROR] ", mes, " | ", error

  #NOTIF_WARNING.connect do(mes, warning: string, code: int):
    #echo "[WARN] ", mes, " | ", warning, " (code=", code, ")"

  NOTIF_INFO.connect do(mes, info: string, code: int):
    echo "[INFO] ", mes, " | ", info

  var running = true

  while running:
    app.eventLoop(SDLEventRouter)

    if win.isKeyJustPressed(CKey_P):
      if paused:
        NOTIF_KEYBOARD_INPUT.connect(kbHandler)
        paused = false
        echo "Resuming keyboard events"
      else:
        NOTIF_KEYBOARD_INPUT.disconnect(kbHandler)
        paused = true
        echo "Keyboard events PAUSED"

    # Read current SDL error (if not empty → NOTIF_WARNING emitted)
    if win.isKeyJustPressed(CKey_E):
      let err = win.getError()
      if err.len > 0:
        echo "SDL Error: ", err

    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# EXAMPLE 10 — Full Application: Mini Text Editor
# ═══════════════════════════════════════════════════════════════════

proc example10_mini_editeur() =
  ## Combines everything into a console-based mini text editor:
  ##   - UTF-8 input via SDL_EVENT_TEXT_INPUT
  ##   - Backspace, Enter, Escape
  ##   - Ctrl+C → copy (displays content)
  ##   - Ctrl+A → select all (clears)
  ##   - F11    → borderless fullscreen
  ##   - F1     → help

  let app = initSDL3App()

  var win: SDL3Window
  new(win)
  app.initWindow(win, "Mini Editor — F1 for help", "900", "600")

  NOTIF_ERROR.connect do(mes, error: string):
    echo "[ERROR] ", mes, " | ", error

  var lines  = @[""]          # text lines
  var curLine = 0              # current line index
  var isFullscreen = false
  var running = true

  proc printDoc() =
    echo "══════════════════════"
    for i, l in lines:
      let marker = if i == curLine: "▶ " else: "  "
      echo marker, l
    echo "══════════════════════"

  proc printHelp() =
    echo """
    ┌─ HELP ──────────────────────────────┐
    │  Type          → insert text        │
    │  Enter         → new line           │
    │  Backspace     → erase              │
    │  Ctrl+C        → show doc           │
    │  Ctrl+A        → clear all          │
    │  F11           → fullscreen         │
    │  Escape        → quit               │
    └──────────────────────────────────────┘"""

  printHelp()

  while running:
    app.eventLoop(SDLEventRouter)

    # ── Character Input ─────────────────────────────────────────
    if win.textInput.len > 0:
      lines[curLine].add(win.textInput)

    # ── Backspace ─────────────────────────────────────────────────
    if win.isKeyJustPressed(CKey_Backspace):
      if lines[curLine].len > 0:
        var i = lines[curLine].len - 1
        while i > 0 and (lines[curLine][i].ord and 0xC0) == 0x80:
          dec i
        lines[curLine] = lines[curLine][0 ..< i]
      elif curLine > 0:
        # Merge with previous line
        let tail = lines[curLine]
        lines.delete(curLine)
        dec curLine
        lines[curLine].add(tail)

    # ── Enter → new line ───────────────────────────────────
    if win.isKeyJustPressed(CKey_Enter):
      inc curLine
      lines.insert("", curLine)

    # ── Ctrl+C → show document ────────────────────────────
    if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_C):
      printDoc()

    # ── Ctrl+A → clear all ─────────────────────────────────────
    if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_A):
      lines   = @[""]
      curLine = 0
      echo "(document cleared)"

    # ── F1 → help ─────────────────────────────────────────────────
    if win.isKeyJustPressed(CKey_F1):
      printHelp()

    # ── F11 → fullscreen ─────────────────────────────────────────
    if win.isKeyJustPressed(CKey_F11):
      isFullscreen = not isFullscreen
      win.setFullscreen(isFullscreen, desktopResolution = true)

    # ── Escape → quit ───────────────────────────────────────────
    if win.isKeyJustPressed(CKey_Escape):
      running = false

    win.updateWindow()

  win.quitWindow()
  app.quitSDL3App()


# ═══════════════════════════════════════════════════════════════════
# ENTRY POINT — launches desired example
# ═══════════════════════════════════════════════════════════════════

when isMainModule:
  echo """
  Choose an example:
    1  → Simple Window
    2  → Keyboard
    3  → Mouse
    4  → Text Input
    5  → Modifiers
    6  → Fullscreen
    7  → Resize / Reposition
    8  → Multi-window
    9  → Dynamic Notifiers
   10  → Mini Editor
  """
  let choix = readLine(stdin)
  case choix
  of "1":  example1_fenetre_simple()
  of "2":  example2_clavier()
  of "3":  example3_souris()
  of "4":  example4_texte()
  of "5":  example5_modificateurs()
  of "6":  example6_fullscreen()
  of "7":  example7_resize_reposition()
  of "8":  example8_multi_fenetres()
  of "9":  example9_notifiers()
  of "10": example10_mini_editeur()
  else:
    echo "Invalid choice."