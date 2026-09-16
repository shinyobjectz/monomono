# lua-system: whatever `lua` and `luac` are on PATH (use when a host already pins its interpreter)
load("@monomono//rules/lua:toolchain.bzl", "lua_toolchain")
lua_toolchain(
    name = "lua",
    interpreter_path = "lua",
    compiler_path = "luac",
    version = "system",
)
