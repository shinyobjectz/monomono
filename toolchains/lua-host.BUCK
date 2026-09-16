# lua-host: no interpreter; tests and binaries run through [lua] host = <program> (+ host_args), e.g. an app's sandboxed runtime. [lua] bin is optional, for bundle/meta.
load("@monomono//rules/lua:toolchain.bzl", "lua_toolchain")
lua_toolchain(
    name = "lua",
    interpreter_path = read_root_config("lua", "bin", ""),
    host = ([read_root_config("lua", "host", "")] + read_root_config("lua", "host_args", "").split(" ")) if read_root_config("lua", "host", "") else [],
    version = read_root_config("lua", "version", "5.4"),
    visibility = ["PUBLIC"],
)
