# modules/aws-bootstrap/variables.tf

variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., prod, nonprod, dev, staging)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "github_repositories" {
  description = "List of GitHub repositories in format 'owner/repo' that can assume the role"
  type        = list(string)
  
  validation {
    condition = alltrue([
      for repo in var.github_repositories : can(regex("^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$", repo))
    ])
    error_message = "GitHub repositories must be in format 'owner/repo'."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "force_destroy_state_bucket" {
  description = "Enable force destroy on the S3 state bucket (WARNING: This allows deletion of non-empty buckets)"
  type        = bool
  default     = false
}

variable "enable_state_lifecycle" {
  description = "Enable lifecycle management for S3 state bucket"
  type        = bool
  default     = true
}

variable "state_version_expiration_days" {
  description = "Number of days to retain noncurrent versions of state files"
  type        = number
  default     = 90
  
  validation {
    condition     = var.state_version_expiration_days > 0
    error_message = "State version expiration days must be greater than 0."
  }
}

variable "enable_dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB lock table"
  type        = bool
  default     = true
}

variable "create_github_oidc_provider" {
  description = "Whether to create a new GitHub OIDC provider (set to false if one already exists)"
  type        = bool
  default     = true
}

variable "existing_github_oidc_provider_arn" {
  description = "ARN of existing GitHub OIDC provider (required if create_github_oidc_provider is false)"
  type        = string
  default     = ""
  
  validation {
    condition = var.create_github_oidc_provider || var.existing_github_oidc_provider_arn != ""
    error_message = "existing_github_oidc_provider_arn must be provided when create_github_oidc_provider is false."
  }
}

variable "additional_terraform_policies" {
  description = "List of additional IAM policy ARNs to attach to the Terraform execution role"
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/PowerUserAccess" # Adjust based on your needs
  ]
}

variable "terraform_state_key_prefix" {
  description = "Prefix for Terraform state keys in S3"
  type        = string
  default     = "terraform"
}

# GitHub Environment Management Variables
variable "manage_github_environments" {
  description = "Whether to manage GitHub environments and secrets via Terraform"
  type        = bool
  default     = false
}

variable "github_repository_name" {
  description = "GitHub repository name in format 'owner/repo' (required if manage_github_environments is true)"
  type        = string
  default     = ""
  
  validation {
    condition = !var.manage_github_environments || can(regex("^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$", var.github_repository_name))
    error_message = "GitHub repository must be in format 'owner/repo' when manage_github_environments is true."
  }
}

variable "github_reviewers" {
  description = "GitHub users and teams that can approve deployments (applied to prod environment)"
  type = object({
    users = optional(list(string), [])
    teams = optional(list(string), [])
  })
  default = {
    users = []
    teams = []
  }
}

variable "github_protected_branches" {
  description = "Enable protected branches policy for GitHub environment"
  type        = bool
  default     = true
}

variable "github_custom_branch_policies" {
  description = "Enable custom branch policies for GitHub environment"
  type        = bool
  default     = false
}

variable "github_wait_timer_minutes" {
  description = "Wait timer in minutes before deployment (0 to disable, applied to prod environment)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.github_wait_timer_minutes >= 0 && var.github_wait_timer_minutes <= 43200
    error_message = "Wait timer must be between 0 and 43200 minutes (30 days)."
  }
}

variable "additional_github_secrets" {
  description = "Additional secrets to add to the GitHub environment"
  type        = map(string)
  default     = {}
  sensitive   = true
}
