# go: go_binary / go_library / go_test on the system go (toolchain + bootstrap)
load("@prelude//toolchains/go:system_go_bootstrap_toolchain.bzl", "system_go_bootstrap_toolchain")
load("@prelude//toolchains/go:system_go_toolchain.bzl", "system_go_toolchain")
system_go_toolchain(
    name = "go",
    visibility = ["PUBLIC"],
)
system_go_bootstrap_toolchain(
    name = "go_bootstrap",
    visibility = ["PUBLIC"],
)
