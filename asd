"""Core data models for the security gate POA&M engine.

The single most important thing in this file is `Finding.finding_key`.
It deliberately EXCLUDES the installed package version so that patching
openssl 3.0.1 -> 3.0.2 while the CVE persists keeps the SAME POA&M item
and the same remediation clock. Version is a mutable attribute, not identity.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field, asdict
from datetime import date, datetime, timezone
from typing import Any

SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]
SEVERITY_RANK = {s: i for i, s in enumerate(SEVERITY_ORDER)}

# POA&M lifecycle. `status` is Open/Closed only; a deviation is a separate
# attribute so an excepted item still APPEARS in the POA&M rather than vanishing.
STATUS_OPEN = "Open"
STATUS_CLOSED = "Closed"

DEVIATION_RISK_ADJUSTED = "Risk Adjusted"
DEVIATION_FALSE_POSITIVE = "False Positive"
DEVIATION_OPERATIONAL = "Operational Requirement"
VALID_DEVIATIONS = {
    DEVIATION_RISK_ADJUSTED,
    DEVIATION_FALSE_POSITIVE,
    DEVIATION_OPERATIONAL,
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def today_iso() -> str:
    return datetime.now(timezone.utc).date().isoformat()


@dataclass
class Finding:
    """A single vulnerability observation from one scan."""

    vuln_id: str
    pkg_name: str
    target: str                      # normalized location, never contains image tag
    installed_version: str = ""
    fixed_version: str = ""
    severity: str = "UNKNOWN"
    cvss_score: float | None = None
    cvss_vector: str = ""
    title: str = ""
    primary_url: str = ""
    pkg_type: str = ""
    purl: str = ""
    fix_status: str = ""             # trivy: fixed / affected / will_not_fix / end_of_life
    published_date: str = ""

    @property
    def finding_key(self) -> str:
        raw = f"{self.vuln_id}|{self.pkg_name}|{self.target}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]

    @property
    def has_fix(self) -> bool:
        return bool(self.fixed_version.strip())


@dataclass
class PoamRecord:
    """A persisted POA&M line item. Never deleted, only transitioned."""

    poam_id: str
    finding_key: str
    vuln_id: str
    pkg_name: str
    target: str

    installed_version: str = ""
    fixed_version: str = ""
    severity: str = "UNKNOWN"
    original_severity: str = ""      # severity at first detection, for drift detection
    cvss_score: float | None = None
    cvss_vector: str = ""
    title: str = ""
    primary_url: str = ""
    pkg_type: str = ""
    purl: str = ""
    fix_status: str = ""

    status: str = STATUS_OPEN
    first_detected: str = ""
    last_detected: str = ""
    closed_date: str = ""
    reopened_count: int = 0
    scheduled_completion_date: str = ""

    # Deviation / exception metadata, applied from the central exception store.
    deviation_type: str = ""
    deviation_ref: str = ""
    deviation_justification: str = ""
    deviation_approved_by: str = ""
    deviation_expires: str = ""

    first_seen_digest: str = ""
    last_seen_digest: str = ""
    first_seen_tag: str = ""
    last_seen_tag: str = ""

    # Free-form, survives round trips.
    notes: str = ""

    @property
    def is_open(self) -> bool:
        return self.status == STATUS_OPEN

    @property
    def has_active_deviation(self) -> bool:
        return bool(self.deviation_type)

    @property
    def gating(self) -> bool:
        """Open, and not covered by an active deviation -> counts toward the gate."""
        return self.is_open and not self.has_active_deviation

    def is_overdue(self, as_of: str | None = None) -> bool:
        if not self.gating or not self.scheduled_completion_date:
            return False
        ref = as_of or today_iso()
        return self.scheduled_completion_date < ref

    @property
    def poam_status(self) -> str:
        """Combined status column for the rendered workbook."""
        if self.status == STATUS_CLOSED:
            return STATUS_CLOSED
        if self.deviation_type:
            return f"Open - {self.deviation_type}"
        return STATUS_OPEN

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "PoamRecord":
        known = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in d.items() if k in known})


@dataclass
class ScanMeta:
    """Provenance for one gate execution. Goes in the workbook and the telemetry.

    The trivy DB timestamp matters: the DB refreshes roughly every 6 hours, so
    the same image scanned two days apart legitimately yields different results.
    Without this recorded, that looks like a bug.
    """

    component_id: str = ""
    image_ref: str = ""
    image_digest: str = ""
    image_tag: str = ""
    scan_timestamp: str = field(default_factory=utc_now_iso)
    trivy_version: str = ""
    vuln_db_updated_at: str = ""
    vuln_db_next_update: str = ""
    java_db_version: str = ""
    policy_profile: str = ""
    policy_sha: str = ""
    gate_version: str = ""
    run_id: str = ""
    run_url: str = ""
    repository: str = ""
    actor: str = ""
    git_sha: str = ""
    is_initial_scan: bool = True

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class DiffResult:
    """Outcome of reconciling a scan against prior POA&M state."""

    new: list[PoamRecord] = field(default_factory=list)
    closed: list[PoamRecord] = field(default_factory=list)
    reopened: list[PoamRecord] = field(default_factory=list)
    persisting: list[PoamRecord] = field(default_factory=list)
    severity_drift: list[dict[str, Any]] = field(default_factory=list)
    all_records: list[PoamRecord] = field(default_factory=list)

    def counts(self) -> dict[str, int]:
        return {
            "new": len(self.new),
            "closed": len(self.closed),
            "reopened": len(self.reopened),
            "persisting": len(self.persisting),
            "severity_drift": len(self.severity_drift),
            "total_open": len([r for r in self.all_records if r.is_open]),
            "total_closed": len([r for r in self.all_records if not r.is_open]),
        }

    def severity_breakdown(self, only_gating: bool = True) -> dict[str, int]:
        out = {s: 0 for s in SEVERITY_ORDER}
        for r in self.all_records:
            if only_gating and not r.gating:
                continue
            if not only_gating and not r.is_open:
                continue
            out[r.severity if r.severity in out else "UNKNOWN"] += 1
        return out
