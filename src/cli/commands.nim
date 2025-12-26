####################################################################################################################################################
################################################################## CLI COMMANDS ####################################################################
####################################################################################################################################################

type
  CLICommand = object
    desc:string
    help:string
    exec:proc (args:Table[string, string])

var CLICOMMANDREGISTRY = initTable[string, CLICommand]()

proc registerCLICommand(name:string, cmd:CLICommand) =
  CLICOMMANDREGISTRY[name] = cmd

macro makeCLICommand(body:untyped) =
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
        exec = quote("@") do:
          proc (`@arg`:Table[string,string]) =
            `@code`
      else: continue

  return quote do:
    registerCLICommand(`name`, CLICommand(desc:`desc`, help:`help`, exec:`exec`))

proc parseCommand(line:string):(string,Table[string,string]) =
  var res = initTable[string, string]()
  var name = ""

  if  line.len < 1: return (name, res)

  var data = line.split(" ")
  name = data[0]
  for i in 1..<data.len:
    let d = data[i]
    if d.len < 1: continue
    if d[0] == '-':
      if d[1] == '-':
        let args = d.split(":")
        res[args[0][2..^1]] = args[1]
      else:
        res[d[1..^1]] = ""
    else:
      res[d] = ""

  return (name, res)

proc execCommand(data:(string, Table[string, string])) =
  if not CLICOMMANDREGISTRY.hasKey(data[0]):
    stdout.write("Command `" & data[0] & "` not found.\nTry `?` to get available commands.\n")
    return

  let cmd = CLICOMMANDREGISTRY[data[0]]
  cmd.exec(data[1])

makeCLICommand:
  NAME = "?"
  DESC = "Get information about the available commands."
  HELP = "Get informations about the available commands"
  EXEC =
    for key, cmd in CLICOMMANDREGISTRY:
      stdout.write(key, " : ", cmd.desc, "\n")
    
makeCLICommand:
  NAME = "help"
  DESC = "Get help about some given commands."
  HELP = "Enter `help <cmd>` to get help about that command."
  EXEC =
    for arg in args.keys:
      if not CLICOMMANDREGISTRY.hasKey(arg):
        stdout.write("Command `" & arg & "` not found.\nTry `?` to get available commands.\n")
        continue

      let cmd = CLICOMMANDREGISTRY[arg]
      stdout.write(arg & " : " & cmd.desc & "\n")
    