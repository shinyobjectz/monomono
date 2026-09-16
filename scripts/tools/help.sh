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
  just pkg init js bun           # packages/js managed by the bun adapter
  just pkg add js zod
  just pkg sync

Areas, public repos, hosts

  just area add server           # folder + AGENTS.md + BUCK
  just submodule add <url> [name]
  just ci sync                   # git/ci/github -> .github/workflows
  just agents sync               # root AGENTS.md + .agents/skills

The package

  just mono status
  just mono update [vX.Y.Z]      # bump .mono, run migrations, sync
TXT
}

if [[ ${1-} == sdlc ]]; then
  sdlc
  exit 0
fi

(cd "$MONO_ROOT" && just --list --unsorted)
echo
sdlc
