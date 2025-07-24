# terraform-workspace-bootstrap/main.tf
# Single configuration that works with terraform workspaces

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  # This backend config will be empty initially for bootstrap
  # After first run, you'll migrate to use the created S3 bucket
  backend "s3" {
    # These will be provided via terraform init -backend-config
    # or will be empty for initial local state bootstrap
  }
}

# Local values that change based on workspace
locals {
  # Map workspace names to environment configurations
  environment_config = {
    prod = {
      environment                             = "prod"
      force_destroy_state_bucket              = false
      state_version_expiration_days           = 365
      enable_dynamodb_point_in_time_recovery  = true
      github_reviewers = {
        users = var.prod_reviewers
        teams = var.prod_reviewer_teams
      }
      github_protected_branches    = true
      github_wait_timer_minutes    = var.prod_wait_timer_minutes
      additional_terraform_policies = var.prod_terraform_policies
      create_github_oidc_provider  = true
    }
    
    nonprod = {
      environment                             = "nonprod"
      force_destroy_state_bucket              = true
      state_version_expiration_days           = 90
      enable_dynamodb_point_in_time_recovery  = false
      github_reviewers = {
        users = []
        teams = []
      }
      github_protected_branches    = false
      github_wait_timer_minutes    = 0
      additional_terraform_policies = var.nonprod_terraform_policies
      create_github_oidc_provider  = false  # Reuse from prod
    }
  }

  # Current workspace configuration
  current_config = local.environment_config[terraform.workspace]
  
  # Get the prod workspace OIDC provider ARN for nonprod to reuse
  # This only works after prod workspace has been created
  prod_oidc_provider_arn = terraform.workspace == "nonprod" ? var.existing_oidc_provider_arn : ""
}

# Data source to get existing OIDC provider (for nonprod workspace)
data "aws_iam_openid_connect_provider" "existing_github" {
  count = terraform.workspace == "nonprod" && var.existing_oidc_provider_arn != "" ? 1 : 0
  arn   = var.existing_oidc_provider_arn
}

# AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = terraform.workspace
      ManagedBy   = "terraform"
      Purpose     = "bootstrap"
      Workspace   = terraform.workspace
    }
  }
}

# GitHub Provider
provider "github" {
  owner = var.github_owner
}

# Single module call that adapts based on workspace
module "aws_bootstrap" {
  source = "../modules/aws-bootstrap"  # Path to your module

  project_name        = var.project_name
  environment         = local.current_config.environment
  github_repositories = var.github_repositories

  # Environment-specific settings from locals
  force_destroy_state_bucket              = local.current_config.force_destroy_state_bucket
  enable_state_lifecycle                  = true
  state_version_expiration_days           = local.current_config.state_version_expiration_days
  enable_dynamodb_point_in_time_recovery  = local.current_config.enable_dynamodb_point_in_time_recovery

  # OIDC Provider settings
  create_github_oidc_provider       = local.current_config.create_github_oidc_provider
  existing_github_oidc_provider_arn = local.prod_oidc_provider_arn

  # IAM Policies
  additional_terraform_policies = local.current_config.additional_terraform_policies

  # GitHub Environment Management
  manage_github_environments = var.manage_github_environments
  github_repository_name     = var.github_repository_name
  github_reviewers           = local.current_config.github_reviewers
  github_protected_branches  = local.current_config.github_protected_branches
  github_wait_timer_minutes  = local.current_config.github_wait_timer_minutes

  # Environment-specific secrets
  additional_github_secrets = merge(
    var.common_github_secrets,
    terraform.workspace == "prod" ? var.prod_github_secrets : var.nonprod_github_secrets
  )

  tags = {
    Environment = terraform.workspace
    CostCenter  = var.cost_center
    Owner       = var.owner_team
  }
}

# Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub organization or user name"
  type        = string
}

variable "github_repository_name" {
  description = "GitHub repository name in format 'owner/repo'"
  type        = string
}

variable "github_repositories" {
  description = "List of GitHub repositories that can assume AWS roles"
  type        = list(string)
}

variable "manage_github_environments" {
  description = "Whether to manage GitHub environments via Terraform"
  type        = bool
  default     = true
}

# Production-specific variables
variable "prod_reviewers" {
  description = "GitHub users who can approve production deployments"
  type        = list(string)
  default     = []
}

variable "prod_reviewer_teams" {
  description = "GitHub teams who can approve production deployments"
  type        = list(string)
  default     = []
}

variable "prod_wait_timer_minutes" {
  description = "Wait timer before production deployment"
  type        = number
  default     = 5
}

variable "prod_terraform_policies" {
  description = "IAM policies for production Terraform role"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
}

variable "nonprod_terraform_policies" {
  description = "IAM policies for non-production Terraform role"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
}

# GitHub Secrets
variable "common_github_secrets" {
  description = "Secrets common to all environments"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "prod_github_secrets" {
  description = "Production-specific GitHub secrets"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "nonprod_github_secrets" {
  description = "Non-production-specific GitHub secrets"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# OIDC Provider ARN (for nonprod to reuse prod's provider)
variable "existing_oidc_provider_arn" {
  description = "ARN of existing GitHub OIDC provider (for nonprod workspace)"
  type        = string
  default     = ""
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = "engineering"
}

variable "owner_team" {
  description = "Team that owns these resources"
  type        = string
  default     = "devops"
}

# Outputs
output "workspace_info" {
  description = "Current workspace information"
  value = {
    workspace           = terraform.workspace
    environment         = local.current_config.environment
    config_applied      = local.current_config
  }
}

output "bootstrap_results" {
  description = "Bootstrap results for current workspace"
  value = {
    aws_role_arn           = module.aws_bootstrap.github_actions_role_arn
    state_bucket          = module.aws_bootstrap.terraform_state_bucket_name
    lock_table            = module.aws_bootstrap.terraform_lock_table_name
    github_environment    = module.aws_bootstrap.github_environment_name
    github_secrets        = module.aws_bootstrap.github_secrets_created
    backend_config        = module.aws_bootstrap.terraform_backend_config
  }
}

output "next_steps" {
  description = "Next steps based on current workspace"
  value = terraform.workspace == "prod" ? [
    "✅ Production workspace bootstrap complete!",
    "📋 Save the OIDC provider ARN for nonprod workspace:",
    "   OIDC_ARN='${module.aws_bootstrap.github_oidc_provider_arn}'",
    "🔄 Now run nonprod workspace:",
    "   terraform workspace select nonprod",
    "   terraform apply -var='existing_oidc_provider_arn=${module.aws_bootstrap.github_oidc_provider_arn}'",
    "🚀 After both workspaces: migrate to remote state backend"
  ] : [
    "✅ Non-production workspace bootstrap complete!",
    "🎉 Both environments are now ready!",
    "🔄 Next: Migrate both workspaces to use remote state backend",
    "📚 See the migration guide for detailed steps"
  ]
}

# Backend configuration for migration
output "backend_configs" {
  description = "Backend configurations for state migration"
  value = {
    terraform_workspace = terraform.workspace
    bucket             = module.aws_bootstrap.terraform_state_bucket_name
    key                = "bootstrap/${terraform.workspace}/terraform.tfstate"
    region             = var.aws_region
    dynamodb_table     = module.aws_bootstrap.terraform_lock_table_name
    encrypt            = true
  }
}

# Example migration commands
output "migration_commands" {
  description = "Commands to migrate to remote state"
  value = [
    "# Step 1: Configure backend for current workspace",
    "terraform init -migrate-state \\",
    "  -backend-config='bucket=${module.aws_bootstrap.terraform_state_bucket_name}' \\",
    "  -backend-config='key=bootstrap/${terraform.workspace}/terraform.tfstate' \\",
    "  -backend-config='region=${var.aws_region}' \\",
    "  -backend-config='dynamodb_table=${module.aws_bootstrap.terraform_lock_table_name}' \\",
    "  -backend-config='encrypt=true'",
    "",
    "# Step 2: Verify state migration",
    "terraform plan"
  ]
}
