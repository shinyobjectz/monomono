# Scripts

Backends for your own just recipes. The package's recipes live in `packages/monomono`; these are yours.

## Rules

- Three buckets only: `build/`, `tools/`, `update/`.
- `hooks/pre-build.{sh,lua}` runs before every `just build`; with no hook, `just build` is exactly `buck2 build //...`.
- `build/` is a bridge for steps buck2 cannot own yet. When a rule exists, move the step into a `BUCK` file and delete the script.
- `tools/` is one-shot helpers the CLI exposes. `update/` refreshes pins or generated stores.
- A script is `<name>.sh` or `<name>.lua`. Lua runs under `toolchains//:lua` with `scripts/lib/` and the `mono` stdlib on its path, so a consumer never has to write bash. Another language only when neither can do the job honestly.
- No markdown how-tos. Usage is `just --list` and the recipe comment.
