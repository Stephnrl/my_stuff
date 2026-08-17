"""Turn raw Trivy JSON into normalized Findings.

The subtle bug this file exists to prevent: for OS packages Trivy reports
`Target` as something like "myacr.azurecr.us/team/api:v1.4.2 (debian 12.1)".
That string contains the image TAG. If it lands in the finding identity key,
every release produces an entirely new set of findings and the POA&M diff
never matches anything. We normalize it to "os:debian" instead.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Iterable

from .models import Finding, SEVERITY_ORDER

# Matches the "(debian 12.1)" / "(alpine 3.19.1)" suffix Trivy appends.
_OS_SUFFIX = re.compile(r"\(([a-z0-9\-]+)\s+[^)]*\)\s*$", re.IGNORECASE)


def normalize_target(result: dict[str, Any], vuln: dict[str, Any]) -> str:
    """Produce a location string that is stable across image versions."""
    pkg_path = (vuln.get("PkgPath") or "").strip()
    if pkg_path:
        return pkg_path

    cls = (result.get("Class") or "").lower()
    target = (result.get("Target") or "").strip()

    if cls == "os-pkgs":
        os_family = (result.get("Type") or "").strip().lower()
        if not os_family:
            m = _OS_SUFFIX.search(target)
            os_family = m.group(1).lower() if m else "unknown"
        return f"os:{os_family}"

    # lang-pkgs and friends: Target is normally a lockfile path, which is stable.
    # Defensively strip any image-ref prefix if one leaked in.
    if "@sha256:" in target or _OS_SUFFIX.search(target):
        return f"{cls or 'pkgs'}:{result.get('Type', 'unknown')}"
    return target


def _extract_cvss(vuln: dict[str, Any], prefer: str = "nvd") -> tuple[float | None, str]:
    """Pull a CVSS v3 score/vector, preferring one source but accepting any."""
    cvss = vuln.get("CVSS") or {}
    order = [prefer] + [k for k in cvss.keys() if k != prefer]
    for source in order:
        entry = cvss.get(source) or {}
        score = entry.get("V3Score", entry.get("V4Score"))
        vector = entry.get("V3Vector", entry.get("V4Vector", ""))
        if score is not None:
            return float(score), vector or ""
    return None, ""


def _severity_from_nvd(vuln: dict[str, Any]) -> str:
    """Derive a severity band from the NVD CVSS score, ignoring vendor rating."""
    score, _ = _extract_cvss(vuln, prefer="nvd")
    if score is None:
        return (vuln.get("Severity") or "UNKNOWN").upper()
    if score >= 9.0:
        return "CRITICAL"
    if score >= 7.0:
        return "HIGH"
    if score >= 4.0:
        return "MEDIUM"
    if score > 0:
        return "LOW"
    return "UNKNOWN"


def findings_from_trivy(
    report: dict[str, Any],
    severity_source: str = "vendor",
    ignore_unfixed: bool = False,
) -> list[Finding]:
    """Flatten a Trivy image report into deduplicated Findings.

    severity_source:
      "vendor" - use Trivy's Severity field (distro maintainer rating; usually
                 more accurate about real-world exploitability on that distro)
      "nvd"    - derive the band from the NVD CVSS v3 base score (usually
                 harsher; some compliance programs mandate it)
    """
    findings: dict[str, Finding] = {}

    for result in report.get("Results") or []:
        for vuln in result.get("Vulnerabilities") or []:
            fixed_version = (vuln.get("FixedVersion") or "").strip()
            if ignore_unfixed and not fixed_version:
                continue

            if severity_source == "nvd":
                severity = _severity_from_nvd(vuln)
            else:
                severity = (vuln.get("Severity") or "UNKNOWN").upper()
            if severity not in SEVERITY_ORDER:
                severity = "UNKNOWN"

            score, vector = _extract_cvss(vuln, prefer="nvd")
            identifier = vuln.get("PkgIdentifier") or {}

            f = Finding(
                vuln_id=(vuln.get("VulnerabilityID") or "").strip(),
                pkg_name=(vuln.get("PkgName") or "").strip(),
                target=normalize_target(result, vuln),
                installed_version=(vuln.get("InstalledVersion") or "").strip(),
                fixed_version=fixed_version,
                severity=severity,
                cvss_score=score,
                cvss_vector=vector,
                title=(vuln.get("Title") or "").strip()[:500],
                primary_url=(vuln.get("PrimaryURL") or "").strip(),
                pkg_type=(result.get("Type") or "").strip(),
                purl=(identifier.get("PURL") or "").strip(),
                fix_status=(vuln.get("Status") or "").strip(),
                published_date=(vuln.get("PublishedDate") or "")[:10],
            )
            if not f.vuln_id or not f.pkg_name:
                continue

            # Same key can appear twice (multiple Results touching one package).
            # Keep the highest-severity instance.
            existing = findings.get(f.finding_key)
            if existing is None or SEVERITY_ORDER.index(f.severity) < SEVERITY_ORDER.index(
                existing.severity
            ):
                findings[f.finding_key] = f

    return list(findings.values())


def scan_metadata_from_trivy(report: dict[str, Any]) -> dict[str, str]:
    """Pull DB provenance out of the report so the POA&M is reproducible."""
    meta: dict[str, str] = {}
    for key in ("SchemaVersion", "ArtifactName", "ArtifactType"):
        if key in report:
            meta[key] = str(report[key])

    metadata = report.get("Metadata") or {}
    repo_digests = metadata.get("RepoDigests") or []
    if repo_digests:
        meta["repo_digest"] = repo_digests[0]
    repo_tags = metadata.get("RepoTags") or []
    if repo_tags:
        meta["repo_tag"] = repo_tags[0]

    os_info = metadata.get("OS") or {}
    if os_info:
        meta["os"] = f"{os_info.get('Family', '')} {os_info.get('Name', '')}".strip()

    return meta


def load_report(path: str | Path) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def digest_from_ref(image_ref: str) -> str:
    """Extract sha256:... from a digest-pinned reference."""
    if "@" in image_ref:
        return image_ref.split("@", 1)[1]
    return ""
