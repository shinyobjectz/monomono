"""Domain-free macros over the buck2 prelude.

load("@monomono//rules:defs.bzl", "mono_check", "mono_script", "mono_feature_tests")
"""

load("@monomono//rules/lua:defs.bzl", "lua_test")

def mono_script(name, main, resources = None, visibility = ["PUBLIC"], **kwargs):
    """A runnable shell script: `just run //path:name`."""
    native.sh_binary(
        name = name,
        main = main,
        resources = resources or [],
        visibility = visibility,
        **kwargs
    )

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

def mono_feature_tests(name, tests, deps = None, labels = None):
    """One test target per file in a feature's test/ folder, plus a test_suite named `name`.
    .sh files run as shell checks; .lua files run under toolchains//:lua with `deps` on LUA_PATH."""
    targets = []
    for t in tests:
        base = t.split("/")[-1]
        if base.endswith(".lua"):
            tname = name + "-" + base[:-4]
            lua_test(name = tname, src = t, deps = deps or [], labels = (labels or []) + ["feature:" + name])
        else:
            tname = name + "-" + base.removesuffix(".sh")
            mono_check(name = tname, test = t, labels = (labels or []) + ["feature:" + name])
        targets.append(":" + tname)
    native.test_suite(name = name, tests = targets, visibility = ["PUBLIC"])
