# terraform-module-aws-eks-landing-zone/modules/k8s-namespace/outputs.tf

# Primary Namespace Information
output "namespace_name" {
  description = "Name of the created namespace"
  value       = kubernetes_namespace_v1.namespace.metadata[0].name
}

output "namespace_uid" {
  description = "UID of the created namespace"
  value       = kubernetes_namespace_v1.namespace.metadata[0].uid
}

output "namespace_labels" {
  description = "Labels applied to the namespace"
  value       = kubernetes_namespace_v1.namespace.metadata[0].labels
}

output "namespace_annotations" {
  description = "Annotations applied to the namespace"
  value       = kubernetes_namespace_v1.namespace.metadata[0].annotations
}

# Team and Environment Information
output "team_name" {
  description = "Team that owns this namespace"
  value       = var.team_name
}

output "environment" {
  description = "Environment for this namespace"
  value       = var.environment
}

output "pod_security_standard" {
  description = "Pod Security Standard enforced in this namespace"
  value       = var.pod_security_standard
}

# Service Accounts
output "default_service_account_name" {
  description = "Name of the default service account (if created)"
  value       = var.create_default_service_account ? kubernetes_service_account_v1.default[0].metadata[0].name : null
}

output "additional_service_accounts" {
  description = "Names of additional service accounts created"
  value = {
    for name, sa in kubernetes_service_account_v1.additional : 
    name => sa.metadata[0].name
  }
}

output "service_account_role_arn" {
  description = "IAM role ARN associated with service accounts"
  value       = var.service_account_role_arn
}

# Secrets and ConfigMaps
output "secrets" {
  description = "Names of secrets created in the namespace"
  value = {
    for name, secret in kubernetes_secret_v1.secrets : 
    name => secret.metadata[0].name
  }
  sensitive = true
}

output "config_maps" {
  description = "Names of ConfigMaps created in the namespace"
  value = {
    for name, cm in kubernetes_config_map_v1.config_maps : 
    name => cm.metadata[0].name
  }
}

# Resource Quota Information
output "resource_quota_enabled" {
  description = "Whether resource quotas are enabled"
  value       = var.enable_resource_quota
}

output "primary_resource_quota_name" {
  description = "Name of the primary resource quota (if created)"
  value       = var.enable_resource_quota ? kubernetes_resource_quota_v1.main[0].metadata[0].name : null
}

output "resource_quota_spec" {
  description = "Resource quota specifications applied"
  value       = var.enable_resource_quota ? local.resource_quota_spec : {}
}

output "storage_quota_enabled" {
  description = "Whether storage quotas are enabled"
  value       = var.enable_storage_quota
}

output "storage_quota_name" {
  description = "Name of the storage quota (if created)"
  value       = var.enable_storage_quota ? kubernetes_resource_quota_v1.storage[0].metadata[0].name : null
}

output "object_count_quota_enabled" {
  description = "Whether object count quotas are enabled"
  value       = var.enable_object_count_quota
}

output "priority_quotas" {
  description = "Priority-based resource quotas created"
  value = {
    for name, quota in kubernetes_resource_quota_v1.compute_priority : 
    name => {
      name = quota.metadata[0].name
      spec = quota.spec[0].hard
    }
  }
}

# LimitRange Information
output "limit_range_enabled" {
  description = "Whether limit ranges are enabled"
  value       = var.enable_limit_range
}

output "container_limit_range_name" {
  description = "Name of the container limit range (if created)"
  value       = var.enable_limit_range ? kubernetes_limit_range_v1.container_limits[0].metadata[0].name : null
}

output "limit_range_spec" {
  description = "Limit range specifications applied"
  value       = var.enable_limit_range ? local.limit_range_spec : {}
}

output "pod_limit_range_enabled" {
  description = "Whether pod-level limit ranges are enabled"
  value       = var.enable_pod_limit_range
}

output "pvc_limit_range_enabled" {
  description = "Whether PVC limit ranges are enabled"
  value       = var.enable_pvc_limit_range
}

# Network Policy Information
output "network_policy_enabled" {
  description = "Whether network policies are enabled"
  value       = var.enable_network_policy
}

output "default_deny_all_enabled" {
  description = "Whether default deny-all policy is enabled"
  value       = var.enable_network_policy && var.default_deny_all
}

output "network_policies_created" {
  description = "List of network policies created"
  value = compact([
    var.enable_network_policy && var.default_deny_all ? kubernetes_network_policy_v1.default_deny_all[0].metadata[0].name : "",
    var.enable_network_policy && var.allow_ingress_controller ? kubernetes_network_policy_v1.allow_ingress_controller[0].metadata[0].name : "",
    var.enable_network_policy && var.allow_intra_namespace ? kubernetes_network_policy_v1.allow_intra_namespace[0].metadata[0].name : "",
    var.enable_network_policy && var.allow_dns ? kubernetes_network_policy_v1.allow_dns[0].metadata[0].name : "",
    var.enable_network_policy && var.allow_monitoring ? kubernetes_network_policy_v1.allow_monitoring[0].metadata[0].name : "",
    var.enable_network_policy && var.allow_external_egress ? kubernetes_network_policy_v1.allow_external_egress[0].metadata[0].name : ""
  ])
}

output "cross_namespace_policies" {
  description = "Cross-namespace network policies created"
  value = {
    for name, policy in kubernetes_network_policy_v1.allow_cross_namespace : 
    name => policy.metadata[0].name
  }
}

output "application_network_policies" {
  description = "Application-specific network policies created"
  value = {
    for name, policy in kubernetes_network_policy_v1.application_specific : 
    name => policy.metadata[0].name
  }
}

# Security Configuration Summary
output "security_configuration" {
  description = "Summary of security configuration applied"
  value = {
    pod_security_standard     = var.pod_security_standard
    resource_quota_enabled    = var.enable_resource_quota
    limit_range_enabled       = var.enable_limit_range
    network_policy_enabled    = var.enable_network_policy
    default_deny_all          = var.enable_network_policy && var.default_deny_all
    service_account_token_automount = var.automount_service_account_token
  }
}

# Resource Limits Summary
output "resource_limits_summary" {
  description = "Summary of resource limits and quotas"
  value = {
    max_pods           = var.max_pods
    max_services       = var.max_services
    max_deployments    = var.max_deployments
    max_load_balancers = var.max_load_balancers
    resource_quota     = var.enable_resource_quota ? local.resource_quota_spec : {}
    container_limits   = var.enable_limit_range ? local.limit_range_spec.container : {}
  }
}

# Monitoring Information
output "monitoring_enabled" {
  description = "Whether monitoring is enabled for this namespace"
  value       = var.enable_monitoring
}

output "monitoring_quota_enabled" {
  description = "Whether monitoring quotas are enabled"
  value       = var.enable_monitoring_quota
}

# Integration Information for Other Modules
output "integration_info" {
  description = "Information for integrating with other modules"
  value = {
    namespace_name          = kubernetes_namespace_v1.namespace.metadata[0].name
    team_name              = var.team_name
    environment            = var.environment
    labels                 = local.common_labels
    resource_quota_enabled = var.enable_resource_quota
    network_policy_enabled = var.enable_network_policy
    pod_security_standard  = var.pod_security_standard
  }
}

# RBAC Integration
output "rbac_integration" {
  description = "Information for RBAC module integration"
  value = {
    namespace           = kubernetes_namespace_v1.namespace.metadata[0].name
    kubernetes_group    = "${var.team_name}-users"
    service_accounts    = merge(
      var.create_default_service_account ? {
        "default" = kubernetes_service_account_v1.default[0].metadata[0].name
      } : {},
      {
        for name, sa in kubernetes_service_account_v1.additional : 
        name => sa.metadata[0].name
      }
    )
  }
}

# Monitoring Integration
output "monitoring_integration" {
  description = "Information for monitoring system integration"
  value = {
    namespace     = kubernetes_namespace_v1.namespace.metadata[0].name
    team          = var.team_name
    environment   = var.environment
    labels        = local.common_labels
    enabled       = var.enable_monitoring
    quota_enabled = var.enable_monitoring_quota
  }
}

# Network Policy Integration
output "network_policy_integration" {
  description = "Information for network policy management"
  value = {
    namespace              = kubernetes_namespace_v1.namespace.metadata[0].name
    team                   = var.team_name
    environment            = var.environment
    enabled                = var.enable_network_policy
    default_deny_all       = var.default_deny_all
    allowed_namespaces     = keys(var.allowed_namespaces)
    ingress_controller_access = var.allow_ingress_controller
    monitoring_access      = var.allow_monitoring
    external_egress        = var.allow_external_egress
  }
}

# Configuration Validation
output "configuration_validation" {
  description = "Configuration validation summary"
  value = {
    namespace_created       = kubernetes_namespace_v1.namespace.metadata[0].name != ""
    quotas_applied         = var.enable_resource_quota ? length(keys(local.resource_quota_spec)) > 0 : false
    limits_applied         = var.enable_limit_range ? length(keys(local.limit_range_spec)) > 0 : false
    network_policies_count = length(compact([
      var.enable_network_policy && var.default_deny_all ? "deny-all" : "",
      var.enable_network_policy && var.allow_ingress_controller ? "ingress" : "",
      var.enable_network_policy && var.allow_intra_namespace ? "intra" : "",
      var.enable_network_policy && var.allow_dns ? "dns" : "",
      var.enable_network_policy && var.allow_monitoring ? "monitoring" : "",
      var.enable_network_policy && var.allow_external_egress ? "external" : ""
    ]))
    service_accounts_count = (var.create_default_service_account ? 1 : 0) + length(var.additional_service_accounts)
    secrets_count          = length(var.secrets)
    config_maps_count      = length(var.config_maps)
  }
}

# Troubleshooting Information
output "troubleshooting_info" {
  description = "Information for troubleshooting namespace issues"
  value = {
    namespace_name        = kubernetes_namespace_v1.namespace.metadata[0].name
    namespace_uid         = kubernetes_namespace_v1.namespace.metadata[0].uid
    pod_security_standard = var.pod_security_standard
    prevent_destroy       = var.prevent_destroy
    
    # Resource constraints
    resource_quota = var.enable_resource_quota ? {
      enabled = true
      name    = kubernetes_resource_quota_v1.main[0].metadata[0].name
      spec    = local.resource_quota_spec
    } : { enabled = false }
    
    limit_range = var.enable_limit_range ? {
      enabled = true
      name    = kubernetes_limit_range_v1.container_limits[0].metadata[0].name
      spec    = local.limit_range_spec
    } : { enabled = false }
    
    # Network restrictions
    network_policies = var.enable_network_policy ? {
      enabled          = true
      default_deny_all = var.default_deny_all
      policies_count   = length(compact([
        var.default_deny_all ? "deny-all" : "",
        var.allow_ingress_controller ? "ingress" : "",
        var.allow_intra_namespace ? "intra" : "",
        var.allow_dns ? "dns" : "",
        var.allow_monitoring ? "monitoring" : "",
        var.allow_external_egress ? "external" : ""
      ]))
    } : { enabled = false }
  }
}
