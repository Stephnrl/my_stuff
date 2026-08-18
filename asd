# Container Security Gate

A modular security gate for container image pipelines in Azure Government.
Teams build however they want; the gate scans, maintains a POA&M with real
diff history, applies centrally-approved deviations, and enforces policy.

## The contract

The gate needs exactly two things:

| Input | What it is | Why |
|---|---|---|
| `image_ref` | Digest-pinned reference (`registry/repo@sha256:…`) | Immutable and unambiguous. Every build tool — ACR Tasks, `docker build`, buildkit, kaniko — ends at a digest. |
| `component_id` | Stable identity, e.g. `myorg/platform/api` | POA&M continuity across releases. **Never** the version tag. |

Everything else is optional. This split is what makes the gate work for a team
using `1.4.2-20260816120000-a3f9c1` and a team using `:latest` at the same time.

> **If you key POA&M history on the tag, every release produces a brand-new
> POA&M and the diff never matches anything.** That is the single mistake this
> design exists to prevent.

Initial-vs-recurring is **derived** from whether state exists, never taken as
an input — teams get that wrong or misreport it.

## How teams hook in

Three surfaces, one implementation:

1. **Reusable workflow** (`.github/workflows/gate.yml`) — the primary path. Own
   job, own runner, and enforceable via repository rulesets. Without a ruleset
   you have built a library, not a gate.
2. **Composite action** (`action.yml`) — for teams needing the scan inside their
   own job. The reusable workflow just calls this.
3. **CLI** (`python -m poam gate`) — for non-GitHub runners or local debugging.

See `examples/` for all three.

## What it does

```
build (any tool) ──▶ digest ──▶ trivy scan ──▶ normalize
                                                  │
                        prior POA&M state ────────┤
                                                  ▼
                                             reconcile
                                    NEW / CLOSED / REOPENED / PERSISTING
                                                  │
                              central exceptions ─┤
                                                  ▼
                                          policy evaluation
                                                  │
                            ┌─────────────────────┼──────────────────┐
                            ▼                     ▼                  ▼
                      POA&M xlsx            gate decision      telemetry
                      + SBOM + state         pass/fail        Log Analytics
```

**JSON is the source of truth; the xlsx is a render.** Nothing ever parses a
workbook back. Round-tripping through Excel loses types and merged-cell
structure and will eventually corrupt the audit trail.

## Diff semantics

Finding identity is `sha256(vuln_id | pkg_name | normalized_target)`, which
deliberately **excludes the installed version**. Bumping openssl 3.0.1 → 3.0.2
while the CVE persists keeps the same POA&M ID and the same remediation clock.

|  | in current scan | absent from current scan |
|---|---|---|
| **prior, open** | `PERSISTING` — refresh version, keep due date | `CLOSED` — stamp `closed_date` |
| **prior, closed** | `REOPENED` — bump counter, same POA&M ID | stays closed |
| **not in prior** | `NEW` — assign ID, set due date | — |

Rows are never deleted. Severity reclassification is tracked separately and
re-derives the due date from the **original** detection date, so an escalation
tightens the deadline rather than granting a fresh window.

## Exceptions

Deviations live in a **central, security-owned repo**, never in the team's own
repository. They are applied *after* the scan, to the POA&M records.

The gate never passes `--ignorefile` to Trivy. Suppression at scan time deletes
the finding from the output entirely and it never reaches the POA&M — an
assessor wants deviations *documented*, not disappeared. An excepted finding
still appears, marked `Open - Risk Adjusted`; it just stops counting.

Expiry is enforced, and expired entries fail closed.

## Emergency bypass

A GitHub **Environment** (`security-gate-bypass`) with required reviewers, not a
workflow input. The environment records approver identity and timestamp
natively. A bypass requires written justification, lands in the POA&M, and
fires a high-priority alert. A quiet bypass becomes the default path within a
quarter.

## Azure Government gotchas

**Trivy DB mirroring is the hardest dependency.** Gov-boundary runners generally
cannot reach `ghcr.io`. `mirror-trivy-db.yml` copies both databases into ACR via
ORAS every 4 hours. The gate refuses to run against a DB older than
`max_db_age_hours` — a silently stale DB is a gate that passes everything, which
is worse than a gate that fails loudly.

**POA&M content is CUI.** It is an enumerated list of your exploitable
weaknesses. Keep it on Gov-boundary runners, behind a private endpoint, with
shared keys disabled. `upload_artifacts` defaults to `false`; GitHub artifact
retention is also far too short for an audit record.

**Scans are not reproducible across days by design.** The DB refreshes every
~6 hours, so the same digest scanned twice legitimately yields different
results. Trivy version and DB timestamp are recorded on every POA&M — that
metadata is your answer when a team reports it as a bug.

## Deploying

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit
terraform init -backend-config=backend.hcl
terraform validate    # run this — it was not run for you
terraform plan
```

Provider is pinned to `environment = "usgovernment"` with `use_oidc = true`.
Nothing creates an ACR; the only ACR interaction is an additive diagnostic
setting feeding the coverage-gap alert.

Wire the outputs into GitHub org/repo variables:

```bash
terraform output -json github_variables
```

## Alerting

Nine rules in `terraform/alerts.tf`. The two that matter most detect the
**absence** of signal:

- **Coverage gap** — joins ACR push events against gate events and flags any
  digest that reached the registry without being gated. Everything else only
  fires when the gate ran, so this is what catches the team that quietly
  stopped calling the workflow.
- **Component went quiet** — a previously-active component that stopped being
  scanned.

Plus: bypass used, new critical, regression, deviations expiring, overdue
items, stale vulnerability DB, and DB-mirror heartbeat missing.

## Rollout sequence

Do not start with enforcement.

1. **Mirror the DB first** and let it run for a few days. Everything depends on it.
2. **Run every team on `observe`** for 2–4 weeks. Full POA&M, full history, zero
   build failures. This surfaces the real backlog so you negotiate the
   enforcement date from evidence rather than a guess.
3. **Turn on the coverage alert** before enforcement, so you know your actual
   denominator.
4. **Move to `standard`**, then `fedramp-moderate` per component.
5. **Add the ruleset** to make the gate non-optional.
6. **Then** consider signed attestations + admission control (see below).

## Testing

```bash
pip install -r requirements.txt pytest
python -m pytest tests/ -v          # 28 tests, covers the state machine
```

Local dry run, no Azure needed:

```bash
python -m poam gate \
  --trivy-json scan.json \
  --component-id org/team/app \
  --image-ref "registry/app@sha256:$(printf 'a%.0s' {1..64})" \
  --store local://./.gate-state \
  --out-dir ./out --no-telemetry
```

Lint the exception store in CI:

```bash
python -m poam validate-exceptions --exceptions exceptions/
```

## Phase 2

Have the gate emit a signed attestation (cosign with Key Vault KMS — keyless
Fulcio will not work in Gov) and attach SBOM + scan results to the image as OCI
referrers in ACR. Then admission control via Ratify/Gatekeeper refuses any image
lacking a passing gate attestation. That moves you from "CI checked it" to "the
cluster will not run it", which no one can route around.

## Not verified here

- `terraform validate` / `plan` — no Terraform binary was available. Structural
  and variable-reference checks passed; run the real thing before applying.
- Live Azure calls — blob ETag concurrency and the Logs Ingestion path are
  written against the documented APIs but untested against a real subscription.
- **Confirm DCR / Logs Ingestion API availability in your Gov region.** Azure
  Monitor features reach Government after commercial, and this is the component
  most likely to be missing.
- SLA day counts in `fedramp-moderate.yaml` are a starting point. Confirm
  against your SSP and your 3PAO.
