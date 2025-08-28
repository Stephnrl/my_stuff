# terraform-module-aws-eks-landing-zone/modules/k8s-namespace/resource-quota.tf

# Primary ResourceQuota for the namespace
resource "kubernetes_resource_quota_v1" "main" {
  count = var.enable_resource_quota ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-quota"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-quota"
        "app.kubernetes.io/component" = "resource-quota"
      }
    )
    
    annotations = {
      "platform.company.com/quota-type" = "primary"
      "platform.company.com/environment" = var.environment
    }
  }
  
  spec {
    hard = local.resource_quota_spec
    
    # Scope selectors for fine-grained control
    dynamic "scope_selector" {
      for_each = var.quota_scope_selectors
      content {
        dynamic "match_expression" {
          for_each = scope_selector.value.match_expressions
          content {
            operator   = match_expression.value.operator
            scope_name = match_expression.value.scope_name
            values     = match_expression.value.values
          }
        }
      }
    }
  }
}

# Storage-specific ResourceQuota (if enabled)
resource "kubernetes_resource_quota_v1" "storage" {
  count = var.enable_storage_quota ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-storage-quota"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-storage-quota"
        "app.kubernetes.io/component" = "storage-quota"
      }
    )
    
    annotations = {
      "platform.company.com/quota-type" = "storage"
      "platform.company.com/environment" = var.environment
    }
  }
  
  spec {
    hard = var.storage_quota_spec
  }
}

# Compute-specific ResourceQuota for different priority classes
resource "kubernetes_resource_quota_v1" "compute_priority" {
  for_each = var.compute_priority_quotas
  
  metadata {
    name      = "${var.namespace_name}-${each.key}-quota"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-${each.key}-quota"
        "app.kubernetes.io/component" = "priority-quota"
        "priority-class"              = each.key
      }
    )
    
    annotations = {
      "platform.company.com/quota-type" = "priority-class"
      "platform.company.com/priority-class" = each.key
    }
  }
  
  spec {
    hard = each.value.limits
    
    scope_selector {
      match_expression {
        operator   = "In"
        scope_name = "PriorityClass"
        values     = [each.key]
      }
    }
  }
}

# Environment-specific quota adjustments
resource "kubernetes_resource_quota_v1" "environment_specific" {
  count = var.enable_environment_quota && contains(["staging", "prod"], var.environment) ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-${var.environment}-quota"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-${var.environment}-quota"
        "app.kubernetes.io/component" = "environment-quota"
      }
    )
    
    annotations = {
      "platform.company.com/quota-type" = "environment-specific"
      "platform.company.com/environment" = var.environment
    }
  }
  
  spec {
    hard = var.environment == "prod" ? var.production_quota_overrides : var.staging_quota_overrides
    
    # Apply to specific resource types only
    scopes = var.environment_quota_scopes
  }
}

# Object count quotas (separate from resource quotas for clarity)
resource "kubernetes_resource_quota_v1" "object_count" {
  count = var.enable_object_count_quota ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-object-count-quota"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-object-count-quota"
        "app.kubernetes.io/component" = "object-count-quota"
      }
    )
    
    annotations = {
      "platform.company.com/quota-type" = "object-count"
      "platform.company.com/description" = "Limits the number of Kubernetes objects"
    }
  }
  
  spec {
    hard = {
      # Core objects
      "pods"                         = var.max_pods
      "services"                     = var.max_services
      "secrets"                      = var.max_secrets
      "configmaps"                   = var.max_configmaps
      "persistentvolumeclaims"       = var.max_pvcs
      
      # Workload objects  
      "deployments.apps"             = var.max_deployments
      "statefulsets.apps"            = var.max_statefulsets
      "jobs.batch"                   = var.max_jobs
      "cronjobs.batch"               = var.max_cronjobs
      
      # Networking objects
      "services.loadbalancers"       = var.max_load_balancers
      "ingresses.networking.k8s.io"  = var.max_ingresses
      
      # RBAC objects (if teams can create them)
      "roles.rbac.authorization.k8s.io"        = var.max_roles
      "rolebindings.rbac.authorization.k8s.io" = var.max_role_bindings
      
      # Custom Resource limits (if using operators)
      "horizontalpodautoscalers.autoscaling" = var.max_hpas
      "verticalpodautoscalers.autoscaling.k8s.io" = var.max_vpas
    }
  }
}

# Monitoring ResourceQuota usage with custom resources (if monitoring is enabled)
resource "kubernetes_resource_quota_v1" "monitoring" {
  count = var.enable_monitoring_quota && var.enable_monitoring ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-monitoring-quota"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-monitoring-quota"
        "app.kubernetes.io/component" = "monitoring-quota"
      }
    )
    
    annotations = {
      "platform.company.com/quota-type" = "monitoring"
      "platform.company.com/description" = "Limits monitoring-related resources"
    }
  }
  
  spec {
    hard = {
      # Prometheus-related resources
      "prometheuses.monitoring.coreos.com"        = "1"
      "servicemonitors.monitoring.coreos.com"     = var.max_service_monitors
      "podmonitors.monitoring.coreos.com"         = var.max_pod_monitors
      "prometheusrules.monitoring.coreos.com"     = var.max_prometheus_rules
      
      # Grafana-related resources  
      "grafanadashboards.integreatly.org"         = var.max_grafana_dashboards
      "grafanadatasources.integreatly.org"        = var.max_grafana_datasources
    }
  }
}
