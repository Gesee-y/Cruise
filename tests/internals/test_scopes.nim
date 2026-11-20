template verifyScopeInternals() = {.plugin: "deps/scopes_compile_plugin.nim".}

# The assertions execute inside the plugin, where the NIF API is available.
verifyScopeInternals()
