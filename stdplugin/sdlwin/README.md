# SDL3 Backend — Cruise over SDL3

---

## Introduction

This package is the SDL3 concrete backend for the Cruise windowing abstraction. It provides a fully working implementation of every abstract `method` defined by the core library — window creation, event polling, keyboard and mouse input, fullscreen management, and more — by wrapping the `sdl3_nim` package (dinau/sdl3_nim, futhark-generated).

The result is a thin but complete bridge: your application code calls the same `isKeyJustPressed`, `setFullscreen`, or `resizeWindow` it would call on any backend, and the SDL3 layer handles the translation to native SDL calls, fires the appropriate `NOTIF_*` signals, and keeps the input state machine in sync. You never touch SDL directly from application code.

---

## Philosophy

The SDL3 backend follows three rules that keep it honest.

**Strict method dispatch, no casting in hotpaths.** Every overriding method takes `SDL3Window` directly as its receiver. There is no `CWindow` parameter followed by an internal `cast` — Nim's dynamic dispatch routes the call correctly without that pattern, and removing the cast eliminates an entire class of subtle bugs at the cost of nothing.

**Events fire before state is cleared.** Notifiers such as `NOTIF_KEYBOARD_INPUT` and `NOTIF_MOUSE_BUTTON` are emitted inside `handleKeyboardInputs` and `handleMouseEvents`, which run before `updateInputState` clears the `just_pressed` and `just_released` flags. This means a notifier handler always observes a fully accurate snapshot of the current frame's edge state — no race between signal emission and state reset.

**Modifier detection is post-insertion.** The `detectModifiers` helper is called after the triggering key has already been written into the sparse-set. This means that if the pressed key is itself a modifier (e.g. `LShift`), it will appear in its own `mkey` field — no special-casing required and no frame of lag on modifier self-registration.

---

## Features

### SDL3Window — The Concrete Window Type

`SDL3Window` extends `CWindow` with two SDL-specific fields: `handle`, which holds the raw `ptr SDL_Window` and is exported so the event router can perform window-ID lookups, and `textInput`, a UTF-8 string that accumulates all `SDL_EVENT_TEXT_INPUT` characters received during the current frame and is wiped at the start of the next one.

```nim
type
  SDL3Window* = ref object of CWindow
    handle*    : ptr SDL_Window   # exported for window-ID routing
    lastError  : string
    textInput* : string           # UTF-8 chars typed this frame
```

Everything else — geometry, visibility, fullscreen state, input state machine — is inherited from `CWindow` and managed through the same abstract accessors the rest of the library uses.

---

### App Initialisation and Teardown

Two procs bracket the lifetime of an SDL3 application. `initSDL3App` calls `SDL_Init(SDL_INIT_VIDEO)` and returns a `CApp`; on failure it emits `NOTIF_ERROR` and returns an empty app rather than raising. `quitSDL3App` calls `SDL_Quit_proc` and is safe to call even if initialisation never succeeded.

```nim
let app = initSDL3App()

var win: SDL3Window
new(win)
app.initWindow(win, "My Window", "1280", "720")

# ... game loop ...

win.quitWindow()
app.quitSDL3App()
```

`initWindow` accepts up to five positional string arguments — title, width, height, x, y — all optional, defaulting to `"Window"`, `800`, `600`, and `SDL_WINDOWPOS_CENTERED`. Because SDL3's `SDL_CreateWindow` no longer takes a position argument, the backend issues a separate `SDL_SetWindowPosition` call immediately after creation.

---

### Full Method Coverage

Every abstract method from the core library has a concrete SDL3 override. Each one performs the SDL call, updates the relevant cached field on `SDL3Window`, and emits the matching notifier.

```nim
method resizeWindow*(win: SDL3Window, width, height: int) =
  SDL_SetWindowSize(win.handle, width.cint, height.cint)
  win.width  = width
  win.height = height
  NOTIF_WINDOW_RESIZED.emit((CWindow(win), width, height))

method repositionWindow*(win: SDL3Window, x, y: int) =
  SDL_SetWindowPosition(win.handle, x.cint, y.cint)
  win.x = x
  win.y = y
  NOTIF_WINDOW_REPOSITIONED.emit((CWindow(win), x, y))

method setWindowTitle*(win: SDL3Window, newTitle: string) =
  SDL_SetWindowTitle(win.handle, newTitle.cstring)
  win.title = newTitle
  NOTIF_WINDOW_TITLE_CHANGED.emit((CWindow(win), newTitle))
```

Minimize, maximize, restore, hide, show, raise, update, and quit all follow the same pattern. `updateWindow` calls `SDL_UpdateWindowSurface` and emits `NOTIF_WARNING` when SDL reports an error — expected and non-fatal when a GPU renderer is in use, since GPU renderers swap buffers themselves.

---

### Fullscreen — Borderless and Exclusive

`setFullscreen` supports both SDL3 fullscreen modes through a single call. When `desktopResolution` is true, the backend calls `SDL_SetWindowFullscreenMode(win.handle, nil)` first to select the native desktop resolution, then engages fullscreen — producing a borderless overlay. When `desktopResolution` is false, it goes straight to exclusive fullscreen at the window's own resolution. Any SDL failure emits `NOTIF_ERROR` and returns early without changing `win.fullscreen`.

```nim
# F11 → borderless fullscreen at native resolution
win.setFullscreen(true, desktopResolution = true)

# F10 → exclusive fullscreen at window resolution
win.setFullscreen(true, desktopResolution = false)

# Return to windowed
win.setFullscreen(false)
```

---

### Key Translation — `convertKey`

`convertKey` maps every `SDL_Keycode` to a `KeyInput` enum value via a single exhaustive `case` statement. It handles letters, digits, function keys, navigation keys, all modifiers (left and right variants), lock keys, the full numpad, and common punctuation. Any unrecognised keycode returns `CKey_None`, which the event router silently ignores.

The `sdl3_nim` futhark bindings rename `SDLK_a` through `SDLK_z` to `SDLK_a_const` through `SDLK_z_const` to avoid Nim keyword collisions; the backend accounts for this throughout the mapping table.

```nim
method convertKey*(win: SDL3Window, rawKey: uint): KeyInput =
  case SDL_Keycode(rawKey)
  of SDLK_a:      CKey_A
  of SDLK_SPACE:  CKey_Space
  of SDLK_LSHIFT: CKey_LShift
  of SDLK_KP_0:   CKey_Num0
  # ... full table ...
  else: CKey_None
```

---

### Event Routing — `SDLEventRouter`

`SDLEventRouter` is the proc you pass to `eventLoop` each frame. It drains the SDL3 event queue with `SDL_PollEvent` and dispatches each event to the matching `SDL3Window` via `findWindow`, which looks up windows by `SDL_WindowID`. After the queue is empty it calls `handleKeyboardInputs` and `handleMouseEvents` on every window to fire the input notifiers while edge flags are still live.

```nim
while running:
  app.eventLoop(SDLEventRouter)

  if app.isKeyJustPressed(CKey_Escape): running = false
  win.updateWindow()
```

The router handles seven SDL event categories in order: quit, window events, key down/up, text input, mouse motion, mouse wheel, and mouse button down/up. Each category resolves the target window from the event's `windowID` field before touching any state, so multiple windows in a single `CApp` each receive only their own events.

---

### Keyboard Input — Edge Flags and Modifier Context

When a `SDL_EVENT_KEY_DOWN` or `SDL_EVENT_KEY_UP` arrives, the router translates the keycode, retrieves or creates a `KeyboardEvent` from the sparse-set, and sets the three state flags according to the event kind and repeat status.

Auto-repeat events (`ev.key.repeat == true`) set `pressed = true` but leave both `just_pressed` and `just_released` false — they represent a key being held, not a new press. This prevents held keys from triggering single-frame logic on every repeat tick.

After insertion, `detectModifiers` walks the sparse-set for currently pressed modifier keys and attaches up to two of them as `mkey` and `pkey` on the triggering event. Because insertion happens first, a modifier key pressed alone will find itself in the set and correctly populate its own `mkey` field.

```nim
# Query modifier combinations directly from InputState
if win.isKeyPressed(CKey_LCtrl) and win.isKeyJustPressed(CKey_S):
  save()

# Or read modifier context from the notifier payload
NOTIF_KEYBOARD_INPUT.connect do(w: CWindow, ev: KeyboardEvent):
  if ev.just_pressed:
    echo ev.key, " with modifier: ", ev.mkey
```

---

### Text Input — UTF-8 Accumulation

SDL3 separates printable character input from key events via `SDL_EVENT_TEXT_INPUT`. Each frame, the router appends incoming UTF-8 text to `win.textInput`. The `clearFrameState` method (called at the top of `SDLEventRouter`) resets this buffer before new events are processed, so `win.textInput` always contains exactly the characters typed during the current frame.

```nim
# Accumulate text across frames in your own buffer
var buffer = ""

while running:
  app.eventLoop(SDLEventRouter)

  if win.textInput.len > 0:
    buffer.add(win.textInput)

  if win.isKeyJustPressed(CKey_Backspace) and buffer.len > 0:
    # Step back one UTF-8 code point
    var i = buffer.len - 1
    while i > 0 and (buffer[i].ord and 0xC0) == 0x80: dec i
    buffer = buffer[0 ..< i]

  if win.isKeyJustPressed(CKey_Enter):
    echo "Submitted: ", buffer
    buffer = ""
```

---

### Mouse Motion — Dual-Axis Storage

Mouse motion events store the same `MouseMotionEvent` under both `CMouseAxis_X` and `CMouseAxis_Y`, making each axis independently queryable. The event carries both absolute position (`x`, `y`) and frame-relative delta (`xrel`, `yrel`). The delta is zeroed by `updateMouseMotion` at the end of each frame in which no motion was received.

```nim
let ax = win.getAxis(CMouseAxis_X)
if ax.kind == AxisMotion:
  echo "pos=(", ax.motion.x, ",", ax.motion.y, ")  ",
       "delta=(", ax.motion.xrel, ",", ax.motion.yrel, ")"
```

---

### Mouse Wheel — Natural Scroll Normalisation

SDL3 exposes a `direction` field on wheel events that indicates whether the platform uses natural scrolling (content follows finger). When `direction == SDL_MOUSEWHEEL_FLIPPED`, the backend multiplies x and y by −1 before storing the event, normalising all platforms to the same convention: positive Y means scroll up (away from the user), positive X means scroll right. The wheel value is stored under both `CMouseAxis_WheelX` and `CMouseAxis_WheelY`.

```nim
NOTIF_MOUSE_WHEEL.connect do(w: CWindow, ev: MouseWheelEvent):
  if ev.ywheel > 0: zoomIn()
  elif ev.ywheel < 0: zoomOut()
```

---

### Multi-Window Support

A single `CApp` can hold any number of `SDL3Window` instances. The event router identifies the target window for every event by matching the event's `SDL_WindowID` against the handle of each registered window. Windows are independent: input state, text buffers, and notifier payloads all carry the originating window reference, so handlers can distinguish events by `win.id`.

```nim
app.initWindow(w1, "Main",      "800", "600", "100", "100")
app.initWindow(w2, "Secondary", "400", "300", "950", "100")

NOTIF_WINDOW_EVENT.connect do(win: CWindow, ev: WindowEvent):
  if ev.kind == WINDOW_CLOSE:
    if win.id == w1.id: running = false
    elif win.id == w2.id: w2.quitWindow(); w2Alive = false

while running:
  app.eventLoop(SDLEventRouter)   # pumps events for ALL windows

  if w2Alive and w2.isKeyJustPressed(CKey_Space):
    echo "Space pressed in W2"
```

Windows can be destroyed and recreated at runtime — `quitWindow` calls `SDL_DestroyWindow` and nils the handle, and a new `initWindow` call on a fresh `SDL3Window` object registers a new entry in `app.windows`.

---

### Dynamic Notifier Connection

Notifier handlers can be connected and disconnected at runtime. This is useful for pausing input handling during menus, cutscenes, or modal dialogs without polluting the main loop with guard flags.

```nim
proc kbHandler(w: CWindow, ev: KeyboardEvent) =
  if ev.just_pressed: echo ev.key

NOTIF_KEYBOARD_INPUT.connect(kbHandler)

# Later — pause keyboard logging
NOTIF_KEYBOARD_INPUT.disconnect(kbHandler)

# Resume
NOTIF_KEYBOARD_INPUT.connect(kbHandler)
```

---

## Naming Conventions from sdl3_nim

The `sdl3_nim` package is futhark-generated and applies several automatic renames that the backend accounts for throughout:

- Struct fields named `type` are renamed to `type_field` (e.g. `ev.type_field` instead of `ev.type`).
- Struct fields named `mod` are renamed to `mod_field`.
- `SDLK_a` through `SDLK_z` are renamed to `SDLK_a_const` through `SDLK_z_const` to avoid colliding with Nim's `a`..`z` identifier range.
- `SDL_Quit` (the proc) is renamed `SDL_Quit_proc` to avoid colliding with the `SDL_Quit` event constant.

These renames are handled transparently inside the backend; application code never encounters them.

---

## Summary

The SDL3 backend is a complete, production-ready implementation of the CWindow abstraction on top of SDL3. It covers the full surface area of the abstract interface — window lifecycle, all input devices, text entry, fullscreen, multi-window routing, and diagnostic error reporting — while adding two SDL-specific conveniences: `textInput` for frame-batched UTF-8 character input, and natural scroll normalisation for mouse wheel events.

The single entry point for application code is `SDLEventRouter`, passed to `eventLoop` once per frame. Everything else — SDL initialisation, event translation, modifier detection, axis storage, signal emission — happens automatically inside the backend. Switching to a different backend in the future requires no changes to application logic: only the router proc and the concrete window type need to change.