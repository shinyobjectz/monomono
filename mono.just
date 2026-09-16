# monomono — recipes every consumer gets. The root justfile imports this file.
# Bodies call scripts under this file's directory. No logic lives here.

mono_home := source_directory()
mono_root := justfile_directory()
export MONO_HOME := mono_home
export MONO_ROOT := mono_root

# List recipes
default:
    @just --list --unsorted

# Recipes plus the spec-first lifecycle
help:
    @"{{mono_home}}/scripts/tools/help.sh"

# buck2, host adapters, context store, package adapters, submodules, ci
setup:
    @"{{mono_home}}/scripts/tools/setup.sh"

# Required binaries and repo shape
doctor:
    @"{{mono_home}}/scripts/tools/doctor.sh"

# Definition of green: doctor, feature check, buck2 build //..., buck2 test //...
check:
    @"{{mono_home}}/scripts/tools/check.sh"

# buck2 build [target...]  (default //...)
[positional-arguments]
build *args:
    @"{{mono_home}}/scripts/build/buck.sh" build "$@"

# buck2 test [target...]  (default //...)
[positional-arguments]
test *args:
    @"{{mono_home}}/scripts/build/buck.sh" test "$@"

# buck2 run <target> [args...]
[positional-arguments]
run *args:
    @"{{mono_home}}/scripts/build/buck.sh" run "$@"

# buck2 targets [pattern]  (default //...)
[positional-arguments]
targets *args:
    @"{{mono_home}}/scripts/build/buck.sh" targets "$@"

# The package itself: status | version | update [ref] | migrate | sync | diff
[positional-arguments]
mono *args:
    @"{{mono_home}}/scripts/tools/mono.sh" "$@"

# Root AGENTS.md link + generate .agents/skills: sync | status | skills | check
[positional-arguments]
agents *args:
    @"{{mono_home}}/scripts/tools/agents-host.sh" "$@"

# Junk drawer, projects, Gherkin features
[positional-arguments]
context *args:
    @"{{mono_home}}/scripts/tools/context/context.sh" "$@"

# Ecosystems under packages/: list | adapters | init <eco> <adapter> | add|update|sync <eco> ...
[positional-arguments]
pkg *args:
    @"{{mono_home}}/scripts/update/pkg.sh" "$@"

# buck2 toolchains: list | available | add <name>
[positional-arguments]
toolchain *args:
    @"{{mono_home}}/scripts/tools/toolchain.sh" "$@"

# Top-level areas: list | add <name>
[positional-arguments]
area *args:
    @"{{mono_home}}/scripts/tools/area.sh" "$@"

# Public repos under submodules/: add <url> [name] | update | list | sync
[positional-arguments]
submodule *args:
    @"{{mono_home}}/scripts/tools/submodule.sh" "$@"

# git/ci: sync | run | status
[positional-arguments]
ci *args:
    @"{{mono_home}}/scripts/tools/ci.sh" "$@"
