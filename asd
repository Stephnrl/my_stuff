output "detector_id" {
  description = "ID of the GuardDuty detector in the delegated admin (security) account."
  value       = aws_guardduty_detector.this.id
}

output "detector_arn" {
  description = "ARN of the GuardDuty detector."
  value       = aws_guardduty_detector.this.arn
}

output "publishing_destination_id" {
  description = "ID of the S3 publishing destination for findings."
  value       = aws_guardduty_publishing_destination.findings.id
}

output "findings_bucket_arn" {
  description = "ARN of the findings bucket (module-created or passed-through)."
  value       = local.findings_bucket_arn
}

output "findings_bucket_name" {
  description = "Name of the findings bucket, if the module created it."
  value       = var.create_findings_bucket ? aws_s3_bucket.findings[0].id : null
}

output "findings_kms_key_arn" {
  description = "ARN of the KMS CMK encrypting findings (module-created or passed-through)."
  value       = local.findings_kms_key_arn
}

output "findings_kms_key_alias" {
  description = "Alias of the KMS CMK, if the module created it."
  value       = var.create_findings_bucket ? aws_kms_alias.findings[0].name : null
}

output "enabled_features" {
  description = "Map of GuardDuty features managed by this module and whether they are enabled."
  value = {
    S3_DATA_EVENTS         = var.enable_s3_protection
    EKS_AUDIT_LOGS         = var.enable_eks_audit_logs
    EBS_MALWARE_PROTECTION = var.enable_ebs_malware_protection
    RDS_LOGIN_EVENTS       = var.enable_rds_login_events
    LAMBDA_NETWORK_LOGS    = var.enable_lambda_network_logs
    RUNTIME_MONITORING     = var.enable_runtime_monitoring
  }
}
