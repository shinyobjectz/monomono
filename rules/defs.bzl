"""Domain-free macros over the buck2 prelude.

load("@monomono//rules:defs.bzl", "mono_check", "mono_script", "mono_feature_tests")
"""

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

def mono_feature_tests(name, tests, labels = None):
    """One sh_test per file in a feature's test/ folder, plus a test_suite named `name`."""
    targets = []
    for t in tests:
        tname = name + "-" + t.split("/")[-1].removesuffix(".sh")
        mono_check(name = tname, test = t, labels = (labels or []) + ["feature:" + name])
        targets.append(":" + tname)
    native.test_suite(name = name, tests = targets, visibility = ["PUBLIC"])
