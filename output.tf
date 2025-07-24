# modules/aws-bootstrap/outputs.tf

# S3 State Bucket Information
output "terraform_state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "terraform_state_bucket_region" {
  description = "Region of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.region
}

# DynamoDB Lock Table Information
output "terraform_lock_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "terraform_lock_table_arn" {
  description = "ARN of the DynamoDB table for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.arn
}

# GitHub OIDC Provider Information
output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_github_oidc_provider_arn
}

# IAM Role Information
output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions Terraform execution"
  value       = aws_iam_role.github_actions_terraform.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions Terraform execution"
  value       = aws_iam_role.github_actions_terraform.name
}

# Terraform Backend Configuration
output "terraform_backend_config" {
  description = "Terraform backend configuration for use in other projects"
  value = {
    bucket         = aws_s3_bucket.terraform_state.bucket
    key            = "${var.terraform_state_key_prefix}/terraform.tfstate"
    region         = local.region
    dynamodb_table = aws_dynamodb_table.terraform_locks.name
    encrypt        = true
  }
}

# Complete backend configuration as a formatted string
output "terraform_backend_config_hcl" {
  description = "Formatted HCL backend configuration for copying into Terraform files"
  value = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.bucket}"
        key            = "${var.terraform_state_key_prefix}/terraform.tfstate"
        region         = "${local.region}"
        dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
        encrypt        = true
      }
    }
  EOT
}

# GitHub Actions Environment Variables
output "github_actions_env_vars" {
  description = "Environment variables for GitHub Actions workflows"
  value = {
    AWS_ROLE_ARN           = aws_iam_role.github_actions_terraform.arn
    AWS_ROLE_SESSION_NAME  = "${var.project_name}-github-actions-${var.environment}"
    TF_STATE_BUCKET        = aws_s3_bucket.terraform_state.bucket
    TF_STATE_DYNAMODB_TABLE = aws_dynamodb_table.terraform_locks.name
    TF_STATE_REGION        = local.region
  }
}

# Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources were created"
  value       = local.account_id
}

output "aws_region" {
  description = "AWS Region where resources were created"
  value       = local.region
}

# GitHub Environment Information
output "github_environment_name" {
  description = "Name of the GitHub environment created"
  value       = var.manage_github_environments ? github_repository_environment.environment[0].environment : null
}

output "github_environment_url" {
  description = "URL to the GitHub environment settings"
  value       = var.manage_github_environments ? "https://github.com/${var.github_repository_name}/settings/environments/${github_repository_environment.environment[0].environment}" : null
}

output "github_secrets_created" {
  description = "List of GitHub secrets that were created"
  value = var.manage_github_environments ? [
    "AWS_ROLE_ARN",
    "TF_STATE_BUCKET", 
    "TF_STATE_DYNAMODB_TABLE",
    "TF_STATE_REGION"
  ] : []
}
