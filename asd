output "oidc_provider_arn" {
  description = "ARN of the AAP OIDC provider registered in IAM"
  value       = aws_iam_openid_connect_provider.aap.arn
}

output "oidc_issuer_url" {
  description = "Issuer URL — configure this in AAP's AWS credential type"
  value       = local.aap_issuer_url
}

output "role_arns" {
  description = "Map of job-template-key to role ARN. Plug these into AAP AWS credentials."
  value = {
    for k, m in module.job_template_role : k => m.role_arn
  }
}
