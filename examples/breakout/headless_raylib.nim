type
  KeyboardKey* = distinct int32
  RaylibContext* = object

const
  KEY_A* = KeyboardKey(65)
  KEY_D* = KeyboardKey(68)
  KEY_ESCAPE* = KeyboardKey(256)
  KEY_RIGHT* = KeyboardKey(262)
  KEY_LEFT* = KeyboardKey(263)

proc pollInput*() = discard
proc windowShouldClose*(): bool = false
proc keyDown*(key: KeyboardKey): bool = false
proc keyPressed*(key: KeyboardKey): bool = false
proc clearBackground*(color: array[4, uint8]) = discard
proc drawRectangle*(x, y, width, height: int32; color: array[4, uint8]) = discard
