# ProjectOps

Declarative Kanban + Scrum automation for GitHub Projects v2. Issue events in,
board field updates out, driven by a YAML rules file rather than code.

Ships as a Python package, a CLI, and a composite action.

---

## Start here: pick your auth path

This decides everything else, so resolve it before writing any code.

| Your board is… | Use | Why |
| --- | --- | --- |
| Org-owned, public | GitHub App (`Organization projects: Read and write`) | Clean bot identity, short-lived tokens |
| Org-owned, private | Fine-grained PAT | Apps **cannot** read items in private Projects v2 |
| User-owned (any) | Classic PAT, `project` scope (+ `repo` if private repos) | App tokens cannot reach user projects |
| Anything | ~~`GITHUB_TOKEN`~~ | Repo-scoped; cannot touch Projects v2 at all |

The private-org-project limitation is structural: the `ProjectV2Actor` union
that defines project collaborators admits only `User` and `Team`. A GitHub App
bot cannot be added as a collaborator through the UI or the API, so `items`
returns `totalCount: 0` while the project's title and id resolve normally. That
silent-zero failure mode is why `projectops doctor` exists.

**Recommendation for a fresh repo:** create a free org, keep the board public
while you build, use a fine-grained PAT to get the logic working, then swap to
App auth as a separate, isolated change.

## Setup

```bash
pip install -e ".[dev,app]"

export PROJECTOPS_TOKEN=ghp_...
export GITHUB_REPOSITORY=your-org/your-repo

# Create the board in the GitHub UI first, then:
projectops doctor
```

`doctor` prints every field, its type, its options, and the current iteration.
Copy the real field names into `projectops.yml` — do not guess them.

Your board needs, at minimum:

- **Status** — single select: Backlog, Ready, In Progress, Blocked, Done, Cancelled
- **Sprint** — iteration field
- **Story Points** — number
- **Priority** — single select: P0…P3

For the Scrum hierarchy use repository/org **issue types** (Epic, Feature,
Story, Task) plus native **sub-issues**, rather than a label taxonomy. Both are
first-class in the API and survive board rebuilds.

## Usage

```bash
projectops sync --issue 42 --event opened --dry-run   # resolve, print, write nothing
projectops sync --issue 42 --event opened
projectops sprint-report
```

## Rules

Evaluated top to bottom; **last match wins**. Order general → specific.

```yaml
rules:
  - when: {event: opened}
    set: {Status: Backlog, Priority: P2}
  - when: {label: ready}
    set: {Status: Ready}
  - when: {event: closed, state_reason: COMPLETED}
    set: {Status: Done}
  - when: {any_label: [incident, sev1]}
    set: {Priority: P0, Status: In Progress}
```

Conditions: `event`, `label`, `any_label`, `issue_type`, `state`,
`state_reason`, `assigned`. All keys present must match.

## Testing this with Copilot CLI

The suite is green as shipped, so you have a baseline to detect regressions.

```bash
# 1. Plan mode — Shift+Tab, then:
"Read AGENTS.md. Add burndown reporting: a `burndown` CLI command that
 reports remaining points for the current iteration, plus a scheduled
 workflow posting it as a project status update. Ask before assuming
 field names."

# 2. Accept plan → autopilot + /fleet
```

Good `/fleet` candidates here — independent modules, bounded output:

- burndown query + CLI command + tests
- `ProjectV2` webhook handler for `projects_v2_item` events
- retry/backoff hardening in `graphql.py`
- `action.yml` input validation
- `doctor --json` for machine-readable output

Poor `/fleet` candidates — sequential, shared state:

- anything touching `fields.py` and `board.py` together
- auth refactors (one file, tightly coupled logic)

Remember `/fleet` multiplies token consumption roughly by subagent count.

Useful flags for the Actions path:

```bash
copilot -p "..." -s --allow-all-tools --allow-all-paths --no-ask-user \
        --agent projectops --model claude-sonnet-4.6
```

Node 22 is required, both `--allow-all-tools` and `--allow-all-paths` are
needed (tool consent and path consent are separate axes — miss either and the
CLI hangs waiting for input that never arrives on a headless runner), and point
`XDG_CONFIG_HOME` at `${{ runner.temp }}`.

## The agentic layer

For judgement calls this package deliberately does not make — story sizing,
bug-vs-feature classification, sprint summaries — use GitHub Agentic Workflows
rather than raw `copilot` in a step. Its agent runs read-only and buffers
writes through validated safe outputs, and it already has `update-project`,
`create-project-status-update`, `set-issue-field` and `link-sub-issue`.

```bash
gh extension install github/gh-aw
gh aw --help
```

Same token constraints apply — its convention is split
`GH_AW_READ_PROJECT_TOKEN` / `GH_AW_WRITE_PROJECT_TOKEN` secrets.

## Known limits

- Installation tokens expire after one hour; long runs must re-mint.
- No webhook handler yet — `projects_v2_item` events (someone dragging a card
  in the UI) are not observed, so board→issue sync is one-way.
- Sprint rollover reports but does not move incomplete items forward.

## Layout

```
src/projectops/     auth · graphql · fields · board · mapping · config · cli
.github/actions/    composite action
.github/workflows/  issue sync, sprint rollover
.github/agents/     Copilot CLI custom agent
AGENTS.md           repo context for coding agents
projectops.yml      board configuration
```
