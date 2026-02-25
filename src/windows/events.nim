

type
  KeyInput* = enum
    CKey_None     = 0,
    CKey_A        = 1,
    CKey_B        = 2,
    CKey_C        = 3,
    CKey_D        = 4,
    CKey_E        = 5,
    CKey_F        = 6,
    CKey_G        = 7,
    CKey_H        = 8,
    CKey_I        = 9,
    CKey_J        = 10,
    CKey_K        = 11,
    CKey_L        = 12,
    CKey_M        = 13,
    CKey_N        = 14,
    CKey_O        = 15,
    CKey_P        = 16,
    CKey_Q        = 17,
    CKey_R        = 18,
    CKey_S        = 19,
    CKey_T        = 20,
    CKey_U        = 21,
    CKey_V        = 22,
    CKey_W        = 23,
    CKey_X        = 24,
    CKey_Y        = 25,
    CKey_Z        = 26,
    CKey_0        = 27,
    CKey_1        = 28,
    CKey_2        = 29,
    CKey_3        = 30,
    CKey_4        = 31,
    CKey_5        = 32,
    CKey_6        = 33,
    CKey_7        = 34,
    CKey_8        = 35,
    CKey_9        = 36,
    CKey_Space    = 37,
    CKey_Enter    = 38,
    CKey_Escape   = 39,
    CKey_Tab      = 40,
    CKey_Backspace = 41,
    CKey_Delete   = 42,
    CKey_Insert   = 43,
    CKey_Home     = 44,
    CKey_End      = 45,
    CKey_PageUp   = 46,
    CKey_PageDown = 47,
    CKey_Up       = 48,
    CKey_Down     = 49,
    CKey_Left     = 50,
    CKey_Right    = 51,
    CKey_F1       = 52,
    CKey_F2       = 53,
    CKey_F3       = 54,
    CKey_F4       = 55,
    CKey_F5       = 56,
    CKey_F6       = 57,
    CKey_F7       = 58,
    CKey_F8       = 59,
    CKey_F9       = 60,
    CKey_F10      = 61,
    CKey_F11      = 62,
    CKey_F12      = 63,
    CKey_LShift   = 64,
    CKey_RShift   = 65,
    CKey_LCtrl    = 66,
    CKey_RCtrl    = 67,
    CKey_LAlt     = 68,
    CKey_RAlt     = 69,
    CKey_LSuper   = 70,
    CKey_RSuper   = 71,
    CKey_CapsLock = 72,
    CKey_NumLock  = 73,
    CKey_ScrollLock = 74,
    CKey_PrintScreen = 75,
    CKey_Pause    = 76,
    CKey_Num0     = 77,
    CKey_Num1     = 78,
    CKey_Num2     = 79,
    CKey_Num3     = 80,
    CKey_Num4     = 81,
    CKey_Num5     = 82,
    CKey_Num6     = 83,
    CKey_Num7     = 84,
    CKey_Num8     = 85,
    CKey_Num9     = 86,
    CKey_NumAdd   = 87,
    CKey_NumSub   = 88,
    CKey_NumMul   = 89,
    CKey_NumDiv   = 90,
    CKey_NumEnter = 91,
    CKey_NumDecimal = 92,
    CKey_Comma    = 93,
    CKey_Period   = 94,
    CKey_Slash    = 95,
    CKey_Backslash = 96,
    CKey_Semicolon = 97,
    CKey_Apostrophe = 98,
    CKey_LBracket = 99,
    CKey_RBracket = 100,
    CKey_Minus    = 101,
    CKey_Equal    = 102,
    CKey_Grave    = 103,
    CKey_Count    = 104

  MouseButton* = enum
    CMouseBtn_None    = 0,
    CMouseBtn_Left    = 1,
    CMouseBtn_Right   = 2,
    CMouseBtn_Middle  = 3,
    CMouseBtn_X1      = 4,
    CMouseBtn_X2      = 5,
    CMouseBtn_Count   = 6

  MouseAxis* = enum
    CMouseAxis_None   = 0,
    CMouseAxis_X      = 1,
    CMouseAxis_Y      = 2,
    CMouseAxis_WheelX = 3,
    CMouseAxis_WheelY = 4,
    CMouseAxis_Count  = 5

  WindowEventKind* = enum
    WINDOW_RESIZED
    WINDOW_MOVED
    WINDOW_MAXIMIZED
    WINDOW_MINIMIZED
    WINDOW_RESTORED
    WINDOW_SHOWN
    WINDOW_HIDDEN
    WINDOW_HAVE_FOCUS
    WINDOW_LOSE_FOCUS
    WINDOW_CLOSE


## ============================================================
##  SparseSet
##  - sparse : tableau indexé par l'enum, contient la position
##             dans dense (-1 = absent)
##  - dense  : contient uniquement les touches déjà utilisées
##             au cours de la session
## ============================================================

type
  SparseSet*[E: enum, T] = object
    sparse: array[E, int]   ## sparse[key] = index dans dense, -1 si absent
    dense*: seq[T]          ## données compactes
    keys*: seq[E]           ## clés parallèles à dense (pour itération)

proc initSparseSet*[E: enum, T](): SparseSet[E, T] =
  for i in low(E)..high(E):
    result.sparse[i] = -1

proc contains*[E: enum, T](s: SparseSet[E, T], key: E): bool =
  s.sparse[key] != -1

proc `[]`*[E: enum, T](s: SparseSet[E, T], key: E): lent T =
  assert s.contains(key), "SparseSet: key not found"
  s.dense[s.sparse[key]]

proc `[]`*[E: enum, T](s: var SparseSet[E, T], key: E): var T =
  assert s.contains(key), "SparseSet: key not found"
  s.dense[s.sparse[key]]

proc insert*[E: enum, T](s: var SparseSet[E, T], key: E, val: T) =
  ## Insère ou remplace la valeur associée à key.
  if s.contains(key):
    s.dense[s.sparse[key]] = val
  else:
    s.sparse[key] = s.dense.len
    s.dense.add(val)
    s.keys.add(key)

proc len*[E: enum, T](s: SparseSet[E, T]): int = s.dense.len


## ============================================================
##  Event types
## ============================================================

type
  WindowEvent* = object
    case kind*: WindowEventKind
    of WINDOW_RESIZED:
      width*  : int
      height* : int
    of WINDOW_MOVED:
      x_pos* : int
      y_pos* : int
    of WINDOW_MAXIMIZED,
       WINDOW_MINIMIZED,
       WINDOW_RESTORED,
       WINDOW_SHOWN,
       WINDOW_HIDDEN,
       WINDOW_HAVE_FOCUS,
       WINDOW_LOSE_FOCUS,
       WINDOW_CLOSE:
      discard

  KeyboardEvent* = object
    id*          : int
    key*         : KeyInput
    just_pressed* : bool
    pressed*     : bool
    just_released*: bool
    ## Modifier keys
    mkey*        : KeyInput   ## main modifier (ex: LShift)
    pkey*        : KeyInput   ## secondary modifier

  MouseClickEvent* = object
    button*      : MouseButton
    just_pressed* : bool
    pressed*     : bool
    just_released*: bool
    clicks*      : int

  MouseMotionEvent* = object
    x*    : int
    y*    : int
    xrel* : int
    yrel* : int

  MouseWheelEvent* = object
    xwheel* : int
    ywheel* : int

  AxisEventKind* = enum
    AxisMotion
    AxisWheel

  AxisEvent* = object
    case kind*: AxisEventKind
    of AxisMotion: motion*: MouseMotionEvent
    of AxisWheel:  wheel*:  MouseWheelEvent

  DeviceState* = object
    updated* : bool
    cnt*     : int

  InputData* = object
    keyboard* : SparseSet[KeyInput, KeyboardEvent]
    mouseButtons* : SparseSet[MouseButton, MouseClickEvent]
    axes* : SparseSet[MouseAxis, AxisEvent]

  InputState* = object
    data*    : InputData
    kbState* : DeviceState
    mbState* : DeviceState
    mmState* : DeviceState
    mwState* : DeviceState

proc initDeviceState*(): DeviceState =
  DeviceState(updated: false, cnt: 0)

proc resetCount*(d: var DeviceState) =
  d.cnt = 0

proc updateCount*(d: var DeviceState) =
  inc d.cnt

proc initInputData*(): InputData =
  result.keyboard     = initSparseSet[KeyInput, KeyboardEvent]()
  result.mouseButtons = initSparseSet[MouseButton, MouseClickEvent]()
  result.axes         = initSparseSet[MouseAxis, AxisEvent]()

## ============================================================
##  InputState
## ============================================================

proc initInputState*(): InputState =
  result.data    = initInputData()
  result.kbState = initDeviceState()
  result.mbState = initDeviceState()
  result.mmState = initDeviceState()
  result.mwState = initDeviceState()

proc resetCounts*(inp: var InputState) =
  resetCount(inp.kbState)
  resetCount(inp.mbState)
  resetCount(inp.mmState)
  resetCount(inp.mwState)

proc updateKeyboardCount*(inp: var InputState)    = updateCount(inp.kbState)
proc updateMouseButtonCount*(inp: var InputState) = updateCount(inp.mbState)
proc updateMouseMotionCount*(inp: var InputState) = updateCount(inp.mmState)
proc updateMouseWheelCount*(inp: var InputState)  = updateCount(inp.mwState)

proc setKeyEvent*(inp: var InputState, ev: KeyboardEvent) =
  inp.data.keyboard.insert(ev.key, ev)

proc setMouseButtonEvent*(inp: var InputState, ev: MouseClickEvent) =
  inp.data.mouseButtons.insert(ev.button, ev)

proc setMotionEvent*(inp: var InputState, ev: MouseMotionEvent) =
  inp.data.axes.insert(CMouseAxis_X, AxisEvent(kind: AxisMotion, motion: ev))

proc setWheelEvent*(inp: var InputState, ev: MouseWheelEvent) =
  inp.data.axes.insert(CMouseAxis_WheelY, AxisEvent(kind: AxisWheel, wheel: ev))

proc updateKeyboardEvents*(data: var InputData) =
  for ev in data.keyboard.dense.mitems:
    ev.just_pressed  = false
    ev.just_released = false

proc updateMouseButton*(data: var InputData) =
  for ev in data.mouseButtons.dense.mitems:
    ev.just_pressed  = false
    ev.just_released = false

proc updateMouseMotion*(data: var InputData) =
  if data.axes.contains(CMouseAxis_X):
    data.axes[CMouseAxis_X].motion.xrel = 0
    data.axes[CMouseAxis_X].motion.yrel = 0

proc updateWheel*(data: var InputData) =
  if data.axes.contains(CMouseAxis_WheelY):
    data.axes[CMouseAxis_WheelY].wheel.xwheel = 0
    data.axes[CMouseAxis_WheelY].wheel.ywheel = 0

proc updateDevice(inp: var InputState, d: var DeviceState,
                  update: proc(data: var InputData)) =
  if d.cnt == 0 and not d.updated:
    d.updated = true
    update(inp.data)
  else:
    d.updated = false

proc updateInputState*(inp: var InputState) =
  updateDevice(inp, inp.kbState, updateKeyboardEvents)
  updateDevice(inp, inp.mbState, updateMouseButton)
  updateDevice(inp, inp.mmState, updateMouseMotion)
  updateDevice(inp, inp.mwState, updateWheel)