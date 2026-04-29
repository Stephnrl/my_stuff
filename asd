################################################################################
# Data sources
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # Resolve findings destination ARNs (module-created or externally supplied)
  findings_bucket_arn  = var.create_findings_bucket ? aws_s3_bucket.findings[0].arn : var.findings_bucket_arn
  findings_kms_key_arn = var.create_findings_bucket ? aws_kms_key.findings[0].arn : var.findings_kms_key_arn

  common_tags = merge(
    {
      ManagedBy  = "terraform"
      Module     = "terraform-aws-guardduty-cmmc"
      Compliance = "CMMC-L2"
    },
    var.tags,
  )
}

################################################################################
# Preflight validation
################################################################################

# Fail fast if caller passes create_findings_bucket=false without both ARNs.
resource "terraform_data" "preflight_validation" {
  lifecycle {
    precondition {
      condition = var.create_findings_bucket || (
        var.findings_bucket_arn != null && var.findings_kms_key_arn != null
      )
      error_message = "When create_findings_bucket = false, you must supply both findings_bucket_arn and findings_kms_key_arn."
    }
  }
}

################################################################################
# GuardDuty detector (in the delegated admin / security account)
################################################################################

resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency

  # We manage features explicitly via aws_guardduty_detector_feature below,
  # so leave the deprecated `datasources` block out.

  tags = local.common_tags
}

################################################################################
# Organization-wide configuration
#
# Delegation itself (aws_guardduty_organization_admin_account) is assumed to
# already be in place in the management account, per the caller's environment.
################################################################################

resource "aws_guardduty_organization_configuration" "this" {
  detector_id                      = aws_guardduty_detector.this.id
  auto_enable_organization_members = var.auto_enable_organization_members
}

################################################################################
# Detector features (applied to the delegated admin's own detector)
################################################################################

resource "aws_guardduty_detector_feature" "s3_data_events" {
  count       = var.enable_s3_protection ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  count       = var.enable_eks_audit_logs ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  count       = var.enable_ebs_malware_protection ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "rds_login_events" {
  count       = var.enable_rds_login_events ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "RDS_LOGIN_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "lambda_network_logs" {
  count       = var.enable_lambda_network_logs ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "LAMBDA_NETWORK_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "runtime_monitoring" {
  count       = var.enable_runtime_monitoring ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = var.runtime_monitoring_eks_addon_management ? "ENABLED" : "DISABLED"
  }

  additional_configuration {
    name   = "ECS_FARGATE_AGENT_MANAGEMENT"
    status = var.runtime_monitoring_ecs_fargate_agent_management ? "ENABLED" : "DISABLED"
  }

  additional_configuration {
    name   = "EC2_AGENT_MANAGEMENT"
    status = var.runtime_monitoring_ec2_agent_management ? "ENABLED" : "DISABLED"
  }
}

################################################################################
# Organization-level feature auto-enablement
#
# Mirror detector features so new / existing member accounts inherit them.
################################################################################

resource "aws_guardduty_organization_configuration_feature" "s3_data_events" {
  count       = var.enable_s3_protection ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "S3_DATA_EVENTS"
  auto_enable = var.auto_enable_organization_members
}

resource "aws_guardduty_organization_configuration_feature" "eks_audit_logs" {
  count       = var.enable_eks_audit_logs ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "EKS_AUDIT_LOGS"
  auto_enable = var.auto_enable_organization_members
}

resource "aws_guardduty_organization_configuration_feature" "ebs_malware_protection" {
  count       = var.enable_ebs_malware_protection ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "EBS_MALWARE_PROTECTION"
  auto_enable = var.auto_enable_organization_members
}

resource "aws_guardduty_organization_configuration_feature" "rds_login_events" {
  count       = var.enable_rds_login_events ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "RDS_LOGIN_EVENTS"
  auto_enable = var.auto_enable_organization_members
}

resource "aws_guardduty_organization_configuration_feature" "lambda_network_logs" {
  count       = var.enable_lambda_network_logs ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "LAMBDA_NETWORK_LOGS"
  auto_enable = var.auto_enable_organization_members
}

resource "aws_guardduty_organization_configuration_feature" "runtime_monitoring" {
  count       = var.enable_runtime_monitoring ? 1 : 0
  detector_id = aws_guardduty_detector.this.id
  name        = "RUNTIME_MONITORING"
  auto_enable = var.auto_enable_organization_members

  additional_configuration {
    name        = "EKS_ADDON_MANAGEMENT"
    auto_enable = var.runtime_monitoring_eks_addon_management ? var.auto_enable_organization_members : "NONE"
  }

  additional_configuration {
    name        = "ECS_FARGATE_AGENT_MANAGEMENT"
    auto_enable = var.runtime_monitoring_ecs_fargate_agent_management ? var.auto_enable_organization_members : "NONE"
  }

  additional_configuration {
    name        = "EC2_AGENT_MANAGEMENT"
    auto_enable = var.runtime_monitoring_ec2_agent_management ? var.auto_enable_organization_members : "NONE"
  }
}

################################################################################
# Publishing destination (findings export to S3)
#
# CMMC AU.L2-3.3.1 / 3.3.2: preserve audit records beyond GuardDuty's
# default 90-day console retention.
################################################################################

resource "aws_guardduty_publishing_destination" "findings" {
  detector_id     = aws_guardduty_detector.this.id
  destination_arn = local.findings_bucket_arn
  kms_key_arn     = local.findings_kms_key_arn

  # Bucket policy + KMS key policy must be in place first, or GuardDuty will
  # reject the publishing destination with a permissions error.
  depends_on = [
    aws_s3_bucket_policy.findings,
    aws_kms_key_policy.findings,
  ]
}
