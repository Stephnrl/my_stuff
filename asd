# Default profile for internal, non-regulated workloads.
name: standard
severity_source: vendor
ignore_unfixed: false
severity_sla_days:
  CRITICAL: 30
  HIGH: 60
  MEDIUM: 120
  LOW: 365
  DEFAULT: 120
grace_period_days: 7
fail_on:
  new: [CRITICAL]
  overdue: [CRITICAL, HIGH]
  reopened: [CRITICAL]
  escalated_into: [CRITICAL]
deviations:
  require_expiry: true
  max_days: 180
  warn_before_expiry_days: 14
reset_sla_on_reopen: true
