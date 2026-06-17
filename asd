# Multi-Zone ACR Image Build — Standardization Plan

## Goal

Turn the existing three-zone (A/B/C) proof of concept into a reusable, opinionated
standard that multiple teams can adopt **without learning ACR task files or `az acr run`**.
Teams should bring only what they already understand — a Dockerfile and a few inputs —
while the platform team owns and enforces the build/scan/promote logic centrally.

## Core Principle

The interface teams consume is **GitHub Actions**. The ACR task YAML and `az acr run`
invocation are private implementation details owned by the platform team and never exposed.

- Teams provide: a Dockerfile + inputs (image name, tag, build args, dockerfile path).
- Platform owns: task definitions, scan gates, tagging conventions, base images,
  agent-pool selection, CA bundle / JFrog mirror config, promotion/dispatch.
- Enforceability is the payoff: gates live in the shared workflow, not in team hands,
  so they cannot be bypassed.

## Current State

- Three zones in the PoC:
  - **Zone A** — ACR task (`build:` + `push:` YAML) on the **public** agent pool. Builds a
    bootstrap image (no company data), pushes to ACR, then runs a security gate
    (Trivy + SBOM + POAM scan).
  - **Zone B** — ACR task on the **internal** agent pool. Builds the internal image
    (CA bundle, JFrog mirror, etc.) from the bootstrap.
  - **Zone C** — downstream deployment via GitHub `repository_dispatch`.
- A `ci-templates` repo already exists with composite actions (security gate,
  repository dispatch) that can be sourced.
- Task files are currently hand-authored by the platform owner — the adoption blocker.

## Target Architecture

### 1. Reusable workflow as the golden path
Promote the A→B→C orchestration from composite actions to a **reusable workflow**
(`on: workflow_call`).

Rationale: composite actions cannot span multiple jobs, select different runners per
stage, or express job dependencies. The public-pool (A) vs internal-pool (B) split with a
gate in between is naturally separate jobs with `needs:` — i.e., reusable-workflow territory.

### 2. Composite actions as building blocks
Keep `security-gate`, `repository-dispatch`, and the build steps as composite actions
*inside* the reusable workflow. They remain individually consumable for teams that need to
deviate from the golden path.

### 3. Parameterized, platform-owned task files
Maintain **one canonical task file per zone**, templated with `{{ .Values.x }}` and
overridden at runtime with `--set key=value` (and `--set-secret` for secrets).
Teams pass values as action inputs; they never see or edit the YAML.

### 4. `az acr build` vs `az acr run`
- **Pure build + push legs (e.g., Zone A bootstrap):** use `az acr build` directly — no
  task file needed. Pass `-t`, `--build-arg`, `--agent-pool` on the CLI.
- **Multi-step legs (security gate combos, Zone B internal build, conditional/dependency
  flows):** use `az acr run` + the platform task YAML.
- Note: when run through Azure, only tasks (`az acr run -f`) support value templating;
  `az acr build` renders run variables only. That's fine — the simple legs don't need
  `.Values` because args are passed on the CLI.

## Key Implementation Detail — Single-Context Handling

`az acr run` takes exactly **one** context, and `-f` is resolved relative to that context's
root. The platform task file must therefore live *inside the team's build context at
runtime*.

Solution: the composite action **injects** the platform task file into the team's
checked-out source before invoking the run. This resolves the "central task file +
per-team source" tension cleanly.

```bash
# inside the platform composite action
cp "$GITHUB_ACTION_PATH/tasks/bootstrap-build.yaml" ./acr-task.yaml
az acr run -r "$REGISTRY" --agent-pool "$AGENT_POOL" \
  -f acr-task.yaml . \
  --set image="$IMAGE" \
  --set tag="$TAG" \
  --set dockerfile="$DOCKERFILE"
```

## Task File Distribution

**Default: bundle task files in `ci-templates`** alongside the actions.
- Versioning is unified — a single `@v1` pin covers both action logic and task definitions.
- Every change goes through PR review, which is what a security-bearing standard needs.

**OCI artifact distribution (deferred / optional):** justified only if
- the internal Zone B pool should source task defs registry-natively without reaching
  GitHub, or
- there will be non-GitHub consumers (Azure DevOps, manual `az acr run`) of the same files.

Otherwise it's an extra moving part to govern with no current benefit.

## What Teams Write

```yaml
jobs:
  ship:
    uses: myorg/ci-templates/.github/workflows/secure-image.yml@v1
    with:
      image: payments-api
      dockerfile: ./Dockerfile
      build-args: |
        FOO=bar
    secrets: inherit
```

Behind that single pinned reference: public bootstrap build → Trivy/SBOM/POAM gate →
internal build on the locked-down pool → Zone C dispatch.

## Example Platform-Owned Task File

`tasks/bootstrap-build.yaml`:

```yaml
version: v1.1.0
steps:
  - build: -t {{.Run.Registry}}/{{.Values.image}}:{{.Values.tag}} -f {{.Values.dockerfile}} .
  - push: ["{{.Run.Registry}}/{{.Values.image}}:{{.Values.tag}}"]
```

## Design Decisions Summary

| Decision | Choice | Why |
|---|---|---|
| Team-facing interface | GitHub Actions only | Teams know Actions + Dockerfiles, not task files |
| Orchestration unit | Reusable workflow (`workflow_call`) | Spans jobs/runners + dependencies; composite actions can't |
| Reusable parts | Composite actions inside the workflow | Composable, individually sourceable |
| Task authoring | One parameterized file per zone, `--set` values | Platform owns logic; teams pass inputs |
| Simple build legs | `az acr build` (no YAML) | Simplest; no templating needed |
| Multi-step legs | `az acr run` + task YAML | Needs `.Values` templating + multi-step flow |
| Task-file + source context | Action injects YAML into team context | `az acr run` allows only one context |
| Task-file distribution | Bundle in `ci-templates` | Unified versioning + PR governance |
| OCI artifact distribution | Deferred | Only if Zone B isolation or non-GitHub consumers require it |

## Suggested Next Steps

1. Author `secure-image.yml` reusable workflow wiring Zones A/B/C with per-job agent-pool
   selection and the gate as a `needs:` dependency between A and B.
2. Refactor the existing security-gate and repository-dispatch composite actions to be
   called from the reusable workflow.
3. Create the canonical per-zone task files in `ci-templates/tasks/` and implement the
   inject-then-run pattern in the build composite action.
4. Convert the Zone A bootstrap build to `az acr build` if it is build+push only.
5. Define the input contract (image, tag, dockerfile, build-args, etc.) and document it as
   the single thing teams must provide.
6. Pin a `v1` release tag so teams adopt a stable, versioned standard.
