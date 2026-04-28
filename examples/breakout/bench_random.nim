import std/math

proc quantizeCoord(value: float32): uint32 =
  cast[uint32](int32(round(value * 1024'f32)))

proc mixSeed*(parts: openArray[uint32]): uint32 =
  var hash = 2166136261'u32
  for part in parts:
    hash = (hash xor part) * 16777619'u32
  hash = (hash xor (hash shr 16)) * 2246822519'u32
  hash = (hash xor (hash shr 13)) * 3266489917'u32
  hash xor (hash shr 16)

proc sampleUnit*(parts: openArray[uint32]): float32 =
  let value = mixSeed(parts) and 0x00ff_ffff'u32
  value.float32 / 16777216.0'f32

proc eventSeed*(tag: uint32; tick: int; x, y: float32): uint32 =
  mixSeed([tag, tick.uint32, quantizeCoord(x), quantizeCoord(y)])

proc angleFromSeed*(seed: uint32): float32 =
  PI.float32 + sampleUnit([seed, 0xA341316Cu32]) * PI.float32

proc chanceFromSeed*(seed: uint32): float32 =
  sampleUnit([seed, 0xC8013EA4'u32])

proc shakeOffsetFromTick*(tick, axis: int; strength: float32): float32 =
  strength - sampleUnit([0x9E3779B9'u32, tick.uint32, axis.uint32]) * (strength * 2)

proc shakeColorFromTick*(tick, channel: int): uint8 =
  uint8(int(sampleUnit([0x85EBCA6B'u32, tick.uint32, channel.uint32]) * 255'f32))
