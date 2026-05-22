@dataclass
class PoamItem:
    poam_id: str
    status: str
    source_tool: str
    scan_date: str
    review_cycle: str

    image: str
    image_digest: str
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
    deviation_type: str
    business_justification: str
    environment_context: str
    compensating_controls: str
    exploitability_assessment: str
    remediation_constraint: str
    remediation_plan: str
    milestones: str
    scheduled_completion_date: str
    risk_acceptance_expiration: str
    review_frequency: str
    closure_criteria: str

    owner: str
    vendor_dependency: str
    false_positive: str
    operational_requirement: str
    risk_adjustment: str
    justification: str
    deviation_rationale: str
    evidence_required: str
    comments: str
