# Git

How this repo talks to its host. Source of truth lives here; host-specific paths are generated copies.

## Rules

- `ci/github/` is the workflow source. `just ci sync` copies it to `.github/workflows` (GitHub does not follow symlinks there).
- `ci/local/check.sh` is the definition of green. CI and `just check` run the same thing.
- Secrets never live in the repo. Reference them by name in workflows; values stay in the host's secret store.
- Issue tracking is the host's job. Do not author a second tracker in the tree.
