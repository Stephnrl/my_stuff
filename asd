"""Reconcile a fresh scan against prior POA&M state.

Pure functions, no I/O, no Azure. Everything here is unit-testable, which
matters because a bug in this file silently corrupts an audit artifact.

State machine per finding_key:

                     in current scan        absent from current scan
    prior Open       -> PERSISTING          -> CLOSED (stamp closed_date)
    prior Closed     -> REOPENED            -> stays Closed
    not in prior     -> NEW                 -> n/a
"""

from __future__ import annotations

from typing import Any, Iterable

from .models import (
    STATUS_CLOSED,
    STATUS_OPEN,
    DiffResult,
    Finding,
    PoamRecord,
    ScanMeta,
    today_iso,
)


def _add_days(iso_date: str, days: int) -> str:
    from datetime import date, timedelta

    y, m, d = (int(x) for x in iso_date.split("-"))
    return (date(y, m, d) + timedelta(days=days)).isoformat()


def next_poam_id(component_id: str, seq: int) -> str:
    """Sequential and never reused. Prefix keeps IDs readable in a merged POA&M."""
    slug = component_id.strip("/").replace("/", "-").replace("_", "-").upper()
    slug = "".join(ch for ch in slug if ch.isalnum() or ch == "-")[-24:]
    return f"{slug}-{seq:04d}"


def _record_from_finding(
    finding: Finding,
    poam_id: str,
    meta: ScanMeta,
    sla_days: dict[str, int],
    as_of: str,
) -> PoamRecord:
    sla = sla_days.get(finding.severity, sla_days.get("DEFAULT", 90))
    return PoamRecord(
        poam_id=poam_id,
        finding_key=finding.finding_key,
        vuln_id=finding.vuln_id,
        pkg_name=finding.pkg_name,
        target=finding.target,
        installed_version=finding.installed_version,
        fixed_version=finding.fixed_version,
        severity=finding.severity,
        original_severity=finding.severity,
        cvss_score=finding.cvss_score,
        cvss_vector=finding.cvss_vector,
        title=finding.title,
        primary_url=finding.primary_url,
        pkg_type=finding.pkg_type,
        purl=finding.purl,
        fix_status=finding.fix_status,
        status=STATUS_OPEN,
        first_detected=as_of,
        last_detected=as_of,
        scheduled_completion_date=_add_days(as_of, sla),
        first_seen_digest=meta.image_digest,
        last_seen_digest=meta.image_digest,
        first_seen_tag=meta.image_tag,
        last_seen_tag=meta.image_tag,
    )


def _refresh_mutable_fields(record: PoamRecord, finding: Finding, meta: ScanMeta, as_of: str) -> None:
    """Update the attributes that legitimately change while identity holds."""
    record.installed_version = finding.installed_version
    record.fixed_version = finding.fixed_version
    record.cvss_score = finding.cvss_score
    record.cvss_vector = finding.cvss_vector
    record.fix_status = finding.fix_status
    record.purl = finding.purl or record.purl
    record.title = finding.title or record.title
    record.primary_url = finding.primary_url or record.primary_url
    record.last_detected = as_of
    record.last_seen_digest = meta.image_digest
    record.last_seen_tag = meta.image_tag


def reconcile(
    findings: Iterable[Finding],
    prior_records: Iterable[PoamRecord],
    meta: ScanMeta,
    sla_days: dict[str, int] | None = None,
    next_seq: int = 1,
    as_of: str | None = None,
    reset_sla_on_reopen: bool = True,
) -> tuple[DiffResult, int]:
    """Return (DiffResult, next_sequence_number).

    `reset_sla_on_reopen` - when a closed finding comes back, restart the
    remediation clock. Default True: a regression is a fresh obligation.
    Set False if your assessor wants continuity from original discovery.
    """
    sla_days = sla_days or {"CRITICAL": 30, "HIGH": 30, "MEDIUM": 90, "LOW": 180, "DEFAULT": 90}
    as_of = as_of or today_iso()
    seq = next_seq

    current: dict[str, Finding] = {f.finding_key: f for f in findings}
    prior: dict[str, PoamRecord] = {r.finding_key: r for r in prior_records}

    result = DiffResult()

    for key, finding in current.items():
        existing = prior.get(key)

        if existing is None:
            record = _record_from_finding(finding, next_poam_id(meta.component_id, seq), meta, sla_days, as_of)
            seq += 1
            result.new.append(record)
            result.all_records.append(record)
            continue

        was_closed = existing.status == STATUS_CLOSED
        prior_severity = existing.severity

        _refresh_mutable_fields(existing, finding, meta, as_of)

        # Severity reclassification on an otherwise unchanged finding is worth
        # surfacing: a Medium promoted to Critical is a real posture change.
        if finding.severity != prior_severity:
            existing.severity = finding.severity
            result.severity_drift.append(
                {
                    "poam_id": existing.poam_id,
                    "vuln_id": existing.vuln_id,
                    "pkg_name": existing.pkg_name,
                    "from": prior_severity,
                    "to": finding.severity,
                    "escalation": _is_escalation(prior_severity, finding.severity),
                }
            )
            # Re-derive the due date from the ORIGINAL detection date so an
            # escalation tightens the deadline instead of granting a new window.
            sla = sla_days.get(finding.severity, sla_days.get("DEFAULT", 90))
            base = existing.first_detected or as_of
            existing.scheduled_completion_date = _add_days(base, sla)

        if was_closed:
            existing.status = STATUS_OPEN
            existing.closed_date = ""
            existing.reopened_count += 1
            if reset_sla_on_reopen:
                sla = sla_days.get(finding.severity, sla_days.get("DEFAULT", 90))
                existing.scheduled_completion_date = _add_days(as_of, sla)
            result.reopened.append(existing)
        else:
            result.persisting.append(existing)

        result.all_records.append(existing)

    # Anything previously open and absent from this scan is remediated.
    for key, record in prior.items():
        if key in current:
            continue
        if record.status == STATUS_OPEN:
            record.status = STATUS_CLOSED
            record.closed_date = as_of
            result.closed.append(record)
        result.all_records.append(record)

    result.all_records.sort(key=_sort_key)
    return result, seq


def _is_escalation(old: str, new: str) -> bool:
    from .models import SEVERITY_RANK

    return SEVERITY_RANK.get(new, 99) < SEVERITY_RANK.get(old, 99)


def _sort_key(record: PoamRecord) -> tuple:
    from .models import SEVERITY_RANK

    return (
        0 if record.is_open else 1,
        SEVERITY_RANK.get(record.severity, 99),
        record.scheduled_completion_date or "9999-12-31",
        record.vuln_id,
        record.pkg_name,
    )


def summarize(result: DiffResult) -> dict[str, Any]:
    """Compact summary suitable for telemetry and job-summary rendering."""
    counts = result.counts()
    by_sev_new: dict[str, int] = {}
    for r in result.new:
        by_sev_new[r.severity] = by_sev_new.get(r.severity, 0) + 1

    overdue = [r for r in result.all_records if r.is_overdue()]
    by_sev_overdue: dict[str, int] = {}
    for r in overdue:
        by_sev_overdue[r.severity] = by_sev_overdue.get(r.severity, 0) + 1

    return {
        **counts,
        "open_by_severity": result.severity_breakdown(only_gating=False),
        "gating_by_severity": result.severity_breakdown(only_gating=True),
        "new_by_severity": by_sev_new,
        "overdue_count": len(overdue),
        "overdue_by_severity": by_sev_overdue,
        "deviations_active": len([r for r in result.all_records if r.has_active_deviation]),
        "escalations": len([d for d in result.severity_drift if d["escalation"]]),
    }
