variable "team_name" {
  description = "Name of the team (used for naming resources)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.team_name))
    error_message = "Team name must contain only alphanumeric characters and hyphens."
  }
}

variable "oidc_provider_arn_parameter" {
  description = "SSM Parameter Store path for OIDC provider ARN"
  type        = string
  default     = "/landing-zone/oidc-provider-arn"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repos" {
  description = "List of GitHub repositories that can assume this role"
  type        = list(string)
  default     = []
}

variable "permission_boundary_arn" {
  description = "ARN of permission boundary policy to attach to roles"
  type        = string
  default     = null
}

variable "team_policy_type" {
  description = "Type of permissions for the team (developer, data-scientist, admin, custom)"
  type        = string
  default     = "developer"
  validation {
    condition     = contains(["developer", "data-scientist", "admin", "custom"], var.team_policy_type)
    error_message = "Policy type must be one of: developer, data-scientist, admin, custom."
  }
}

variable "custom_policies" {
  description = "List of custom policy ARNs to attach when using custom policy type"
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID that this team will have access to"
  type        = string
  default     = null
}

variable "resource_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "max_session_duration" {
  description = "Maximum session duration for the role (in seconds)"
  type        = number
  default     = 3600
  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Max session duration must be between 3600 (1 hour) and 43200 (12 hours)."
  }
}

variable "allowed_instance_types" {
  description = "List of allowed EC2 instance types"
  type        = list(string)
  default     = ["t3.*", "t3a.*", "t4g.*", "m5.*", "m5a.*", "m6i.*"]
}

variable "deny_admin_access" {
  description = "Whether to deny administrative actions even for admin role type"
  type        = bool
  default     = true
}

variable "allowed_regions" {
  description = "List of allowed AWS regions for resource creation"
  type        = list(string)
  default     = []
}

variable "enable_cost_controls" {
  description = "Enable cost control restrictions (instance types, resource limits)"
  type        = bool
  default     = true
}

variable "additional_trusted_entities" {
  description = "Additional trusted entities for the role (e.g., AWS services)"
  type        = list(string)
  default     = []
}
