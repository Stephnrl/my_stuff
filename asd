# FedRAMP Moderate-aligned profile.
#
# Remediation timelines below reflect the commonly applied FedRAMP continuous
# monitoring windows (High 30 days, Moderate 90, Low 180). CONFIRM THESE
# AGAINST YOUR OWN SSP AND YOUR 3PAO before treating them as authoritative -
# they are a starting point, not compliance advice.
name: fedramp-moderate

# "vendor" uses the distro maintainer's rating (Trivy's Severity field).
# "nvd" derives the band from the NVD CVSS v3 base score - harsher, and what
# some assessors expect. Switching this WILL reclassify existing findings and
# show up as severity drift on the next run; expect a noisy first scan.
severity_source: vendor

# Report everything, including vulnerabilities with no available fix. Unfixed
# criticals still belong in the POA&M with a vendor-dependency deviation.
ignore_unfixed: false

severity_sla_days:
  CRITICAL: 30
  HIGH: 30
  MEDIUM: 90
  LOW: 180
  DEFAULT: 90

# Days a brand-new finding may sit before it fails the build. 0 = fail
# immediately. A small window (3-7) absorbs the case where a CVE is disclosed
# between a team's last green build and their next one.
grace_period_days: 0

fail_on:
  new: [CRITICAL, HIGH]
  overdue: [CRITICAL, HIGH, MEDIUM]
  reopened: [CRITICAL, HIGH]
  # An existing Medium reclassified upward is not "new", so without this rule
  # it would slip through every gate.
  escalated_into: [CRITICAL]

deviations:
  require_expiry: true
  max_days: 90
  allowed_types:
    - Risk Adjusted
    - False Positive
    - Operational Requirement
  warn_before_expiry_days: 14

# A regression restarts the remediation clock. Set false if your assessor
# wants continuity from the original discovery date instead.
reset_sla_on_reopen: true
