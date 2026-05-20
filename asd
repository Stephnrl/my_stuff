#!/usr/bin/env python3
"""
trivy_security_review_tool.py

Parse Trivy JSON scan results and produce a security-review package:
- Normalized findings CSV
- High/Critical review CSV
- Exceptions CSV
- Markdown summary
- Machine-readable review JSON

Designed for self-hosted runner images and other CI build images where raw CVSS
severity alone is not enough to justify approval or rejection.

Example:
  python trivy_security_review_tool.py \
    --input trivy-results.json \
    --output-dir trivy-review \
    --image myacr.azurecr.us/runner/full:2026.05.20 \
    --policy policy.yaml

Optional policy.yaml example:

risk:
  fail_on:
    - actively_exploited
    - critical_fix_available
    - expired_exception
  sla_days:
    CRITICAL: 15
    HIGH: 30
    MEDIUM: 90
    LOW: 180

runner_context:
  network_exposure: internal_only
  public_inbound: false
  repo_scope: private_internal_only
  uses_oidc: true
  ephemeral_runner: false

exceptions:
  - vulnerability_id: CVE-2024-12345
    package: openssl
    decision: temporary_exception
    owner: security@example.com
    expires: 2026-08-31
    justification: Vendor fix not available in base image channel.

package_usage:
  dotnet-sdk: build_time
  azure-cli: build_time
  terraform: build_time
  kubectl: build_time
  openssl: runtime

kev:
  - CVE-2023-1234

known_exploited:
  - CVE-2023-1234
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover
    yaml = None


SEVERITY_ORDER = {
    "UNKNOWN": 0,
    "LOW": 1,
    "MEDIUM": 2,
    "HIGH": 3,
    "CRITICAL": 4,
}

DEFAULT_POLICY: Dict[str, Any] = {
    "risk": {
        "fail_on": [
            "actively_exploited",
            "critical_fix_available",
            "expired_exception",
        ],
        "sla_days": {
            "CRITICAL": 15,
            "HIGH": 30,
            "MEDIUM": 90,
            "LOW": 180,
            "UNKNOWN": 180,
        },
    },
    "runner_context": {
        "network_exposure": "unknown",
        "public_inbound": None,
        "repo_scope": "unknown",
        "uses_oidc": None,
        "ephemeral_runner": None,
    },
    "exceptions": [],
    "package_usage": {},
    "kev": [],
    "known_exploited": [],
}


@dataclass
class ExceptionRecord:
    vulnerability_id: str
    package: str
    decision: str
    owner: str
    expires: str
    justification: str

    def is_expired(self, today: date) -> bool:
        try:
            return datetime.strptime(self.expires, "%Y-%m-%d").date() < today
        except ValueError:
            return True


@dataclass
class Finding:
    target: str
    result_type: str
    vulnerability_id: str
    package_name: str
    installed_version: str
    fixed_version: str
    severity: str
    title: str
    description: str
    primary_url: str
    status: str
    pkg_path: str
    cvss_score: Optional[float]
    cvss_vector: str
    published_date: str
    last_modified_date: str
    package_usage: str = "unknown"
    fix_available: bool = False
    known_exploited: bool = False
    cisa_kev: bool = False
    exception_status: str = "none"
    exception_owner: str = ""
    exception_expires: str = ""
    exception_justification: str = ""
    risk_decision: str = "needs_review"
    risk_reason: str = ""
    remediation_sla_days: Optional[int] = None
    remediation_due_date: str = ""
    workflow_status: str = "pass"


@dataclass
class ReviewSummary:
    image: str
    generated_at: str
    total_findings: int
    by_severity: Dict[str, int]
    by_decision: Dict[str, int]
    fix_available_high_critical: int
    known_exploited_count: int
    cisa_kev_count: int
    expired_exception_count: int
    workflow_status: str
    outputs: Dict[str, str] = field(default_factory=dict)


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_policy(path: Optional[Path]) -> Dict[str, Any]:
    policy = json.loads(json.dumps(DEFAULT_POLICY))
    if not path:
        return policy

    if not path.exists():
        raise FileNotFoundError(f"Policy file not found: {path}")

    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in {".yaml", ".yml"}:
        if yaml is None:
            raise RuntimeError("PyYAML is required for YAML policies. Install with: pip install pyyaml")
        loaded = yaml.safe_load(text) or {}
    else:
        loaded = json.loads(text)

    deep_merge(policy, loaded)
    return policy


def deep_merge(base: Dict[str, Any], overlay: Dict[str, Any]) -> Dict[str, Any]:
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base


def best_cvss(vuln: Dict[str, Any]) -> Tuple[Optional[float], str]:
    cvss = vuln.get("CVSS") or {}
    preferred_sources = ["nvd", "redhat", "ghsa", "azure", "ubuntu", "debian"]

    for source in preferred_sources:
        source_data = cvss.get(source)
        if not isinstance(source_data, dict):
            continue
        score = source_data.get("V3Score") or source_data.get("V2Score")
        vector = source_data.get("V3Vector") or source_data.get("V2Vector") or ""
        if score is not None:
            try:
                return float(score), vector
            except (TypeError, ValueError):
                pass

    for source_data in cvss.values():
        if not isinstance(source_data, dict):
            continue
        score = source_data.get("V3Score") or source_data.get("V2Score")
        vector = source_data.get("V3Vector") or source_data.get("V2Vector") or ""
        if score is not None:
            try:
                return float(score), vector
            except (TypeError, ValueError):
                pass

    return None, ""


def normalize_trivy_findings(data: Dict[str, Any]) -> List[Finding]:
    findings: List[Finding] = []

    for result in data.get("Results", []) or []:
        target = result.get("Target", "")
        result_type = result.get("Type", "")

        for vuln in result.get("Vulnerabilities", []) or []:
            score, vector = best_cvss(vuln)
            fixed_version = vuln.get("FixedVersion") or ""
            finding = Finding(
                target=target,
                result_type=result_type,
                vulnerability_id=vuln.get("VulnerabilityID", ""),
                package_name=vuln.get("PkgName", ""),
                installed_version=vuln.get("InstalledVersion", ""),
                fixed_version=fixed_version,
                severity=(vuln.get("Severity") or "UNKNOWN").upper(),
                title=vuln.get("Title", ""),
                description=vuln.get("Description", ""),
                primary_url=vuln.get("PrimaryURL", ""),
                status=vuln.get("Status", ""),
                pkg_path=vuln.get("PkgPath", ""),
                cvss_score=score,
                cvss_vector=vector,
                published_date=vuln.get("PublishedDate", ""),
                last_modified_date=vuln.get("LastModifiedDate", ""),
                fix_available=bool(fixed_version.strip()),
            )
            findings.append(finding)

    return findings


def build_exception_index(policy: Dict[str, Any]) -> Dict[Tuple[str, str], ExceptionRecord]:
    index: Dict[Tuple[str, str], ExceptionRecord] = {}
    for item in policy.get("exceptions", []) or []:
        record = ExceptionRecord(
            vulnerability_id=str(item.get("vulnerability_id", "")),
            package=str(item.get("package", "")),
            decision=str(item.get("decision", "temporary_exception")),
            owner=str(item.get("owner", "")),
            expires=str(item.get("expires", "")),
            justification=str(item.get("justification", "")),
        )
        if record.vulnerability_id and record.package:
            index[(record.vulnerability_id, record.package)] = record
    return index


def classify_findings(findings: List[Finding], policy: Dict[str, Any], today: date) -> List[Finding]:
    package_usage = policy.get("package_usage", {}) or {}
    known_exploited = set(policy.get("known_exploited", []) or [])
    kev = set(policy.get("kev", []) or [])
    exceptions = build_exception_index(policy)
    sla_days = policy.get("risk", {}).get("sla_days", {}) or {}
    fail_on = set(policy.get("risk", {}).get("fail_on", []) or [])

    for finding in findings:
        finding.package_usage = package_usage.get(finding.package_name, "unknown")
        finding.known_exploited = finding.vulnerability_id in known_exploited
        finding.cisa_kev = finding.vulnerability_id in kev

        exception = exceptions.get((finding.vulnerability_id, finding.package_name))
        if exception:
            finding.exception_owner = exception.owner
            finding.exception_expires = exception.expires
            finding.exception_justification = exception.justification
            if exception.is_expired(today):
                finding.exception_status = "expired"
            else:
                finding.exception_status = exception.decision

        finding.remediation_sla_days = int(sla_days.get(finding.severity, sla_days.get("UNKNOWN", 180)))
        finding.remediation_due_date = calculate_due_date(finding, today)

        decision, reason = decide_risk(finding)
        finding.risk_decision = decision
        finding.risk_reason = reason

        finding.workflow_status = "pass"
        if "expired_exception" in fail_on and finding.exception_status == "expired":
            finding.workflow_status = "fail"
        if "actively_exploited" in fail_on and (finding.known_exploited or finding.cisa_kev):
            finding.workflow_status = "fail"
        if (
            "critical_fix_available" in fail_on
            and finding.severity == "CRITICAL"
            and finding.fix_available
            and finding.exception_status not in {"temporary_exception", "risk_accepted", "accepted"}
        ):
            finding.workflow_status = "fail"

    return findings


def calculate_due_date(finding: Finding, today: date) -> str:
    days = finding.remediation_sla_days or 180
    if finding.published_date:
        try:
            published = parse_trivy_date(finding.published_date)
            return (published.date() + timedelta(days=days)).isoformat()
        except ValueError:
            pass
    return (today + timedelta(days=days)).isoformat()


def parse_trivy_date(value: str) -> datetime:
    # Trivy dates are commonly RFC3339-like, e.g. 2024-01-01T00:00:00Z
    value = value.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value)


def decide_risk(finding: Finding) -> Tuple[str, str]:
    if finding.exception_status == "expired":
        return "reject", "Exception is expired."

    if finding.exception_status in {"temporary_exception", "risk_accepted", "accepted"}:
        return "accept_with_exception", "Finding has an active documented exception."

    if finding.known_exploited or finding.cisa_kev:
        return "reject", "Known exploited / KEV vulnerability requires remediation or explicit exception."

    if finding.severity == "CRITICAL" and finding.fix_available:
        return "reject", "Critical vulnerability has a fixed version available."

    if finding.severity == "CRITICAL" and not finding.fix_available:
        return "temporary_exception_required", "Critical vulnerability has no fixed version available."

    if finding.severity == "HIGH" and finding.fix_available:
        if finding.package_usage in {"runtime", "unknown"}:
            return "remediate", "High vulnerability has a fix and package may be used."
        return "patch_on_cadence", "High vulnerability has a fix, but package is classified as build-time tooling."

    if finding.severity == "HIGH" and not finding.fix_available:
        return "temporary_exception_required", "High vulnerability has no fixed version available."

    if finding.severity in {"MEDIUM", "LOW", "UNKNOWN"}:
        return "monitor", "Below high severity; track through normal patch cadence."

    return "needs_review", "Unable to classify finding automatically."


def finding_to_row(f: Finding) -> Dict[str, Any]:
    row = asdict(f)
    row["cvss_score"] = "" if f.cvss_score is None else f.cvss_score
    return row


def write_csv(path: Path, findings: Iterable[Finding]) -> None:
    rows = [finding_to_row(f) for f in findings]
    fieldnames = list(asdict(Finding(
        target="",
        result_type="",
        vulnerability_id="",
        package_name="",
        installed_version="",
        fixed_version="",
        severity="",
        title="",
        description="",
        primary_url="",
        status="",
        pkg_path="",
        cvss_score=None,
        cvss_vector="",
        published_date="",
        last_modified_date="",
    )).keys())

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def summarize(findings: List[Finding], image: str, output_paths: Dict[str, Path]) -> ReviewSummary:
    by_severity: Dict[str, int] = {}
    by_decision: Dict[str, int] = {}

    for f in findings:
        by_severity[f.severity] = by_severity.get(f.severity, 0) + 1
        by_decision[f.risk_decision] = by_decision.get(f.risk_decision, 0) + 1

    workflow_status = "fail" if any(f.workflow_status == "fail" for f in findings) else "pass"

    return ReviewSummary(
        image=image,
        generated_at=datetime.now(timezone.utc).isoformat(),
        total_findings=len(findings),
        by_severity=dict(sorted(by_severity.items(), key=lambda x: SEVERITY_ORDER.get(x[0], 0), reverse=True)),
        by_decision=dict(sorted(by_decision.items())),
        fix_available_high_critical=sum(
            1 for f in findings
            if f.severity in {"HIGH", "CRITICAL"} and f.fix_available
        ),
        known_exploited_count=sum(1 for f in findings if f.known_exploited),
        cisa_kev_count=sum(1 for f in findings if f.cisa_kev),
        expired_exception_count=sum(1 for f in findings if f.exception_status == "expired"),
        workflow_status=workflow_status,
        outputs={k: str(v) for k, v in output_paths.items()},
    )


def write_markdown_summary(path: Path, summary: ReviewSummary, findings: List[Finding], policy: Dict[str, Any]) -> None:
    top_rejects = [f for f in findings if f.risk_decision in {"reject", "remediate"}]
    top_rejects.sort(key=lambda f: (SEVERITY_ORDER.get(f.severity, 0), f.cvss_score or 0), reverse=True)

    runner_context = policy.get("runner_context", {}) or {}

    lines: List[str] = []
    lines.append("# Trivy Security Review Summary")
    lines.append("")
    lines.append(f"**Image:** `{summary.image}`")
    lines.append(f"**Generated:** `{summary.generated_at}`")
    lines.append(f"**Workflow Status:** `{summary.workflow_status.upper()}`")
    lines.append("")

    lines.append("## Runner Context")
    lines.append("")
    lines.append("| Control | Value |")
    lines.append("|---|---|")
    for key, value in runner_context.items():
        lines.append(f"| {key} | {value} |")
    lines.append("")

    lines.append("## Finding Counts by Severity")
    lines.append("")
    lines.append("| Severity | Count |")
    lines.append("|---|---:|")
    for severity, count in summary.by_severity.items():
        lines.append(f"| {severity} | {count} |")
    lines.append("")

    lines.append("## Finding Counts by Risk Decision")
    lines.append("")
    lines.append("| Decision | Count |")
    lines.append("|---|---:|")
    for decision, count in summary.by_decision.items():
        lines.append(f"| {decision} | {count} |")
    lines.append("")

    lines.append("## Key Metrics")
    lines.append("")
    lines.append(f"- Total findings: **{summary.total_findings}**")
    lines.append(f"- HIGH/CRITICAL with fix available: **{summary.fix_available_high_critical}**")
    lines.append(f"- Known exploited findings: **{summary.known_exploited_count}**")
    lines.append(f"- CISA KEV findings: **{summary.cisa_kev_count}**")
    lines.append(f"- Expired exceptions: **{summary.expired_exception_count}**")
    lines.append("")

    lines.append("## Top Findings Requiring Action")
    lines.append("")
    if not top_rejects:
        lines.append("No reject/remediate findings identified by policy.")
    else:
        lines.append("| Severity | CVE | Package | Installed | Fixed | Decision | Reason |")
        lines.append("|---|---|---|---|---|---|---|")
        for f in top_rejects[:25]:
            lines.append(
                f"| {f.severity} | {f.vulnerability_id} | {f.package_name} | "
                f"{f.installed_version} | {f.fixed_version or 'N/A'} | "
                f"{f.risk_decision} | {f.risk_reason} |"
            )
    lines.append("")

    lines.append("## Suggested Security Approval Language")
    lines.append("")
    lines.append(
        "This runner image is approved for controlled internal CI usage subject to the documented "
        "network isolation, repository scope restrictions, least-privilege identity controls, "
        "recurring rebuild cadence, and exception expiration process. HIGH and CRITICAL findings "
        "are not blanket-accepted; they are triaged according to exploitability, fix availability, "
        "package usage, runner exposure, and documented compensating controls."
    )
    lines.append("")

    path.write_text("\n".join(lines), encoding="utf-8")


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, default=str)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Parse Trivy JSON and apply security-review logic.")
    parser.add_argument("--input", required=True, type=Path, help="Path to Trivy JSON output.")
    parser.add_argument("--output-dir", required=True, type=Path, help="Directory for review outputs.")
    parser.add_argument("--image", default="unknown", help="Image name/tag being reviewed.")
    parser.add_argument("--policy", type=Path, help="Optional YAML/JSON policy file.")
    parser.add_argument(
        "--fail-on-policy",
        action="store_true",
        help="Exit non-zero if policy status is fail. Useful after approval baseline is mature.",
    )
    args = parser.parse_args(argv)

    trivy_data = load_json(args.input)
    policy = load_policy(args.policy)
    today = date.today()

    findings = normalize_trivy_findings(trivy_data)
    classify_findings(findings, policy, today)

    output_dir: Path = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    all_csv = output_dir / "trivy-all-findings.csv"
    high_critical_csv = output_dir / "trivy-high-critical-findings.csv"
    exceptions_csv = output_dir / "trivy-exceptions.csv"
    summary_md = output_dir / "trivy-security-review-summary.md"
    review_json = output_dir / "trivy-security-review.json"

    high_critical = [f for f in findings if f.severity in {"HIGH", "CRITICAL"}]
    exceptions = [f for f in findings if f.exception_status != "none"]

    write_csv(all_csv, findings)
    write_csv(high_critical_csv, high_critical)
    write_csv(exceptions_csv, exceptions)

    output_paths = {
        "all_csv": all_csv,
        "high_critical_csv": high_critical_csv,
        "exceptions_csv": exceptions_csv,
        "summary_md": summary_md,
        "review_json": review_json,
    }
    summary = summarize(findings, args.image, output_paths)
    write_markdown_summary(summary_md, summary, findings, policy)
    write_json(review_json, {
        "summary": asdict(summary),
        "findings": [finding_to_row(f) for f in findings],
        "policy": policy,
    })

    print(f"Security review status: {summary.workflow_status.upper()}")
    print(f"Total findings: {summary.total_findings}")
    print(f"Wrote outputs to: {output_dir}")

    if args.fail_on_policy and summary.workflow_status == "fail":
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
