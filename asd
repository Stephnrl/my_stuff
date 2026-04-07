# config-aggregator.tf — Security Account (Delegated Admin)
#
# Org-wide Config aggregator. Pulls configuration and compliance data
# from every member account automatically — no per-account auth needed
# because this account is already a delegated admin for Config.

resource "aws_iam_role" "config_aggregator" {
  name = "aws-config-aggregator-role"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "org" {
  name = "org-config-aggregator"
  tags = var.tags

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator.arn
  }
}





# cmmc-conformance-pack.tf — Security Account
#
# Deploys CMMC 2.0 Level 2 Config rules to ALL member accounts in the Org.
# Rules evaluate resources locally in each member account.
# Results aggregate back here via the Config aggregator.
#
# Download the template first:
#   cd conformance-packs
#   curl -o cmmc-2.0-level-2.yaml \
#     https://raw.githubusercontent.com/awslabs/aws-config-rules/master/aws-config-conformance-packs/Operational-Best-Practices-for-CMMC-2.0-Level-2.yaml
#
# Review and remove any rules not available in your GovCloud region before deploying.

resource "aws_config_organization_conformance_pack" "cmmc_level_2" {
  name = "cmmc-2-0-level-2"

  template_body = file("${path.module}/conformance-packs/cmmc-2.0-level-2.yaml")

  dynamic "input_parameter" {
    for_each = var.cmmc_params
    content {
      parameter_name  = input_parameter.key
      parameter_value = input_parameter.value
    }
  }

  excluded_accounts = var.conformance_pack_excluded_accounts

  depends_on = [
    aws_config_configuration_aggregator.org
  ]
}




output "config_aggregator_name" {
  description = "Name of the organization Config aggregator"
  value       = aws_config_configuration_aggregator.org.name
}

output "cmmc_conformance_pack_name" {
  description = "Name of the CMMC 2.0 Level 2 organization conformance pack"
  value       = aws_config_organization_conformance_pack.cmmc_level_2.name
}



variable "region" {
  description = "Primary AWS GovCloud region"
  type        = string
  default     = "us-gov-west-1"
}

variable "conformance_pack_excluded_accounts" {
  description = "Account IDs to exclude from the CMMC conformance pack (e.g., sandbox accounts)"
  type        = list(string)
  default     = []
}

variable "cmmc_params" {
  description = "Override parameters for the CMMC 2.0 Level 2 conformance pack"
  type        = map(string)
  default = {
    AccessKeysRotatedParamMaxAccessKeyAge                                 = "90"
    AcmCertificateExpirationCheckParamDaysToExpiration                    = "90"
    CwLoggroupRetentionPeriodCheckParamMinRetentionTime                   = "365"
    IamPasswordPolicyParamMaxPasswordAge                                  = "60"
    IamPasswordPolicyParamMinimumPasswordLength                           = "14"
    IamPasswordPolicyParamPasswordReusePrevention                         = "24"
    IamCustomerPolicyBlockedKmsActionsParamBlockedActionsPatterns         = "kms:Decrypt,kms:ReEncryptFrom"
    IamInlinePolicyBlockedKmsActionsParamBlockedActionsPatterns           = "kms:Decrypt,kms:ReEncryptFrom"
    BackupPlanMinFrequencyAndMinRetentionCheckParamRequiredFrequencyUnit  = "days"
    BackupPlanMinFrequencyAndMinRetentionCheckParamRequiredFrequencyValue = "1"
    BackupPlanMinFrequencyAndMinRetentionCheckParamRequiredRetentionDays  = "35"
  }
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    ManagedBy   = "terraform"
    Environment = "security"
  }
}











