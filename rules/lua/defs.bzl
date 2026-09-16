"""Lua targets. Every .lua file gets a place in the graph.

load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_binary", "lua_test", "lua_bundle", "lua_embed")

lua_library   modules on a LUA_PATH root; syntax-checked with luac -p on every build
lua_binary    runnable wrapper: `just run //path:name -- args`
lua_test      the script must exit 0: `just test //path:name`
lua_bundle    one file: package.preload for every module, then main; optional bytecode
lua_embed     a bundle as a C header or Rust source, for a host that carries its logic inline
"""

load("@monomono//rules/lua:toolchain.bzl", "LuaToolchainInfo")

LuaLibraryInfo = provider(fields = {
    "roots": provider_field(list),     # dirs to put on LUA_PATH, transitive
    "modules": provider_field(list),   # structs (name, src), transitive
})

def _module_name(rel, root):
    if root and rel.startswith(root + "/"):
        rel = rel[len(root) + 1:]
    if not rel.endswith(".lua"):
        fail("lua source must end in .lua: " + rel)
    name = rel[:-4]
    if name == "init":
        name = ""
    elif name.endswith("/init"):
        name = name[:-5]
    return name.replace("/", "."), rel

def _transitive(deps):
    roots = []
    modules = []
    for d in deps:
        info = d[LuaLibraryInfo]
        for r in info.roots:
            if r not in roots:
                roots.append(r)
        modules.extend(info.modules)
    return roots, modules

def _check(ctx, tc, src, tag):
    if tc.compiler == None:
        return None
    stamp = ctx.actions.declare_output("check", tag + ".ok")
    ctx.actions.run(
        cmd_args("sh", "-c", 'set -e; "$1" -p "$2" && : >"$3"', "--", tc.compiler, src, stamp.as_output()),
        category = "lua_check",
        identifier = tag,
    )
    return stamp

def _lua_library_impl(ctx):
    tc = ctx.attrs._lua_toolchain[LuaToolchainInfo]
    tree = {}
    mods = []
    stamps = []
    for src in ctx.attrs.srcs:
        name, rel = _module_name(src.short_path, ctx.attrs.root)
        tree[rel] = src
        mods.append(struct(name = name, src = src))
        st = _check(ctx, tc, src, rel.replace("/", "_"))
        if st != None:
            stamps.append(st)
    root_dir = ctx.actions.symlinked_dir("modules", tree)
    roots, tmods = _transitive(ctx.attrs.deps)
    return [
        DefaultInfo(default_output = root_dir, other_outputs = stamps),
        LuaLibraryInfo(roots = [root_dir] + roots, modules = mods + tmods),
    ]

lua_library = rule(
    impl = _lua_library_impl,
    attrs = {
        "srcs": attrs.list(attrs.source()),
        "deps": attrs.list(attrs.dep(providers = [LuaLibraryInfo]), default = []),
        "root": attrs.string(default = "", doc = "package-relative dir that is the module root"),
        "_lua_toolchain": attrs.toolchain_dep(default = "toolchains//:lua", providers = [LuaToolchainInfo]),
    },
)

def _interp_in_script(tc):
    if tc.interpreter_artifact != None:
        return cmd_args(tc.interpreter_artifact, format = '"$root/{}"')
    return cmd_args('"' + tc.interpreter_path + '"')

def _wrapper(ctx, tc, main, deps):
    """A bash wrapper. Paths are project-relative; the script finds the project root from its own
    location under buck-out, so it works from `buck2 run`, from a test runner, and by hand."""
    roots, _ = _transitive(deps)
    path_parts = []
    for r in roots:
        path_parts.append(cmd_args(r, format = "$root/{}/?.lua"))
        path_parts.append(cmd_args(r, format = "$root/{}/?/init.lua"))
    path_parts.append(";")
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        'here=$(cd "$(dirname "$0")" && pwd -P)',
        'root=${here%%/buck-out/*}',
        cmd_args('export LUA_PATH="', cmd_args(path_parts, delimiter = ";"), '"', delimiter = ""),
        cmd_args("exec ", _interp_in_script(tc), ' "$root/', main, '" "$@"', delimiter = ""),
    ]
    script, hidden = ctx.actions.write(ctx.attrs.name + ".sh", lines, is_executable = True, allow_args = True)
    inputs = [main] + hidden + roots
    if tc.interpreter_artifact != None:
        inputs.append(tc.interpreter_artifact)
    return script, inputs

def _lua_binary_impl(ctx):
    tc = ctx.attrs._lua_toolchain[LuaToolchainInfo]
    script, inputs = _wrapper(ctx, tc, ctx.attrs.main, ctx.attrs.deps)
    return [
        DefaultInfo(default_output = script, other_outputs = inputs),
        RunInfo(args = cmd_args(script, hidden = inputs)),
    ]

lua_binary = rule(
    impl = _lua_binary_impl,
    attrs = {
        "main": attrs.source(),
        "deps": attrs.list(attrs.dep(providers = [LuaLibraryInfo]), default = []),
        "_lua_toolchain": attrs.toolchain_dep(default = "toolchains//:lua", providers = [LuaToolchainInfo]),
    },
)

def _lua_test_impl(ctx):
    tc = ctx.attrs._lua_toolchain[LuaToolchainInfo]
    script, inputs = _wrapper(ctx, tc, ctx.attrs.src, ctx.attrs.deps)
    cmd = cmd_args(script, hidden = inputs)
    return [
        DefaultInfo(default_output = script, other_outputs = inputs),
        RunInfo(args = cmd),
        ExternalRunnerTestInfo(
            type = "custom",
            command = [cmd] + ctx.attrs.args,
            env = ctx.attrs.env,
            labels = ctx.attrs.labels,
            run_from_project_root = True,
            use_project_relative_paths = True,
        ),
    ]

lua_test = rule(
    impl = _lua_test_impl,
    attrs = {
        "src": attrs.source(),
        "deps": attrs.list(attrs.dep(providers = [LuaLibraryInfo]), default = []),
        "args": attrs.list(attrs.string(), default = []),
        "env": attrs.dict(attrs.string(), attrs.string(), default = {}),
        "labels": attrs.list(attrs.string(), default = []),
        "_lua_toolchain": attrs.toolchain_dep(default = "toolchains//:lua", providers = [LuaToolchainInfo]),
    },
)

def _lua_bundle_impl(ctx):
    tc = ctx.attrs._lua_toolchain[LuaToolchainInfo]
    _, mods = _transitive(ctx.attrs.deps)
    out_name = ctx.attrs.out or (ctx.attrs.name + ".lua")
    source = ctx.actions.declare_output(out_name if not ctx.attrs.bytecode else ctx.attrs.name + ".src.lua")
    cmd = cmd_args(tc.interpreter, ctx.attrs._bundler, source.as_output(), ctx.attrs.main)
    for m in mods:
        cmd.add(cmd_args(m.src, format = m.name + "={}"))
    ctx.actions.run(cmd, category = "lua_bundle", identifier = ctx.attrs.name)
    if not ctx.attrs.bytecode:
        return [DefaultInfo(default_output = source)]
    if tc.compiler == None:
        fail("lua_bundle bytecode=True needs a compiler on the toolchain")
    out = ctx.actions.declare_output(out_name)
    ctx.actions.run(
        cmd_args(tc.compiler, "-s", "-o", out.as_output(), source),
        category = "lua_bytecode",
        identifier = ctx.attrs.name,
    )
    return [DefaultInfo(default_output = out, other_outputs = [source])]

lua_bundle = rule(
    impl = _lua_bundle_impl,
    attrs = {
        "main": attrs.source(),
        "deps": attrs.list(attrs.dep(providers = [LuaLibraryInfo]), default = []),
        "out": attrs.option(attrs.string(), default = None),
        "bytecode": attrs.bool(default = False),
        "_bundler": attrs.source(default = "monomono//rules/lua:bundle.lua"),
        "_lua_toolchain": attrs.toolchain_dep(default = "toolchains//:lua", providers = [LuaToolchainInfo]),
    },
)

def _lua_embed_impl(ctx):
    tc = ctx.attrs._lua_toolchain[LuaToolchainInfo]
    ext = {"c": ".h", "rust": ".rs"}[ctx.attrs.lang]
    out = ctx.actions.declare_output(ctx.attrs.out or (ctx.attrs.name + ext))
    src = ctx.attrs.src[DefaultInfo].default_outputs[0]
    ctx.actions.run(
        cmd_args(tc.interpreter, ctx.attrs._embedder, out.as_output(), ctx.attrs.lang, ctx.attrs.symbol or ctx.attrs.name.replace("-", "_"), src),
        category = "lua_embed",
        identifier = ctx.attrs.name,
    )
    return [DefaultInfo(default_output = out)]

lua_embed = rule(
    impl = _lua_embed_impl,
    attrs = {
        "src": attrs.dep(doc = "a lua_bundle (or any single-file target)"),
        "lang": attrs.enum(["c", "rust"], default = "c"),
        "symbol": attrs.option(attrs.string(), default = None),
        "out": attrs.option(attrs.string(), default = None),
        "_embedder": attrs.source(default = "monomono//rules/lua:embed.lua"),
        "_lua_toolchain": attrs.toolchain_dep(default = "toolchains//:lua", providers = [LuaToolchainInfo]),
    },
)
