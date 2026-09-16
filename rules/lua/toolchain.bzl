"""Lua toolchains: which interpreter runs the scripts, and where it came from.

System:   lua_toolchain(name = "lua", interpreter_path = "lua", compiler_path = "luac")
Hermetic: lua_hermetic_toolchain(name = "lua", version = "5.4.7")      # 5.1.5, 5.3.6, 5.4.7 have pinned hashes
LuaJIT:   luajit_hermetic_toolchain(name = "lua")                      # pinned v2.1 commit
Both hermetic forms build once from source with make + cc into buck-out, cached by hash.
Sub-targets of `<name>-build`: [lua] [luac] [liblua] [include], for hosts that embed.

Tools:    luacheck_toolchain(name = "luacheck")    pure-Lua linter, pinned source, runs under the interpreter
          stylua_toolchain(name = "stylua")        prebuilt formatter, pinned per platform
"""

LuaToolchainInfo = provider(fields = {
    "interpreter": provider_field(typing.Any),
    "interpreter_artifact": provider_field(typing.Any, default = None),
    "interpreter_path": provider_field(str, default = ""),
    "compiler": provider_field(typing.Any, default = None),
    "compiler_artifact": provider_field(typing.Any, default = None),
    "compiler_path": provider_field(str, default = ""),
    "version": provider_field(str, default = ""),
    "flavor": provider_field(str, default = "lua"),   # lua | luajit
    "dialect": provider_field(str, default = "5.4"),  # 5.1 | 5.3 | 5.4 | jit
    "host": provider_field(list, default = []),        # a host command that runs a module (lua-host); no interpreter
    "modules": provider_field(typing.Any, default = None),  # a dir put on LUA_PATH for the interpreter itself (LuaJIT: jit/*.lua for -b)
})

LuaToolInfo = provider(fields = {
    "run": provider_field(typing.Any),        # cmd_args that runs the tool
    "inputs": provider_field(list, default = []),
})

def _dialect_of(version, flavor):
    if flavor == "luajit":
        return "jit"
    if version.startswith("5.1"):
        return "5.1"
    if version.startswith("5.2") or version.startswith("5.3"):
        return "5.3"
    return "5.4"

def _lua_toolchain_impl(ctx):
    if ctx.attrs.interpreter != None:
        interp_art = ctx.attrs.interpreter[DefaultInfo].default_outputs[0]
        interp = cmd_args(interp_art)
    elif ctx.attrs.interpreter_path:
        interp_art = None
        interp = cmd_args(ctx.attrs.interpreter_path)
    else:
        interp_art = None
        interp = None
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
            flavor = ctx.attrs.flavor,
            dialect = ctx.attrs.dialect or _dialect_of(ctx.attrs.version, ctx.attrs.flavor),
            host = ctx.attrs.host,
            modules = ctx.attrs.modules[DefaultInfo].default_outputs[0] if ctx.attrs.modules != None else None,
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
        "flavor": attrs.enum(["lua", "luajit"], default = "lua"),
        "dialect": attrs.option(attrs.string(), default = None),
        "host": attrs.list(attrs.string(), default = [], doc = "command that runs a module: <host> <main> -- args (lua-host)"),
        "modules": attrs.option(attrs.dep(), default = None, doc = "dir of Lua modules the interpreter itself needs on LUA_PATH (LuaJIT: jit/*.lua)"),
    },
    is_toolchain_rule = True,
)

def _lua_tool_impl(ctx):
    return [DefaultInfo(), LuaToolInfo(run = cmd_args(ctx.attrs.path), inputs = [])]

# A tool on this machine, named by configuration (read_config in the fragment): lua-language-server and the like.
lua_tool = rule(impl = _lua_tool_impl, attrs = {"path": attrs.string()}, is_toolchain_rule = True)

LUA_SHA256 = {
    "5.1.5": "2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333",
    "5.3.6": "fc5fd69bb8736323f026672b1b7235da613d7177e72558893a0bdcd320466d60",
    "5.4.7": "9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30",
}

LUAJIT_COMMIT = "c6ffc141a8762b41703f9287d63d93622a13dd8f"
LUAJIT_SHA256 = "6e5fec07750add912e7c3eae0c194d24cd6d023714e1f04a0298a5b4819e4457"

_BUILD = """
set -eu
out="$PWD/$OUT"
cp -RL "$SRCS" "$BUCK_SCRATCH_PATH/lua"
cd "$BUCK_SCRATCH_PATH/lua"
# POSIX + dlopen on every platform. LUA_USE_MACOSX would add readline on 5.3, which is not hermetic.
sys="-DLUA_USE_POSIX -DLUA_USE_DLOPEN"
case `uname -s` in Darwin) libs=""; ldflags="" ;; *) libs="-ldl"; ldflags="-Wl,-E" ;; esac   # -Wl,-E exports the API so C modules on LUA_CPATH resolve it
make -s -C src all CC="${CC:-cc}" MYCFLAGS="-fPIC $sys" MYLIBS="$libs" MYLDFLAGS="$ldflags" >/dev/null
mkdir -p "$out/bin" "$out/lib" "$out/include"
cp src/lua src/luac "$out/bin/"
cp src/liblua.a "$out/lib/"
cp src/lua.h src/luaconf.h src/lualib.h src/lauxlib.h "$out/include/"
cp src/lua.hpp "$out/include/" 2>/dev/null || cp etc/lua.hpp "$out/include/"
"""

_BUILD_JIT = """
set -eu
out="$PWD/$OUT"
cp -RL "$SRCS" "$BUCK_SCRATCH_PATH/luajit"
cd "$BUCK_SCRATCH_PATH/luajit"
case `uname -s` in Darwin) export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}" ;; esac
make -s -C src CC="${CC:-cc}" BUILDMODE=static >/dev/null
mkdir -p "$out/bin" "$out/lib" "$out/include"
cp src/luajit "$out/bin/lua"
cp src/libluajit.a "$out/lib/liblua.a"
cp src/lua.h src/luaconf.h src/lualib.h src/lauxlib.h src/luajit.h src/lua.hpp "$out/include/"
mkdir -p "$out/share/jit" && cp src/jit/*.lua "$out/share/jit/"
"""

def _build(name, src, bash, with_luac, visibility):
    outs = {
        "lua": ["bin/lua"],
        "liblua": ["lib/liblua.a"],
        "include": ["include"],
    }
    if with_luac:
        outs["luac"] = ["bin/luac"]
    else:
        outs["share"] = ["share"]
    native.genrule(
        name = name + "-build",
        srcs = [src],
        outs = outs,
        default_outs = ["bin/lua"],
        bash = bash,
        visibility = visibility,
    )

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
    _build(name, ":" + name + "-src", _BUILD, True, visibility)
    lua_toolchain(
        name = name,
        interpreter = ":" + name + "-build[lua]",
        compiler = ":" + name + "-build[luac]",
        version = version,
        flavor = "lua",
        visibility = visibility,
    )

def luajit_hermetic_toolchain(name, commit = LUAJIT_COMMIT, sha256 = LUAJIT_SHA256, visibility = ["PUBLIC"]):
    """Pinned LuaJIT v2.1 from GitHub, built with make and the system C compiler, cached in buck-out."""
    native.http_archive(
        name = name + "-src",
        urls = ["https://github.com/LuaJIT/LuaJIT/archive/{}.tar.gz".format(commit)],
        sha256 = sha256,
        strip_prefix = "LuaJIT-" + commit,
        visibility = visibility,
    )
    _build(name, ":" + name + "-src", _BUILD_JIT, False, visibility)
    lua_toolchain(
        name = name,
        interpreter = ":" + name + "-build[lua]",
        modules = ":" + name + "-build[share]",
        version = "jit-2.1",
        flavor = "luajit",
        visibility = visibility,
    )

def lua_cxx_library(name, build = "toolchains//:lua-build", visibility = ["PUBLIC"]):
    """The hermetic interpreter as a C library, for a cxx or rust host that embeds Lua. Needs toolchains//:cxx."""
    native.prebuilt_cxx_library(
        name = name,
        static_lib = build + "[liblua]",
        header_dirs = [build + "[include]"],
        header_namespace = "",
        preferred_linkage = "static",
        exported_linker_flags = ["-lm", "-ldl"],
        visibility = visibility,
    )

# --- tools -------------------------------------------------------------------

LUACHECK_VERSION = "1.2.0"
LUACHECK_SHA256 = "8efe62a7da4fdb32c0c22ec1f7c9306cbc397d7d40493c29988221a059636e25"
ARGPARSE_VERSION = "0.7.1"
ARGPARSE_SHA256 = "d344e49404c3e7b3e7fa4fe6741c106f25909d9b24923cb08dcceda1f9754809"

def _luacheck_toolchain_impl(ctx):
    tc = ctx.attrs.lua[LuaToolchainInfo]
    src = ctx.attrs.src[DefaultInfo].default_outputs[0]
    argparse = ctx.attrs.argparse[DefaultInfo].default_outputs[0]
    # luacheck is pure Lua: run its entry script under the toolchain interpreter with its src (and argparse) on the path
    run = cmd_args(
        "env",
        cmd_args("LUA_PATH=", cmd_args(src, format = "{}/src/?.lua;{}/src/?/init.lua;"), cmd_args(argparse, format = "{}/src/?.lua;"), cmd_args(ctx.attrs.shim, format = "{}/?.lua;;"), delimiter = ""),
        tc.interpreter,
        cmd_args(src, format = "{}/bin/luacheck.lua"),
    )
    inputs = [src, argparse, ctx.attrs.shim] + ([tc.interpreter_artifact] if tc.interpreter_artifact != None else [])
    return [DefaultInfo(), LuaToolInfo(run = run, inputs = inputs)]

_luacheck_toolchain = rule(
    impl = _luacheck_toolchain_impl,
    attrs = {
        "src": attrs.dep(),
        "argparse": attrs.dep(),
        "shim": attrs.source(allow_directory = True, default = "monomono//rules/lua:shim"),
        "lua": attrs.toolchain_dep(default = "toolchains//:lua", providers = [LuaToolchainInfo]),
    },
    is_toolchain_rule = True,
)

def luacheck_toolchain(name, version = LUACHECK_VERSION, sha256 = LUACHECK_SHA256, visibility = ["PUBLIC"]):
    native.http_archive(
        name = name + "-src",
        urls = ["https://github.com/lunarmodules/luacheck/archive/refs/tags/v{}.tar.gz".format(version)],
        sha256 = sha256,
        strip_prefix = "luacheck-" + version,
        visibility = visibility,
    )
    native.http_archive(
        name = name + "-argparse",
        urls = ["https://github.com/luarocks/argparse/archive/refs/tags/{}.tar.gz".format(ARGPARSE_VERSION)],
        sha256 = ARGPARSE_SHA256,
        strip_prefix = "argparse-" + ARGPARSE_VERSION,
        visibility = visibility,
    )
    _luacheck_toolchain(name = name, src = ":" + name + "-src", argparse = ":" + name + "-argparse", visibility = visibility)

STYLUA_VERSION = "v2.5.2"
STYLUA_SHA256 = {
    "macos-aarch64": "92ff0889e16324801bc072692974bb67f8161e62010fc90f96c62a17f81f32c7",
    "macos-x86_64": "53c50a1605d0a6345d160a1a5a21db40cf2bf9cd23c17f7c277a63a1bff3a7f",
    "linux-x86_64": "bcb0d855e91f102f28a370e850f8566b3b44b79e6274d806ea5246837c0fd5ab",
    "linux-aarch64": "0ef2ebf0b7e5a652b65c4cb96c6d9ffb3981a98547de3c764465bbf54a8d761a",
}

def _stylua_toolchain_impl(ctx):
    bin = ctx.attrs.archive[DefaultInfo].default_outputs[0]
    run = cmd_args(cmd_args(bin, format = "{}/stylua"))
    return [DefaultInfo(), LuaToolInfo(run = run, inputs = [bin])]

_stylua_toolchain = rule(
    impl = _stylua_toolchain_impl,
    attrs = {"archive": attrs.dep()},
    is_toolchain_rule = True,
)

def stylua_toolchain(name, version = STYLUA_VERSION, visibility = ["PUBLIC"]):
    """Prebuilt stylua for the host platform, pinned per platform."""
    for plat, sha in STYLUA_SHA256.items():
        native.http_archive(
            name = "{}-{}".format(name, plat),
            urls = ["https://github.com/JohnnyMorganz/StyLua/releases/download/{}/stylua-{}.zip".format(version, plat)],
            sha256 = sha,
            visibility = visibility,
        )
    archive = select({
        "DEFAULT": ":{}-linux-x86_64".format(name),
        "prelude//os/constraints:macos": select({
            "DEFAULT": ":{}-macos-x86_64".format(name),
            "prelude//cpu/constraints:arm64": ":{}-macos-aarch64".format(name),
        }),
        "prelude//os/constraints:linux": select({
            "DEFAULT": ":{}-linux-x86_64".format(name),
            "prelude//cpu/constraints:arm64": ":{}-linux-aarch64".format(name),
        }),
    })
    _stylua_toolchain(name = name, archive = archive, visibility = visibility)
