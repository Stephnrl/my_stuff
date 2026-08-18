exceptions:
  # Real vulnerability, mitigated architecturally.
  - component_id: org/platform/api
    vuln_id: CVE-2024-0001
    pkg_name: openssl
    deviation_type: Risk Adjusted
    justification: >-
      TLS is terminated at the ingress gateway; this container never parses
      untrusted certificates. Exploitation requires attacker-controlled input
      to the affected code path, which is unreachable in this deployment.
    approved_by: security-team
    ref: DR-2026-0042
    expires_on: 2026-11-01

  # Scanner misattribution.
  - component_id: org/platform/api
    vuln_id: CVE-2024-0003
    pkg_name: libxml2
    target: "os:debian"
    deviation_type: False Positive
    justification: >-
      Advisory applies to the python binding, which is not installed. Verified
      against the SBOM for digest sha256:3f2a...; only the shared library is
      present and it is not linked by any process in the image.
    approved_by: security-team
    ref: DR-2026-0043
    expires_on: 2026-10-15

  # Vendor dependency: no upstream fix exists yet.
  - component_id: org/platform/*
    vuln_id: CVE-2024-0004
    pkg_name: curl
    deviation_type: Operational Requirement
    justification: >-
      No fixed version published by the distro maintainer as of 2026-08-16.
      Tracked upstream at bugs.example/12345. Egress is restricted to an
      allow-listed proxy, limiting exposure. Re-review when the fix ships.
    approved_by: security-team
    ref: DR-2026-0044
    expires_on: 2026-09-30
