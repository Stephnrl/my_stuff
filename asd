"""Emit one structured event per gate run to Log Analytics.

Uses the Logs Ingestion API (Data Collection Endpoint + Data Collection Rule +
custom table). The older HTTP Data Collector API is on a deprecation path;
do not build on it.

Telemetry failure NEVER fails the build. A monitoring outage must not become a
delivery outage - but it does emit a loud warning, and the "no gate events for
component X in N days" alert in Terraform catches sustained silence.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any

from .models import ScanMeta, utc_now_iso


def build_event(
    meta: ScanMeta,
    summary: dict[str, Any],
    decision: Any,
    exception_report: dict[str, Any],
    duration_seconds: float | None = None,
    poam_uri: str = "",
    sbom_uri: str = "",
) -> dict[str, Any]:
    """One flat-ish record. Keep field names stable - KQL alerts depend on them."""
    gating = summary.get("gating_by_severity", {})
    open_by = summary.get("open_by_severity", {})
    return {
        "TimeGenerated": utc_now_iso(),
        "ComponentId": meta.component_id,
        "Repository": meta.repository,
        "ImageDigest": meta.image_digest,
        "ImageTag": meta.image_tag,
        "ImageRef": meta.image_ref,
        "GateResult": getattr(decision, "result", "unknown"),
        "BypassUsed": bool(getattr(decision, "bypass_used", False)),
        "BypassActor": getattr(decision, "bypass_actor", "") or "",
        "BypassReason": (getattr(decision, "bypass_reason", "") or "")[:1000],
        "IsInitialScan": bool(meta.is_initial_scan),
        "PolicyProfile": meta.policy_profile,
        "PolicyFingerprint": meta.policy_sha,
        "GateVersion": meta.gate_version,
        "TrivyVersion": meta.trivy_version,
        "VulnDbUpdatedAt": meta.vuln_db_updated_at,
        "VulnDbAgeHours": _db_age_hours(meta.vuln_db_updated_at),
        "NewCount": summary.get("new", 0),
        "ClosedCount": summary.get("closed", 0),
        "ReopenedCount": summary.get("reopened", 0),
        "PersistingCount": summary.get("persisting", 0),
        "TotalOpen": summary.get("total_open", 0),
        "OverdueCount": summary.get("overdue_count", 0),
        "EscalationCount": summary.get("escalations", 0),
        "CriticalOpen": gating.get("CRITICAL", 0),
        "HighOpen": gating.get("HIGH", 0),
        "MediumOpen": gating.get("MEDIUM", 0),
        "LowOpen": gating.get("LOW", 0),
        "CriticalOpenIncludingDeviations": open_by.get("CRITICAL", 0),
        "HighOpenIncludingDeviations": open_by.get("HIGH", 0),
        "NewCritical": summary.get("new_by_severity", {}).get("CRITICAL", 0),
        "NewHigh": summary.get("new_by_severity", {}).get("HIGH", 0),
        "DeviationsActive": summary.get("deviations_active", 0),
        "DeviationsExpiringSoon": len(exception_report.get("expiring_soon", [])),
        "DeviationsExpired": len(exception_report.get("expired", [])),
        "DeviationsRejected": len(exception_report.get("rejected", [])),
        "ViolationCount": len(getattr(decision, "violations", []) or []),
        "ViolationSummary": "; ".join(getattr(decision, "reasons", []) or [])[:1000],
        "RunId": meta.run_id,
        "RunUrl": meta.run_url,
        "Actor": meta.actor,
        "CommitSha": meta.git_sha,
        "DurationSeconds": duration_seconds or 0.0,
        "PoamUri": poam_uri,
        "SbomUri": sbom_uri,
    }


def _db_age_hours(updated_at: str) -> float:
    if not updated_at:
        return -1.0
    try:
        from datetime import datetime, timezone

        ts = updated_at.replace("Z", "+00:00")
        dt = datetime.fromisoformat(ts)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return round((datetime.now(timezone.utc) - dt).total_seconds() / 3600.0, 2)
    except Exception:
        return -1.0


def emit(
    event: dict[str, Any],
    dce_endpoint: str = "",
    dcr_immutable_id: str = "",
    stream_name: str = "Custom-SecurityGate_CL",
    environment: str = "public",
) -> bool:
    """Send the event. Returns True on success. Never raises."""
    dce_endpoint = dce_endpoint or os.environ.get("GATE_DCE_ENDPOINT", "")
    dcr_immutable_id = dcr_immutable_id or os.environ.get("GATE_DCR_IMMUTABLE_ID", "")

    if not dce_endpoint or not dcr_immutable_id:
        print("::notice::Telemetry not configured (no DCE/DCR); skipping Log Analytics emit.")
        return False

    try:
        from azure.identity import AzureAuthorityHosts, DefaultAzureCredential
        from azure.monitor.ingestion import LogsIngestionClient

        if environment == "usgovernment":
            authority = AzureAuthorityHosts.AZURE_GOVERNMENT
            audience = "https://monitor.azure.us"
        else:
            authority = AzureAuthorityHosts.AZURE_PUBLIC_CLOUD
            audience = "https://monitor.azure.com"

        credential = DefaultAzureCredential(authority=authority)
        client = LogsIngestionClient(
            endpoint=dce_endpoint, credential=credential, credential_scopes=[f"{audience}/.default"]
        )
        client.upload(rule_id=dcr_immutable_id, stream_name=stream_name, logs=[event])
        return True
    except Exception as exc:  # pragma: no cover - needs Azure
        print(f"::warning::Failed to emit gate telemetry to Log Analytics: {exc}", file=sys.stderr)
        return False


def write_local(event: dict[str, Any], path: str) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(event, fh, indent=2)
