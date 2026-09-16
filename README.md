# monomono

A monorepo contract you attach, not a template you fork.

monomono gives a repo four things and takes no opinion about anything else: a `just` door, a buck2 build graph, an `AGENTS.md` contract, and a spec-first lifecycle. No language, vendor, cloud, framework, or domain is assumed. Toolchains are declared one at a time. Package ecosystems are adapters you pick. Domains are folders you name.

It is delivered as a versioned package. Consumers pin a release at `.mono`, import its recipes, and move forward with `just mono update`.

## Attach it

```
curl -fsSL https://raw.githubusercontent.com/shinyobjectz/monomono/main/bin/monomono | bash -s -- init
just setup
just check
```

`init` adds this repo as a git submodule at `.mono` pinned to the latest tag, copies the skeleton once (never overwriting), links `AGENTS.md`, and writes `mono.toml`. `--vendor` copies instead of submoduling. `--ref vX.Y.Z` pins a version.

## What a consumer looks like

```
justfile             import '.mono/mono.just' plus your own recipes
mono.toml            pinned version, mode, modules
AGENTS.md            -> .agents/AGENTS.md, the repo contract (yours)
CLAUDE.md            Claude Code bootstrap
.buckroot .buckconfig BUCK
toolchains/BUCK      genrule, python_bootstrap, test. Nothing else until you add it.
app/                 deliverables
library/             shared code, one folder per domain
packages/<eco>/      third-party manifests and lockfiles, behind an adapter
context/             sqlite junk drawer + projects/<p>/features/<f>/{bdd,test,BUCK}
scripts/             your just backends: build/ tools/ update/
git/ci/              CI source; .github/workflows is a generated copy
submodules/          public repos as git submodules
.agents/             standing rules and generated skills
.mono/               this package
```

Every folder carries an `AGENTS.md` with its rules. Agents read the root contract first and the nested one before editing a tree.

## The door

```
just                       list recipes
just setup | doctor | check
just build | test | run | targets           buck2
just toolchain available | add rust          compose toolchains/BUCK from fragments
just pkg init js bun; just pkg add js zod    ecosystem adapters (bun, npm, cargo, uv, mix, go)
just context project new x                   then feature new, check, test
just area add server                         folder + AGENTS.md + BUCK
just submodule add <url>
just agents sync                             root AGENTS.md link + .agents/skills
just ci sync | run
just mono status | update [vX.Y.Z]
```

`just check` is the definition of green: doctor, Gherkin and front-matter checks (bash and awk, no interpreter needed), `buck2 build //...`, `buck2 test //...`. CI runs the same script.

## Buck2

The consumer is the buck2 project root. `.buckconfig` declares the bundled prelude, `toolchains//`, and `monomono//` (this package as a cell). `toolchains/BUCK` starts with the three toolchains needed to run a genrule and a test, and `just toolchain add <name>` appends a fragment for cxx, python, rust, go, haskell, or ocaml, hoisting `load()` lines to the top. Feature tests are `sh_test` targets under `context/`, so the lifecycle is enforced by the same graph that builds the product. Swap the generated `sh_test` for your language's test rule when you have one.

`@monomono//rules:defs.bzl` exposes small macros: `mono_check` (a shell test from the repo root), `mono_script` (a runnable), `mono_feature_tests` (one target per test file plus a suite).

## Versioning

Releases are semver tags. `mono.toml` records the version a consumer is on. `just mono update [ref]` moves `.mono` to the tag, runs every `migrations/<version>.sh` between the old and new version in order, adds template files that did not exist before, resyncs generated files, and stages the result. Consumer-owned files (`AGENTS.md`, `justfile`, `BUCK`, folder rules) are never overwritten; a change that must reach them ships as a migration.

## Develop

```
just selftest       scaffold a throwaway consumer from this checkout and run its just check
just release X.Y.Z  VERSION, commit, tag, push
```

Rules for this repo are in `AGENTS.md`. The one that matters most: presuppose nothing a consumer did not ask for.

## Lineage

Extracted from [Jetway](https://github.com/content-jet/jetway), ContentJet's application monorepo, by removing everything that was about ContentJet.

MIT.
