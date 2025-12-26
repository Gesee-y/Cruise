####################################################################################################################################################
################################################################### CLI WRITER #####################################################################
####################################################################################################################################################

## So we need a writer, something that write text.
## Since it's not a text writer, let's set up the DSL

type
  CLIHistory = object
    data:seq[string]
    index:int

  CLIWriter = object
    current_text:string
    active:bool
    selected:int
    history:CLIHistory


proc newCLIHistory():CLIHistory =
  return CLIHistory(data:newSeq[string](), index: -1)

proc newCLIWriter():CLIWriter =
  return CLIWriter(current_text:"", active:false, selected: -1, history:newCLIHistory())

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

proc moveCursor(cw:var CLIWriter, key:Key, current_y:int, xpos:int, pos:tuple[x:int, y:int]) =
  let tw = terminalWidth()


  case key.arrow:
    of ArrowUp:
      if current_y == 0 and (cw.history.index < cw.history.data.len):
        cw.current_text = cw.history.data[cw.history.index]
        cw.history.index -= 1
        stdout.cursorBackward(pos.x-PROMPT_NAME.len)
        stdout.write(cw.current_text)
      else:
        if cw.selected + PROMPT_NAME.len >= tw:
          stdout.cursorUp()
          cw.selected -= tw

    of ArrowDown:
      if (current_y == cw.current_text.len mod tw) and (cw.history.index < cw.history.data.len-1):
        cw.current_text = cw.history.data[cw.history.index+1]
        cw.history.index += 1
        stdout.cursorBackward(pos.x-PROMPT_NAME.len)
        stdout.write(cw.current_text)
      else:
        if current_y < cw.current_text.len mod tw:
          cw.selected += tw
          stdout.cursorDown()

    of ArrowLeft:
      if cw.selected > -1: 
        if pos.x > 0:
          cursorBackward()
        else:
          cursorUp()
          setCursorXpos(tw-1)
        cw.selected -= 1
    of ArrowRight:
      if cw.selected+1 < cw.current_text.len: 
        if pos.x < tw-1:
          cursorForward()
        else:
          cursorDown()
          setCursorXpos(0)
        cw.selected += 1

proc takeChar(cw:var CLIWriter):CLICharAction =

  let cursorPos = getCursorPos()
  var current_y = (cw.selected + PROMPT_NAME.len) mod terminalWidth()
  var xpos = (cursorPos.x + terminalWidth()*current_y) - PROMPT_NAME.len
  var key = getKey()
  var action:CLICharAction = CLINone

  #echo key

  case key.kind:
    of kkEnter:
      action = CLIReturn
      setCursorXpos(0)
      let intery = (cw.current_text.len div terminalWidth())-current_y
      if intery > 0:
        cursorDown(intery)
      cw.history.data.add(cw.current_text)
      cw.history.index += 1
      cw.selected = -1
    of kkEscape:
      action = CLIQuit
    of kkArrow:
      moveCursor(cw, key, current_y, xpos, cursorPos)
    of kkBackspace, kkChar:
      var offs = 1
      if key.kind == kkChar:
        cw.current_text.insert(""&key.value,cw.selected+1)
        cw.selected += 1
      elif cw.selected > -1:
        cw.current_text.delete(cw.selected..cw.selected)
        cw.selected -= 1
        offs = -1
      elif cw.current_text.len == 0:
        return action

      var up = (cw.selected + PROMPT_NAME.len) div terminalWidth()
      var down = ((cw.current_text.len-1 + PROMPT_NAME.len) div terminalWidth()) - up

      while up > 0:
        cursorUp()
        up -= 1

      setCursorXpos(PROMPT_NAME.len)

      stdout.write(cw.current_text)
      if key.kind == kkBackspace: stdout.write(" ")
      setCursorXpos((cursorPos.x+offs) mod terminalWidth())

      while down > 0:
        cursorUp()
        down -= 1
    else: discard

  return action

