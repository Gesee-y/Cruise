#############################################################################################################################
################################################## WINDOWING ABSTRACTION ####################################################
#############################################################################################################################

include "events.nim"

type
  CWindow = ref object of RootObj
    id:int
    childrens:seq[int]
    inputs:InputState

  CApp = ref object
    windows: seq[CWindow]

include "evloop.nim"
include "inputmap.nim"

## ============================================================
##  Window lifecycle notifiers
## ============================================================

## Emitted when a window has been successfully created.
## Carries the newly created window.
notifier NOTIF_WINDOW_CREATED(win: CWindow)

## Emitted when a window has been updated (re-rendered).
notifier NOTIF_WINDOW_UPDATED(win: CWindow)

## Emitted when a window has been closed.
notifier NOTIF_WINDOW_EXITTED(win: CWindow)

## Emitted when a window has been minimized.
notifier NOTIF_WINDOW_MINIMIZED(win: CWindow)

## Emitted when a window has been maximized (fills the screen).
notifier NOTIF_WINDOW_MAXIMIZED(win: CWindow)

## Emitted when a previously minimized/maximized window is restored.
notifier NOTIF_WINDOW_RESTORED(win: CWindow)

## Emitted when a window has been hidden.
notifier NOTIF_WINDOW_HIDDEN(win: CWindow)

## Emitted when a hidden window has been made visible again.
notifier NOTIF_WINDOW_SHOWN(win: CWindow)

## Emitted when a window has been raised to the top of the window stack.
notifier NOTIF_WINDOW_RAISED(win: CWindow)

## Emitted to signal a delay/sleep tick, carrying the duration in ms.
notifier NOTIF_WINDOW_DELAYING(t: int)

## Emitted when the title of a window has changed.
## Carries the window and its new title string.
notifier NOTIF_WINDOW_TITLE_CHANGED(win: CWindow, newTitle: string)

## Emitted when a window has been moved.
## Carries the window and the new top-left position (x, y).
notifier NOTIF_WINDOW_REPOSITIONED(win: CWindow, x: int, y: int)

## Emitted when a window has been resized.
## Carries the window and the new dimensions (width, height).
notifier NOTIF_WINDOW_RESIZED(win: CWindow, width: int, height: int)

## Emitted when fullscreen mode changes on a window.
##   active            – true = entering fullscreen, false = returning to windowed.
##   desktopResolution – true = use the native screen resolution,
##                       false = keep the window's own resolution.
notifier NOTIF_WINDOW_FULLSCREEN(win: CWindow, active: bool,
                                 desktopResolution: bool)


## ============================================================
##  Diagnostic notifiers
## ============================================================

## Emitted on a severe error that prevents the program from continuing.
## Connect a handler that raises or logs the error.
##   mes   – human-readable context message.
##   error – error string or code (empty string = no extra detail).
notifier NOTIF_ERROR(mes: string, error: string)

## Emitted when a non-fatal problem is detected.
##   mes     – human-readable context message.
##   warning – warning description.
##   code    – optional numeric code (0 = none).
notifier NOTIF_WARNING(mes: string, warning: string, code: int)

## Emitted to convey informational messages (driver info, version, …).
##   mes  – human-readable context message.
##   info – information string.
##   code – optional numeric code (0 = none).
notifier NOTIF_INFO(mes: string, info: string, code: int)


## ============================================================
##  Abstract backend interface
##  Override these procs for each concrete backend (SDL, GLFW…).
## ============================================================

method initWindow*(app: CApp, win: CWindow, args: varargs[string]): CWindow {.base.} =
  ## Create and register a new window in the app.
  ## Implementations must emit NOTIF_WINDOW_CREATED on success.
  NOTIF_WINDOW_CREATED.emit((result,))

method resizeWindow*(win: CWindow, width, height: int) {.base.} =
  ## Resize the window to (width × height).
  ## Implementations must emit NOTIF_WINDOW_RESIZED on success.
  NOTIF_WINDOW_RESIZED.emit((win, width, height))

method repositionWindow*(win: CWindow, x, y: int) {.base.} =
  ## Move the window to position (x, y).
  ## Implementations must emit NOTIF_WINDOW_REPOSITIONED on success.
  NOTIF_WINDOW_REPOSITIONED.emit((win, x, y))

method setWindowTitle*(win: CWindow, newTitle: string) {.base.} =
  ## Change the window title.
  ## Implementations must emit NOTIF_WINDOW_TITLE_CHANGED on success.
  NOTIF_WINDOW_TITLE_CHANGED.emit((win, newTitle))

method maximizeWindow*(win: CWindow) {.base.} =
  ## Maximize the window to fill the screen.
  ## Implementations must emit NOTIF_WINDOW_MAXIMIZED on success.
  NOTIF_WINDOW_MAXIMIZED.emit((win,))

method minimizeWindow*(win: CWindow) {.base.} =
  ## Minimize the window to the taskbar.
  ## Implementations must emit NOTIF_WINDOW_MINIMIZED on success.
  NOTIF_WINDOW_MINIMIZED.emit((win,))

method restoreWindow*(win: CWindow) {.base.} =
  ## Restore a minimized or maximized window to its previous size.
  ## Implementations must emit NOTIF_WINDOW_RESTORED on success.
  NOTIF_WINDOW_RESTORED.emit((win,))

method hideWindow*(win: CWindow) {.base.} =
  ## Hide the window (makes it invisible without closing it).
  ## Implementations must emit NOTIF_WINDOW_HIDDEN on success.
  NOTIF_WINDOW_HIDDEN.emit((win,))

method showWindow*(win: CWindow) {.base.} =
  ## Make a hidden window visible again.
  ## Implementations must emit NOTIF_WINDOW_SHOWN on success.
  NOTIF_WINDOW_SHOWN.emit((win,))

method raiseWindow*(win: CWindow) {.base.} =
  ## Bring the window to the top of the window stack (give it focus).
  ## Implementations must emit NOTIF_WINDOW_RAISED on success.
  NOTIF_WINDOW_RAISED.emit((win,))

method setFullscreen*(win: CWindow, active: bool,
                    desktopResolution: bool = false) {.base.} =
  ## Toggle fullscreen mode.
  ##   active            – true to enter fullscreen, false to return to windowed.
  ##   desktopResolution – when true, use the native desktop resolution.
  ## Implementations must emit NOTIF_WINDOW_FULLSCREEN on success.
  NOTIF_WINDOW_FULLSCREEN.emit((win, active, desktopResolution))

method updateWindow*(win: CWindow) {.base.} =
  ## Trigger a re-render of the window contents.
  ## Implementations must emit NOTIF_WINDOW_UPDATED on success.
  NOTIF_WINDOW_UPDATED.emit((win,))

method getError*(win: CWindow): string {.base.} =
  ## Return the latest backend error string for this window.
  ## After retrieving the error, emit one of:
  ##   NOTIF_INFO    – for informational messages
  ##   NOTIF_WARNING – for non-fatal problems
  ##   NOTIF_ERROR   – for severe errors
  ""

proc getWindowID*(win: CWindow): int =
  ## Return the numeric id of the window.
  win.id

method quitWindow*(win: CWindow) {.base.} =
  ## Close the window and release its resources.
  ## Implementations must emit NOTIF_WINDOW_EXITTED on success.
  NOTIF_WINDOW_EXITTED.emit((win,))
