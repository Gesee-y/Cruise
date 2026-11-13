# ################################################################################################################################################################## #
# ##################################################################### BYTECODE BACKEND ########################################################################### #
# ################################################################################################################################################################## #

import std/[os, syncio]

template translateToBytecode*() = {.plugin: "deps/bytecode_plugin.nim".}
func setShaderName*(str: static[string]) = discard
func setShaderType*[T](base: typedesc[T], ty: static[string]) {.untyped.} = discard

  # ###################################################################################################### #
 # ############################################# DEFAULT TYPES ########################################## #
# ###################################################################################################### #

template uniform*(val: static[string]) {.pragma.}
template ssbo*() {.pragma.}
template globalIndex*() {.pragma.}
template fragmentOutput*() {.pragma.}
template vertexOutput*() {.pragma.}
template vertexVarying*() {.pragma.}
template vertexInput*() {.pragma.}
template fragmentInput*() {.pragma.}


proc readBytecode*(path: string, maxBytecodeWord=256): seq[uint32] =
  result = @[]
  if not fileExists(path):
    return
  var file = open(path, fmRead)
  defer: file.close()
  var word = 0'u32
  while file.readBuffer(addr word, sizeof(word)) == sizeof(word):
    result.add word
