# luals: lua-language-server on this machine ([lua] luals = path, default on PATH), for lua_typecheck
load("@monomono//rules/lua:toolchain.bzl", "lua_tool")
lua_tool(
    name = "luals",
    path = read_root_config("lua", "luals", "lua-language-server"),
    visibility = ["PUBLIC"],
)
