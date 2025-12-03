############################################################ TESTING THE EVENT SYSTEM INTERNALS ###################################################

# import unittest
#include "../../src/events/events.nim"

import unittest
import asyncdispatch
import threadpool
import ../../src/events/events 
import macros
import times
import os

var added = 0

proc adds(a:int, b:int, c=(a,b)) =
  added = a + b

# ===========================
# TEST 1 : Macro notifier
# ===========================
test "macro notifier generate a Notifier":
  notifier myEvent(a:int, b:int)

  check myEvent != nil
  check myEvent.listeners.len == 0
  check myEvent.state != nil

# ===========================
# TEST 2 : destructuredCall
# ===========================

test "destructuredCall of a funtion":
  let t = (3, 5)
  destructuredCall(adds, t)
  check added == 8
