include "../../src/ecs/fragment.nim"
import unittest

type
  Test = object
    x:int
    y:float

const N = 4

SoAFragArr(N):
  var arr: Test

############################################
# TESTS
############################################

suite "SoAFragmentArray - tests complets":

  test "création de blocs":
    check newBlock(arr, 0)
    check newBlock(arr, 4)
    check arr.blocks.len == 2

  test "refus chevauchement":
    check newBlock(arr, 2) == false

  test "écriture et lecture":
    arr[0] = Test(x:1, y:1.1)
    arr[5] = Test(x:5, y:5.5)

    check arr[0].x == 1
    check arr[5].y == 5.5

  test "itération globale":
    var count = 0
    for v in arr.iter:
      discard v
      inc count
    check count == arr.blocks.len * N

  test "swap valeurs":
    arr[0] = Test(x:10, y:10)
    arr[1] = Test(x:20, y:20)
    swapVals(arr, 0, 1)
    check arr[0].x == 20
    check arr[1].x == 10