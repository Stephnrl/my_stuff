# examples/bootstrap/main.tf
# This file should be run first to bootstrap your AWS infrastructure

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Purpose     = "bootstrap"
    }
  }
}

# Production Environment Bootstrap
module "bootstrap_prod" {
  source = "../../modules/aws-bootstrap"

  project_name        = var.project_name
  environment         = "prod"
  github_repositories = var.github_repositories

  # Security settings for production
  force_destroy_state_bucket              = false
  enable_state_lifecycle                  = true
  state_version_expiration_days           = 365  # Keep versions longer in prod
  enable_dynamodb_point_in_time_recovery  = true

  # Use existing OIDC provider if you already have one
  create_github_oidc_provider = true
  
  # Production typically needs more restrictive permissions
  additional_terraform_policies = [
    "arn:aws:iam::aws:policy/PowerUserAccess",
    # Add more specific policies as needed
  ]

  tags = {
    CostCenter = "engineering"
    Owner      = "devops-team"
  }
}

# Non-Production Environment Bootstrap
module "bootstrap_nonprod" {
  source = "../../modules/aws-bootstrap"

  project_name        = var.project_name
  environment         = "nonprod"
  github_repositories = var.github_repositories

  # More relaxed settings for non-prod
  force_destroy_state_bucket              = true   # Allow cleanup in dev/staging
  enable_state_lifecycle                  = true
  state_version_expiration_days           = 90     # Shorter retention
  enable_dynamodb_point_in_time_recovery  = false  # Cost optimization

  # Reuse the OIDC provider from prod
  create_github_oidc_provider       = false
  existing_github_oidc_provider_arn = module.bootstrap_prod.github_oidc_provider_arn

  # Non-prod might need broader permissions for experimentation
  additional_terraform_policies = [
    "arn:aws:iam::aws:policy/PowerUserAccess",
  ]

  tags = {
    CostCenter = "engineering"
    Owner      = "devops-team"
  }
}

# Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "myproject"  # Change this to your project name
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "github_repositories" {
  description = "List of GitHub repositories that can assume the roles"
  type        = list(string)
  default = [
    "your-org/your-infrastructure-repo",
    "your-org/your-application-repo"
  ]
}

# Outputs
output "prod_environment" {
  description = "Production environment configuration"
  value = {
    role_arn                = module.bootstrap_prod.github_actions_role_arn
    state_bucket           = module.bootstrap_prod.terraform_state_bucket_name
    lock_table             = module.bootstrap_prod.terraform_lock_table_name
    backend_config         = module.bootstrap_prod.terraform_backend_config
    github_env_vars        = module.bootstrap_prod.github_actions_env_vars
  }
}

output "nonprod_environment" {
  description = "Non-production environment configuration"
  value = {
    role_arn                = module.bootstrap_nonprod.github_actions_role_arn
    state_bucket           = module.bootstrap_nonprod.terraform_state_bucket_name
    lock_table             = module.bootstrap_nonprod.terraform_lock_table_name
    backend_config         = module.bootstrap_nonprod.terraform_backend_config
    github_env_vars        = module.bootstrap_nonprod.github_actions_env_vars
  }
}

# Output the backend configurations as formatted strings for easy copying
output "prod_backend_config_hcl" {
  description = "Formatted Terraform backend configuration for production"
  value       = module.bootstrap_prod.terraform_backend_config_hcl
}

output "nonprod_backend_config_hcl" {
  description = "Formatted Terraform backend configuration for non-production"
  value       = module.bootstrap_nonprod.terraform_backend_config_hcl
}
