# Context

Knowledge that is not code. Two stores, two jobs. Do not invent a third (no `docs/`, no stray READMEs).

## Rules

- If the impulse is "write a markdown file", write a record into `dump/` instead: `just context put <volume> --title "..." [body]`.
- `AGENTS.md`, Gherkin `.feature`, `feature.md`, and `PROJECT.md` are the only markdown this tree allows.
- Read before you write. `just context get <query>` and the feature folder, so you do not duplicate a note or a spec.

| Path | Write when | Shape |
| --- | --- | --- |
| `dump/` | a thought, scrape, decision, quote, link, research dump | SQLite volumes and records |
| `projects/` | a project you build, plus its features | `projects/<slug>/PROJECT.md` and `features/<slug>/` |

A note that hardens into a requirement moves into Gherkin; leave a pointer row in the dump. Do not keep two living specs.
