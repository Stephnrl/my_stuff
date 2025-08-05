# Example usage of the GitHub Repository Module
# File: main.tf (in your parent/landing zone repository)

terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure GitHub provider
provider "github" {
  owner = var.github_organization
  token = var.github_token
}

# Example: Create a team repository with OIDC environments
module "team_data_engineering_repo" {
  source = "./modules/github-repo"

  # Basic repository configuration
  repository_name        = "team-data-engineering-infrastructure"
  repository_description = "Infrastructure as Code for Data Engineering Team"
  repository_visibility  = "private"
  
  # Repository features
  has_issues      = true
  has_projects    = true
  has_wiki        = false
  has_discussions = false
  
  # Initialize with common templates
  auto_init          = true
  gitignore_template = "Terraform"
  license_template   = "mit"
  
  # Topics for organization
  topics = [
    "terraform",
    "aws",
    "infrastructure",
    "data-engineering",
    "iac"
  ]
  
  # Branch protection for main branch
  enable_branch_protection        = true
  protected_branch_pattern        = "main"
  require_up_to_date_before_merge = true
  required_status_checks          = ["ci/terraform-plan", "ci/terraform-validate"]
  
  # PR requirements
  dismiss_stale_reviews           = true
  require_code_owner_reviews      = true
  required_approving_review_count = 1
  require_last_push_approval      = true
  
  # OIDC Environments - This is the key part for your use case!
  environments = {
    "development" = {
      wait_timer = 0
      reviewers = [{
        teams = ["data-engineering"]
        users = []
      }]
      can_admins_bypass   = true
      prevent_self_review = false
      secrets = {
        "AWS_ROLE_ARN"    = aws_iam_role.team_dev_role.arn
        "AWS_REGION"      = var.aws_region
        "ENVIRONMENT"     = "development"
      }
    }
    
    "staging" = {
      wait_timer = 5 # 5 minute wait timer
      reviewers = [{
        teams = ["data-engineering", "platform-team"]
        users = []
      }]
      can_admins_bypass   = false
      prevent_self_review = true
      secrets = {
        "AWS_ROLE_ARN"    = aws_iam_role.team_staging_role.arn
        "AWS_REGION"      = var.aws_region
        "ENVIRONMENT"     = "staging"
      }
    }
    
    "production" = {
      wait_timer = 30 # 30 minute wait timer for production
      reviewers = [{
        teams = ["platform-team", "security-team"]
        users = ["senior-engineer-1", "tech-lead"]
      }]
      can_admins_bypass   = false
      prevent_self_review = true
      secrets = {
        "AWS_ROLE_ARN"    = aws_iam_role.team_prod_role.arn
        "AWS_REGION"      = var.aws_region
        "ENVIRONMENT"     = "production"
      }
    }
  }
  
  # Repository-level secrets (not environment-specific)
  repository_secrets = {
    "TERRAFORM_CLOUD_TOKEN" = var.terraform_cloud_token
    "GITHUB_TOKEN"          = var.github_token
  }
  
  # Team access permissions
  team_access = {
    "data-engineering" = "maintain"
    "platform-team"    = "admin"
    "security-team"    = "pull"
  }
  
  # Individual collaborators if needed
  collaborators = {
    "external-consultant" = "pull"
  }
  
  # Custom issue labels for team workflow
  issue_labels = {
    "aws-infrastructure" = {
      color       = "FF9500"
      description = "Related to AWS infrastructure changes"
    }
    "security-review" = {
      color       = "D73A49"
      description = "Requires security team review"
    }
    "data-pipeline" = {
      color       = "0366D6"
      description = "Related to data pipeline infrastructure"
    }
  }
  
  # Webhooks for integration (optional)
  webhooks = {
    "slack-notifications" = {
      url          = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
      content_type = "json"
      insecure_ssl = false
      secret       = var.slack_webhook_secret
      active       = true
      events       = ["push", "pull_request", "deployment"]
    }
  }
}

# Example AWS IAM roles for OIDC (you mentioned you're not worried about this part yet)
# But including for context of how the Role ARNs would be created

resource "aws_iam_role" "team_dev_role" {
  name = "team-data-engineering-dev-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_organization}/${module.team_data_engineering_repo.repository_name}:environment:development"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "team_staging_role" {
  name = "team-data-engineering-staging-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_organization}/${module.team_data_engineering_repo.repository_name}:environment:staging"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "team_prod_role" {
  name = "team-data-engineering-prod-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_organization}/${module.team_data_engineering_repo.repository_name}:environment:production"
          }
        }
      }
    ]
  })
}

# Data sources
data "aws_caller_identity" "current" {}

# Variables for the example
variable "github_organization" {
  description = "GitHub organization name"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "terraform_cloud_token" {
  description = "Terraform Cloud API token"
  type        = string
  sensitive   = true
}

variable "slack_webhook_secret" {
  description = "Slack webhook secret"
  type        = string
  sensitive   = true
}

# Outputs
output "repository_info" {
  description = "Information about the created repository"
  value = {
    name          = module.team_data_engineering_repo.repository_name
    url           = module.team_data_engineering_repo.repository_url
    ssh_clone_url = module.team_data_engineering_repo.repository_ssh_clone_url
    environments  = module.team_data_engineering_repo.environments
  }
}
