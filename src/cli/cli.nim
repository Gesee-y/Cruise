###################################################################################################################################################
################################################################### CRUISE CLI TOOLS ##############################################################
###################################################################################################################################################

#[
So now we first need our interface to write things. So we need:
  - progress bar
  - banner
  - prompt
  - Choices
  - Full control over the rendering and colors
  - commands
  - history

Let's 
]#

import strutils, terminal, macros, tables

type
  CLICharAction = enum
    CLIQuit
    CLIReturn
    CLINone
  
  KeyKind* = enum
    kkNone, kkArrow, kkEscape, kkEnter, kkChar, kkBackspace

  ArrowKey = enum
    ArrowUp, ArrowDown, ArrowLeft, ArrowRight

  ColorScheme = object
    success:ForegroundColor
    warning:ForegroundColor
    error:ForegroundColor
    chill:ForegroundColor
    default:ForegroundColor
    weird:ForegroundColor
    note:ForegroundColor

  Key* = object
    case kind*: KeyKind
    of kkArrow: arrow: ArrowKey
    of kkChar: value*: char
    else: discard


const
  AUTHOR = "K. Elisee"
  VERSION = "v0.1.0"
  HELP1 = "Type \"help\" to get all commands"
  HELP2 = "\"?`cmd`\" for help on a command. 'esc' to quit."
  DOC = "Documention in progress"
  DATE = "20/12/2025"

when defined(windows):
  proc getRawChar(): int {.importc: "_getch", header: "<conio.h>".}
else:
  import std/termios
  proc getRawChar(): int =
    let fd = stdin.getFileHandle()
    var oldMode, newMode: Termios
    discard fd.tcGetAttr(oldMode.addr)
    newMode = oldMode
    newMode.c_lflag = newMode.c_lflag and not (ICANON or ECHO)
    discard fd.tcSetAttr(TCSANOW, newMode.addr)
    result = ord(stdin.readChar())
    discard fd.tcSetAttr(TCSANOW, oldMode.addr)

proc getKey*(): Key =
  let k = getRawChar()

  if k == 8: return Key(kind: kkBackspace)
  if k == 127: return Key(kind: kkBackspace)

  when defined(windows):
    if k == 224 or k == 0:
      case getRawChar()
      of 72: return Key(kind: kkArrow, arrow: ArrowUp)
      of 80: return Key(kind: kkArrow, arrow: ArrowDown)
      of 75: return Key(kind: kkArrow, arrow: ArrowLeft)
      of 77: return Key(kind: kkArrow, arrow: ArrowRight)
      else: return Key(kind: kkNone)
    elif k == 27: return Key(kind: kkEscape)
    elif k == 13: return Key(kind: kkEnter)
  else:
    if k == 27:
      let k2 = getRawChar() 
      if k2 == 91:
        case getRawChar()
        of 65: return Key(kind: kkArrow, arrow: ArrowUp)
        of 66: return Key(kind: kkArrow, arrow: ArrowDown)
        of 67: return Key(kind: kkArrow, arrow: ArrowRight)
        of 68: return Key(kind: kkArrow, arrow: ArrowLeft)
        else: return Key(kind: kkNone)
      return Key(kind: kkEscape)
    elif k == 10 or k == 13: return Key(kind: kkEnter)

  return Key(kind: kkChar, value: chr(k))

const
  PROMPT_NAME = "cruise> "

let default_color_scheme = ColorScheme(success:fgGreen, warning:fgYellow, 
  error:fgRed, chill:fgCyan, default:fgWhite)


const CHECK = "✓"

include "utilities.nim"
include "writer.nim"
include "commands.nim"

proc startSession() =
  printBanner()
  printPrompt()
  var writer = newCLIWriter()
  writer.active = true
  var last_action = CLINone

  while writer.active:
    if last_action == CLIReturn:
      stdout.write("\n")
      let cmd_data = parseCommand(writer.current_text)
      execCommand(cmd_data)
      stdout.write("\n")
      setCursorXPos(0)
      eraseLine()
      printPrompt()
      writer.current_text = ""
    elif last_action == CLIQuit:
      writer.active = false
    last_action = takeChar(writer)

startSession()
