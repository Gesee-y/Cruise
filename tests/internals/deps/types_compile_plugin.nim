import plugins
import std/assertions

include ../../../src/CVM/deps/types

proc verifyTypeCache() =
  let cache = newTypeCache()
  assert cache.instances.len == 16, "the primitive type cache must have a stable base set"
  assert cache.getType("int").kind == PrimitiveType, "int must be available"
  assert cache.getType("float32").kind == PrimitiveType, "float32 must be available"
  assert cache.getType("missing").kind == UnknownType, "unknown names must not resolve"

verifyTypeCache()

proc emptyOutput(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)

var inp = loadPluginInput()
saveTree emptyOutput(inp)
