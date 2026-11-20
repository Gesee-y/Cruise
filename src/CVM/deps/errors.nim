{.feature: "assumeSync".}

# ###################################################################################################### #
# ############################################# ERRORS HANDLING ######################################## #
# ###################################################################################################### #

type
  CError = object
    info: LineInfo
    msg: string

var irGenErrors: seq[CError] = @[]
var semErrors: seq[CError] = @[] 

proc reportIRError*(info: LineInfo, msg: string) =
  irGenErrors.add(CError(info: info, msg: msg))

proc reportSemError*(info: LineInfo, msg: string) =
  semErrors.add(CError(info: info, msg: msg))

proc flushIRErrors*(n: var NifBuilder) =
  for e in irGenErrors:
    n.addTree errorTree(e.msg, e.info)

proc flushSemErrors*(n: var NifBuilder) =
  for e in semErrors:
    n.addTree errorTree(e.msg, e.info)