"""Exception handling and the gate decision.

Design rule enforced here: exceptions are applied AFTER the scan, to the POA&M
records. We never hand Trivy an --ignorefile, because suppression at scan time
deletes the finding from the output entirely and it never reaches the POA&M.
An assessor wants to see the deviation documented, not disappeared.
"""

from __future__ import annotations

import fnmatch
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

import yaml

from .models import (
    VALID_DEVIATIONS,
    DiffResult,
    PoamRecord,
    SEVERITY_ORDER,
    today_iso,
)

DEFAULT_POLICY: dict[str, Any] = {
    "name": "default",
    "severity_source": "vendor",
    "ignore_unfixed": False,
    "severity_sla_days": {"CRITICAL": 30, "HIGH": 30, "MEDIUM": 90, "LOW": 180, "DEFAULT": 90},
    "grace_period_days": 0,
    "fail_on": {
        "new": ["CRITICAL"],
        "overdue": ["CRITICAL", "HIGH"],
        "reopened": [],
        "escalated_into": [],
    },
    "deviations": {
        "require_expiry": True,
        "max_days": 90,
        "allowed_types": sorted(VALID_DEVIATIONS),
        "warn_before_expiry_days": 14,
    },
    "reset_sla_on_reopen": True,
}


@dataclass
class Exception_:
    """One approved deviation from the central exception store."""

    component_id: str
    vuln_id: str = "*"
    pkg_name: str = "*"
    target: str = "*"
    deviation_type: str = "Risk Adjusted"
    justification: str = ""
    approved_by: str = ""
    expires_on: str = ""
    ref: str = ""
    source_file: str = ""

    def matches(self, record: PoamRecord, component_id: str) -> bool:
        return (
            fnmatch.fnmatch(component_id, self.component_id)
            and fnmatch.fnmatch(record.vuln_id, self.vuln_id)
            and fnmatch.fnmatch(record.pkg_name, self.pkg_name)
            and fnmatch.fnmatch(record.target, self.target)
        )

    def is_expired(self, as_of: str | None = None) -> bool:
        if not self.expires_on:
            return False
        return self.expires_on < (as_of or today_iso())

    def days_to_expiry(self, as_of: str | None = None) -> int | None:
        if not self.expires_on:
            return None
        from datetime import date

        ref = as_of or today_iso()
        a = date(*(int(x) for x in ref.split("-")))
        b = date(*(int(x) for x in self.expires_on.split("-")))
        return (b - a).days


@dataclass
class GateDecision:
    result: str = "pass"                  # pass | fail | pass_with_bypass
    reasons: list[str] = field(default_factory=list)
    violations: list[dict[str, Any]] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    bypass_used: bool = False
    bypass_reason: str = ""
    bypass_actor: str = ""

    @property
    def failed(self) -> bool:
        return self.result == "fail"


def load_policy(path: str | Path | None) -> dict[str, Any]:
    policy = json.loads(json.dumps(DEFAULT_POLICY))  # deep copy
    if not path:
        return policy
    with open(path, "r", encoding="utf-8") as fh:
        loaded = yaml.safe_load(fh) or {}
    for key, value in loaded.items():
        if isinstance(value, dict) and isinstance(policy.get(key), dict):
            policy[key].update(value)
        else:
            policy[key] = value
    return policy


def policy_fingerprint(policy: dict[str, Any]) -> str:
    """Hash of the effective policy, recorded in the POA&M for auditability."""
    blob = json.dumps(policy, sort_keys=True).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:16]


def load_exceptions(paths: Iterable[str | Path]) -> tuple[list[Exception_], list[str]]:
    """Load every *.yaml/*.yml under the given files or directories.

    Returns (valid_exceptions, validation_errors). Malformed entries are
    rejected loudly rather than silently ignored - a broken exception file
    must not quietly become "no exceptions" or "everything excepted".
    """
    exceptions: list[Exception_] = []
    errors: list[str] = []
    files: list[Path] = []

    for p in paths:
        path = Path(p)
        if path.is_dir():
            files.extend(sorted(path.rglob("*.yaml")))
            files.extend(sorted(path.rglob("*.yml")))
        elif path.is_file():
            files.append(path)

    for f in files:
        if f.name in {"schema.json", "schema.yaml"}:
            continue
        try:
            data = yaml.safe_load(f.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError as exc:
            errors.append(f"{f}: unparseable YAML: {exc}")
            continue

        entries = data.get("exceptions") if isinstance(data, dict) else data
        if not isinstance(entries, list):
            errors.append(f"{f}: expected a top-level 'exceptions' list")
            continue

        for i, raw in enumerate(entries):
            if not isinstance(raw, dict):
                errors.append(f"{f}[{i}]: entry is not a mapping")
                continue
            missing = [k for k in ("component_id", "vuln_id", "justification", "approved_by") if not raw.get(k)]
            if missing:
                errors.append(f"{f}[{i}]: missing required field(s): {', '.join(missing)}")
                continue
            dev_type = str(raw.get("deviation_type", "Risk Adjusted"))
            if dev_type not in VALID_DEVIATIONS:
                errors.append(f"{f}[{i}]: invalid deviation_type '{dev_type}'")
                continue
            expires = raw.get("expires_on", "")
            exceptions.append(
                Exception_(
                    component_id=str(raw["component_id"]),
                    vuln_id=str(raw.get("vuln_id", "*")),
                    pkg_name=str(raw.get("pkg_name", "*")),
                    target=str(raw.get("target", "*")),
                    deviation_type=dev_type,
                    justification=str(raw["justification"]),
                    approved_by=str(raw["approved_by"]),
                    expires_on=str(expires) if expires else "",
                    ref=str(raw.get("ref", "")),
                    source_file=str(f),
                )
            )

    return exceptions, errors


def apply_exceptions(
    records: Iterable[PoamRecord],
    exceptions: list[Exception_],
    component_id: str,
    policy: dict[str, Any],
    as_of: str | None = None,
) -> dict[str, Any]:
    """Stamp deviation metadata onto matching records. Fails closed on expiry."""
    dev_cfg = policy.get("deviations", {})
    require_expiry = dev_cfg.get("require_expiry", True)
    max_days = dev_cfg.get("max_days", 90)
    warn_days = dev_cfg.get("warn_before_expiry_days", 14)

    applied = 0
    expiring_soon: list[dict[str, Any]] = []
    rejected: list[str] = []
    expired_hits: list[str] = []

    usable: list[Exception_] = []
    for exc in exceptions:
        if require_expiry and not exc.expires_on:
            rejected.append(f"{exc.vuln_id} ({exc.source_file}): no expires_on and policy requires one")
            continue
        if exc.is_expired(as_of):
            expired_hits.append(f"{exc.vuln_id} expired {exc.expires_on} ({exc.source_file})")
            continue
        remaining = exc.days_to_expiry(as_of)
        if remaining is not None and max_days and remaining > max_days:
            rejected.append(
                f"{exc.vuln_id} ({exc.source_file}): expiry {exc.expires_on} exceeds max_days={max_days}"
            )
            continue
        usable.append(exc)

    for record in records:
        if not record.is_open:
            continue
        for exc in usable:
            if not exc.matches(record, component_id):
                continue
            record.deviation_type = exc.deviation_type
            record.deviation_ref = exc.ref
            record.deviation_justification = exc.justification
            record.deviation_approved_by = exc.approved_by
            record.deviation_expires = exc.expires_on
            applied += 1
            remaining = exc.days_to_expiry(as_of)
            if remaining is not None and remaining <= warn_days:
                expiring_soon.append(
                    {
                        "poam_id": record.poam_id,
                        "vuln_id": record.vuln_id,
                        "expires_on": exc.expires_on,
                        "days_remaining": remaining,
                        "approved_by": exc.approved_by,
                    }
                )
            break

    return {
        "applied": applied,
        "usable": len(usable),
        "expiring_soon": expiring_soon,
        "rejected": rejected,
        "expired": expired_hits,
    }


def evaluate(
    diff: DiffResult,
    policy: dict[str, Any],
    bypass: bool = False,
    bypass_reason: str = "",
    bypass_actor: str = "",
    as_of: str | None = None,
) -> GateDecision:
    """Decide pass/fail. Only gating records (open, no active deviation) count."""
    as_of = as_of or today_iso()
    decision = GateDecision()
    fail_on = policy.get("fail_on", {})
    grace = int(policy.get("grace_period_days", 0) or 0)

    def _sev_set(key: str) -> set[str]:
        return {s.upper() for s in (fail_on.get(key) or [])}

    # 1. New findings above threshold, outside any grace window.
    new_sevs = _sev_set("new")
    if new_sevs:
        for r in diff.new:
            if not r.gating or r.severity not in new_sevs:
                continue
            if grace:
                from datetime import date, timedelta

                first = date(*(int(x) for x in r.first_detected.split("-")))
                if date(*(int(x) for x in as_of.split("-"))) < first + timedelta(days=grace):
                    decision.warnings.append(
                        f"{r.poam_id} {r.vuln_id} ({r.severity}) new, within {grace}-day grace period"
                    )
                    continue
            decision.violations.append(_violation(r, "new"))

    # 2. Anything past its scheduled completion date.
    overdue_sevs = _sev_set("overdue")
    if overdue_sevs:
        for r in diff.all_records:
            if r.severity in overdue_sevs and r.is_overdue(as_of):
                decision.violations.append(_violation(r, "overdue"))

    # 3. Regressions: a previously closed finding that came back.
    reopened_sevs = _sev_set("reopened")
    if reopened_sevs:
        for r in diff.reopened:
            if r.gating and r.severity in reopened_sevs:
                decision.violations.append(_violation(r, "reopened"))

    # 4. Severity escalation into a listed band on an existing item.
    escalated_sevs = _sev_set("escalated_into")
    if escalated_sevs:
        by_id = {r.poam_id: r for r in diff.all_records}
        for drift in diff.severity_drift:
            if not drift["escalation"] or drift["to"] not in escalated_sevs:
                continue
            r = by_id.get(drift["poam_id"])
            if r and r.gating:
                decision.violations.append(_violation(r, f"escalated {drift['from']}->{drift['to']}"))

    # Deduplicate: one item can trip several rules.
    seen: set[str] = set()
    unique: list[dict[str, Any]] = []
    for v in decision.violations:
        if v["poam_id"] in seen:
            continue
        seen.add(v["poam_id"])
        unique.append(v)
    decision.violations = unique

    if unique:
        by_rule: dict[str, int] = {}
        for v in unique:
            by_rule[v["rule"]] = by_rule.get(v["rule"], 0) + 1
        decision.reasons = [f"{count} {rule} finding(s)" for rule, count in sorted(by_rule.items())]
        if bypass:
            decision.result = "pass_with_bypass"
            decision.bypass_used = True
            decision.bypass_reason = bypass_reason
            decision.bypass_actor = bypass_actor
        else:
            decision.result = "fail"
    else:
        decision.result = "pass"
        if bypass:
            decision.warnings.append("Bypass was requested but no violations were present.")

    return decision


def _violation(record: PoamRecord, rule: str) -> dict[str, Any]:
    return {
        "rule": rule,
        "poam_id": record.poam_id,
        "vuln_id": record.vuln_id,
        "pkg_name": record.pkg_name,
        "installed_version": record.installed_version,
        "fixed_version": record.fixed_version,
        "severity": record.severity,
        "target": record.target,
        "scheduled_completion_date": record.scheduled_completion_date,
    }
