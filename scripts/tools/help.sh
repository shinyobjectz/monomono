#!/usr/bin/env bash
# Recipe list plus the lifecycle this CLI enforces.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

sdlc() {
  cat <<'TXT'
Lifecycle (every session)

  Spec
    just context project new <slug>              # skip if it exists
    just context feature new <project> <slug>
    rewrite feature.md and bdd/*.feature
    just context feature check <project> <slug>

  Lock
    just context feature test <project> <slug> <name>   # red sh_test target in the feature's BUCK
    just test //context/...                              # stays red until implemented

  Build
    implement in library/ or app/ as buck2 targets — not in context/
    just build            # buck2 build //...
    just test             # buck2 test //...
    just check            # doctor + features + build + test (what CI runs)

Context that is not a feature

  just context put <volume> --title "..." [body]
  just context get [query|volume|id]

Toolchains and ecosystems

  just toolchain available       # fragments: cxx, python, rust, go, ...
  just toolchain add rust        # appends to toolchains/BUCK
  just toolchain add lua         # hermetic Lua 5.4 (or lua-5.1, lua-5.3, luajit, lua-system, lua-config, lua-host)
  just pkg init js bun           # packages/js managed by the bun adapter
  just pkg add js zod
  just pkg sync

Areas, public repos, hosts

  just area add server           # folder + AGENTS.md + BUCK
  just submodule add <url> [name]
  just ci sync                   # git/ci/github -> .github/workflows
  just agents sync               # root AGENTS.md + .agents/skills

Lua

  lua_library / lua_test / lua_binary / lua_bundle in BUCK files (@monomono//rules/lua:defs.bzl)
  just context feature test <p> <s> --steps     # bind bdd/*.feature in test/steps.lua -> <s>-gherkin target
  just lua repl | cover | profile | meta | fmt   # dev loop over the graph
  just lua trace | observe <feature target>     # span tree + OTLP trace.json; trace read back as Gherkin
  MONO_TELEMETRY_PROFILE=<module>               # your collector's span and attribute names
  just tool <name>                              # scripts/tools/<name>.sh or .lua
  scripts/hooks/pre-build.{sh,lua}              # runs before just build

The package

  just mono status
  just mono update [vX.Y.Z]      # bump packages/monomono, run migrations, sync
TXT
}

if [[ ${1-} == sdlc ]]; then
  sdlc
  exit 0
fi

(cd "$MONO_ROOT" && just --list --unsorted)
echo
sdlc
