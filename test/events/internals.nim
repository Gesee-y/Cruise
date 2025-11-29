############################################################ TESTING THE EVENT SYSTEM INTERNALS ###################################################

# import unittest
include "../../src/events/events.nim"


proc tst(x:int, y:float) =
  echo(x)
  echo(y)

#destructuredCall(tst, (1,2.0), 2)

let a = (1, 2.0)
destructuredCall(tst, a)

dumpTree:
  proc(int, int, int)
  pro(1,2)
echo tuple[x:int]
var data = notifier(my_signal(x:int, y:int, z:int))

echo data.listeners