################################################################################
# Core / naming
################################################################################

variable "name_prefix" {
  description = "Prefix applied to created resources (bucket, KMS alias, etc.)."
  type        = string
  default     = "org-guardduty"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase alphanumeric and hyphens, starting/ending with alphanumeric."
  }
}

variable "tags" {
  description = "Tags applied to all resources. For CMMC scoping, include a data classification tag (e.g. `DataClassification = \"CUI\"`)."
  type        = map(string)
  default     = {}
}

################################################################################
# Detector
################################################################################

variable "finding_publishing_frequency" {
  description = "Frequency at which GuardDuty exports updated findings. CMMC SI.L2-3.14.3 favors faster alerting; FIFTEEN_MINUTES is the most aggressive."
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.finding_publishing_frequency)
    error_message = "Must be FIFTEEN_MINUTES, ONE_HOUR, or SIX_HOURS."
  }
}

################################################################################
# Organization enrollment
################################################################################

variable "auto_enable_organization_members" {
  description = "Controls whether GuardDuty is auto-enabled for member accounts. ALL = enable for all existing and new. NEW = only new joiners. NONE = manual."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "NEW", "NONE"], var.auto_enable_organization_members)
    error_message = "Must be ALL, NEW, or NONE."
  }
}

################################################################################
# Protection plans / features
#
# All features default to enabled for CMMC L2 coverage (SI.L2-3.14.6/7).
# Flip individual features off if a workload type is not present, to control
# cost (e.g. disable RDS_LOGIN_EVENTS if you do not run Aurora).
################################################################################

variable "enable_s3_protection" {
  description = "Enable S3 Protection (monitors S3 data events). Recommended for any env storing CUI in S3."
  type        = bool
  default     = true
}

variable "enable_eks_audit_logs" {
  description = "Enable EKS audit log monitoring."
  type        = bool
  default     = true
}

variable "enable_ebs_malware_protection" {
  description = "Enable Malware Protection for EC2 (scans EBS volumes on suspicious findings)."
  type        = bool
  default     = true
}

variable "enable_rds_login_events" {
  description = "Enable RDS Protection (Aurora anomalous login detection)."
  type        = bool
  default     = true
}

variable "enable_lambda_network_logs" {
  description = "Enable Lambda Protection (monitors Lambda network activity)."
  type        = bool
  default     = true
}

variable "enable_runtime_monitoring" {
  description = "Enable unified Runtime Monitoring (EC2, ECS-Fargate, EKS). This is mutually exclusive with EKS_RUNTIME_MONITORING; the module enforces this."
  type        = bool
  default     = true
}

variable "runtime_monitoring_ec2_agent_management" {
  description = "Let GuardDuty auto-manage the runtime agent on EC2 (SSM-based install/update). Only used if enable_runtime_monitoring = true."
  type        = bool
  default     = true
}

variable "runtime_monitoring_ecs_fargate_agent_management" {
  description = "Let GuardDuty auto-manage the runtime agent on ECS Fargate tasks. Only used if enable_runtime_monitoring = true."
  type        = bool
  default     = true
}

variable "runtime_monitoring_eks_addon_management" {
  description = "Let GuardDuty manage the EKS add-on for runtime monitoring. Only used if enable_runtime_monitoring = true."
  type        = bool
  default     = true
}

################################################################################
# Findings export (S3 publishing destination)
#
# CMMC AU.L2-3.3.1/2/8: retain audit records, protect audit info at rest
# and in transit. The module creates an encrypted S3 bucket and CMK by default.
################################################################################

variable "create_findings_bucket" {
  description = "If true, create the S3 bucket and KMS CMK for findings export. Set to false if you publish findings to a bucket in a separate logging account (supply findings_bucket_arn and findings_kms_key_arn)."
  type        = bool
  default     = true
}

variable "findings_bucket_name" {
  description = "Override the generated findings bucket name. If null, a name is derived from name_prefix and the account ID. Only used when create_findings_bucket = true."
  type        = string
  default     = null
}

variable "findings_bucket_arn" {
  description = "ARN of a pre-existing findings bucket. Required when create_findings_bucket = false."
  type        = string
  default     = null
}

variable "findings_kms_key_arn" {
  description = "ARN of a pre-existing KMS CMK used to encrypt findings. Required when create_findings_bucket = false."
  type        = string
  default     = null
}

variable "findings_retention_days" {
  description = "Total retention (days) for exported findings before expiration. Default 2555 (~7 years) aligns with common CMMC/DFARS audit-retention expectations. Set to 0 to disable expiration entirely."
  type        = number
  default     = 2555

  validation {
    condition     = var.findings_retention_days == 0 || var.findings_retention_days >= 365
    error_message = "findings_retention_days must be 0 (no expiration) or >= 365."
  }
}

variable "findings_transition_to_ia_days" {
  description = "Days after which findings transition to S3 Standard-IA."
  type        = number
  default     = 30
}

variable "findings_transition_to_glacier_days" {
  description = "Days after which findings transition to Glacier Flexible Retrieval for long-term retention."
  type        = number
  default     = 365
}

variable "enable_object_lock" {
  description = "Enable S3 Object Lock on the findings bucket (WORM protection for audit integrity, CMMC AU.L2-3.3.8). Must be set at bucket creation; changing this later requires recreating the bucket."
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Object Lock retention mode: GOVERNANCE (privileged users can override) or COMPLIANCE (no one can override). COMPLIANCE is stricter but irrevocable."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retention_days" {
  description = "Default Object Lock retention in days when enable_object_lock = true."
  type        = number
  default     = 365
}

variable "kms_deletion_window_days" {
  description = "KMS CMK deletion waiting period (7-30)."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "Must be between 7 and 30."
  }
}
