def classify_deviation_type(vuln: Dict[str, Any]) -> str:
    """
    Classify the finding into a deviation/risk handling category.

    This is intentionally conservative. It does not auto-approve risk.
    It gives Cyber a starting point for review.
    """
    pkg_name = safe_str(vuln.get("PkgName")).lower()
    fixed_version = safe_str(vuln.get("FixedVersion"))

    if not fixed_version:
        return "Vendor Dependency / Operational Requirement"

    if "terraform" in pkg_name:
        return "Operational Requirement / Temporary Risk Acceptance"

    if "azcopy" in pkg_name or "azure" in pkg_name or "az" == pkg_name:
        return "Operational Requirement"

    if "dotnet" in pkg_name or "aspnetcore" in pkg_name or "netcore" in pkg_name:
        return "Operational Requirement / Migration Dependency"

    if "node" in pkg_name or "npm" in pkg_name:
        return "Operational Requirement / Migration Dependency"

    if "python" in pkg_name or "pip" in pkg_name:
        return "Operational Requirement / Migration Dependency"

    return "Temporary Risk Acceptance"


def business_justification_for_package(vuln: Dict[str, Any]) -> str:
    pkg_name = safe_str(vuln.get("PkgName")).lower()

    if "terraform" in pkg_name:
        return (
            "Terraform is included in the enterprise GitHub Actions runner image to support "
            "approved infrastructure-as-code workflows. Terraform 1.5.7 is retained for "
            "compatibility and licensing considerations while teams migrate to approved newer "
            "versions or alternatives. Immediate removal may disrupt existing deployment pipelines."
        )

    if "azcopy" in pkg_name:
        return (
            "AzCopy is included to support application team CI/CD workflows involving Azure Storage, "
            "artifact movement, deployment automation, and operational data transfer. Removing this "
            "component may break approved deployment workflows."
        )

    if "azure" in pkg_name or pkg_name.startswith("az"):
        return (
            "Azure CLI or related Azure tooling is included to support deployment automation, "
            "resource management, CI/CD operations, and application team workflows in Azure Government. "
            "Immediate removal may disrupt approved pipeline functionality."
        )

    if "dotnet" in pkg_name or "aspnetcore" in pkg_name or "netcore" in pkg_name:
        return (
            ".NET SDK/runtime components are included to support application teams that build, test, "
            "and deploy .NET workloads. Multiple versions may be required while teams migrate between "
            "supported application frameworks."
        )

    if "node" in pkg_name or "npm" in pkg_name:
        return (
            "Node.js and related package tooling are included to support frontend builds, JavaScript "
            "application pipelines, GitHub Actions tooling, and application packaging workflows."
        )

    if "python" in pkg_name or "pip" in pkg_name:
        return (
            "Python and related package tooling are included to support automation, scripting, testing, "
            "packaging, and DevSecOps pipeline functions required by application teams."
        )

    return (
        "The affected component is included in the enterprise GitHub Actions runner image to support "
        "approved CI/CD, build, test, packaging, deployment, or operational automation workflows. "
        "Removal or immediate upgrade requires compatibility validation to avoid disrupting application teams."
    )


def environment_context() -> str:
    return (
        "The affected component is present in a self-hosted GitHub Actions runner image deployed on "
        "Azure Government AKS. Runners operate within an internal/private VNet/Subnet in a spoke VNet "
        "peered to a hub VNet with Palo Alto NVA inspection and policy enforcement. Runner workloads "
        "are isolated to a dedicated AKS node pool using taints/tolerations. Runners are ephemeral "
        "through the scale set deployment model and are recreated rather than maintained as persistent hosts."
    )


def compensating_controls_text() -> str:
    return (
        "Compensating controls include Azure Government private networking, no direct public exposure "
        "for runner workloads, hub/spoke traffic control through Palo Alto NVA, dedicated AKS runner "
        "node pool isolation using taints/tolerations, ephemeral runner lifecycle, controlled image build "
        "and release process, recurring Trivy vulnerability scans, SBOM generation where applicable, "
        "monthly POA&M review, and Cyber/security review of accepted findings."
    )


def exploitability_assessment_text(vuln: Dict[str, Any]) -> str:
    severity = safe_str(vuln.get("Severity")).upper()
    fixed_version = safe_str(vuln.get("FixedVersion"))

    base = (
        "Exploitability must be validated by the system owner and Cyber reviewer. The finding exists "
        "within a controlled CI/CD runner environment rather than a public-facing application workload. "
        "Risk is reduced by private network placement, workload isolation, ephemeral execution, and "
        "controlled pipeline usage."
    )

    if severity == "CRITICAL":
        return (
            base
            + " Because this finding is CRITICAL, it requires priority review to confirm whether the "
              "affected package is reachable, invoked by pipelines, exposed to untrusted input, or eligible "
              "for immediate remediation."
        )

    if not fixed_version:
        return (
            base
            + " No fixed version is currently listed in the scanner output, so the item should be tracked "
              "as a vendor dependency or operational requirement until a fix becomes available."
        )

    return base


def remediation_constraint_text(vuln: Dict[str, Any]) -> str:
    pkg_name = safe_str(vuln.get("PkgName")).lower()
    fixed_version = safe_str(vuln.get("FixedVersion"))

    if not fixed_version:
        return (
            "No fixed version is currently listed in the Trivy scan output. Remediation is constrained "
            "by upstream vendor/package availability. The finding will be monitored during monthly review."
        )

    if "terraform" in pkg_name:
        return (
            "Remediation is constrained by Terraform version compatibility, existing infrastructure-as-code "
            "workflow dependencies, and licensing considerations. Migration to an approved newer version or "
            "alternative must be validated before removing Terraform 1.5.7."
        )

    if "dotnet" in pkg_name or "node" in pkg_name or "python" in pkg_name:
        return (
            "Remediation is constrained by application team runtime/build compatibility. The affected runtime "
            "or SDK must be upgraded or removed only after validating that dependent pipelines continue to work."
        )

    if "azcopy" in pkg_name or "azure" in pkg_name:
        return (
            "Remediation is constrained by application team deployment workflows that depend on Azure tooling. "
            "The component will be upgraded after validating compatibility with existing CI/CD usage."
        )

    return (
        "Remediation requires validation that upgrading or removing the affected package does not disrupt "
        "approved CI/CD workflows. If compatible, the package will be updated in the next approved image release."
    )


def risk_acceptance_expiration_date(scan_dt: date, severity: str) -> str:
    """
    Expiration/re-review should usually be shorter than or equal to the remediation window.
    Adjust to your Cyber policy if they require 30/60/90-day acceptance windows.
    """
    severity = severity.upper()

    if severity == "CRITICAL":
        return (scan_dt + timedelta(days=30)).isoformat()

    if severity == "HIGH":
        return (scan_dt + timedelta(days=60)).isoformat()

    if severity == "MEDIUM":
        return (scan_dt + timedelta(days=90)).isoformat()

    return (scan_dt + timedelta(days=180)).isoformat()


def closure_criteria_text(vuln: Dict[str, Any]) -> str:
    fixed_version = safe_str(vuln.get("FixedVersion"))

    if fixed_version:
        return (
            f"Close this item when the affected package is upgraded to fixed version {fixed_version} or later, "
            "the package is removed from the runner image, or Cyber approves a documented risk adjustment, "
            "false positive, or time-bound risk acceptance. Closure must include updated Trivy scan evidence."
        )

    return (
        "Close this item when a vendor fix becomes available and is applied, the package is removed from the "
        "runner image, Cyber approves a false-positive or risk-adjustment determination, or the operational "
        "requirement is formally accepted for the current review period. Closure must include supporting evidence."
    )


def evidence_required_text() -> str:
    return (
        "Required evidence should include the Trivy scan result, image name and digest, package name/version, "
        "CVE details, SBOM if available, pipeline/image build reference, remediation validation or upgrade test "
        "results, and approval or review ticket for any accepted risk."
    )


def deviation_rationale_text(
    image: str,
    target: str,
    vuln: Dict[str, Any],
) -> str:
    vuln_id = safe_str(vuln.get("VulnerabilityID"))
    pkg_name = safe_str(vuln.get("PkgName"))
    installed_version = safe_str(vuln.get("InstalledVersion"))
    fixed_version = safe_str(vuln.get("FixedVersion"))
    severity = safe_str(vuln.get("Severity")).upper()

    fixed_text = (
        f"A fixed version is listed by the scanner: {fixed_version}."
        if fixed_version
        else "No fixed version is currently listed by the scanner."
    )

    return (
        f"{severity} vulnerability {vuln_id} was identified in package {pkg_name} "
        f"version {installed_version} within the self-hosted GitHub Actions runner image {image}, "
        f"target {target}. {fixed_text} "
        "The affected component is included to support approved application team CI/CD workflows. "
        "Immediate removal or upgrade may disrupt build, test, packaging, infrastructure deployment, "
        "or Azure deployment automation activities. "
        "The finding is accepted as a managed, time-bound risk for the current review period and is tracked "
        "in the POA&M. Risk is reduced by Azure Government private networking, hub/spoke traffic inspection "
        "through Palo Alto NVA, dedicated AKS runner node pool isolation using taints/tolerations, ephemeral "
        "runner lifecycle through the scale set deployment model, controlled image builds, recurring vulnerability "
        "scanning, and monthly review. "
        "This deviation does not represent permanent approval. The finding will be reassessed during the next "
        "review cycle and remediated when a fixed version is available, compatibility is validated, the component "
        "is no longer operationally required, or Cyber determines the risk must be remediated sooner."
    )
