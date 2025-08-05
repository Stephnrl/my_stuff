output "team_role_arn" {
  description = "ARN of the team's IAM role"
  value       = aws_iam_role.team_role.arn
}

output "team_role_name" {
  description = "Name of the team's IAM role"
  value       = aws_iam_role.team_role.name
}

output "team_policy_arn" {
  description = "ARN of the team's custom policy (if created)"
  value       = var.team_policy_type != "custom" ? aws_iam_policy.team_policy[0].arn : null
}

output "team_policy_name" {
  description = "Name of the team's custom policy (if created)"
  value       = var.team_policy_type != "custom" ? aws_iam_policy.team_policy[0].name : null
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider used for trust relationship"
  value       = data.aws_ssm_parameter.oidc_provider_arn.value
  sensitive   = true
}

output "github_trust_conditions" {
  description = "GitHub repository conditions used in trust policy"
  value       = local.github_conditions
}

output "role_trust_policy" {
  description = "The trust policy document for the role"
  value       = data.aws_iam_policy_document.github_oidc_trust.json
  sensitive   = true
}
