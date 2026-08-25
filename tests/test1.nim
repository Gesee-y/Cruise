# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import std/syncio

proc main =
  var (a, b, c, d, e) = (1, 2, 3, 4, 5)
  var f = (a + b) * c * d - e 

  echo f

main()