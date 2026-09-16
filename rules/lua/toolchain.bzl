"""Lua toolchain: which interpreter runs the scripts, and where it came from.

System:   lua_toolchain(name = "lua", interpreter_path = "lua", compiler_path = "luac")
Hermetic: lua_hermetic_toolchain(name = "lua", version = "5.4.7")
          pinned source from lua.org, built once by make + cc into buck-out, cached by hash.
          Sub-targets of `<name>-build`: [lua] [luac] [liblua] [include], for hosts that embed.
"""

LuaToolchainInfo = provider(fields = {
    "interpreter": provider_field(typing.Any),   # cmd_args: artifact or program name
    "interpreter_artifact": provider_field(typing.Any, default = None),
    "interpreter_path": provider_field(str, default = ""),
    "compiler": provider_field(typing.Any, default = None),
    "compiler_artifact": provider_field(typing.Any, default = None),
    "compiler_path": provider_field(str, default = ""),
    "version": provider_field(str, default = ""),
})

def _lua_toolchain_impl(ctx):
    if ctx.attrs.interpreter != None:
        interp_art = ctx.attrs.interpreter[DefaultInfo].default_outputs[0]
        interp = cmd_args(interp_art)
    else:
        interp_art = None
        interp = cmd_args(ctx.attrs.interpreter_path)
    comp_art = None
    comp = None
    if ctx.attrs.compiler != None:
        comp_art = ctx.attrs.compiler[DefaultInfo].default_outputs[0]
        comp = cmd_args(comp_art)
    elif ctx.attrs.compiler_path:
        comp = cmd_args(ctx.attrs.compiler_path)
    return [
        DefaultInfo(),
        LuaToolchainInfo(
            interpreter = interp,
            interpreter_artifact = interp_art,
            interpreter_path = ctx.attrs.interpreter_path,
            compiler = comp,
            compiler_artifact = comp_art,
            compiler_path = ctx.attrs.compiler_path,
            version = ctx.attrs.version,
        ),
    ]

lua_toolchain = rule(
    impl = _lua_toolchain_impl,
    attrs = {
        "interpreter": attrs.option(attrs.dep(), default = None),
        "interpreter_path": attrs.string(default = "lua"),
        "compiler": attrs.option(attrs.dep(), default = None),
        "compiler_path": attrs.string(default = ""),
        "version": attrs.string(default = ""),
    },
    is_toolchain_rule = True,
)

LUA_SHA256 = {
    "5.4.7": "9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30",
}

_BUILD = """
set -eu
out="$PWD/$OUT"
cp -RL "$SRCS" "$BUCK_SCRATCH_PATH/lua"
cd "$BUCK_SCRATCH_PATH/lua"
make -s -C src all CC="${CC:-cc}" MYCFLAGS="-fPIC" >/dev/null
mkdir -p "$out/bin" "$out/lib" "$out/include"
cp src/lua src/luac "$out/bin/"
cp src/liblua.a "$out/lib/"
cp src/lua.h src/luaconf.h src/lualib.h src/lauxlib.h src/lua.hpp "$out/include/"
"""

def lua_hermetic_toolchain(name, version = "5.4.7", sha256 = None, visibility = ["PUBLIC"]):
    """Pinned Lua from lua.org, built with make and the system C compiler, cached in buck-out."""
    sha = sha256 or LUA_SHA256.get(version)
    if not sha:
        fail("lua_hermetic_toolchain: no known sha256 for Lua {}; pass sha256 =".format(version))
    native.http_archive(
        name = name + "-src",
        urls = ["https://www.lua.org/ftp/lua-{}.tar.gz".format(version)],
        sha256 = sha,
        strip_prefix = "lua-" + version,
        visibility = visibility,
    )
    native.genrule(
        name = name + "-build",
        srcs = [":" + name + "-src"],
        outs = {
            "lua": ["bin/lua"],
            "luac": ["bin/luac"],
            "liblua": ["lib/liblua.a"],
            "include": ["include"],
        },
        default_outs = ["bin/lua"],
        bash = _BUILD,
        visibility = visibility,
    )
    lua_toolchain(
        name = name,
        interpreter = ":" + name + "-build[lua]",
        compiler = ":" + name + "-build[luac]",
        version = version,
        visibility = visibility,
    )

def lua_cxx_library(name, build = "toolchains//:lua-build", visibility = ["PUBLIC"]):
    """The hermetic interpreter as a C library, for a cxx host that embeds Lua. Needs toolchains//:cxx."""
    native.prebuilt_cxx_library(
        name = name,
        static_lib = build + "[liblua]",
        header_dirs = [build + "[include]"],
        header_namespace = "",
        preferred_linkage = "static",
        exported_linker_flags = ["-lm", "-ldl"],
        visibility = visibility,
    )
