# monomono

A domain-agnostic monorepo contract, delivered as a versioned package. Consumers attach this repo at `packages/monomono`, import `mono.just`, and get a `just` door, a buck2 build graph, an `AGENTS.md` contract, and a spec-first lifecycle, with no opinion about languages, vendors, or domains.

This file is the contract for working on monomono itself. `template/.agents/AGENTS.md` is the contract consumers get.

## Rules

- Presuppose nothing a consumer did not ask for. No language, vendor, cloud, framework, or domain name may appear in `template/`, `scripts/`, or `rules/` as a default. Toolchains are fragments the consumer adds; ecosystems are adapters the consumer picks.
- `template/` is the product. Files there are copied once by `mono init`, never overwritten. If a change needs to reach existing consumers, it is a migration in `migrations/<version>.sh`, not a template edit.
- `scripts/` is the package's behavior. Bash and awk only, `set -euo pipefail`, sourced `scripts/lib.sh`. No interpreter beyond a POSIX shell host is required; buck2's own `python_bootstrap` toolchain is the prelude's, not ours. Every script has a `just` route in `mono.just`.
- `rules/` is the `@monomono//` buck2 cell. `rules/defs.bzl` is macros over the bundled prelude. `rules/lua/` is the one set of real rules, because the prelude has no Lua and the graph for scripts is the point of the package. Add another rule family only when the prelude cannot express it.
- `toolchains/*.BUCK` are fragments. Each names a prelude system toolchain with the name the prelude expects.
- `adapters/*.sh` implement `ensure|add|update|sync` for one ecosystem, with `PKG_DIR` set. They shell out to that ecosystem's own client.
- Versions are semver tags `vX.Y.Z` matching `VERSION`. A breaking change to a consumer-owned file ships with a migration.
- This repo is its own first consumer for `just`: root `justfile` imports `mono.just` and `mono.toml` says `mode = "self"`. It is not a buck2 project root, because a nested cell may not carry its own `[cells]`; `just selftest` scaffolds a throwaway consumer and runs its `just check` instead.
- Only prose: `AGENTS.md`, `README.md`, and `LICENSE`. Usage is `just --list` and script headers.

## Folders

| Path | Owns |
| --- | --- |
| `install.sh` | Machine install: just, buck2, and the bootstrap under `~/.local/bin`. Standalone. |
| `bin/monomono` | Bootstrap. Attaches the package to a repo at `packages/monomono` and scaffolds it. Standalone. |
| `mono.just` | Recipes every consumer imports. |
| `scripts/` | Behavior behind those recipes. `lib.sh`, `build/`, `tools/`, `update/`. |
| `rules/` | Starlark macros, the `@monomono//` cell. |
| `toolchains/` | Toolchain fragments (`<name>.BUCK`). |
| `adapters/` | Package-ecosystem adapters. |
| `template/` | The consumer skeleton. |
| `migrations/` | `<version>.sh` scripts run in order on `just mono update`. |
| `test/` | `init.sh` scaffolds and checks a throwaway consumer. |

## Release

```
just selftest
just release X.Y.Z      # writes VERSION, commits, tags vX.Y.Z, pushes
```

Consumers move with `just mono update [vX.Y.Z]`.
