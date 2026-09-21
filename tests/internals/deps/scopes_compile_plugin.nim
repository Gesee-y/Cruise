import plugins
import std/[assertions, syncio]

include ../../../src/CVM/deps/types
include ../../../src/CVM/deps/scopes

proc verifyTriePaths() =
  var trie = newTrie()
  let root = trie.addNode("position")
  let field = trie.addNode(@["position", "x"])

  assert root == trie.fetchNode("position"), "a root variable must be found"
  assert field == trie.fetchNode(@["position", "x"]), "a field path must be found"
  assert trie.fetchNode(@["position", "y"]) == -1, "an unknown sibling must not resolve"

verifyTriePaths()

proc emptyOutput(n: var NifCursor): NifBuilder =
  result = createTree()
  result.takeTree(n)
  echo renderTree(result)

var inp = loadPluginInput()
saveTree emptyOutput(inp)
