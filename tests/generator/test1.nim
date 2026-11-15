# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.
import std/os
import ../../src/CVM/disassembler

proc main =
  var f = open(currentSourcePath.parentDir / ".." / "shaders" / "deps" / "light_cube_vert.cbc", fmRead)
  var data: seq[uint32] = @[]
  var word: uint32
  while f.readBuffer(addr word, sizeof(uint32)) == sizeof(uint32):
    data.add(word)
  close(f)

  disassemble(data)



main()
