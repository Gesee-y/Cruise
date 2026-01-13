###################################################################################################################################################
################################################################ DATA LAYOUT ######################################################################
###################################################################################################################################################

type
  DataLayout = ref object of PluginNode
  DataChange = object of RootObj

method getChanges(dl:DataLayout):DataChange {.base.} =
  var c:DataChange
  return c

method getAdded(dl:DataLayout) {.base.} = discard
method getRemoved(dl:DataLayout) {.base.} = discard

