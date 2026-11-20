template verifyTypeInternals() = {.plugin: "deps/types_compile_plugin.nim".}

# The assertions execute inside the plugin, where the NIF API is available.
verifyTypeInternals()
