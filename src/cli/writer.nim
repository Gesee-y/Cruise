####################################################################################################################################################
################################################################### CLI WRITER #####################################################################
####################################################################################################################################################

## So we need a writer, something that write text.
## Since it's not a text writer, let's set up the DSL

import terminal, posix

type
  CLICharAction = enum
    CLIQuit
    CLIReturn
    CLINone

  ColorScheme = object
    success:ForegroundColor
    warning:ForegroundColor
    error:ForegroundColor
    chill:ForegroundColor
    default:ForegroundColor
    weird:ForegroundColor
    note:ForegroundColor

  CLIWriter = object
    current_text:string
    active:bool

  KeyKind* = enum
    kkNone, kkArrow, kkEscape, kkEnter, kkChar, kkBackspace

  ArrowKey = enum
    ArrowUp, ArrowDown, ArrowLeft, ArrowRight

  Key* = object
    case kind*: KeyKind
    of kkArrow: arrow: ArrowKey
    of kkChar: value*: char
    else: discard

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

proc printBanner(n:int=0, m:int=0, u:int=0) =
  let offset = " ".repeat(n)
  let nim_offset = " ".repeat(m)
  let up_offset = "\n".repeat(u)

  echo up_offset
  styledEcho styleBright, offset, fgBlack,"_____",fgCyan,"/\\\\\\\\\\\\\\\\\\\\",fgBlack,"_____",fgYellow,"/\\\\\\\\\\\\\\\\\\\\",fgBlack,"_____", fgWhite, "                            | "    
  styledEcho styleBright, offset, fgBlack," __",fgCyan,"/\\\\\\\\////////",fgBlack,"____",fgYellow,"/\\\\\\///////\\\\\\",fgBlack,"___", nim_offset, fgWhite, "                            | Authored by " & AUTHOR       
  styledEcho styleBright, offset, fgBlack,"  ",fgCyan,"/\\\\\\\\/",fgBlack,"____________",fgYellow,"\\/\\\\\\",fgBlack,"_____",fgYellow,"\\/\\\\\\",fgBlack,"___", nim_offset, fgWhite,"                           |"      
  styledEcho styleBright, offset, fgBlack,"  ",fgCyan,"/\\\\\\\\",fgBlack,"______________",fgYellow,"\\/\\\\\\\\\\\\\\\\\\\\\\/",fgBlack,"____", nim_offset,fgWhite, "                          | " & HELP1
  styledEcho styleBright, offset, fgBlack,"  ",fgCyan,"\\/\\\\\\\\",fgBlack,"______________",fgYellow,"\\/\\\\\\\\//////\\\\\\",fgBlack,"____",fgWhite, "                        | " & HELP2
  styledEcho styleBright, offset, fgBlack,"   ",fgCyan,"\\//\\\\\\\\",fgBlack,"_____________",fgYellow,"\\/\\\\\\",fgBlack,"____",fgYellow,"\\//\\\\\\",fgBlack,"___   ", nim_offset, fgYellow,".-. .-..-..-.   .-.", fgWhite, "  | " 
  styledEcho styleBright, offset, fgBlack,"     ",fgCyan,"\\///\\\\\\\\",fgBlack,"___________",fgYellow,"\\/\\\\\\",fgBlack,"_____",fgYellow,"\\//\\\\\\",fgBlack,"__  ", nim_offset, fgYellow,"|  `| || ||  `.'  |", fgWhite, "  | " & VERSION & " (" & DATE & ")"
  styledEcho styleBright, offset, fgBlack,"       _",fgCyan,"\\////\\\\\\\\\\\\\\\\\\",fgBlack,"___",fgYellow,"\\/\\\\\\",fgBlack,"______",fgYellow,"\\//\\\\\\",fgBlack,"_ ", nim_offset, fgYellow,"| |\\  || || |\\ /| |", fgWhite, "  | "
  styledEcho styleBright, offset, fgBlack,"        ____",fgCyan,"\\/////////",fgBlack,"____",fgYellow,"\\///",fgBlack,"________",fgYellow,"\\///",fgBlack,"__", nim_offset, fgYellow,"`-' `-'`-'`-' ` `-'", fgWhite, "  | " & DOC
  styledEcho resetStyle

proc printPrompt(name:string="cruise", sym:string=">") =
  styledWrite stdout, styleBright, fgCyan, name&sym&" "

proc takeChar(cw:var CLIWriter):CLICharAction =

  let pos = getCursorPos().x - PROMPT_NAME.len
  var key = getKey()
  var action:CLICharAction = CLINone

  #echo key

  case key.kind:
    of kkEnter:
      action = CLIReturn
    of kkEscape:
      action = CLIQuit
    of kkArrow:
      case key.arrow:
        of ArrowUp:
          discard
        of ArrowDown:
          discard
        of ArrowLeft:
          if pos > 0: cursorBackward()
        of ArrowRight:
          if pos < cw.current_text.len: cursorForward()
    of kkChar:
      cw.current_text.insert(""&key.value,pos)
      stdout.cursorBackward(pos)
      stdout.write(cw.current_text)
    else: discard

  return action

proc startSession() =
  printBanner()
  var writer = CLIWriter(current_text:"", active:true)
  var last_action = CLIReturn

  while writer.active:
    if last_action == CLIReturn:
      stdout.write('\n')
      printPrompt()
      writer.current_text = ""
    elif last_action == CLIQuit:
      writer.active = false
    last_action = takeChar(writer)
