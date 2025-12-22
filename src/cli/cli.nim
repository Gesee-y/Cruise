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

import parseopt, os, strutils, terminal, typetraits, posix, selectors

const
  AUTHOR = "K. Elisee"
  VERSION = "v0.1.0"
  HELP1 = "Type \"help\" to get all commands"
  HELP2 = "\"?`cmd`\" for help on a command. 'esc' to quit."
  DOC = "Documention in progress"
  DATE = "20/12/2025"

include "writer.nim"

startSession()
