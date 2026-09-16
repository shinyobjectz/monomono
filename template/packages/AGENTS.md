# Packages

The only place a third-party ecosystem may create a manifest or lockfile.

## Rules

- `packages/monomono` is the package itself, pinned to a release. Read-only; `just mono update` moves it.
- One folder per ecosystem: `packages/<eco>`. `just pkg init <eco> <adapter>` marks it; `.eco` names the adapter.
- Add, update, and install through `just pkg …`. Never run an installer in a leaf folder.
- Shipped adapters: `just pkg adapters`. A local `adapter.sh` in the folder overrides them (`ensure|add|update|sync`).
- Expose third-party code to the build as buck2 targets in `packages/<eco>/BUCK`. Areas depend on those targets.
- Do not commit secrets, tokens, or host-specific absolute paths.
