# ------------------------------------------------------------------------------
# Data sources
# ------------------------------------------------------------------------------

data "aws_region" "current" {
  count = var.enabled ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = var.enabled ? 1 : 0
}

data "aws_partition" "current" {
  count = var.enabled ? 1 : 0
}

locals {
  enabled   = var.enabled
  region    = local.enabled ? data.aws_region.current[0].name : ""
  partition = local.enabled ? data.aws_partition.current[0].partition : ""

  # Build full standards ARNs from the short-form paths supplied by the caller.
  # The provider docs show two patterns:
  #   arn:aws:securityhub:::ruleset/...   (global, no region)
  #   arn:aws:securityhub:<region>::standards/...
  enabled_standards_arns = toset([
    for standard in var.enabled_standards :
    startswith(standard, "ruleset/")
    ? "arn:${local.partition}:securityhub:::${standard}"
    : "arn:${local.partition}:securityhub:${local.region}::${standard}"
  ])
}

# ------------------------------------------------------------------------------
# Enable Security Hub on this account
# ------------------------------------------------------------------------------

resource "aws_securityhub_account" "this" {
  count = local.enabled ? 1 : 0

  enable_default_standards  = var.enable_default_standards
  control_finding_generator = var.control_finding_generator
  auto_enable_controls      = var.auto_enable_controls
}

# ------------------------------------------------------------------------------
# Enable the unified Security Hub (v2) service
#
# Security Hub v2 is a separate service that correlates CSPM findings with
# GuardDuty, Inspector, and Macie signals to generate exposure findings and
# attack-path visualizations. AWS recommends enabling both.
#
# Uses the AWSCC provider because the standard AWS provider does not yet have
# a native resource. Tracking issue:
#   https://github.com/hashicorp/terraform-provider-aws/issues/46352
#
# When the aws provider adds aws_securityhub_account_v2, this resource can be
# migrated using `terraform state mv` or an `import`/`removed` block pair.
# ------------------------------------------------------------------------------

resource "awscc_securityhub_hub_v2" "this" {
  count = local.enabled && var.enable_security_hub_v2 ? 1 : 0

  tags = { for k, v in var.tags : k => v }

  depends_on = [aws_securityhub_account.this]
}

# ------------------------------------------------------------------------------
# Standards subscriptions
# https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards.html
# ------------------------------------------------------------------------------

resource "aws_securityhub_standards_subscription" "this" {
  for_each = local.enabled ? local.enabled_standards_arns : toset([])

  depends_on = [aws_securityhub_account.this]

  standards_arn = each.key
}

# ------------------------------------------------------------------------------
# Product subscriptions (e.g. GuardDuty, Inspector, Macie)
# ------------------------------------------------------------------------------

resource "aws_securityhub_product_subscription" "this" {
  for_each = local.enabled ? toset(var.subscribed_products) : toset([])

  depends_on = [aws_securityhub_account.this]

  product_arn = each.key
}

# ------------------------------------------------------------------------------
# Finding aggregator – cross-region aggregation
# ------------------------------------------------------------------------------

resource "aws_securityhub_finding_aggregator" "this" {
  count = local.enabled && var.finding_aggregator_enabled ? 1 : 0

  depends_on = [aws_securityhub_account.this]

  linking_mode      = var.finding_aggregator_linking_mode
  specified_regions = var.finding_aggregator_linking_mode != "ALL_REGIONS" ? var.finding_aggregator_regions : null
}

# ------------------------------------------------------------------------------
# Custom action targets
# ------------------------------------------------------------------------------

resource "aws_securityhub_action_target" "this" {
  for_each = local.enabled ? { for at in var.action_targets : at.identifier => at } : {}

  depends_on = [aws_securityhub_account.this]

  name        = each.value.name
  identifier  = each.value.identifier
  description = each.value.description
}
