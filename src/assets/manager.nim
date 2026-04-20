##########################################################################################################################################################
################################################################# ASSETS MANAGER #########################################################################
##########################################################################################################################################################

type
  CBaseAsset = ref object of RootObj
    id: int
    timestamp: int
    meta: seq[string]

  CAssetManager = ref object
    resources: Table[string, CBaseAsset]

template loadAsset[T](man: CAssetManager, path:string) = 
  if path notin man.resources or man.resources[path]:
    man.resources[T]