# terraform-module-aws-eks-landing-zone/modules/k8s-namespace/variables.tf

# Required Variables
variable "namespace_name" {
  description = "Name of the Kubernetes namespace to create"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.namespace_name)) && length(var.namespace_name) <= 63
    error_message = "Namespace name must be lowercase alphanumeric with hyphens only, max 63 characters."
  }
}

variable "team_name" {
  description = "Name of the team that owns this namespace"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod, etc.)"
  type        = string
  
  validation {
    condition     = contains(["dev", "development", "staging", "stage", "prod", "production", "test", "qa", "monitoring"], var.environment)
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production, test, qa, monitoring."
  }
}

# Namespace Configuration
variable "description" {
  description = "Description of the namespace purpose"
  type        = string
  default     = "Kubernetes namespace for application deployment"
}

variable "labels" {
  description = "Additional labels to apply to the namespace"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Additional annotations to apply to the namespace"
  type        = map(string)
  default     = {}
}

# Pod Security Standards
variable "pod_security_standard" {
  description = "Pod Security Standard to enforce (privileged, baseline, restricted)"
  type        = string
  default     = "restricted"
  
  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.pod_security_standard)
    error_message = "Pod security standard must be one of: privileged, baseline, restricted."
  }
}

# Lifecycle Management
variable "prevent_destroy" {
  description = "Prevent accidental deletion of the namespace"
  type        = bool
  default     = true
}

# Service Account Configuration
variable "create_default_service_account" {
  description = "Whether to create a default service account"
  type        = bool
  default     = true
}

variable "service_account_role_arn" {
  description = "IAM role ARN to associate with the default service account"
  type        = string
  default     = null
}

variable "service_account_annotations" {
  description = "Annotations for service accounts"
  type        = map(string)
  default     = {}
}

variable "automount_service_account_token" {
  description = "Whether to auto-mount service account tokens"
  type        = bool
  default     = false
}

variable "additional_service_accounts" {
  description = "Additional service accounts to create"
  type = map(object({
    labels          = optional(map(string), {})
    annotations     = optional(map(string), {})
    role_arn        = optional(string, null)
    automount_token = optional(bool, null)
  }))
  default = {}
}

# Secrets Configuration
variable "secrets" {
  description = "Secrets to create in the namespace"
  type = map(object({
    type        = optional(string, "Opaque")
    data        = optional(map(string), {})
    binary_data = optional(map(string), null)
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
  }))
  default = {}
}

# ConfigMaps Configuration
variable "config_maps" {
  description = "ConfigMaps to create in the namespace"
  type = map(object({
    data        = optional(map(string), {})
    binary_data = optional(map(string), {})
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
    immutable   = optional(bool, false)
  }))
  default = {}
}

# Resource Quota Configuration
variable "enable_resource_quota" {
  description = "Enable ResourceQuota for the namespace"
  type        = bool
  default     = true
}

variable "resource_quota_overrides" {
  description = "Override default resource quota values"
  type        = map(string)
  default     = {}
}

variable "enable_storage_quota" {
  description = "Enable separate storage quota"
  type        = bool
  default     = true
}

variable "storage_quota_spec" {
  description = "Storage-specific quota specifications"
  type        = map(string)
  default = {
    "requests.storage"                     = "100Gi"
    "persistentvolumeclaims"               = "10"
    "requests.ephemeral-storage"           = "50Gi"
    "limits.ephemeral-storage"             = "100Gi"
  }
}

variable "enable_object_count_quota" {
  description = "Enable object count quotas"
  type        = bool
  default     = true
}

# Object count limits
variable "max_pods" {
  description = "Maximum number of pods"
  type        = string
  default     = "50"
}

variable "max_services" {
  description = "Maximum number of services"
  type        = string
  default     = "10"
}

variable "max_secrets" {
  description = "Maximum number of secrets"
  type        = string
  default     = "20"
}

variable "max_configmaps" {
  description = "Maximum number of configmaps"
  type        = string
  default     = "20"
}

variable "max_pvcs" {
  description = "Maximum number of persistent volume claims"
  type        = string
  default     = "10"
}

variable "max_deployments" {
  description = "Maximum number of deployments"
  type        = string
  default     = "20"
}

variable "max_statefulsets" {
  description = "Maximum number of statefulsets"
  type        = string
  default     = "5"
}

variable "max_jobs" {
  description = "Maximum number of jobs"
  type        = string
  default     = "10"
}

variable "max_cronjobs" {
  description = "Maximum number of cronjobs"
  type        = string
  default     = "5"
}

variable "max_load_balancers" {
  description = "Maximum number of load balancer services"
  type        = string
  default     = "2"
}

variable "max_ingresses" {
  description = "Maximum number of ingresses"
  type        = string
  default     = "5"
}

variable "max_roles" {
  description = "Maximum number of roles"
  type        = string
  default     = "10"
}

variable "max_role_bindings" {
  description = "Maximum number of role bindings"
  type        = string
  default     = "10"
}

variable "max_hpas" {
  description = "Maximum number of horizontal pod autoscalers"
  type        = string
  default     = "10"
}

variable "max_vpas" {
  description = "Maximum number of vertical pod autoscalers"
  type        = string
  default     = "5"
}

# Priority-based quotas
variable "compute_priority_quotas" {
  description = "Resource quotas based on priority classes"
  type = map(object({
    limits = map(string)
  }))
  default = {}
}

# Environment-specific quotas
variable "enable_environment_quota" {
  description = "Enable environment-specific quotas"
  type        = bool
  default     = true
}

variable "production_quota_overrides" {
  description = "Production environment quota overrides"
  type        = map(string)
  default = {
    "requests.cpu"    = "20"
    "requests.memory" = "40Gi"
    "limits.cpu"      = "40"
    "limits.memory"   = "80Gi"
  }
}

variable "staging_quota_overrides" {
  description = "Staging environment quota overrides"
  type        = map(string)
  default = {
    "requests.cpu"    = "5"
    "requests.memory" = "10Gi"
    "limits.cpu"      = "10"
    "limits.memory"   = "20Gi"
  }
}

variable "environment_quota_scopes" {
  description = "Scopes for environment-specific quotas"
  type        = list(string)
  default     = []
}

# Quota scope selectors
variable "quota_scope_selectors" {
  description = "Scope selectors for resource quotas"
  type = list(object({
    match_expressions = list(object({
      operator   = string
      scope_name = string
      values     = list(string)
    }))
  }))
  default = []
}

# Monitoring quotas
variable "enable_monitoring_quota" {
  description = "Enable quotas for monitoring resources"
  type        = bool
  default     = false
}

variable "max_service_monitors" {
  description = "Maximum number of ServiceMonitors"
  type        = string
  default     = "10"
}

variable "max_pod_monitors" {
  description = "Maximum number of PodMonitors"
  type        = string
  default     = "10"
}

variable "max_prometheus_rules" {
  description = "Maximum number of PrometheusRules"
  type        = string
  default     = "10"
}

variable "max_grafana_dashboards" {
  description = "Maximum number of Grafana dashboards"
  type        = string
  default     = "20"
}

variable "max_grafana_datasources" {
  description = "Maximum number of Grafana datasources"
  type        = string
  default     = "5"
}

# LimitRange Configuration
variable "enable_limit_range" {
  description = "Enable LimitRange for the namespace"
  type        = bool
  default     = true
}

variable "limit_range_overrides" {
  description = "Override default limit range values"
  type        = any
  default     = {}
}

variable "enable_pod_limit_range" {
  description = "Enable pod-level LimitRange"
  type        = bool
  default     = true
}

variable "enable_pvc_limit_range" {
  description = "Enable PVC LimitRange"
  type        = bool
  default     = true
}

variable "enable_environment_limits" {
  description = "Enable environment-specific limits"
  type        = bool
  default     = true
}

variable "production_limits" {
  description = "Production environment limits"
  type = object({
    container = object({
      default_request = object({
        cpu    = string
        memory = string
      })
      default = object({
        cpu    = string
        memory = string
      })
      max = object({
        cpu    = string
        memory = string
      })
      min = object({
        cpu    = string
        memory = string
      })
    })
  })
  default = {
    container = {
      default_request = {
        cpu    = "200m"
        memory = "256Mi"
      }
      default = {
        cpu    = "1"
        memory = "1Gi"
      }
      max = {
        cpu    = "4"
        memory = "8Gi"
      }
      min = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# Ephemeral storage limits
variable "enable_ephemeral_storage_limits" {
  description = "Enable ephemeral storage limits"
  type        = bool
  default     = true
}

variable "ephemeral_storage_limits" {
  description = "Ephemeral storage limit configuration"
  type = object({
    default_request = string
    default_limit   = string
    max             = string
    min             = string
    pod_max         = string
    pod_min         = string
  })
  default = {
    default_request = "1Gi"
    default_limit   = "2Gi"
    max             = "10Gi"
    min             = "100Mi"
    pod_max         = "20Gi"
    pod_min         = "500Mi"
  }
}

# Workload-specific limits
variable "workload_specific_limits" {
  description = "Workload-specific limit ranges"
  type = map(object({
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
    limits = list(object({
      type                    = string
      default                 = optional(map(string), {})
      default_request         = optional(map(string), {})
      max                     = optional(map(string), {})
      min                     = optional(map(string), {})
      max_limit_request_ratio = optional(map(string), {})
    }))
  }))
  default = {}
}

# Network Policy Configuration
variable "enable_network_policy" {
  description = "Enable NetworkPolicies for the namespace"
  type        = bool
  default     = true
}

variable "default_deny_all" {
  description = "Create a default deny-all network policy"
  type        = bool
  default     = true
}

variable "allow_ingress_controller" {
  description = "Allow traffic from ingress controllers"
  type        = bool
  default     = true
}

variable "ingress_controller_namespaces" {
  description = "List of ingress controller namespaces to allow traffic from"
  type        = list(string)
  default     = ["ingress-nginx", "kube-system"]
}

variable "ingress_controller_selectors" {
  description = "Pod selectors for ingress controllers"
  type        = list(map(string))
  default = [
    {
      "app.kubernetes.io/name" = "ingress-nginx"
    }
  ]
}

variable "allow_intra_namespace" {
  description = "Allow communication within the namespace"
  type        = bool
  default     = true
}

variable "allow_dns" {
  description = "Allow DNS resolution"
  type        = bool
  default     = true
}

variable "allow_monitoring" {
  description = "Allow monitoring systems to scrape metrics"
  type        = bool
  default     = true
}

variable "monitoring_namespaces" {
  description = "List of monitoring namespaces to allow traffic from"
  type        = list(string)
  default     = ["monitoring", "prometheus", "kube-system"]
}

variable "monitoring_selectors" {
  description = "Pod selectors for monitoring systems"
  type        = list(map(string))
  default = [
    {
      "app.kubernetes.io/name" = "prometheus"
    }
  ]
}

variable "allow_external_egress" {
  description = "Allow egress to external services"
  type        = bool
  default     = true
}

variable "allow_http_egress" {
  description = "Allow HTTP egress (in addition to HTTPS)"
  type        = bool
  default     = false
}

variable "allowed_external_cidrs" {
  description = "List of external CIDR blocks to allow egress to"
  type = list(object({
    cidr   = string
    except = optional(list(string), [])
    ports = optional(list(object({
      protocol = string
      port     = string
    })), [])
  }))
  default = []
}

# Cross-namespace communication
variable "allowed_namespaces" {
  description = "Namespaces allowed to communicate with this namespace"
  type = map(object({
    direction = string # "ingress", "egress", or "both"
    ports = list(object({
      protocol = string
      port     = string
    }))
  }))
  default = {}
}

# Application-specific network policies
variable "application_network_policies" {
  description = "Application-specific network policies"
  type = map(object({
    pod_selector  = map(string)
    policy_types  = list(string)
    labels        = optional(map(string), {})
    annotations   = optional(map(string), {})
    ingress_rules = optional(list(object({
      from = list(object({
        namespace_selector = optional(object({
          match_labels = map(string)
        }), null)
        pod_selector = optional(object({
          match_labels = map(string)
        }), null)
        ip_block = optional(object({
          cidr   = string
          except = optional(list(string), [])
        }), null)
      }))
      ports = list(object({
        protocol = string
        port     = string
      }))
    })), [])
    egress_rules = optional(list(object({
      to = list(object({
        namespace_selector = optional(object({
          match_labels = map(string)
        }), null)
        pod_selector = optional(object({
          match_labels = map(string)
        }), null)
        ip_block = optional(object({
          cidr   = string
          except = optional(list(string), [])
        }), null)
      }))
      ports = list(object({
        protocol = string
        port     = string
      }))
    })), [])
  }))
  default = {}
}

# Network policy defaults and overrides
variable "network_policy_defaults" {
  description = "Default network policy configuration"
  type        = any
  default     = {}
}

variable "network_policy_overrides" {
  description = "Network policy configuration overrides"
  type        = any
  default     = {}
}

# Environment-specific defaults
variable "environment_defaults" {
  description = "Default configuration for development environments"
  type = object({
    resource_quota = optional(map(string), {
      "requests.cpu"       = "2"
      "requests.memory"    = "4Gi"
      "limits.cpu"         = "4"
      "limits.memory"      = "8Gi"
      "pods"               = "20"
      "services"           = "5"
      "persistentvolumeclaims" = "5"
    })
    limit_range = optional(any, {
      container = {
        default_request = {
          cpu    = "100m"
          memory = "128Mi"
        }
        default = {
          cpu    = "500m"
          memory = "512Mi"
        }
        max = {
          cpu    = "2"
          memory = "4Gi"
        }
        min = {
          cpu    = "50m"
          memory = "64Mi"
        }
        max_limit_request_ratio = {
          cpu    = "4"
          memory = "4"
        }
      }
      pod = {
        max = {
          cpu    = "4"
          memory = "8Gi"
        }
        min = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
      pvc = {
        default_request = {
          storage = "1Gi"
        }
        max = {
          storage = "50Gi"
        }
        min = {
          storage = "1Gi"
        }
      }
    })
  })
  default = {}
}

variable "environment_config" {
  description = "Environment-specific configuration overrides"
  type = map(object({
    resource_quota = optional(map(string), {})
    limit_range    = optional(any, {})
  }))
  default = {}
}

# Monitoring and feature flags
variable "enable_monitoring" {
  description = "Enable monitoring for this namespace"
  type        = bool
  default     = true
}
