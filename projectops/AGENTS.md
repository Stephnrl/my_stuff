# Repository context

ProjectOps automates a GitHub Projects v2 board from issue events. A Python
package does the deterministic work; an optional agentic layer handles the
judgement calls.

## Layout

| Path | Purpose |
| --- | --- |
| `src/projectops/auth.py` | PAT + GitHub App credential resolution |
| `src/projectops/graphql.py` | GraphQL transport, retries, error explanation |
| `src/projectops/fields.py` | Field/option/iteration node-id resolution |
| `src/projectops/board.py` | Board reads and writes |
| `src/projectops/mapping.py` | Declarative event → field-value rules |
| `src/projectops/config.py` | `projectops.yml` parsing |
| `src/projectops/cli.py` | `projectops` CLI |
| `.github/actions/projectops/` | Composite action wrapping the CLI |

## Domain facts that are easy to get wrong

1. **Projects v2 is owner-scoped, not repo-scoped.** A project URL is
   `/orgs/<login>/projects/N` or `/users/<login>/projects/N`. There is no
   repo-level project.
2. **Nothing is addressable by name.** Writing `Status = In Progress` needs
   the project id, the field id, *and* the single-select option id. Resolve
   the whole schema once per run (`fields.load_project`) — never per write.
3. **`GITHUB_TOKEN` cannot touch Projects v2 at all**, read or write.
4. **GitHub Apps cannot read items in private Projects v2.** The board's
   metadata resolves but `items` returns `totalCount: 0`, because the
   `ProjectV2Actor` union admits only `User` and `Team`, not `Bot`. Do not
   write code that "retries" past this — it is a platform limit.
5. **App tokens cannot reach user-owned projects.** Those need a classic PAT
   with `project` scope.
6. **GraphQL returns HTTP 200 with an `errors` array.** Never treat a 200 as
   success without checking `errors`.
7. **Iteration windows are half-open**: `[start, start + duration)`.
8. `LABELS`, `MILESTONE`, `ASSIGNEES` and `REPOSITORY` fields are derived from
   the issue and are not writable via `updateProjectV2ItemFieldValue`.

## Conventions

- Python ≥ 3.11, `from __future__ import annotations`, full type hints.
- No network in unit tests. Construct `Field` / `Project` / `Issue` directly.
- Errors must be actionable: say what failed *and* what to check. See
  `graphql._explain` for the standard this repo holds itself to.
- New rule conditions go in `mapping.Condition` **and** `config._CONDITION_KEYS`,
  or the config loader will reject them as unknown keys.

## Commands

```bash
pip install -e ".[dev,app]"
pytest                       # must stay green
ruff check src tests
projectops doctor            # prints live board schema; needs a token
projectops sync --issue 1 --event opened --dry-run
```
