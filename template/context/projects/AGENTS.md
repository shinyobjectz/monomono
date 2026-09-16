# Projects

A project is something you build or operate. Features live under the project they belong to.

```
context/projects/<project>/
  PROJECT.md              # front matter + short context. Under 200 lines.
  features/<slug>/
    feature.md            # front matter + context. Not the contract.
    bdd/*.feature         # the contract
    test/*.sh             # red until implemented; buck2 targets via BUCK
    BUCK
```

## Rules

- `just context project new <slug>`, then `just context feature new <project> <slug>`.
- Gherkin first. Then `just context feature test <project> <slug> <name>` for a red target. Then implement in `library/` or `app/`.
- Swap the generated `sh_test` for your language's test rule in the feature's `BUCK` when you have one. The spec does not care which.
- Slugs are kebab-case.
