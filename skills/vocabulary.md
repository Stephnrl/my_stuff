# Vocabulary

These are the team's definitions. Apply them literally. Do not substitute a
generic notion of a well-formed ticket, and do not soften a verdict because an
item is close.

**Edit this file after every retro.** It's the closest thing the team has to a
written process, and it's what makes agent assessments match human ones.

## Statuses

**Backlog** — exists, not committed. May be unordered and underspecified. No
expectations attached. Nothing in Backlog is late.

**Ready** — meets the Definition of Ready below. Anyone on the team could pick it
up cold, today, without asking a question first.

**In Progress** — someone is actively working it. Team WIP limit is 8. Over that,
say so; finishing beats starting.

**In Review** — a PR is open. Past 2 days here is a smell worth naming.

**Blocked** — waiting on something external. Must carry the `blocked` label and a
comment saying what it's waiting on and who owns unblocking it. An unexplained
Blocked is worse than an honest one — always flag it.

**Done** — merged and verified. Not "the PR is up." Not "it works locally."

## Definition of Ready

An item is Ready only if all four hold:

1. **Clear outcome** — states what will be true when it's finished, not what
   activity will happen.
2. **Acceptance criteria** — someone other than the author could tell whether
   it's done.
3. **No open questions** — nothing is waiting on a decision, an answer, or
   someone else's design.
4. **Sized** — has an Estimate. Not for velocity; for spotting the items nobody
   understands well enough to size.

If an item fails any of these, it is not Ready. Name which one it failed and
what specifically is missing.

## Definition of Done

- Merged to the default branch
- Acceptance criteria demonstrably met
- Tests passing, and new behavior has a test
- Anything operational (runbook, alert, dashboard) updated if the change touches
  production behavior

## Labels

`type:` — mechanical, propose freely
: `bug`, `feature`, `chore`, `toil`, `incident`

`area:` — mechanical, derived from the source repo, propose freely

`needs:` — workflow markers
: `triage` (not yet assessed), `info` (waiting on the reporter)

`blocked` — required whenever Status is Blocked

## Judgment vs mechanics

**Mechanical** — facts about the item. Propose freely, apply on approval:
type, area, needs:triage, needs:info, blocked.

**Judgment** — decisions the team makes: priority, estimate, assignee, sprint
inclusion. Propose only when asked. Never apply unprompted. Sprint commitment in
particular is a human act; a sprint nobody chose is a sprint nobody owns.

## Cadence

Two-week iterations. Two ceremonies:

- **Planning** — pull from the top of the backlog until it feels full. Say out
  loud what "full" means this time.
- **Retro** — one honest conversation, one change. Update this file with it.

Standup is optional when the board is accurate.

## Thresholds

| Signal | Threshold |
|---|---|
| WIP (In Progress, team-wide) | 8 |
| Stale in In Progress | 5 days |
| Stale in In Review | 2 days |
| Blocked without update | 3 days |
| Stranded draft item | 14 days |
| Untriaged backlog size | 10 → mention it at grooming |
