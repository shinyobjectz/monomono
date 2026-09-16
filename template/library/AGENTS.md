# Library

Shared code. One folder per domain. A domain is a boundary you would defend in review, not a language.

## Rules

- Each domain has a `library.md` (front matter for skill generation) and a `BUCK`.
- New code lands in the domain it belongs to, not in `app/` "for now".
- Consumers depend on targets, never on file paths across domains.
- Do not install dependencies here. `just pkg add`.
- Do not add a domain until two real modules have nowhere else to go.

```
library/<domain>/
  library.md      # name, description, summary, do, dont. Under 200 lines.
  BUCK
  ...
```
