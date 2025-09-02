################################################################################
# GitHub OIDC Provider and Terraform Execution Role
# Run this ONCE to set up GitHub Actions authentication
# Save as: terraform/github-oidc-setup/main.tf
################################################################################

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Purpose     = "GitHubActionsOIDC"
      Repository  = var.github_repository
    }
  }
}

################################################################################
# Variables
################################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name (without org prefix)"
  type        = string
}

variable "github_environments" {
  description = "List of GitHub environments that can assume the role"
  type        = list(string)
  default     = ["development", "staging", "production", "production-destroy"]
}

variable "terraform_state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
}

variable "terraform_state_lock_table" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "terraform-state-lock"
}

variable "create_state_bucket" {
  description = "Whether to create the state bucket"
  type        = bool
  default     = true
}

################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}

# Get GitHub OIDC provider thumbprint
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

################################################################################
# GitHub OIDC Provider
################################################################################

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name = "github-actions-oidc-provider"
  }
}

################################################################################
# S3 Bucket for Terraform State (Optional)
################################################################################

resource "aws_s3_bucket" "terraform_state" {
  count = var.create_state_bucket ? 1 : 0

  bucket = var.terraform_state_bucket_name

  tags = {
    Name    = "Terraform State Bucket"
    Purpose = "Terraform State Storage"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  count = var.create_state_bucket ? 1 : 0

  bucket = aws_s3_bucket.terraform_state[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "terraform_state" {
  count = var.create_state_bucket ? 1 : 0

  bucket = aws_s3_bucket.terraform_state[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  count = var.create_state_bucket ? 1 : 0

  bucket = aws_s3_bucket.terraform_state[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  count = var.create_state_bucket ? 1 : 0

  bucket = aws_s3_bucket.terraform_state[0].id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

################################################################################
# DynamoDB Table for State Locking
################################################################################

resource "aws_dynamodb_table" "terraform_state_lock" {
  count = var.create_state_bucket ? 1 : 0

  name           = var.terraform_state_lock_table
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "Terraform State Lock Table"
    Purpose = "Terraform State Locking"
  }
}

################################################################################
# IAM Role for GitHub Actions Terraform Execution
################################################################################

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    sid     = "AllowGitHubOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        # Allow from main branch
        "repo:${var.github_org}/${var.github_repository}:ref:refs/heads/main",
        # Allow from pull requests
        "repo:${var.github_org}/${var.github_repository}:pull_request",
        # Allow from specific environments
        [for env in var.github_environments : 
          "repo:${var.github_org}/${var.github_repository}:environment:${env}"
        ]
      ])
    }
  }
}

resource "aws_iam_role" "github_terraform" {
  name               = "github-actions-terraform-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
  
  tags = {
    Name    = "GitHub Actions Terraform Role"
    Purpose = "Terraform execution from GitHub Actions"
  }
}

################################################################################
# IAM Policy for Terraform Execution
################################################################################

data "aws_iam_policy_document" "terraform_execution" {
  # S3 State Management
  statement {
    sid    = "TerraformStateManagement"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetObjectVersion",
      "s3:ListBucketVersions"
    ]
    resources = [
      "arn:${local.partition}:s3:::${var.terraform_state_bucket_name}",
      "arn:${local.partition}:s3:::${var.terraform_state_bucket_name}/*"
    ]
  }

  # DynamoDB State Locking
  statement {
    sid    = "TerraformStateLocking"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]
    resources = [
      "arn:${local.partition}:dynamodb:${var.aws_region}:${local.account_id}:table/${var.terraform_state_lock_table}"
    ]
  }

  # IAM Management for Contractor Roles
  statement {
    sid    = "IAMRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:UpdateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRoleTags",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:UpdateAssumeRolePolicy"
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/contractor-*",
      "arn:${local.partition}:iam::${local.account_id}:role/github-actions-terraform-role"
    ]
  }

  # IAM Policy Management
  statement {
    sid    = "IAMPolicyManagement"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:UpdatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyTags",
      "iam:TagPolicy",
      "iam:UntagPolicy"
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:policy/contractor-*"
    ]
  }

  # IAM Read Permissions
  statement {
    sid    = "IAMReadAccess"
    effect = "Allow"
    actions = [
      "iam:GetAccountAuthorizationDetails",
      "iam:GetAccountPasswordPolicy",
      "iam:GetAccountSummary",
      "iam:ListRoles",
      "iam:ListPolicies",
      "iam:ListInstanceProfiles",
      "iam:ListOpenIDConnectProviders",
      "iam:GetOpenIDConnectProvider"
    ]
    resources = ["*"]
  }

  # General Read Permissions
  statement {
    sid    = "GeneralReadAccess"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
      "account:GetAccountInformation"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_execution" {
  name        = "github-actions-terraform-policy"
  description = "Policy for GitHub Actions to manage contractor IAM resources via Terraform"
  policy      = data.aws_iam_policy_document.terraform_execution.json

  tags = {
    Name = "GitHub Actions Terraform Policy"
  }
}

resource "aws_iam_role_policy_attachment" "terraform_execution" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = aws_iam_policy.terraform_execution.arn
}

################################################################################
# Outputs
################################################################################

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_terraform_role_arn" {
  description = "ARN of the IAM role for GitHub Actions (set as TERRAFORM_ROLE_ARN secret)"
  value       = aws_iam_role.github_terraform.arn
}

output "terraform_state_bucket" {
  description = "Name of the S3 bucket for Terraform state (set as TERRAFORM_STATE_BUCKET secret)"
  value       = var.terraform_state_bucket_name
}

output "setup_instructions" {
  description = "Instructions for completing GitHub setup"
  value = <<-EOT
    GitHub Actions Setup Instructions:
    
    1. Add the following secrets to your GitHub repository:
       - TERRAFORM_ROLE_ARN: ${aws_iam_role.github_terraform.arn}
       - TERRAFORM_STATE_BUCKET: ${var.terraform_state_bucket_name}
    
    2. Create GitHub environments in Settings > Environments:
       - development (no protection rules)
       - staging (1 reviewer required)
       - production (2 reviewers required)
       - production-destroy (2 reviewers + manual approval)
    
    3. Push the workflow file to: .github/workflows/terraform-iam.yml
    
    4. The workflow will trigger on:
       - Pull requests (validate & plan)
       - Push to main (auto-apply)
       - Manual dispatch (all actions)
  EOT
}

################################################################################
# terraform.tfvars.example - Example Configuration
################################################################################
# Save as terraform.tfvars and customize

# github_org                  = "your-github-org"
# github_repository           = "contractor-iam-management"
# terraform_state_bucket_name = "your-company-terraform-state"
# terraform_state_lock_table  = "terraform-state-lock"
# create_state_bucket         = true
# aws_region                  = "us-east-1"
# github_environments = [
#   "development",
#   "staging", 
#   "production",
#   "production-destroy"
# ]
