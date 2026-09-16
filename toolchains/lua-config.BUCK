# lua-config: the interpreter named in the root configuration — [lua] bin = /path/to/lua in .buckconfig.local (an app may write it per machine)
load("@monomono//rules/lua:toolchain.bzl", "lua_toolchain")
lua_toolchain(
    name = "lua",
    interpreter_path = read_root_config("lua", "bin", "lua"),
    compiler_path = read_root_config("lua", "luac", ""),
    version = read_root_config("lua", "version", "5.4"),
    visibility = ["PUBLIC"],
)
