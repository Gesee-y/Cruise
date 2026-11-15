{.feature: "assumeSync".}

import std/syncio
import ../../src/CVM/bytecode

type Vec2 = object
  x, y: float32

proc `+`(a, b: Vec2): Vec2 = a
proc `*`(a: Vec2, b: float32): Vec2 = a
proc `+=`(a: var Vec2, b: Vec2) = discard
proc `-=`(a: var Vec2, b: Vec2) = discard
proc `*=`(a: var Vec2, b: float32) = discard
proc `/=`(a: var Vec2, b: float32) = discard

translateToBytecode()
setShaderName("test_inplace_ops")
setShaderType(Vec2, "vec2f")

var length {.uniform.}: int = 0

proc main(gid {.globalIndex.}: int,
          input {.ssbo.}: seq[float32], output {.ssbo.}: var seq[float32],
          vecInput {.ssbo.}: seq[Vec2], vecOutput {.ssbo.}: var seq[Vec2],
          intInput {.ssbo.}: seq[int32], intOutput {.ssbo.}: var seq[int32]) =
  if gid < length:
    var scalar = input[gid]
    scalar += 4.0'f32
    scalar *= 2.0'f32
    scalar -= 3.0'f32
    scalar /= 5.0'f32
    output[gid] = input[gid]
    output[gid] += scalar

    var vector = vecInput[gid]
    var otherVector = vecInput[gid]
    vector += otherVector
    vector *= 2.0'f32
    vector -= otherVector
    vector /= 2.0'f32
    vecOutput[gid] = vector
    vecOutput[gid] += vector

    var integer = intInput[gid]
    integer += 4
    integer *= 2
    integer -= 3
    intOutput[gid] = integer
