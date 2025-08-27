# terraform-module-aws-eks-landing-zone/modules/team-iam-role/variables.tf

# Required Variables
variable "team_name" {
  description = "Name of the team (used for naming resources and namespaces)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.team_name)) && length(var.team_name) <= 32
    error_message = "Team name must be lowercase alphanumeric with hyphens only, max 32 characters."
  }
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repositories" {
  description = "List of GitHub repository names that can assume this role"
  type        = list(string)
  
  validation {
    condition     = length(var.github_repositories) > 0
    error_message = "At least one GitHub repository must be specified."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  type        = string
  
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.oidc_provider_arn))
    error_message = "OIDC provider ARN must be valid GitHub Actions provider."
  }
}

# GitHub Configuration
variable "github_environments" {
  description = "List of GitHub environments that can assume this role (optional, allows any if not specified)"
  type        = list(string)
  default     = null
}

# Console Access Configuration
variable "enable_console_access" {
  description = "Whether to allow AWS Console access to this role"
  type        = bool
  default     = true
}

variable "require_mfa" {
  description = "Whether to require MFA for console access"
  type        = bool
  default     = true
}

variable "required_principal_tags" {
  description = "Required principal tags for console access"
  type        = map(string)
  default = {
    Department = "engineering"
  }
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds (1 hour to 12 hours)"
  type        = number
  default     = 3600  # 1 hour
  
  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Session duration must be between 1 hour (3600) and 12 hours (43200) seconds."
  }
}

# EKS Configuration
variable "cluster_arn" {
  description = "EKS cluster ARN (optional, will use wildcard if not provided)"
  type        = string
  default     = null
}

# AWS Services Access
variable "enable_ecr_access" {
  description = "Whether to grant ECR access"
  type        = bool
  default     = true
}

variable "ecr_repositories" {
  description = "List of ECR repository names to grant access to"
  type        = list(string)
  default     = []
  
  # Auto-generate team-specific repos if not provided
  validation {
    condition = length(var.ecr_repositories) > 0 || !var.enable_ecr_access
    error_message = "ECR repositories must be specified when ECR access is enabled."
  }
}

variable "s3_buckets" {
  description = "List of S3 bucket names to grant access to"
  type        = list(string)
  default     = []
}

variable "enable_cloudwatch_logs" {
  description = "Whether to grant CloudWatch Logs access"
  type        = bool
  default     = false
}

# Custom Policies
variable "custom_policies" {
  description = "Map of custom IAM policies to attach (name -> policy JSON)"
  type        = map(string)
  default     = {}
}

variable "managed_policy_arns" {
  description = "List of AWS managed policy ARNs to attach"
  type        = list(string)
  default     = []
}

# Advanced Configuration
variable "path" {
  description = "Path for the IAM role"
  type        = string
  default     = "/"
  
  validation {
    condition     = can(regex("^/.*/$", var.path)) || var.path == "/"
    error_message = "Path must begin and end with '/' or be just '/'."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary policy (optional)"
  type        = string
  default     = null
}

# Tagging
variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "enable_assume_role_policy_validation" {
  description = "Whether to validate assume role policy conditions"
  type        = bool
  default     = true
}

# AWS Services Integration
variable "additional_aws_services" {
  description = "Additional AWS services configuration"
  type = object({
    secrets_manager = optional(object({
      enabled = bool
      secrets = optional(list(string), [])
    }), { enabled = false })
    
    ssm = optional(object({
      enabled    = bool
      parameters = optional(list(string), [])
    }), { enabled = false })
    
    rds = optional(object({
      enabled    = bool
      db_clusters = optional(list(string), [])
    }), { enabled = false })
  })
  default = {}
}

# Environment-specific settings
variable "environment_config" {
  description = "Environment-specific configuration"
  type = map(object({
    max_session_duration = optional(number)
    additional_policies  = optional(map(string), {})
    tags                = optional(map(string), {})
  }))
  default = {}
}
