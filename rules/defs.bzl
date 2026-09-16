"""Domain-free macros over the buck2 prelude.

load("@monomono//rules:defs.bzl", "mono_check", "mono_script", "mono_feature_tests")
"""

load("@monomono//rules/lua:defs.bzl", "lua_feature_test", "lua_test")

def mono_script(name, main, resources = None, visibility = ["PUBLIC"], **kwargs):
    """A runnable shell script: `just run //path:name`."""
    native.sh_binary(name = name, main = main, resources = resources or [], visibility = visibility, **kwargs)

def mono_check(name, test, args = None, env = None, labels = None, **kwargs):
    """A shell check that runs from the repo root (cwd = project root): `just test //path:name`."""
    native.sh_test(
        name = name,
        test = test,
        args = args or [],
        env = env or {},
        labels = (labels or []) + ["buck2_run_from_project_root"],
        **kwargs
    )

def mono_feature_tests(name, tests, features = None, steps = None, deps = None, labels = None, runner = None, runner_cmd = None):
    """A feature's test targets plus a test_suite named `name`.
    .sh files run as shell checks; .lua files run under toolchains//:lua with `deps` on LUA_PATH;
    when `steps` names a steps file, every .feature in `features` runs as Gherkin scenarios
    and the run is traced as spans (MONO_TRACE_OUT=file for OTLP JSON; MONO_TELEMETRY_PROFILE names them)."""
    targets = []
    tags = (labels or []) + ["feature:" + name]
    for t in tests:
        base = t.split("/")[-1]
        if base.endswith(".lua"):
            tname = name + "-" + base[:-4]
            lua_test(name = tname, src = t, deps = deps or [], labels = tags)
        else:
            tname = name + "-" + base.removesuffix(".sh")
            mono_check(name = tname, test = t, labels = tags)
        targets.append(":" + tname)
    step_files = steps if type(steps) == "list" else ([steps] if steps else [])
    if step_files and features:
        lua_feature_test(name = name + "-gherkin", features = features, steps = step_files[0], deps = deps or [], labels = tags, runner = runner, runner_cmd = runner_cmd or [])
        targets.append(":" + name + "-gherkin")
    native.test_suite(name = name, tests = targets, visibility = ["PUBLIC"])
