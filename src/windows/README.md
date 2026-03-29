# Cruise Windowing: A Backend-Agnostic Windowing Abstraction for Nim

---

## Introduction

Cruise Windowing is a lightweight, backend-agnostic windowing and input abstraction layer written in Nim. It provides a unified API for creating and managing application windows, handling keyboard and mouse input, and dispatching OS events — regardless of the underlying windowing backend (SDL, GLFW, or anything else you choose to plug in).

At its core, Cruise Windowing is made of three interlocking pieces: a **window abstraction** (`CWindow` / `CApp`), an **event loop** with a structured input state machine, and a **signal/notifier system** that decouples your application logic from backend-specific plumbing. Together they let you write game loops, desktop tools, and multimedia applications that can be retargeted to a new backend without touching a single line of application code.

---

## Philosophy

Cruise Windowing is built around three convictions.

**Separation of concerns first.** The library never assumes a specific backend. Every platform-specific operation — creating a window, polling events, translating raw key codes — is expressed as an overridable `method`. The base implementations are intentionally minimal: they emit the appropriate notification and return. Concrete backends fill in the blanks by overriding those methods. Your application code only ever speaks to the abstraction.

**Events as first-class signals.** Rather than relying on callbacks or a monolithic event queue, CWindow uses a typed notifier system. Every observable state change — a window being resized, a key being pressed, a fatal error — is represented as a named notifier that any part of the codebase can subscribe to. This makes the data flow explicit and auditable, and it means you can react to platform events without coupling your logic to the event loop implementation.

**Input as a state machine, not a stream.** Raw OS events are transient; game and UI logic needs to ask questions like "is this key held?" or "was that button just released this frame?" Cruise Windowing solves this by maintaining a structured `InputState` per window that is reset and updated once per frame by the event loop. Queries are O(1) thanks to a `SparseSet` backing store indexed directly by enum values.

---

## Features

### Backend-Agnostic Window Lifecycle

`CWindow` and `CApp` are plain Nim `ref object` types. A `CApp` holds a sequence of `CWindow` instances; each window tracks its own geometry, visibility, fullscreen state, child window list, and input state. All mutation goes through `method` calls that backends override.

```nim
# The base types — no backend dependency whatsoever
type
  CWindow* = ref object of RootObj
    id*, width*, height*, x*, y* : int
    title*       : string
    fullscreen*  : bool
    visible*     : bool
    childrens*   : seq[int]
    inputs*      : InputState

  CApp* = ref object
    windows* : seq[CWindow]
```

A backend creates a window by overriding `initWindow`, populating the fields, and emitting `NOTIF_WINDOW_CREATED`. From that point on, the rest of the library treats all backends identically.

---

### Typed Notifier System

Every significant event in the system is represented by a named, typed notifier. Notifiers are declared with a `notifier` macro that stamps out both the signal type and its `emit` proc. Subscribers connect to a notifier at any point and receive strongly-typed payloads — no casting, no stringly-typed event kinds.

```nim
## Window lifecycle notifiers (selection)
notifier NOTIF_WINDOW_CREATED(win: CWindow)
notifier NOTIF_WINDOW_RESIZED(win: CWindow, width: int, height: int)
notifier NOTIF_WINDOW_FULLSCREEN(win: CWindow, active: bool, desktopResolution: bool)
notifier NOTIF_WINDOW_EXITTED(win: CWindow)

## Diagnostic notifiers
notifier NOTIF_ERROR(mes: string, error: string)
notifier NOTIF_WARNING(mes: string, warning: string, code: int)
notifier NOTIF_INFO(mes: string, info: string, code: int)

## Input notifiers
notifier NOTIF_KEYBOARD_INPUT(win: CWindow, ev: KeyboardEvent)
notifier NOTIF_MOUSE_BUTTON(win: CWindow, ev: MouseClickEvent)
notifier NOTIF_MOUSE_MOTION(win: CWindow, ev: MouseMotionEvent)
notifier NOTIF_MOUSE_WHEEL(win: CWindow, ev: MouseWheelEvent)
```

Emitting a notifier is a single call on the backend side. Consuming it is equally clean on the application side, with no dependency on the backend that produced it.

---

### Overridable Backend Interface

Every platform operation is expressed as a `method` on `CWindow` or `CApp`. The base implementations emit the correct notifier and do nothing else — they are valid stubs that let you compile and run against the abstraction before any backend exists.

```nim
method resizeWindow*(win: CWindow, width, height: int) {.base.} =
  NOTIF_WINDOW_RESIZED.emit((win, width, height))

method setFullscreen*(win: CWindow, active: bool,
                      desktopResolution: bool = false) {.base.} =
  NOTIF_WINDOW_FULLSCREEN.emit((win, active, desktopResolution))

method convertKey*(win: CWindow, rawKey: int): KeyInput {.base.} =
  CKey_None
```

An SDL backend, for example, overrides `initWindow` to call `SDL_CreateWindow`, overrides `convertKey` to map `SDLK_*` constants to `KeyInput` values, and so on. The application never changes.

---

### Frame-Accurate Input State Machine

Cruise Window does not expose raw events to application code. Instead, it maintains an `InputState` per window that is advanced exactly once per frame by `eventLoop`. Each key and mouse button tracks three Boolean flags: `pressed` (held this frame), `just_pressed` (rising edge), and `just_released` (falling edge). Axes track absolute position and relative delta, with the delta zeroed each frame.

```nim
# Query helpers — identical API for keyboard and mouse
proc isKeyPressed*(win: CWindow, key: KeyInput): bool
proc isKeyJustPressed*(win: CWindow, key: KeyInput): bool
proc isKeyJustReleased*(win: CWindow, key: KeyInput): bool
proc isKeyReleased*(win: CWindow, key: KeyInput): bool

proc isMouseButtonPressed*(win: CWindow, btn: MouseButton): bool
proc isMouseButtonJustPressed*(win: CWindow, btn: MouseButton): bool

# App-wide variants — true if ANY window satisfies the condition
proc isKeyJustPressed*(app: CApp, key: KeyInput): bool
```

The `SparseSet[E, T]` that backs the state machine provides O(1) insert, lookup, and iteration over only the keys that have ever been touched — there is no cost for the 100+ key codes that are never used in a given session.

---

### SparseSet — O(1) Input Storage

The `SparseSet` is the data structure that makes the input system efficient. It pairs a fixed-size sparse array (indexed directly by enum ordinal) with a compact dense sequence. Lookup and insert are constant time; iteration visits only active entries.

```nim
type
  SparseSet*[E: enum, T] = object
    sparse : array[E, int]   # sparse[key] = index in dense, -1 if absent
    dense* : seq[T]          # compact data
    keys*  : seq[E]          # parallel key list for iteration

# Usage is transparent — the event loop manages this for you
proc isKeyPressed*(win: CWindow, key: KeyInput): bool =
  let kb = win.inputs.data.keyboard
  if not kb.contains(key): return false
  kb[key].pressed
```

The same structure is used for keyboard events (`SparseSet[KeyInput, KeyboardEvent]`), mouse buttons (`SparseSet[MouseButton, MouseClickEvent]`), and axes (`SparseSet[MouseAxis, AxisEvent]`).

---

### InputMap — Composable Action Bindings

`InputMap` lets you bind multiple keyboard keys and mouse buttons to a single named action. It carries a `strength` float for analog-style weighting. The `inputMap` template dispatches each argument to the correct internal set at compile time, with zero runtime branching.

```nim
# Declare action bindings
let Jump  = inputMap(CKey_Space, CKey_Up,      strength = 1.0)
let Shoot = inputMap(CKey_Z,     CMouseBtn_Left, strength = 0.8)

# Query the whole action in one call
if win.isKeyJustPressed(Jump):
  player.jump()

if win.isKeyPressed(Shoot):
  player.fire(Shoot.strength)
```

Bindings can be mutated at runtime for remapping:

```nim
proc replaceKey*(inp: var InputMap, old, new: KeyInput)
proc addKey*(inp: var InputMap, key: KeyInput)
proc removeKey*(inp: var InputMap, btn: MouseButton)
```

---

### The Event Loop

`eventLoop` is the heartbeat of the application. It performs three steps in strict order: reset per-frame counters on every window, invoke one or more router procedures that poll OS events and update state, then advance the input state machine. The router pattern keeps event polling decoupled from the loop driver.

```nim
proc eventLoop*(app: CApp, routers: varargs[proc(app: CApp)])

# Typical usage
while running:
  eventLoop(app, pollSDLEvents)   # your backend router goes here

  if myWin.isKeyJustPressed(CKey_Escape):
    running = false

  if myWin.isKeyPressed(Jump):
    player.jump()
```

Passing multiple routers is supported for layered event handling (e.g. a UI layer and a game layer that each respond to distinct event subsets).

---

### Rich Key and Axis Enumeration

Cruise Windowing ships with a comprehensive `KeyInput` enum covering the full standard keyboard (letters, digits, function keys, modifiers, numpad, punctuation) and a `MouseButton` / `MouseAxis` enum set for pointer devices. All enum values have stable integer ordinals so they can be used as array indices without hashing.

```nim
type KeyInput* = enum
  CKey_None, CKey_A .. CKey_Z,
  CKey_0 .. CKey_9,
  CKey_F1 .. CKey_F12,
  CKey_LShift, CKey_RShift, CKey_LCtrl, CKey_RCtrl,
  CKey_LAlt, CKey_RAlt, CKey_LSuper, CKey_RSuper,
  CKey_Space, CKey_Enter, CKey_Escape, CKey_Tab,
  CKey_Up, CKey_Down, CKey_Left, CKey_Right,
  # ... numpad, punctuation, locks, etc.
  CKey_Count  # sentinel

type MouseAxis* = enum
  CMouseAxis_X, CMouseAxis_Y,
  CMouseAxis_WheelX, CMouseAxis_WheelY
```

`getAxis` returns a tagged-union `AxisEvent` that is either an `AxisMotion` (absolute position + relative delta) or an `AxisWheel` (scroll amounts), zeroed gracefully when the axis has never been seen.

---

## Summary

Cruise Windowing gives you a clean, composable foundation for Nim windowing applications:

A **typed notifier system** makes every window, input, and diagnostic event observable without coupling producers to consumers. A **method-based backend interface** means your application logic is written once and runs on any windowing backend that provides concrete overrides. A **frame-accurate input state machine** backed by a `SparseSet` gives you rising-edge, falling-edge, and held-state queries in O(1) with zero boilerplate. **InputMap** lifts raw key queries to named, rebindable actions with optional strength weighting. And the **`eventLoop` proc** ties it all together into a three-phase, router-driven frame cycle that is easy to extend without touching the core.

The result is a library that stays out of your way when you know what you are doing, and gives you a clear extension point everywhere you need to add something new.