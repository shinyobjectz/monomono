"""Lua targets. Every .lua file gets a place in the graph.

load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_binary", "lua_test", "lua_tests", "lua_repl",
     "lua_bundle", "lua_embed", "lua_wasm", "lua_meta", "lua_lint", "lua_format", "lua_feature_test")

lua_library        modules on LUA_PATH (+ cpath dirs on LUA_CPATH, + resources); compile-checked on every build
                   sub-targets: [repl] the interpreter with this library on the path, [meta] LuaLS stubs + .luarc.json
lua_binary         runnable wrapper: `just run //path:name -- args`; MONO_LUA_HOOK=cover|profile instruments it
lua_test           the script must exit 0; write tests with require("mono.spec") for named cases and TAP
lua_tests          one lua_test per file plus a suite
lua_repl           a standalone REPL target over some libraries
lua_bundle         one file: package.preload per module (loaded with its real chunk name), then main; dialect-gated; optional bytecode
lua_embed          a bundle as a C header or Rust source
lua_wasm           a bundle as an ES module for wasmoon in the browser
lua_meta           LuaLS ---@meta stubs and a .luarc.json for a set of libraries
lua_lint           luacheck over sources, as a test (toolchains//:luacheck)
lua_format         stylua --check over sources, as a test; [fix] sub-target rewrites (toolchains//:stylua)
lua_feature_test   Gherkin scenarios run against a steps file, emitting a span tree in the consumer's vocabulary (MONO_TELEMETRY_PROFILE)
"""

load("@monomono//rules/lua:toolchain.bzl", "LuaToolInfo", "LuaToolchainInfo")

# Attribute names and meanings are frozen under this number; a change ships with a migration and a bump.
RULES_API = 1

LuaMetaInfo = provider(fields = {
    "provided": provider_field(list, default = []),  # project-relative paths of hand-written stubs (lua_typecheck ignores them as sources)
})

LuaLibraryInfo = provider(fields = {
    "roots": provider_field(list),     # dirs to put on LUA_PATH, transitive
    "cpaths": provider_field(list),    # dirs to put on LUA_CPATH, transitive
    "modules": provider_field(list),   # structs (name, src), transitive
})

_TOOLCHAIN = attrs.toolchain_dep(default = "toolchains//:lua", providers = [LuaToolchainInfo])
_STDLIB = attrs.dep(default = "monomono//rules/lua:lib")
_DEPS = attrs.list(attrs.dep(providers = [LuaLibraryInfo]), default = [])
_TC_OVERRIDE = attrs.option(attrs.toolchain_dep(providers = [LuaToolchainInfo]), default = None, doc = "run this target under another lua_toolchain (e.g. toolchains//:luajit) instead of toolchains//:lua")

def _tc(ctx):
    """The toolchain for this target: the `toolchain` attr when set, else toolchains//:lua."""
    override = getattr(ctx.attrs, "toolchain", None)
    return (override or ctx.attrs._lua_toolchain)[LuaToolchainInfo]

def _infos(deps):
    return [d[LuaLibraryInfo] for d in deps]

def _module_name(rel, root, prefix = ""):
    if root and rel.startswith(root + "/"):
        rel = rel[len(root) + 1:]
    if not rel.endswith(".lua"):
        fail("lua source must end in .lua: " + rel)
    name = rel[:-4]
    if name == "init":
        name = ""
    elif name.endswith("/init"):
        name = name[:-5]
    name = name.replace("/", ".")
    if prefix:
        name = prefix + "." + name if name else prefix
        rel = prefix.replace(".", "/") + "/" + rel
    return name, rel

def _strip_root(rel, root):
    if root and rel.startswith(root + "/"):
        return rel[len(root) + 1:]
    return rel

def _merge(infos):
    roots = []
    cpaths = []
    modules = []
    for info in infos:
        for r in info.roots:
            if r not in roots:
                roots.append(r)
        for c in info.cpaths:
            if c not in cpaths:
                cpaths.append(c)
        modules.extend(info.modules)
    return roots, cpaths, modules

def _interp_inputs(tc):
    return [tc.interpreter_artifact] if tc.interpreter_artifact != None else []

def _runtime_name(tc):
    if tc.flavor == "luajit":
        return "LuaJIT"
    if tc.dialect == "5.1":
        return "Lua 5.1"
    if tc.dialect == "5.3":
        return "Lua 5.3"
    return "Lua 5.4"

# --- wrapper ------------------------------------------------------------------

def _interp_in_script(tc, prefer_host = True):
    if prefer_host and tc.host:
        return cmd_args(['"' + h + '"' for h in tc.host if h], delimiter = " ")   # lua-host: the host wins over bin
    if tc.interpreter_artifact != None:
        return cmd_args(tc.interpreter_artifact, format = '"$root/{}"')
    if tc.interpreter_path:
        return cmd_args('"' + tc.interpreter_path + '"')
    if tc.host:
        return cmd_args(['"' + h + '"' for h in tc.host if h], delimiter = " ")
    fail("toolchains//:lua has neither an interpreter nor a host command")

def _needs_interp(tc, what):
    if tc.interpreter == None:
        fail(what + " needs an interpreter: set [lua] bin (lua-config) or use the hermetic lua toolchain")
    return tc.interpreter

def _wrapper(ctx, tc, mode, main, infos, extra_args = []):
    """A bash wrapper. Paths are project-relative; the script finds the project root from its own
    location under buck-out, so it works from `buck2 run`, from a test runner, and by hand.
    mode: run (main + args) | repl (-i unless args) | features (cd root; main = runner, then extra args)"""
    roots, cpaths, _ = _merge(infos)
    stdlib = ctx.attrs._stdlib[DefaultInfo].default_outputs[0]
    lib = cmd_args(stdlib, format = "$root/{}/lib")
    path_parts = []
    root_parts = []
    for r in roots:
        path_parts.append(cmd_args(r, format = "$root/{}/?.lua"))
        path_parts.append(cmd_args(r, format = "$root/{}/?/init.lua"))
        root_parts.append(cmd_args(r, format = "$root/{}"))
    path_parts.append(cmd_args(lib, format = "{}/?.lua"))
    path_parts.append(cmd_args(lib, format = "{}/?/init.lua"))
    path_parts.append(";")
    cpath_parts = [cmd_args(c, format = "$root/{}/?.so") for c in cpaths] + [";"]
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        'here=$(cd "$(dirname "$0")" && pwd -P)',
        "root=${here%%/buck-out/*}",
        cmd_args('export LUA_PATH="', cmd_args(path_parts, delimiter = ";"), '"', delimiter = ""),
        cmd_args('export LUA_CPATH="', cmd_args(cpath_parts, delimiter = ";"), '"', delimiter = ""),
        cmd_args('export MONO_LUA_ROOTS="', cmd_args(root_parts, delimiter = ";"), '"', delimiter = ""),
        cmd_args('lib="', lib, '"', delimiter = ""),
        cmd_args('main="', cmd_args(main, format = "$root/{}") if main != None else "", '"', delimiter = ""),
        "hook=${MONO_LUA_HOOK:-}",
    ]
    if mode == "features":
        lines.append('cd "$root"')
        lines.append(cmd_args('set -- "$main" ' + ("-- " if tc.host else ""), cmd_args(extra_args, delimiter = " ", quote = "shell"), ' "$@"', delimiter = ""))
    elif mode == "repl":
        lines.append("if [[ $# -eq 0 ]]; then set -- -i; fi")
    elif tc.host:
        lines.append('set -- "$main" -- "$@"')   # host command: <host> <module> -- args (host wins over bin; bin still serves bundle/meta/check)
    else:
        lines.append('if [[ -n $hook ]]; then set -- "$lib/mono/$hook.lua" "$main" "$@"; else set -- "$main" "$@"; fi')
    lines.append(cmd_args("exec ", _interp_in_script(tc, prefer_host = mode != "repl"), ' "$@"', delimiter = ""))
    script, hidden = ctx.actions.write(ctx.attrs.name + ".sh", lines, is_executable = True, allow_args = True)
    inputs = hidden + roots + cpaths + [stdlib] + _interp_inputs(tc) + extra_args
    if main != None:
        inputs.append(main)
    return script, inputs

def _run_providers(script, inputs):
    return [DefaultInfo(default_output = script, other_outputs = inputs), RunInfo(args = cmd_args(script, hidden = inputs))]

# --- meta ---------------------------------------------------------------------

def _meta_outputs(ctx, tc, infos, provided):
    roots, _, mods = _merge(infos)
    outdir = ctx.actions.declare_output("meta", dir = True)
    roots_file, hidden = ctx.actions.write("roots.txt", [cmd_args(r) for r in roots], allow_args = True)
    cmd = cmd_args(_needs_interp(tc, "lua_meta"), ctx.attrs._meta, outdir.as_output(), roots_file, hidden = roots + hidden)
    for p in provided:
        cmd.add(cmd_args(p, format = "--provided={}"))
    for m in mods:
        cmd.add(cmd_args(m.src, format = m.name + "={}"))
    ctx.actions.run(cmd, category = "lua_meta", identifier = ctx.attrs.name, env = {"MONO_LUA_RUNTIME": _runtime_name(tc)})
    return outdir

# --- library ------------------------------------------------------------------

def _lua_library_impl(ctx):
    tc = _tc(ctx)
    tree = {}
    mods = []
    stamps = []
    for src in ctx.attrs.srcs:
        name, rel = _module_name(src.short_path, ctx.attrs.root, ctx.attrs.prefix)
        tree[rel] = src
        mods.append(struct(name = name, src = src))
        if tc.interpreter != None:
            stamp = ctx.actions.declare_output("check", rel.replace("/", "_") + ".ok")
            ctx.actions.run(
                cmd_args("sh", "-c", 'set -e; "$@" && : >"$0"', stamp.as_output(), tc.interpreter, ctx.attrs._checker, src),
                category = "lua_check",
                identifier = rel,
            )
            stamps.append(stamp)
    for res in ctx.attrs.resources:
        rel = _strip_root(res.short_path, ctx.attrs.root)
        tree[(ctx.attrs.prefix.replace(".", "/") + "/" + rel) if ctx.attrs.prefix else rel] = res
    root_dir = ctx.actions.symlinked_dir("modules", tree)
    roots, cpaths, tmods = _merge(_infos(ctx.attrs.deps))
    info = LuaLibraryInfo(roots = [root_dir] + roots, cpaths = ctx.attrs.cpath + cpaths, modules = mods + tmods)
    subs = {}
    if tc.interpreter != None:
        repl_script, repl_inputs = _wrapper(ctx, tc, "repl", None, [info])
        outdir = _meta_outputs(ctx, tc, [info], [])
        subs = {
            "repl": _run_providers(repl_script, repl_inputs),
            "meta": [DefaultInfo(default_output = outdir)],
        }
    return [DefaultInfo(default_output = root_dir, other_outputs = stamps, sub_targets = subs), info]

lua_library = rule(
    impl = _lua_library_impl,
    attrs = {
        "srcs": attrs.list(attrs.source()),
        "deps": _DEPS,
        "root": attrs.string(default = "", doc = "package-relative dir that is the module root"),
        "prefix": attrs.string(default = "", doc = "module name prefix: prefix = 'hourly-check' makes compare.lua require-able as 'hourly-check.compare' even from its own BUCK"),
        "cpath": attrs.list(attrs.source(allow_directory = True), default = [], doc = "dirs holding C modules (.so)"),
        "resources": attrs.list(attrs.source(), default = [], doc = "data files, readable via require('mono.resource')"),
        "toolchain": _TC_OVERRIDE,
        "_lua_toolchain": _TOOLCHAIN,
        "_stdlib": _STDLIB,
        "_checker": attrs.source(default = "monomono//rules/lua:check.lua"),
        "_meta": attrs.source(default = "monomono//rules/lua:meta.lua"),
    },
)

# --- binary / test / repl ----------------------------------------------------

def _lua_binary_impl(ctx):
    tc = _tc(ctx)
    script, inputs = _wrapper(ctx, tc, "run", ctx.attrs.main, _infos(ctx.attrs.deps))
    return _run_providers(script, inputs)

lua_binary = rule(
    impl = _lua_binary_impl,
    attrs = {"main": attrs.source(), "deps": _DEPS, "toolchain": _TC_OVERRIDE, "_lua_toolchain": _TOOLCHAIN, "_stdlib": _STDLIB},
)

def _test_info(cmd, ctx):
    return ExternalRunnerTestInfo(
        type = "custom",
        command = [cmd] + ctx.attrs.args,
        env = ctx.attrs.env,
        labels = ctx.attrs.labels,
        run_from_project_root = True,
        use_project_relative_paths = True,
    )

def _lua_test_impl(ctx):
    tc = _tc(ctx)
    script, inputs = _wrapper(ctx, tc, "run", ctx.attrs.src, _infos(ctx.attrs.deps))
    cmd = cmd_args(script, hidden = inputs)
    return _run_providers(script, inputs) + [_test_info(cmd, ctx)]

_TEST_ATTRS = {
    "args": attrs.list(attrs.string(), default = []),
    "env": attrs.dict(attrs.string(), attrs.string(), default = {}),
    "labels": attrs.list(attrs.string(), default = []),
}

lua_test = rule(
    impl = _lua_test_impl,
    attrs = dict({"src": attrs.source(), "deps": _DEPS, "toolchain": _TC_OVERRIDE, "_lua_toolchain": _TOOLCHAIN, "_stdlib": _STDLIB}, **_TEST_ATTRS),
)

def lua_tests(name, srcs, deps = None, labels = None, **kwargs):
    """One lua_test per file plus a test_suite named `name`."""
    targets = []
    for s in srcs:
        tname = name + "-" + s.split("/")[-1].removesuffix(".lua")
        lua_test(name = tname, src = s, deps = deps or [], labels = (labels or []) + ["suite:" + name], **kwargs)
        targets.append(":" + tname)
    native.test_suite(name = name, tests = targets, visibility = ["PUBLIC"])

def _lua_repl_impl(ctx):
    tc = _tc(ctx)
    script, inputs = _wrapper(ctx, tc, "repl", None, _infos(ctx.attrs.deps))
    return _run_providers(script, inputs)

lua_repl = rule(
    impl = _lua_repl_impl,
    attrs = {"deps": _DEPS, "toolchain": _TC_OVERRIDE, "_lua_toolchain": _TOOLCHAIN, "_stdlib": _STDLIB},
)

# --- bundle / embed / wasm ---------------------------------------------------

def _lua_bundle_impl(ctx):
    tc = _tc(ctx)
    _, _, mods = _merge(_infos(ctx.attrs.deps))
    mods = sorted(mods, key = lambda m: m.name)
    out_name = ctx.attrs.out or (ctx.attrs.name + ".lua")
    dialect = ctx.attrs.dialect or tc.dialect
    source = ctx.actions.declare_output(out_name if not ctx.attrs.bytecode else ctx.attrs.name + ".src.lua")
    cmd = cmd_args(_needs_interp(tc, "lua_bundle"), ctx.attrs._bundler, source.as_output(), ctx.attrs.main, dialect)
    for m in mods:
        cmd.add(cmd_args(m.src, format = m.name + "={}"))
    ctx.actions.run(cmd, category = "lua_bundle", identifier = ctx.attrs.name)
    if not ctx.attrs.bytecode:
        return [DefaultInfo(default_output = source)]
    out = ctx.actions.declare_output(out_name)
    if tc.compiler != None:
        ctx.actions.run(cmd_args(tc.compiler, "-s", "-o", out.as_output(), source), category = "lua_bytecode", identifier = ctx.attrs.name)
    elif tc.flavor == "luajit":
        env = {}
        if tc.modules != None:
            env["LUA_PATH"] = cmd_args(tc.modules, format = "{}/?.lua;;")
        ctx.actions.run(cmd_args(tc.interpreter, "-b", "-s", source, out.as_output()), env = env, category = "lua_bytecode", identifier = ctx.attrs.name)
    else:
        fail("lua_bundle bytecode=True needs a compiler on the toolchain")
    return [DefaultInfo(default_output = out, other_outputs = [source])]

lua_bundle = rule(
    impl = _lua_bundle_impl,
    attrs = {
        "main": attrs.source(),
        "deps": _DEPS,
        "out": attrs.option(attrs.string(), default = None),
        "bytecode": attrs.bool(default = False),
        "dialect": attrs.option(attrs.enum(["5.1", "5.3", "5.4", "jit", "portable"]), default = None, doc = "default: the toolchain's; portable = 5.1 ∩ 5.4"),
        "_bundler": attrs.source(default = "monomono//rules/lua:bundle.lua"),
        "toolchain": _TC_OVERRIDE,
        "_lua_toolchain": _TOOLCHAIN,
    },
)

def _lua_embed_impl(ctx):
    tc = _tc(ctx)
    ext = {"c": ".h", "rust": ".rs"}[ctx.attrs.lang]
    out = ctx.actions.declare_output(ctx.attrs.out or (ctx.attrs.name + ext))
    src = ctx.attrs.src[DefaultInfo].default_outputs[0]
    ctx.actions.run(
        cmd_args(_needs_interp(tc, "lua_embed"), ctx.attrs._embedder, out.as_output(), ctx.attrs.lang, ctx.attrs.symbol or ctx.attrs.name.replace("-", "_"), src),
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
        "toolchain": _TC_OVERRIDE,
        "_lua_toolchain": _TOOLCHAIN,
    },
)

def _lua_wasm_impl(ctx):
    tc = _tc(ctx)
    out = ctx.actions.declare_output(ctx.attrs.out or (ctx.attrs.name + ".mjs"))
    src = ctx.attrs.src[DefaultInfo].default_outputs[0]
    ctx.actions.run(cmd_args(_needs_interp(tc, "lua_wasm"), ctx.attrs._wasm, out.as_output(), src, ctx.attrs.name), category = "lua_wasm", identifier = ctx.attrs.name)
    return [DefaultInfo(default_output = out)]

lua_wasm = rule(
    impl = _lua_wasm_impl,
    attrs = {
        "src": attrs.dep(doc = "a source lua_bundle (not bytecode)"),
        "out": attrs.option(attrs.string(), default = None),
        "_wasm": attrs.source(default = "monomono//rules/lua:wasm.lua"),
        "toolchain": _TC_OVERRIDE,
        "_lua_toolchain": _TOOLCHAIN,
    },
)

# --- meta / lint / format ----------------------------------------------------

def _lua_meta_impl(ctx):
    tc = _tc(ctx)
    outdir = _meta_outputs(ctx, tc, _infos(ctx.attrs.deps), ctx.attrs.provided)
    return [DefaultInfo(default_output = outdir), LuaMetaInfo(provided = [ctx.label.package + "/" + p.short_path for p in ctx.attrs.provided])]

lua_meta = rule(
    impl = _lua_meta_impl,
    attrs = {
        "deps": _DEPS,
        "provided": attrs.list(attrs.source(), default = [], doc = "---@meta files you render yourself; modules they declare are not stubbed"),
        "toolchain": _TC_OVERRIDE,
        "_lua_toolchain": _TOOLCHAIN,
        "_meta": attrs.source(default = "monomono//rules/lua:meta.lua"),
    },
)

def _lua_typecheck_impl(ctx):
    tool = ctx.attrs._luals[LuaToolInfo]
    if ctx.attrs.meta == None and ctx.attrs.luarc == None:
        fail("lua_typecheck: pass meta (generated stubs + luarc) or luarc (your own .luarc.json), or both")
    meta = ctx.attrs.meta[DefaultInfo] if ctx.attrs.meta != None else None
    outdir = meta.default_outputs[0] if meta != None else None
    # hand-written stubs under `path` are already in the meta dir; seen twice they report duplicate fields
    prefix = ctx.attrs.path.rstrip("/") + "/"
    minfo = ctx.attrs.meta.get(LuaMetaInfo) if ctx.attrs.meta != None else None
    ignore = ",".join(['"{}"'.format(p[len(prefix):]) for p in minfo.provided if p.startswith(prefix)]) if minfo else ""
    if ctx.attrs.luarc != None:
        # your own .luarc.json, used as it is: relative paths in it are yours to resolve (LuaLS reads them against the checked dir)
        cmd = cmd_args(
            "sh", "-c", 'out=$("$@" 2>&1); echo "$out"; echo "$out" | grep -q "no problems found"', "--",
            tool.run, "--check", ctx.attrs.path, "--configpath", ctx.attrs.luarc, "--checklevel", ctx.attrs.level.capitalize(),
            hidden = ([outdir] if outdir != None else []) + tool.inputs + ctx.attrs.srcs,
        )
        return [DefaultInfo(), RunInfo(args = cmd), _test_info(cmd, ctx)]
    # LuaLS resolves relative library paths against the checked dir, so the luarc is rewritten to absolute paths
    # at run time (the action runs from the project root). LuaLS exits 0 even with diagnostics; the sentence is the verdict.
    cmd = cmd_args(
        "sh", "-c",
        'meta="$1"; ignore="$2"; shift 2; rc=$(mktemp); sed -e "s#^    \\"\\.\\"#    \\"$PWD/$meta\\"#" -e "s#\\"buck-out/#\\"$PWD/buck-out/#g" -e "s#\\"workspace.checkThirdParty\\": false,#\\"workspace.checkThirdParty\\": false, \\"workspace.ignoreDir\\": [$ignore],#" "$meta/.luarc.json" >"$rc"; out=$("$@" --configpath "$rc" 2>&1); rm -f "$rc"; echo "$out"; echo "$out" | grep -q "no problems found"', "--",
        outdir, ignore, tool.run, "--check", ctx.attrs.path, "--checklevel", ctx.attrs.level.capitalize(),
        hidden = [outdir] + tool.inputs + ctx.attrs.srcs,
    )
    return [DefaultInfo(), RunInfo(args = cmd), _test_info(cmd, ctx)]

lua_typecheck = rule(
    impl = _lua_typecheck_impl,
    attrs = dict({
        "meta": attrs.option(attrs.dep(), default = None, doc = "a lua_meta target (or a lua_library[meta]): the dir holding stubs and a generated .luarc.json"),
        "luarc": attrs.option(attrs.source(), default = None, doc = "your own .luarc.json; used verbatim instead of the generated one"),
        "path": attrs.string(doc = "project-relative dir LuaLS checks"),
        "srcs": attrs.list(attrs.source(), default = [], doc = "the files under path, so a change re-runs the check (glob them)"),
        "level": attrs.enum(["error", "warning", "information"], default = "warning"),
        "_luals": attrs.toolchain_dep(default = "toolchains//:luals", providers = [LuaToolInfo]),
    }, **_TEST_ATTRS),
)

def _lua_lint_impl(ctx):
    tool = ctx.attrs._luacheck[LuaToolInfo]
    cmd = cmd_args(tool.run, "--no-color", ctx.attrs.srcs, ctx.attrs.flags, hidden = tool.inputs + ([ctx.attrs.config] if ctx.attrs.config else []))
    if ctx.attrs.config:
        cmd.add(cmd_args(ctx.attrs.config, format = "--config={}"))
    return [DefaultInfo(), RunInfo(args = cmd), _test_info(cmd, ctx)]

lua_lint = rule(
    impl = _lua_lint_impl,
    attrs = dict({
        "srcs": attrs.list(attrs.source()),
        "config": attrs.option(attrs.source(), default = None, doc = ".luacheckrc"),
        "flags": attrs.list(attrs.string(), default = []),
        "_luacheck": attrs.toolchain_dep(default = "toolchains//:luacheck", providers = [LuaToolInfo]),
    }, **_TEST_ATTRS),
)

def _lua_format_impl(ctx):
    tool = ctx.attrs._stylua[LuaToolInfo]
    check = cmd_args(tool.run, "--check", ctx.attrs.srcs, hidden = tool.inputs)
    fix = cmd_args(tool.run, ctx.attrs.srcs, hidden = tool.inputs)
    return [
        DefaultInfo(sub_targets = {"fix": [DefaultInfo(), RunInfo(args = fix)]}),
        RunInfo(args = check),
        _test_info(check, ctx),
    ]

lua_format = rule(
    impl = _lua_format_impl,
    attrs = dict({
        "srcs": attrs.list(attrs.source()),
        "_stylua": attrs.toolchain_dep(default = "toolchains//:stylua", providers = [LuaToolInfo]),
    }, **_TEST_ATTRS),
)

# --- gherkin ------------------------------------------------------------------

def _lua_path_env(infos):
    roots, cpaths, _ = _merge(infos)
    parts = []
    for r in roots:
        parts.append(cmd_args(r, format = "{}/?.lua"))
        parts.append(cmd_args(r, format = "{}/?/init.lua"))
    parts.append(";")
    return {
        "LUA_PATH": cmd_args(parts, delimiter = ";"),
        "LUA_CPATH": cmd_args([cmd_args(c, format = "{}/?.so") for c in cpaths] + [";"], delimiter = ";"),
        "MONO_LUA_ROOTS": cmd_args(roots, delimiter = ";"),
    }

def _lua_feature_test_impl(ctx):
    tc = _tc(ctx)
    infos = _infos(ctx.attrs.deps)
    if ctx.attrs.runner != None or ctx.attrs.runner_cmd:
        # someone else's runner: <runner> --steps <file> <feature>..., from the project root, with the module path in the environment
        head = ctx.attrs.runner[RunInfo].args if ctx.attrs.runner != None else cmd_args(ctx.attrs.runner_cmd)
        # the verdict is the exit code; a "# N passed, M failed, K undefined" line and MONO_REPORT_OUT are conventions for people and apps, nothing here reads them
        cmd = cmd_args(head, (["--steps", ctx.attrs.steps] if ctx.attrs.steps != None else []), ctx.attrs.features, hidden = [r for i in infos for r in i.roots])
        env = dict(ctx.attrs.env)
        env.update(_lua_path_env(infos))
        return [DefaultInfo(), RunInfo(args = cmd), ExternalRunnerTestInfo(
            type = "custom", command = [cmd] + ctx.attrs.args, env = env, labels = ctx.attrs.labels,
            run_from_project_root = True, use_project_relative_paths = True)]
    stdlib = ctx.attrs._stdlib[DefaultInfo].default_outputs[0]
    if ctx.attrs.steps == None:
        fail("lua_feature_test: steps is required unless you pass runner or runner_cmd")
    script, inputs = _wrapper(ctx, tc, "features", ctx.attrs._runner, infos, ["--steps", ctx.attrs.steps] + ctx.attrs.features)
    cmd = cmd_args(script, hidden = inputs + [stdlib])
    return _run_providers(script, inputs) + [_test_info(cmd, ctx)]

lua_feature_test = rule(
    impl = _lua_feature_test_impl,
    attrs = dict({
        "features": attrs.list(attrs.source(), doc = "Gherkin .feature files"),
        "steps": attrs.option(attrs.source(), default = None, doc = "step definitions: a Lua file using require('mono.steps'); optional with your own runner, which then gets only the features"),
        "runner": attrs.option(attrs.dep(providers = [RunInfo]), default = None, doc = "your own runner target; monomono's is not used"),
        "runner_cmd": attrs.list(attrs.string(), default = [], doc = "your own runner as a host command"),
        "deps": _DEPS,
        "_runner": attrs.source(default = "monomono//rules/lua:lib/mono/features.lua"),
        "toolchain": _TC_OVERRIDE,
        "_lua_toolchain": _TOOLCHAIN,
        "_stdlib": _STDLIB,
    }, **_TEST_ATTRS),
)
