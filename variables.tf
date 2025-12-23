# ==============================================================================
# Variables for ARC Deployment Module
# ==============================================================================

# ------------------------------------------------------------------------------
# Namespace Configuration
# ------------------------------------------------------------------------------
variable "create_namespaces" {
  description = "Whether to create the namespaces (set to false if they already exist)"
  type        = bool
  default     = true
}

variable "controller_namespace" {
  description = "Namespace for the ARC controller"
  type        = string
  default     = "arc-systems"
}

variable "runners_namespace" {
  description = "Namespace for the runner pods"
  type        = string
  default     = "arc-runners"
}

# ------------------------------------------------------------------------------
# Common Labels
# ------------------------------------------------------------------------------
variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Helm Configuration
# ------------------------------------------------------------------------------
variable "chart_version" {
  description = "Version of the ARC Helm charts to deploy"
  type        = string
  default     = "0.10.0"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 600
}

variable "controller_release_name" {
  description = "Helm release name for the controller"
  type        = string
  default     = "arc-controller"
}

variable "runner_release_name" {
  description = "Helm release name for the runner scale set"
  type        = string
  default     = "arc-runner-set"
}

# ------------------------------------------------------------------------------
# Controller Configuration
# ------------------------------------------------------------------------------
variable "deploy_controller" {
  description = "Whether to deploy the ARC controller (set to false if already deployed)"
  type        = bool
  default     = true
}

variable "controller_image" {
  description = "Controller image configuration"
  type = object({
    repository  = string
    tag         = string
    pull_policy = string
  })
  default = {
    repository  = ""  # Empty = use chart default
    tag         = ""  # Empty = use chart default
    pull_policy = "IfNotPresent"
  }
}

variable "controller_resources" {
  description = "Resource requests and limits for the controller"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

# ------------------------------------------------------------------------------
# JFrog Configuration
# ------------------------------------------------------------------------------
variable "jfrog_config" {
  description = "JFrog Artifactory configuration for private images"
  type = object({
    enabled     = bool
    server      = string
    username    = string
    password    = string
    secret_name = string
  })
  default = {
    enabled     = false
    server      = ""
    username    = ""
    password    = ""
    secret_name = "jfrog-pull-secret"
  }
  sensitive = true
}

# ------------------------------------------------------------------------------
# GitHub Configuration
# ------------------------------------------------------------------------------
variable "github_config" {
  description = "GitHub configuration for the runners"
  type = object({
    url          = string  # Repository, Org, or Enterprise URL
    runner_group = string  # Runner group name (org/enterprise only)
  })
}

variable "github_auth" {
  description = "GitHub authentication configuration"
  type = object({
    secret_name         = string
    use_app             = bool
    app_id              = string
    app_installation_id = string
    app_private_key     = string
    pat_token           = string
  })
  sensitive = true
}

# ------------------------------------------------------------------------------
# Runner Scale Set Configuration
# ------------------------------------------------------------------------------
variable "runner_scale_set_name" {
  description = "Name of the runner scale set (used in workflow runs-on)"
  type        = string
  default     = "arc-runner-set"
}

variable "runner_scaling" {
  description = "Runner scaling configuration"
  type = object({
    min_runners = number
    max_runners = number
  })
  default = {
    min_runners = 0
    max_runners = 10
  }
}

variable "runner_image" {
  description = "Runner image configuration"
  type = object({
    repository  = string
    tag         = string
    pull_policy = string
  })
  default = {
    repository  = "ghcr.io/actions/actions-runner"
    tag         = "latest"
    pull_policy = "IfNotPresent"
  }
}

variable "runner_resources" {
  description = "Resource requests and limits for runners"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "4Gi"
    }
  }
}

# ------------------------------------------------------------------------------
# Container Mode Configuration
# ------------------------------------------------------------------------------
variable "container_mode" {
  description = "Container mode for runner pods (none, dind, kubernetes)"
  type        = string
  default     = "dind"

  validation {
    condition     = contains(["none", "dind", "kubernetes"], var.container_mode)
    error_message = "Container mode must be one of: none, dind, kubernetes"
  }
}
