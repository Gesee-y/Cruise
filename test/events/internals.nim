############################################################ TESTING THE EVENT SYSTEM INTERNALS ###################################################

# import unittest
#include "../../src/events/events.nim"

import unittest
import ../../src/events/events 

# ===========================
# TEST 1 : Macro notifier
# ===========================
test "macro notifier generate a Notifier":
  notifier myEvent(a:int, b:string)

  emit(myEvent, (1, "c"))
  check myEvent != nil
  check myEvent.listeners.len == 0
  check myEvent.state != nil

# ===========================
# TEST 2 : destructuredCall
# ===========================
proc add(a:int, b:int): int = a + b

test "destructuredCall of a funtion":
  let t = (3, 5)
  destructuredCall(r, add, t)
  check r == 8


