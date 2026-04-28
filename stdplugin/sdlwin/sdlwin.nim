## =============================================================
##  SDL3 Backend — window lifecycle
##
##  Uses the sdl3_nim package (dinau/sdl3_nim, futhark-generated).
##  Naming conventions from that package:
##    - struct fields named `type`  → `type_field`
##    - struct fields named `mod`   → `mod_field`
##    - SDLK_a … SDLK_z            → SDLK_a_const … SDLK_z_const
##    - SDL_Quit (proc collision)   → SDL_Quit_proc
##
##  Every method takes SDL3Window directly — no internal casting.
## =============================================================

import strutils
import ../../externalLibs/sdl3_nim/src/sdl3_nim
import ../../src/windows/windows
export SDL_Delay

# ---------------------------------------------------------------------------
# SDL3-specific subtypes
# ---------------------------------------------------------------------------

type
  SDL3Window* = ref object of CWindow
    ## Wraps an SDL_Window handle with cached metadata.
    ## `handle` is exported so sdl3_events.nim can do window-ID routing.
    handle*    : ptr SDL_Window
    lastError  : string
    ## UTF-8 text accumulated from SDL_EVENT_TEXT_INPUT this frame.
    ## Cleared at the start of every eventLoop iteration.
    textInput* : string

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc sdlError*(): string =
  ## Drain and return the current SDL error string.
  result = $SDL_GetError()
  SDL_ClearError()

proc nextWindowID(app: CApp): int = app.windows.len

# ---------------------------------------------------------------------------
# App init / teardown
# ---------------------------------------------------------------------------

proc initSDL3App*(): CApp =
  ## Initialise the SDL3 video subsystem.
  ## Emits NOTIF_ERROR on failure and returns an uninitialised app.
  result = CApp()
  if not SDL_Init(SDL_INIT_VIDEO):
    NOTIF_ERROR.emit(("SDL_Init failed", sdlError()))
    return

proc quitSDL3App*(app: CApp) =
  ## Shut down SDL3.  Safe to call even if init failed.
  SDL_Quit_proc()
  
# ---------------------------------------------------------------------------
# Per-frame state reset
# ---------------------------------------------------------------------------

method clearFrameState*(win: CWindow) {.base.} = discard
method clearFrameState*(win: SDL3Window) =
  ## Wipe the accumulated text-input buffer for this window.
  ## Call at the top of each game-loop iteration, before polling events.
  win.textInput = ""

proc clearFrameState*(app: CApp) =
  ## Convenience: clear frame state on every window.
  for w in app.windows:
    w.clearFrameState()

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


method maximizeWindow*(win: SDL3Window) =
  SDL_MaximizeWindow(win.handle)
  NOTIF_WINDOW_MAXIMIZED.emit((CWindow(win),))


method minimizeWindow*(win: SDL3Window) =
  SDL_MinimizeWindow(win.handle)
  NOTIF_WINDOW_MINIMIZED.emit((CWindow(win),))


method restoreWindow*(win: SDL3Window) =
  SDL_RestoreWindow(win.handle)
  NOTIF_WINDOW_RESTORED.emit((CWindow(win),))


method hideWindow*(win: SDL3Window) =
  SDL_HideWindow(win.handle)
  win.visible = false
  NOTIF_WINDOW_HIDDEN.emit((CWindow(win),))


method showWindow*(win: SDL3Window) =
  SDL_ShowWindow(win.handle)
  win.visible = true
  NOTIF_WINDOW_SHOWN.emit((CWindow(win),))


method raiseWindow*(win: SDL3Window) =
  SDL_RaiseWindow(win.handle)
  NOTIF_WINDOW_RAISED.emit((CWindow(win),))


method setFullscreen*(win: SDL3Window, active: bool,
                      desktopResolution: bool = false) =
  ## Toggle fullscreen on this SDL3 window.
  ##
  ##   desktopResolution = true
  ##     → borderless at native desktop resolution.
  ##       SDL3: call SDL_SetWindowFullscreenMode(win, nil) before engaging.
  ##   desktopResolution = false
  ##     → exclusive fullscreen at the window's own resolution.
  ##
  ## Emits NOTIF_WINDOW_FULLSCREEN on success, NOTIF_ERROR on failure.
  if active:
    if desktopResolution:
      # nil mode → SDL picks the native desktop resolution
      if not SDL_SetWindowFullscreenMode(win.handle, nil):
        NOTIF_ERROR.emit(("SDL_SetWindowFullscreenMode(desktop) failed",
                          sdlError()))
        return
    if not SDL_SetWindowFullscreen(win.handle, true):
      NOTIF_ERROR.emit(("SDL_SetWindowFullscreen(true) failed", sdlError()))
      return
  else:
    if not SDL_SetWindowFullscreen(win.handle, false):
      NOTIF_ERROR.emit(("SDL_SetWindowFullscreen(false) failed", sdlError()))
      return
  win.fullscreen = active
  NOTIF_WINDOW_FULLSCREEN.emit((CWindow(win), active, desktopResolution))


# ---------------------------------------------------------------------------
# Window lifecycle methods
# All methods take SDL3Window directly — proper OOP, no internal casting.
# ---------------------------------------------------------------------------

method initWindow*(app: CApp, sw: var SDL3Window, title: string = "untitled", 
                   posX: int = SDL_WINDOWPOS_CENTERED.int, posY: int = SDL_WINDOWPOS_CENTERED.int,
                   width: int = 200, height: int= 300, args: varargs[string]) =
  ## Create a new SDL3 window and register it in *app*.
  ##
  ## args (positional, all optional):
  ##   [0] title   default "Window"
  ##   [1] width   default 800
  ##   [2] height  default 600
  ##   [3] x       default SDL_WINDOWPOS_CENTERED
  ##   [4] y       default SDL_WINDOWPOS_CENTERED
  ##
  ## Emits NOTIF_WINDOW_CREATED on success, NOTIF_ERROR on failure.
  let handle = SDL_CreateWindow(title.cstring,
                                width.cint, height.cint,
                                SDL_WINDOW_RESIZABLE)
  if handle == nil:
    NOTIF_ERROR.emit(("SDL_CreateWindow failed", sdlError()))

  # SDL3 CreateWindow has no position argument → set it separately
  SDL_SetWindowPosition(handle, posX.cint, posY.cint)

  sw.id         = app.nextWindowID()
  sw.tag        = "SDL"
  sw.handle     = handle
  sw.title      = title
  sw.width      = width
  sw.height     = height
  sw.x          = posX
  sw.y          = posY
  sw.fullscreen = false
  sw.visible    = true
  sw.inputs     = initInputState()

  app.windows.add(sw)
  NOTIF_WINDOW_CREATED.emit((CWindow(sw),))

method updateWindow*(win: SDL3Window) =
  ## Flush the software surface to screen.
  ## Hardware renderers swap buffers themselves; a NOTIF_WARNING is emitted
  ## when SDL reports an error (expected with GPU renderers, not fatal).
  if not SDL_UpdateWindowSurface(win.handle):
    NOTIF_WARNING.emit(("SDL_UpdateWindowSurface", sdlError(), 0))
  NOTIF_WINDOW_UPDATED.emit((CWindow(win),))


method getError*(win: SDL3Window): string =
  ## Retrieve the latest SDL error for this window.
  ## Emits NOTIF_INFO (no error) or NOTIF_WARNING (error present).
  let err = sdlError()
  if err.len == 0:
    NOTIF_INFO.emit(("No pending SDL error", "", 0))
    result = ""
  else:
    win.lastError = err
    NOTIF_WARNING.emit(("SDL error on window", err, 0))
    result = err

method quitWindow*(win: SDL3Window) =
  ## Destroy the SDL3 window and release its resources.
  ## Emits NOTIF_WINDOW_EXITTED on success.
  SDL_DestroyWindow(win.handle)
  win.handle = nil
  NOTIF_WINDOW_EXITTED.emit((CWindow(win),))


method getMousePosition*(win: SDL3Window): tuple[x, y: int] =
  ## Return the cursor position in window-local pixel coordinates.
  ## SDL_GetMouseState returns coords relative to the focused window.
  ## For unfocused-window coords, read from the last MouseMotionEvent instead.
  var fx, fy: cfloat
  discard SDL_GetMouseState(addr fx, addr fy)
  (fx.int, fy.int)

include "events.nim"
