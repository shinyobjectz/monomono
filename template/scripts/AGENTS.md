# Scripts

Backends for your own just recipes. The package's recipes live in `.mono`; these are yours.

## Rules

- Three buckets only: `build/`, `tools/`, `update/`.
- `build/` is a bridge for steps buck2 cannot own yet. When a rule exists, move the step into a `BUCK` file and delete the script.
- `tools/` is one-shot helpers the CLI exposes. `update/` refreshes pins or generated stores.
- Bash by default. Another language only when bash cannot do the job honestly.
- No markdown how-tos. Usage is `just --list` and the recipe comment.
