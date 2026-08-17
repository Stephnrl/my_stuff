"""Gate entrypoint.

    python -m poam gate \
      --trivy-json scan.json \
      --component-id org/repo/api \
      --image-ref myacr.azurecr.us/team/api@sha256:... \
      --image-tag v1.4.2 \
      --policy policies/fedramp-moderate.yaml \
      --exceptions exceptions/ \
      --store az://sagatestate/poam \
      --environment usgovernment \
      --out-dir ./out

Exit codes:
  0  gate passed (or passed with bypass)
  1  gate failed on policy
  2  operational error (bad input, unreachable store, invalid exceptions)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

from . import diff as diff_mod
from . import normalize, policy as policy_mod, render, store as store_mod, telemetry
from .models import ScanMeta, today_iso, utc_now_iso

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_ERROR = 2


def _gh_output(**kwargs: Any) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as fh:
        for key, value in kwargs.items():
            if isinstance(value, bool):
                value = "true" if value else "false"
            fh.write(f"{key}={value}\n")


def _gh_summary(markdown: str) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        print(markdown)
        return
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(markdown + "\n")


def _build_summary_md(meta: ScanMeta, summary: dict, decision: Any, uris: dict) -> str:
    icon = {"pass": "✅", "fail": "❌", "pass_with_bypass": "⚠️"}.get(decision.result, "❔")
    lines = [
        f"## {icon} Security Gate — `{meta.component_id}`",
        "",
        f"**Result:** `{decision.result.upper()}`  |  "
        f"**Scan type:** {'Initial' if meta.is_initial_scan else 'Recurring'}  |  "
        f"**Digest:** `{meta.image_digest[:19]}…`",
        "",
        "| | New | Closed | Reopened | Carried | Overdue |",
        "|---|---|---|---|---|---|",
        f"| Findings | {summary.get('new', 0)} | {summary.get('closed', 0)} | "
        f"{summary.get('reopened', 0)} | {summary.get('persisting', 0)} | "
        f"{summary.get('overdue_count', 0)} |",
        "",
        "**Open by severity (excluding approved deviations)**",
        "",
        "| Critical | High | Medium | Low |",
        "|---|---|---|---|",
    ]
    g = summary.get("gating_by_severity", {})
    lines.append(f"| {g.get('CRITICAL', 0)} | {g.get('HIGH', 0)} | {g.get('MEDIUM', 0)} | {g.get('LOW', 0)} |")
    lines.append("")

    if decision.bypass_used:
        lines += [
            "> ### ⚠️ EMERGENCY BYPASS USED",
            f"> **Approved by:** {decision.bypass_actor}",
            f"> **Justification:** {decision.bypass_reason}",
            "> This is recorded in the POA&M and has alerted the security team.",
            "",
        ]

    if decision.violations:
        lines += [f"### Gate violations ({len(decision.violations)})", ""]
        lines += ["| Rule | POA&M ID | CVE | Severity | Package | Installed | Fixed In | Due |", "|---|---|---|---|---|---|---|---|"]
        for v in decision.violations[:40]:
            lines.append(
                f"| {v['rule']} | {v['poam_id']} | {v['vuln_id']} | {v['severity']} | "
                f"{v['pkg_name']} | {v['installed_version']} | {v['fixed_version'] or '—'} | "
                f"{v['scheduled_completion_date'] or '—'} |"
            )
        if len(decision.violations) > 40:
            lines.append(f"| … | _{len(decision.violations) - 40} more — see the POA&M_ | | | | | | |")
        lines.append("")

    if decision.warnings:
        lines += ["### Warnings", ""] + [f"- {w}" for w in decision.warnings[:20]] + [""]

    lines += [
        "### Artifacts",
        "",
        f"- POA&M: `{uris.get('poam', 'n/a')}`",
        f"- SBOM: `{uris.get('sbom', 'n/a')}`",
        f"- State: `{uris.get('state', 'n/a')}`",
        "",
        f"<sub>Trivy {meta.trivy_version} · DB updated {meta.vuln_db_updated_at or 'unknown'} · "
        f"policy `{meta.policy_profile}` (`{meta.policy_sha}`) · gate `{meta.gate_version}`</sub>",
    ]
    return "\n".join(lines)


def cmd_gate(args: argparse.Namespace) -> int:
    started = time.monotonic()

    try:
        report = normalize.load_report(args.trivy_json)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"::error::Cannot read Trivy report {args.trivy_json}: {exc}")
        return EXIT_ERROR

    pol = policy_mod.load_policy(args.policy)
    pol_sha = policy_mod.policy_fingerprint(pol)

    findings = normalize.findings_from_trivy(
        report,
        severity_source=pol.get("severity_source", "vendor"),
        ignore_unfixed=bool(pol.get("ignore_unfixed", False)),
    )

    digest = args.image_digest or normalize.digest_from_ref(args.image_ref)
    if not digest:
        print("::error::No image digest. Pass a digest-pinned --image-ref or an explicit --image-digest.")
        return EXIT_ERROR

    store = store_mod.build_store(args.store, environment=args.environment)

    exceptions, exc_errors = policy_mod.load_exceptions(args.exceptions or [])
    if exc_errors:
        for e in exc_errors:
            print(f"::error::Invalid exception entry: {e}")
        if not args.allow_invalid_exceptions:
            print("::error::Refusing to run with malformed exception files (fail closed).")
            return EXIT_ERROR

    meta = ScanMeta(
        component_id=args.component_id,
        image_ref=args.image_ref,
        image_digest=digest,
        image_tag=args.image_tag or "",
        trivy_version=args.trivy_version or "",
        vuln_db_updated_at=args.db_updated_at or "",
        vuln_db_next_update=args.db_next_update or "",
        policy_profile=pol.get("name", Path(args.policy).stem if args.policy else "default"),
        policy_sha=pol_sha,
        gate_version=args.gate_version or "",
        run_id=os.environ.get("GITHUB_RUN_ID", ""),
        run_url=(
            f"{os.environ.get('GITHUB_SERVER_URL', '')}/{os.environ.get('GITHUB_REPOSITORY', '')}"
            f"/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"
            if os.environ.get("GITHUB_RUN_ID")
            else ""
        ),
        repository=os.environ.get("GITHUB_REPOSITORY", ""),
        actor=os.environ.get("GITHUB_ACTOR", ""),
        git_sha=os.environ.get("GITHUB_SHA", ""),
    )

    captured: dict[str, Any] = {}

    def mutate(doc: store_mod.StateDocument):
        # Initial vs recurring is DERIVED from state, never taken as an input.
        meta.is_initial_scan = doc.scan_count == 0
        result, next_seq = diff_mod.reconcile(
            findings,
            doc.records,
            meta,
            sla_days=pol.get("severity_sla_days"),
            next_seq=doc.next_seq,
            reset_sla_on_reopen=bool(pol.get("reset_sla_on_reopen", True)),
        )
        exc_report = policy_mod.apply_exceptions(
            result.all_records, exceptions, args.component_id, pol
        )
        doc.records = result.all_records
        doc.next_seq = next_seq
        doc.scan_count += 1
        doc.last_updated = utc_now_iso()
        doc.last_scan = {
            "timestamp": meta.scan_timestamp,
            "digest": digest,
            "tag": meta.image_tag,
            "trivy_version": meta.trivy_version,
            "db_updated_at": meta.vuln_db_updated_at,
            "policy_sha": pol_sha,
            "run_id": meta.run_id,
        }
        captured["diff"] = result
        captured["exc_report"] = exc_report
        return doc, result

    try:
        doc, result, state_uri = store_mod.with_concurrency_retry(
            store, args.component_id, mutate, max_retries=args.max_retries
        )
    except Exception as exc:
        print(f"::error::Failed to commit POA&M state: {exc}")
        return EXIT_ERROR

    exc_report = captured["exc_report"]
    for rejected in exc_report.get("rejected", []):
        print(f"::warning::Exception rejected: {rejected}")
    for expired in exc_report.get("expired", []):
        print(f"::warning::Exception expired and no longer suppressing: {expired}")

    decision = policy_mod.evaluate(
        result,
        pol,
        bypass=args.bypass,
        bypass_reason=args.bypass_reason,
        bypass_actor=args.bypass_actor or os.environ.get("GITHUB_ACTOR", ""),
    )
    summary = diff_mod.summarize(result)

    # Artifacts
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    workbook = render.render_poam(doc.records, result, meta, decision)
    slug = store_mod.component_slug(args.component_id)
    stamp = meta.scan_timestamp.replace(":", "").replace("-", "")
    short_digest = digest.replace("sha256:", "")[:12]

    local_xlsx = out_dir / "poam.xlsx"
    local_xlsx.write_bytes(workbook)
    (out_dir / "state.json").write_text(doc.to_json(), encoding="utf-8")
    (out_dir / "diff.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    uris: dict[str, str] = {"state": state_uri}
    try:
        uris["poam"] = store.put_artifact(
            f"poam/{slug}/latest.xlsx",
            workbook,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        store.put_artifact(
            f"history/{slug}/{stamp}-{short_digest}.xlsx",
            workbook,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        store.put_artifact(
            f"history/{slug}/{stamp}-{short_digest}.json",
            doc.to_json().encode("utf-8"),
            "application/json",
        )
        store.put_artifact(
            f"raw/{slug}/{short_digest}/{stamp}.trivy.json",
            Path(args.trivy_json).read_bytes(),
            "application/json",
        )
        if args.sbom and Path(args.sbom).exists():
            uris["sbom"] = store.put_artifact(
                f"sbom/{slug}/{short_digest}.spdx.json",
                Path(args.sbom).read_bytes(),
                "application/json",
            )
    except Exception as exc:
        print(f"::warning::Artifact upload partially failed: {exc}")

    # Telemetry: best effort, never fatal.
    event = telemetry.build_event(
        meta,
        summary,
        decision,
        exc_report,
        duration_seconds=round(time.monotonic() - started, 2),
        poam_uri=uris.get("poam", ""),
        sbom_uri=uris.get("sbom", ""),
    )
    telemetry.write_local(event, str(out_dir / "gate-event.json"))
    if not args.no_telemetry:
        telemetry.emit(
            event,
            dce_endpoint=args.dce_endpoint,
            dcr_immutable_id=args.dcr_immutable_id,
            stream_name=args.dcr_stream,
            environment=args.environment,
        )

    _gh_summary(_build_summary_md(meta, summary, decision, uris))
    _gh_output(
        gate_result=decision.result,
        gate_passed=not decision.failed,
        bypass_used=decision.bypass_used,
        is_initial_scan=meta.is_initial_scan,
        new_count=summary.get("new", 0),
        closed_count=summary.get("closed", 0),
        reopened_count=summary.get("reopened", 0),
        overdue_count=summary.get("overdue_count", 0),
        critical_open=summary.get("gating_by_severity", {}).get("CRITICAL", 0),
        high_open=summary.get("gating_by_severity", {}).get("HIGH", 0),
        total_open=summary.get("total_open", 0),
        violation_count=len(decision.violations),
        poam_uri=uris.get("poam", ""),
        sbom_uri=uris.get("sbom", ""),
        state_uri=state_uri,
        image_digest=digest,
        poam_xlsx_path=str(local_xlsx),
    )

    print(json.dumps({"result": decision.result, **summary}, indent=2))

    if decision.failed:
        for reason in decision.reasons:
            print(f"::error::Security gate failed: {reason}")
        return EXIT_FAIL
    if decision.bypass_used:
        print(f"::warning::Security gate BYPASSED by {decision.bypass_actor}: {decision.bypass_reason}")
    return EXIT_PASS


def cmd_validate_exceptions(args: argparse.Namespace) -> int:
    exceptions, errors = policy_mod.load_exceptions(args.exceptions)
    for e in errors:
        print(f"::error::{e}")
    stale = [e for e in exceptions if e.is_expired()]
    for e in stale:
        print(f"::warning::Expired exception still present: {e.vuln_id} ({e.expires_on}) in {e.source_file}")
    print(f"Loaded {len(exceptions)} exception(s); {len(errors)} error(s); {len(stale)} expired.")
    return EXIT_ERROR if errors else EXIT_PASS


def cmd_render(args: argparse.Namespace) -> int:
    """Re-render a workbook from an existing state document, no scan required."""
    doc = store_mod.StateDocument.from_json(Path(args.state).read_text(encoding="utf-8"), "")
    meta = ScanMeta(component_id=doc.component_id, is_initial_scan=doc.scan_count <= 1)
    if doc.last_scan:
        meta.image_digest = doc.last_scan.get("digest", "")
        meta.image_tag = doc.last_scan.get("tag", "")
        meta.trivy_version = doc.last_scan.get("trivy_version", "")
        meta.vuln_db_updated_at = doc.last_scan.get("db_updated_at", "")
    from .models import DiffResult

    empty = DiffResult(all_records=doc.records)

    class _NoDecision:
        result = "n/a"
        violations: list = []
        bypass_used = False

    Path(args.out).write_bytes(render.render_poam(doc.records, empty, meta, _NoDecision()))
    print(f"Wrote {args.out}")
    return EXIT_PASS


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="poam", description="Container security gate POA&M engine")
    sub = parser.add_subparsers(dest="command", required=True)

    g = sub.add_parser("gate", help="Run the full gate: diff, policy, render, persist")
    g.add_argument("--trivy-json", required=True)
    g.add_argument("--sbom", default="")
    g.add_argument("--component-id", required=True)
    g.add_argument("--image-ref", required=True)
    g.add_argument("--image-digest", default="")
    g.add_argument("--image-tag", default="")
    g.add_argument("--policy", default="")
    g.add_argument("--exceptions", nargs="*", default=[])
    g.add_argument("--allow-invalid-exceptions", action="store_true")
    g.add_argument("--store", default="local://./.gate-state")
    g.add_argument("--environment", default="public", choices=["public", "usgovernment"])
    g.add_argument("--out-dir", default="./gate-out")
    g.add_argument("--trivy-version", default="")
    g.add_argument("--db-updated-at", default="")
    g.add_argument("--db-next-update", default="")
    g.add_argument("--gate-version", default="")
    g.add_argument("--bypass", action="store_true")
    g.add_argument("--bypass-reason", default="")
    g.add_argument("--bypass-actor", default="")
    g.add_argument("--dce-endpoint", default="")
    g.add_argument("--dcr-immutable-id", default="")
    g.add_argument("--dcr-stream", default="Custom-SecurityGate_CL")
    g.add_argument("--no-telemetry", action="store_true")
    g.add_argument("--max-retries", type=int, default=5)
    g.set_defaults(func=cmd_gate)

    v = sub.add_parser("validate-exceptions", help="Lint the exception store")
    v.add_argument("--exceptions", nargs="+", required=True)
    v.set_defaults(func=cmd_validate_exceptions)

    r = sub.add_parser("render", help="Re-render a workbook from saved state")
    r.add_argument("--state", required=True)
    r.add_argument("--out", default="poam.xlsx")
    r.set_defaults(func=cmd_render)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
