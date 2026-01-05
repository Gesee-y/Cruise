import unittest
import bitops
include "../../src/ecs/table.nim"

############################################
# TYPES & CONSTANTES
############################################

const
  L = MAX_COMPONENT_LAYER
  BITS = sizeof(uint) * 8

############################################
# HELPERS
############################################

proc zeroMask(): ArchetypeMask =
  var m: ArchetypeMask
  for i in 0..<L: m[i] = 0
  m

############################################
# TESTS
############################################

suite "ArchetypeMask – tests complets":

  test "and binaire":
    var a = zeroMask()
    var b = zeroMask()
    a[0] = 0b1011
    b[0] = 0b1101

    let c = a and b
    check c[0] == 0b1001

  test "or binaire":
    var a = zeroMask()
    var b = zeroMask()
    a[1] = 0b0011
    b[1] = 0b0101

    let c = a or b
    check c[1] == 0b0111

  test "xor binaire":
    var a = zeroMask()
    var b = zeroMask()
    a[2] = 0b1111
    b[2] = 0b0101

    let c = a xor b
    check c[2] == 0b1010

  test "not binaire":
    var a = zeroMask()
    a[0] = 0b1010

    let c = not a
    check c[0] == (not 0b1010).uint

  test "setBit explicite (i,j)":
    var a = zeroMask()
    a.setBit(0, 3)
    a.setBit(0, 5)

    check ((a[0] shr 3) and 1) == 1
    check ((a[0] shr 5) and 1) == 1

  test "setBit lineaire":
    var a = zeroMask()
    a.setBit(0)
    a.setBit(1)
    a.setBit(BITS + 2)

    check a.getBit(0) == 1
    check a.getBit(1) == 1
    check a.getBit(BITS + 2) == 1

  test "getBit retourne 0 si non set":
    var a = zeroMask()
    check a.getBit(10) == 0

  test "setBit ne pollue pas les autres couches":
    var a = zeroMask()
    a.setBit(BITS + 1)

    check a[0] == 0
    check a[1] != 0

  test "operations independantes par layer":
    var a = zeroMask()
    var b = zeroMask()

    a[0] = 0b1111
    b[1] = 0b1111

    let c = a or b
    check c[0] == 0b1111
    check c[1] == 0b1111

  test "roundtrip set/get sur toute la plage":
    var a = zeroMask()
    let maxBits = L * BITS

    for i in 0..<maxBits:
      a.setBit(i)
      check a.getBit(i) == 1
