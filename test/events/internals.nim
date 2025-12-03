############################################################ TESTING THE EVENT SYSTEM INTERNALS ###################################################

# import unittest
#include "../../src/events/events.nim"

import unittest
import ../../src/events/events 
import macros

var added = 0

dumpTree:
  proc (x:int, y:int) =
    discard

proc adds(a:int, b:int) =
  added = a + b

proc addz(a:int, b:int):int =
  return a + b

# ===========================
# TEST 1 : Macro notifier
# ===========================
test "macro notifier generate a Notifier":
  notifier myEvent(a:int, b:int)

  map2(myEvent, addz, float)
  echo notif
  myEvent.connect(adds)
  check myEvent != nil
  check myEvent.listeners.len == 1
  check myEvent.state != nil

  myEvent.emit((1,3))
  check added == 4

# ===========================
# TEST 2 : destructuredCall
# ===========================

test "destructuredCall of a funtion":
  let t = (3, 5)
  destructuredCall(adds, t)
  check added == 8


