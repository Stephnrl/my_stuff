# terraform-module-aws-eks-landing-zone/modules/k8s-rbac/variables.tf

# Required Variables
variable "namespace" {
  description = "Kubernetes namespace to create RBAC resources in"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.namespace))
    error_message = "Namespace must be lowercase alphanumeric with hyphens only."
  }
}

variable "team_name" {
  description = "Name of the team (used for naming RBAC resources)"
  type        = string
}

variable "kubernetes_group" {
  description = "Kubernetes group name that maps to EKS Access Entry"
  type        = string
  
  validation {
    condition     = length(var.kubernetes_group) > 0
    error_message = "Kubernetes group name must not be empty."
  }
}

# Permission Level Configuration
variable "permission_level" {
  description = "Permission level to grant (standard, readonly, or custom)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "readonly", "normal", "reader", "admin", "developer", "deployer", "custom"], var.permission_level)
    error_message = "Permission level must be one of: standard (recommended), readonly, custom. Legacy values (normal, reader, admin, developer, deployer) also supported for backward compatibility."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "development", "staging", "stage", "prod", "production", "test", "qa"], var.environment)
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production, test, qa."
  }
}

# Custom Rules (for permission_level = "custom")
variable "custom_rules" {
  description = "Custom RBAC rules when permission_level is 'custom'"
  type = list(object({
    api_groups     = list(string)
    resources      = list(string)
    resource_names = optional(list(string))
    verbs          = list(string)
  }))
  default = null
}

variable "custom_description" {
  description = "Description for custom role"
  type        = string
  default     = "Custom RBAC role"
}

# Additional Configuration
variable "labels" {
  description = "Additional labels to apply to RBAC resources"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Additional annotations to apply to RBAC resources"
  type        = map(string)
  default     = {}
}

# Environment Restrictions
variable "apply_environment_restrictions" {
  description = "Apply environment-specific restrictions (e.g., remove delete verbs in prod)"
  type        = bool
  default     = true
}

# Additional Subjects
variable "additional_subjects" {
  description = "Additional subjects to bind to the role (users or service accounts)"
  type = list(object({
    kind = string # "User", "Group", or "ServiceAccount"
    name = string
  }))
  default = []
  
  validation {
    condition = alltrue([
      for subject in var.additional_subjects : 
      contains(["User", "Group", "ServiceAccount"], subject.kind)
    ])
    error_message = "Subject kind must be one of: User, Group, ServiceAccount."
  }
}

# Service Account Bindings
variable "service_account_bindings" {
  description = "Map of service account names to role bindings"
  type = map(object({
    role_name = optional(string) # If null, uses the primary team role
  }))
  default = {}
}

# Cluster-Wide Access
variable "enable_cluster_readonly" {
  description = "Enable cluster-wide read-only access for the team"
  type        = bool
  default     = false
}

# Additional Custom Roles
variable "additional_roles" {
  description = "Additional custom roles to create in the namespace"
  type = map(object({
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
    rules = list(object({
      api_groups     = list(string)
      resources      = list(string)
      resource_names = optional(list(string))
      verbs          = list(string)
    }))
    subjects = list(object({
      kind = string
      name = string
    }))
  }))
  default = {}
}

# Permission Level Customization
variable "permission_overrides" {
  description = "Override default permissions for specific permission levels"
  type = map(object({
    rules = list(object({
      api_groups     = list(string)
      resources      = list(string)
      resource_names = optional(list(string))
      verbs          = list(string)
    }))
  }))
  default = {}
}

# Production-Specific Settings
variable "prod_restrictions" {
  description = "Additional restrictions for production environments"
  type = object({
    deny_exec               = optional(bool, true)
    deny_port_forward       = optional(bool, true)
    deny_secret_delete      = optional(bool, true)
    deny_configmap_delete   = optional(bool, false)
    require_approval        = optional(bool, false)
  })
  default = {
    deny_exec             = true
    deny_port_forward     = true
    deny_secret_delete    = true
    deny_configmap_delete = false
    require_approval      = false
  }
}

# Resource-Specific Permissions
variable "resource_permissions" {
  description = "Fine-grained permissions for specific resource types"
  type = object({
    deployments = optional(object({
      verbs          = optional(list(string))
      resource_names = optional(list(string))
    }))
    secrets = optional(object({
      verbs          = optional(list(string))
      resource_names = optional(list(string))
    }))
    configmaps = optional(object({
      verbs          = optional(list(string))
      resource_names = optional(list(string))
    }))
    services = optional(object({
      verbs          = optional(list(string))
      resource_names = optional(list(string))
    }))
  })
  default = {}
}

# Advanced Features
variable "enable_pod_security_policy" {
  description = "Enable Pod Security Policy bindings (deprecated in K8s 1.25+)"
  type        = bool
  default     = false
}

variable "enable_aggregation_rules" {
  description = "Enable aggregation rules for the role"
  type        = bool
  default     = false
}

variable "aggregation_rule_selectors" {
  description = "Label selectors for role aggregation"
  type = list(object({
    match_labels = map(string)
  }))
  default = []
}

# Monitoring and Auditing
variable "enable_audit_annotations" {
  description = "Add audit annotations to RBAC resources"
  type        = bool
  default     = true
}

variable "audit_contact" {
  description = "Contact information for RBAC audit purposes"
  type        = string
  default     = ""
}

# Time-Based Access (metadata only, enforcement requires external tooling)
variable "time_based_access" {
  description = "Metadata for time-based access controls"
  type = object({
    enabled    = optional(bool, false)
    start_time = optional(string, "")
    end_time   = optional(string, "")
    timezone   = optional(string, "UTC")
  })
  default = {
    enabled = false
  }
}

# Integration Settings
variable "integrate_with_external_oidc" {
  description = "Add annotations for external OIDC integration"
  type        = bool
  default     = false
}

variable "oidc_issuer" {
  description = "OIDC issuer URL"
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID"
  type        = string
  default     = ""
}
