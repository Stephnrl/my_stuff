---
name: board-ops
description: Use when working with the team's GitHub Projects v2 board — triaging the inbox, checking board health, grooming the backlog, running standup, finding what's at risk this sprint, moving items between statuses, sizing or labeling issues, converting drafts to issues, or answering questions about what the team is working on. Also use for any request mentioning the board, the sprint, the backlog, WIP, or Scrumban.
license: MIT
---

# Board operations

Operate the team's Projects v2 Scrumban board. Treat this as ops work: read
first, show the change, get approval, then act.

## Configuration

Read `~/.copilot/board.env` for `ORG` and `PROJECT_NUMBER`. If that file is
missing, run `scripts/setup.sh` and tell the user to fill it in — do not guess
the org or project number.

## Hard rules

1. **Never write without showing the exact command first.** Print the
   `gh api graphql` call, wait for approval, then run it. Every field update,
   label change, and comment.
2. **Never modify more than 5 items in one action** without showing the full
   list and getting a yes.
3. **Never close an issue.** Propose it; closing is the user's.
4. **Never invent a status, label, or field value.** Read real options from
   `~/.copilot/board-ids.json`. If a value doesn't exist, say so instead of
   picking the nearest match.
5. **On GraphQL `errors`, stop and show the raw error.** Do not retry with a
   modified query hoping something sticks.
6. **Paginate fully before reporting counts.** A number from a partial fetch is
   worse than no number.

## Projects v2 is GraphQL-only

Do not use MCP or built-in project tools — they target Projects Classic and 404
against v2. Always go through `gh api graphql`. Issues, labels, and PRs are fine
via `gh issue` / `gh pr`.

If calls return empty data rather than an error, the cause is almost always one
of: missing scope (`gh auth refresh -s project,read:project`), SAML SSO not
authorized for the org, or the project being user-owned rather than org-owned.
Check in that order.

## Before any write session

Ensure `~/.copilot/board-ids.json` exists and is under a week old:

```bash
bash scripts/board-ids.sh
```

Mutations need node IDs, not names. Read them from that file rather than
re-querying each time.

## Scripts

- `scripts/setup.sh` — one-time: create `board.env`, check scopes, find the
  project number
- `scripts/board-ids.sh` — cache project, field, option, and iteration IDs
- `scripts/board-fetch.sh` — paginated dump of every item as JSON
- `scripts/board-health.sh` — read-only invariant checks, prints findings

Prefer running these over retyping queries inline. If a script doesn't cover
what's needed, the raw queries are in `references/graphql.md`.

## References

- `references/graphql.md` — canonical queries and mutations
- `references/vocabulary.md` — what our statuses and labels actually mean.
  **Read this before assessing anything.** Do not substitute a generic notion
  of a well-formed ticket for the team's definitions.

## Tasks

**"Triage the inbox"** — find issues labeled `needs:triage`. Read each body.
Propose a `type:` label, an `area:` label, and a verdict on whether it meets the
Definition of Ready. Present as a table with issue URLs. Apply only what's
approved. Do not propose priority or assignee — those are judgment calls the
team makes together.

**"Board health"** — run `scripts/board-health.sh` and interpret the output.
Report only failures, worst first. Do not summarize what's fine.

**"What's at risk"** — items in the current iteration, not Done, showing any of:
no assignee, no activity past the state's threshold, Blocked, or In Review with
no open PR. Rank by likelihood of slipping and say why for each. Three real
risks beats twelve hedged ones.

**"Groom"** — walk the backlog top-down against the Definition of Ready in
`references/vocabulary.md`. For each failing item, name specifically what's
missing. Don't rewrite the items; report what needs answering.

**"Standup"** — what moved since yesterday, what's stuck, what's newly blocked.
Terse, no preamble.

**"Write up <thing>"** — turn a rough description into a proper issue body:
outcome, context, acceptance criteria, out of scope. Ask the questions needed
rather than inventing details. Show the draft before creating anything.

## Output style

Be blunt about board problems. If the board is a mess, say so and name the three
worst things. No congratulatory summaries.

Tables for lists of items, one line each, always with the issue URL. No emoji.

When board data can't answer a question, say what's missing. "Nothing records
why this is blocked" is useful; an invented plausible reason is not.
