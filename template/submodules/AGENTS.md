# Submodules

Public or reusable repos attached as git submodules. Their own history, license, and `AGENTS.md`.

## Rules

- Add with `just submodule add <url> [name]`. Update with `just submodule update`. Never `git clone` by hand into this tree.
- No secrets or private-only pipelines here.
- Consume a submodule the way you consume a third-party package: through `packages/` or a buck2 target. Do not copy its source into `library/`.
- `.buckconfig` ignores this tree by default so foreign `BUCK` files do not join `//...`. Remove the ignore per submodule when you want its targets.
