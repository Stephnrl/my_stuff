Resolution Notes / Update:
Summary: The 33+ malware/vulnerability findings identified by Wiz are associated with Ruby Gem dependencies embedded within the GitHub Enterprise Server (GHES) virtual appliance. After investigation, these findings require no direct remediation action on our part and cannot be patched independently.
Justification:
GitHub Enterprise Server is a vendor-managed virtual appliance. All internal components — including the Ruby runtime, bundled Gems, and OS-level packages — are packaged, maintained, and patched exclusively by GitHub as part of their release cycle. Independently modifying, patching, or removing these components would risk breaking the appliance, violating GitHub's support terms, and potentially causing a service outage.
This is consistent with GitHub's own documented guidance: customers should not modify the underlying appliance and should instead apply GHES version upgrades to receive security fixes.
Remediation Plan:

A Plan of Action and Milestones (POA&M) has been created to formally track these findings for compliance purposes.
We are planning an upgrade of our GHES instance to the latest supported release. GitHub routinely updates bundled dependencies (including Ruby Gems) as part of their release process, which is expected to remediate some or all of the flagged findings.
Post-upgrade, we will re-scan the environment with Wiz and reconcile the results against the POA&M. Any residual findings that persist in the latest supported version will be documented as accepted vendor risk.

Risk Acceptance Rationale: These findings represent inherited risk from a vendor-managed appliance. The appropriate control is maintaining the appliance at a current, vendor-supported version — not direct patching of internal components. This approach aligns with standard practices for managing virtual appliances (e.g., vCenter, GitLab Omnibus, etc.).
