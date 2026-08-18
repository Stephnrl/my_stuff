# Onboarding profile: builds a POA&M and full history but never fails a build.
#
# Run every team here for 2-4 weeks first. It surfaces the real backlog without
# blocking anyone, so you negotiate the enforcement date from evidence rather
# than from a guess. Moving a team straight to enforcement on day one is how
# these programs get their bypass switch worn out in week two.
name: observe
severity_source: vendor
ignore_unfixed: false
severity_sla_days:
  CRITICAL: 30
  HIGH: 30
  MEDIUM: 90
  LOW: 180
  DEFAULT: 90
grace_period_days: 0
fail_on:
  new: []
  overdue: []
  reopened: []
  escalated_into: []
deviations:
  require_expiry: true
  max_days: 90
  warn_before_expiry_days: 14
reset_sla_on_reopen: true
