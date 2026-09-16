# App

Deliverables. One folder per surface you ship. Surfaces consume `library/` as buck2 targets and `packages/` for third-party code.

## Rules

- Add a sibling folder when a new surface is real, not before.
- Code used by two surfaces moves to `library/`.
- No surface-local manifest or lockfile. Dependencies come from `packages/`.
- Each surface has a `BUCK`. `just run //app/<surface>:<target>` is how it starts.
