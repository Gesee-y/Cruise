####################################################################################################################################################
################################################################## CLI COMMANDS ####################################################################
####################################################################################################################################################

import macros, tables, strutils

type
  CLICommand = object
    desc:string
    help:string
    exec:proc (args:Table[string, string])

var CLIcommandRegistry = initTable[string, CLICommand]()

proc registerCLICommand(name:string, cmd:CLICommand) =
  CLIcommandRegistry[name] = cmd

macro makeCLICommand(body:untyped) =
  echo body.treeRepr
  var
    name, desc, help:string
    exec:NimNode

  for node in body:
    case node[0].strval:
      of "NAME":
        name = node[1].strval
      of "DESC":
        desc = node[1].strval
      of "HELP":
        help = node[1].strval
      of "EXEC":
        let code = node[1]
        let arg = ident"args"
        exec = quote do:
          proc (`arg`:Table[string,string]) =
            `code`

  return quote do:
    registerCLICommand(`name`, CLICommand(desc:`desc`, help:`help`, exec:`exec`))

proc parseCommand(line:string):(string,Table[string,string]) =
  doAssert line.len > 0
  var res = initTable[string, string]()
  var name = ""

  var data = line.split(" ")
  name = data[0]
  for i in 1..<data.len:
    let d = data[i]
    if d.len <= 1: continue
    if d[0] == '-':
      if d[1] == '-':
        let args = d.split(":")
        res[args[0][2..^1]] = args[1]
      else:
        res[d[1..^1]] = ""
    else:
      res[d] = ""

  return (name, res)

echo parseCommand("install -r --opt:false")
