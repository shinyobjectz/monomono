# test: the no-op test toolchain and the (local) remote-test-execution toolchain every *_test rule depends on
load("@prelude//tests:test_toolchain.bzl", "noop_test_toolchain")
load("@prelude//toolchains:remote_test_execution.bzl", "remote_test_execution_toolchain")
noop_test_toolchain(
    name = "test",
    visibility = ["PUBLIC"],
)
remote_test_execution_toolchain(
    name = "remote_test_execution",
    visibility = ["PUBLIC"],
)
