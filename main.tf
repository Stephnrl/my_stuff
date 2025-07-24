# modules/aws-bootstrap/main.tf

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for consistent naming and tagging
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project      = var.project_name
    ManagedBy    = "terraform"
    Module       = "aws-bootstrap"
  })

  # S3 bucket name - must be globally unique
  state_bucket_name = "${var.project_name}-terraform-state-${var.environment}-${local.account_id}"
  
  # DynamoDB table name
  lock_table_name = "${var.project_name}-terraform-locks-${var.environment}"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.state_bucket_name
  force_destroy = var.force_destroy_state_bucket

  tags = merge(local.common_tags, {
    Name        = local.state_bucket_name
    Description = "Terraform state storage for ${var.project_name} ${var.environment}"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy - Deny unencrypted uploads and enforce SSL
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.terraform_state.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
        }
      },
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  count  = var.enable_state_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "terraform_state_lifecycle"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.state_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name           = local.lock_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = local.lock_table_name
    Description = "Terraform state locking for ${var.project_name} ${var.environment}"
  })
}

# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0
  
  url = "https://token.actions.githubusercontent.com"
  
  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1", # GitHub's thumbprint as of 2023
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"  # Backup thumbprint
  ]

  tags = merge(local.common_tags, {
    Name        = "github-oidc-${var.environment}"
    Description = "GitHub OIDC provider for ${var.project_name} ${var.environment}"
  })
}

# IAM Role for GitHub Actions Terraform
resource "aws_iam_role" "github_actions_terraform" {
  name        = "${var.project_name}-github-actions-terraform-${var.environment}"
  description = "Role for GitHub Actions to run Terraform in ${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_github_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              for repo in var.github_repositories : "repo:${repo}:environment:${var.environment}"
            ]
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-github-actions-terraform-${var.environment}"
    Description = "GitHub Actions Terraform role for ${var.environment}"
  })
}

# IAM Policy for Terraform State Management
resource "aws_iam_policy" "terraform_state_management" {
  name        = "${var.project_name}-terraform-state-${var.environment}"
  description = "Policy for Terraform state management in ${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Sid    = "TerraformStateDynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = aws_dynamodb_table.terraform_locks.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach state management policy to role
resource "aws_iam_role_policy_attachment" "terraform_state_management" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = aws_iam_policy.terraform_state_management.arn
}

# Additional IAM policies for Terraform operations
resource "aws_iam_role_policy_attachment" "terraform_additional_policies" {
  for_each = toset(var.additional_terraform_policies)
  
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = each.value
}
