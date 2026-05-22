#!/usr/bin/env python3

"""
Generate a dynamic POA&M-style CSV and normalized JSON file from Trivy JSON output.

Intended use:
  - Run after `trivy image --format json --output trivy-results.json <image>`
  - Generate monthly review artifacts for HIGH/CRITICAL findings
  - Support DevSecOps justification, exception tracking, and remediation planning

This script does not approve risk. It creates a reviewable artifact.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from dataclasses import dataclass, asdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


SEVERITY_ORDER = {
    "UNKNOWN": 0,
    "LOW": 1,
    "MEDIUM": 2,
    "HIGH": 3,
    "CRITICAL": 4,
}


@dataclass
class PoamItem:
    poam_id: str
    status: str
    source_tool: str
    scan_date: str
    review_cycle: str
    image: str
    target: str
    target_type: str
    vulnerability_id: str
    pkg_name: str
    installed_version: str
    fixed_version: str
    severity: str
    severity_source: str
    cvss_score: str
    title: str
    description: str
    primary_url: str
    weakness_description: str
    remediation_plan: str
    milestones: str
    scheduled_completion_date: str
    owner: str
    vendor_dependency: str
    false_positive: str
    operational_requirement: str
    risk_adjustment: str
    justification: str
    comments: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a POA&M CSV/JSON from Trivy JSON scan results."
    )

    parser.add_argument("--input", required=True, help="Path to Trivy JSON file.")
    parser.add_argument("--output-csv", required=True, help="Path to write POA&M CSV.")
    parser.add_argument("--output-json", required=True, help="Path to write normalized POA&M JSON.")
    parser.add_argument("--image", required=True, help="Image name/tag that was scanned.")
    parser.add_argument("--owner", default="DevSecOps", help="Default owning team.")
    parser.add_argument(
        "--min-severity",
        default="HIGH",
        choices=list(SEVERITY_ORDER.keys()),
        help="Minimum severity to include.",
    )
    parser.add_argument(
        "--review-cycle",
        default="monthly",
        help="Review cadence, for example monthly.",
    )
    parser.add_argument(
        "--days-critical",
        type=int,
        default=30,
        help="Default remediation window for CRITICAL findings.",
    )
    parser.add_argument(
        "--days-high",
        type=int,
        default=60,
        help="Default remediation window for HIGH findings.",
    )
    parser.add_argument(
        "--days-medium",
        type=int,
        default=90,
        help="Default remediation window for MEDIUM findings.",
    )

    return parser.parse_args()


def load_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"Input file not found: {path}")

    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def safe_str(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, sort_keys=True)
    return str(value)


def first_url(vuln: Dict[str, Any]) -> str:
    references = vuln.get("References") or []
    if references:
        return safe_str(references[0])

    primary_url = vuln.get("PrimaryURL")
    if primary_url:
        return safe_str(primary_url)

    return ""


def get_cvss_score(vuln: Dict[str, Any]) -> str:
    """
    Trivy CVSS structure varies by source.
    Example:
      "CVSS": {
        "nvd": {"V3Score": 9.8, ...},
        "redhat": {"V3Score": 7.5, ...}
      }
    """
    cvss = vuln.get("CVSS") or {}
    if not isinstance(cvss, dict):
        return ""

    severity_source = vuln.get("SeveritySource")

    preferred_sources = []
    if severity_source:
        preferred_sources.append(severity_source)

    preferred_sources.extend(["nvd", "redhat", "ghsa", "ubuntu", "debian", "amazon"])

    for source in preferred_sources:
        source_cvss = cvss.get(source)
        if isinstance(source_cvss, dict):
            for key in ("V3Score", "V2Score"):
                if source_cvss.get(key) is not None:
                    return str(source_cvss[key])

    for source_cvss in cvss.values():
        if isinstance(source_cvss, dict):
            for key in ("V3Score", "V2Score"):
                if source_cvss.get(key) is not None:
                    return str(source_cvss[key])

    return ""


def remediation_due_date(
    severity: str,
    scan_dt: date,
    days_critical: int,
    days_high: int,
    days_medium: int,
) -> str:
    severity = severity.upper()

    if severity == "CRITICAL":
        delta = days_critical
    elif severity == "HIGH":
        delta = days_high
    elif severity == "MEDIUM":
        delta = days_medium
    else:
        delta = 180

    return (scan_dt + timedelta(days=delta)).isoformat()


def stable_poam_id(image: str, target: str, vuln_id: str, pkg_name: str) -> str:
    """
    Creates a deterministic ID so the same finding can be tracked month over month.
    """
    raw = f"{image}|{target}|{vuln_id}|{pkg_name}".encode("utf-8")
    digest = hashlib.sha256(raw).hexdigest()[:12].upper()
    return f"POAM-{digest}"


def default_remediation_plan(vuln: Dict[str, Any]) -> str:
    fixed_version = safe_str(vuln.get("FixedVersion"))

    if fixed_version:
        return (
            f"Update package to fixed version {fixed_version}, rebuild the runner image, "
            "rescan with Trivy, and attach scan evidence to close the item."
        )

    return (
        "No fixed version is currently listed in the scan output. Monitor upstream vendor "
        "advisory/package repository, rebuild the runner image when a fix becomes available, "
        "and document compensating controls or risk acceptance if required."
    )


def default_vendor_dependency(vuln: Dict[str, Any]) -> str:
    fixed_version = safe_str(vuln.get("FixedVersion"))
    return "No" if fixed_version else "Yes"


def default_milestones(vuln: Dict[str, Any]) -> str:
    fixed_version = safe_str(vuln.get("FixedVersion"))

    if fixed_version:
        return (
            "1. Validate applicability of CVE to runner image. "
            "2. Update affected package/base image. "
            "3. Rebuild image. "
            "4. Rescan and verify remediation. "
            "5. Submit evidence for closure."
        )

    return (
        "1. Validate applicability of CVE to runner image. "
        "2. Check vendor/upstream fix availability monthly. "
        "3. Document compensating controls. "
        "4. Rebuild and rescan when fix is available."
    )


def build_weakness_description(
    image: str,
    target: str,
    vuln: Dict[str, Any],
) -> str:
    vuln_id = safe_str(vuln.get("VulnerabilityID"))
    pkg_name = safe_str(vuln.get("PkgName"))
    installed = safe_str(vuln.get("InstalledVersion"))
    fixed = safe_str(vuln.get("FixedVersion"))
    severity = safe_str(vuln.get("Severity"))

    fixed_text = f" Fixed version: {fixed}." if fixed else " No fixed version listed by scanner."

    return (
        f"{severity} vulnerability {vuln_id} detected in package {pkg_name} "
        f"version {installed} on image {image}, target {target}.{fixed_text}"
    )


def iter_vulnerabilities(trivy: Dict[str, Any]) -> Iterable[Dict[str, Any]]:
    for result in trivy.get("Results", []) or []:
        target = safe_str(result.get("Target"))
        target_type = safe_str(result.get("Type"))

        for vuln in result.get("Vulnerabilities", []) or []:
            yield {
                "target": target,
                "target_type": target_type,
                "vulnerability": vuln,
            }


def create_poam_items(
    trivy: Dict[str, Any],
    image: str,
    owner: str,
    min_severity: str,
    review_cycle: str,
    days_critical: int,
    days_high: int,
    days_medium: int,
) -> List[PoamItem]:
    scan_dt = datetime.now(timezone.utc).date()
    scan_date = scan_dt.isoformat()
    min_rank = SEVERITY_ORDER[min_severity.upper()]

    items: List[PoamItem] = []

    for finding in iter_vulnerabilities(trivy):
        target = finding["target"]
        target_type = finding["target_type"]
        vuln = finding["vulnerability"]

        severity = safe_str(vuln.get("Severity")).upper() or "UNKNOWN"
        if SEVERITY_ORDER.get(severity, 0) < min_rank:
            continue

        vuln_id = safe_str(vuln.get("VulnerabilityID"))
        pkg_name = safe_str(vuln.get("PkgName"))
        installed_version = safe_str(vuln.get("InstalledVersion"))
        fixed_version = safe_str(vuln.get("FixedVersion"))
        title = safe_str(vuln.get("Title"))
        description = safe_str(vuln.get("Description"))
        severity_source = safe_str(vuln.get("SeveritySource"))
        cvss_score = get_cvss_score(vuln)

        poam_id = stable_poam_id(image, target, vuln_id, pkg_name)

        item = PoamItem(
            poam_id=poam_id,
            status="Open",
            source_tool="Trivy",
            scan_date=scan_date,
            review_cycle=review_cycle,
            image=image,
            target=target,
            target_type=target_type,
            vulnerability_id=vuln_id,
            pkg_name=pkg_name,
            installed_version=installed_version,
            fixed_version=fixed_version,
            severity=severity,
            severity_source=severity_source,
            cvss_score=cvss_score,
            title=title,
            description=description,
            primary_url=first_url(vuln),
            weakness_description=build_weakness_description(image, target, vuln),
            remediation_plan=default_remediation_plan(vuln),
            milestones=default_milestones(vuln),
            scheduled_completion_date=remediation_due_date(
                severity,
                scan_dt,
                days_critical,
                days_high,
                days_medium,
            ),
            owner=owner,
            vendor_dependency=default_vendor_dependency(vuln),
            false_positive="TBD",
            operational_requirement="TBD",
            risk_adjustment="TBD",
            justification="TBD - Security/system owner review required.",
            comments="Generated from Trivy scan. Validate exploitability, package usage, fix availability, and compensating controls.",
        )

        items.append(item)

    return sorted(
        items,
        key=lambda x: (
            -SEVERITY_ORDER.get(x.severity, 0),
            x.vulnerability_id,
            x.pkg_name,
            x.target,
        ),
    )


def write_csv(path: Path, items: List[PoamItem]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = list(PoamItem.__dataclass_fields__.keys())

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for item in items:
            writer.writerow(asdict(item))


def write_json(path: Path, items: List[PoamItem]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "item_count": len(items),
        "items": [asdict(item) for item in items],
    }

    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)


def main() -> int:
    args = parse_args()

    trivy_path = Path(args.input)
    output_csv = Path(args.output_csv)
    output_json = Path(args.output_json)

    trivy = load_json(trivy_path)

    items = create_poam_items(
        trivy=trivy,
        image=args.image,
        owner=args.owner,
        min_severity=args.min_severity,
        review_cycle=args.review_cycle,
        days_critical=args.days_critical,
        days_high=args.days_high,
        days_medium=args.days_medium,
    )

    write_csv(output_csv, items)
    write_json(output_json, items)

    print(f"Generated POA&M CSV: {output_csv}")
    print(f"Generated POA&M JSON: {output_json}")
    print(f"POA&M item count: {len(items)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
