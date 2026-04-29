terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 7.0.0"
    }
  }
}

# Deploy in the security account, which is already the GuardDuty delegated admin.
provider "aws" {
  region = "us-east-1"
  # Assume role into the security account from your CI/CD pipeline:
  # assume_role { role_arn = "arn:aws:iam::SECURITY_ACCOUNT_ID:role/TerraformDeployer" }
}

module "guardduty" {
  source = "../../"

  name_prefix                      = "cmmc-guardduty"
  finding_publishing_frequency     = "FIFTEEN_MINUTES"
  auto_enable_organization_members = "ALL"

  # All protections on by default; toggle off here if a workload type is absent.
  enable_s3_protection          = true
  enable_eks_audit_logs         = true
  enable_ebs_malware_protection = true
  enable_rds_login_events       = true
  enable_lambda_network_logs    = true
  enable_runtime_monitoring     = true

  # CMMC-aligned retention defaults (7 years)
  findings_retention_days = 2555

  # Recommended for CUI environments to prevent tampering with findings
  enable_object_lock         = true
  object_lock_mode           = "GOVERNANCE"
  object_lock_retention_days = 365

  tags = {
    Environment        = "security"
    DataClassification = "CUI"
    ComplianceScope    = "CMMC-L2"
    Owner              = "secops"
  }
}

output "detector_id" {
  value = module.guardduty.detector_id
}

output "findings_bucket" {
  value = module.guardduty.findings_bucket_name
}
