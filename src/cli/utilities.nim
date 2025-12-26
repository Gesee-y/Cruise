####################################################################################################################################################
################################################################### UTILITIES FUNCTIONS ############################################################
####################################################################################################################################################

proc menuMCQ(data:openArray[string]):int =
  if data.len < 1 : return -1

  var current = 0
  let selected = false
  hideCursor()

  while true:
    let offs = 10
    for i in 0..<data.len:
      let l = data[i].len
      stdout.write($(i+1) & ". " & data[i])

      if i == current:
        stdout.write(CHECK.align(l+offs))
      else:
        stdout.write("    ".align(l+offs))

      stdout.write("\n")

    let key = getKey()

    case key.kind:
      of kkEnter:
        showCursor()

        return current
      of kkArrow:
        case key.arrow:
          of ArrowUp:
            current = (current-1) mod data.len
          of ArrowDown:
            current = (current+1) mod data.len
          else: discard
      else: discard

    for i in 0..<data.len:
      cursorUp()

    setCursorXPos(0) 

proc progressBar(status:int) =
  stdout.styledWriteLine(fgRed, "0% ", fgWhite, '='.repeat i-1, '>', "|".align(100-i), if i > 50: fgGreen else: fgYellow, "\t", $i , "%")
