# terraform-module-aws-eks-landing-zone/modules/k8s-rbac/outputs.tf

# Primary Role Information
output "role_name" {
  description = "Name of the created Role"
  value       = kubernetes_role_v1.team_role.metadata[0].name
}

output "role_uid" {
  description = "UID of the created Role"
  value       = kubernetes_role_v1.team_role.metadata[0].uid
}

output "role_binding_name" {
  description = "Name of the created RoleBinding"
  value       = kubernetes_role_binding_v1.team_role_binding.metadata[0].name
}

output "role_binding_uid" {
  description = "UID of the created RoleBinding"
  value       = kubernetes_role_binding_v1.team_role_binding.metadata[0].uid
}

# Team and Permission Information
output "team_name" {
  description = "Team name associated with this RBAC configuration"
  value       = var.team_name
}

output "kubernetes_group" {
  description = "Kubernetes group bound to the role"
  value       = var.kubernetes_group
}

output "permission_level" {
  description = "Permission level granted to the team"
  value       = var.permission_level
}

output "namespace" {
  description = "Namespace where RBAC resources are created"
  value       = var.namespace
}

output "environment" {
  description = "Environment for this RBAC configuration"
  value       = var.environment
}

# Role Rules Information
output "role_rules" {
  description = "RBAC rules applied to the role"
  value = [
    for rule in kubernetes_role_v1.team_role.rule : {
      api_groups     = rule.api_groups
      resources      = rule.resources
      resource_names = rule.resource_names
      verbs          = rule.verbs
    }
  ]
}

output "role_rules_summary" {
  description = "Summary of permissions granted"
  value = {
    permission_level = var.permission_level
    can_create      = contains(flatten([for rule in kubernetes_role_v1.team_role.rule : rule.verbs]), "create")
    can_update      = contains(flatten([for rule in kubernetes_role_v1.team_role.rule : rule.verbs]), "update")
    can_delete      = contains(flatten([for rule in kubernetes_role_v1.team_role.rule : rule.verbs]), "delete")
    can_read        = contains(flatten([for rule in kubernetes_role_v1.team_role.rule : rule.verbs]), "get")
    can_list        = contains(flatten([for rule in kubernetes_role_v1.team_role.rule : rule.verbs]), "list")
  }
}

# Subjects Information
output "primary_subject" {
  description = "Primary subject (group) bound to the role"
  value = {
    kind = "Group"
    name = var.kubernetes_group
  }
}

output "additional_subjects" {
  description = "Additional subjects bound to the role"
  value = [
    for subject in kubernetes_role_binding_v1.team_role_binding.subject : {
      kind = subject.kind
      name = subject.name
    } if subject.name != var.kubernetes_group
  ]
}

# Service Account Bindings
output "service_account_bindings" {
  description = "Service account bindings created"
  value = {
    for name, binding in kubernetes_role_binding_v1.service_account_bindings :
    name => {
      binding_name = binding.metadata[0].name
      role_name    = binding.role_ref[0].name
      sa_name      = name
    }
  }
}

# Cluster-Wide Access
output "cluster_readonly_enabled" {
  description = "Whether cluster-wide read-only access is enabled"
  value       = var.enable_cluster_readonly
}

output "cluster_role_name" {
  description = "Name of the cluster role (if created)"
  value       = var.enable_cluster_readonly ? kubernetes_cluster_role_v1.team_cluster_readonly[0].metadata[0].name : null
}

output "cluster_role_binding_name" {
  description = "Name of the cluster role binding (if created)"
  value       = var.enable_cluster_readonly ? kubernetes_cluster_role_binding_v1.team_cluster_readonly_binding[0].metadata[0].name : null
}

# Custom Roles
output "custom_roles" {
  description = "Additional custom roles created"
  value = {
    for name, role in kubernetes_role_v1.custom_roles :
    name => {
      role_name    = role.metadata[0].name
      binding_name = kubernetes_role_binding_v1.custom_role_bindings[name].metadata[0].name
    }
  }
}

# Security Configuration
output "security_configuration" {
  description = "Summary of security configuration"
  value = {
    permission_level             = var.permission_level
    environment_restrictions     = var.apply_environment_restrictions
    cluster_readonly_enabled     = var.enable_cluster_readonly
    additional_subjects_count    = length(var.additional_subjects)
    service_account_bindings     = length(var.service_account_bindings)
    custom_roles_count          = length(var.additional_roles)
  }
}

# Integration Information
output "integration_info" {
  description = "Information for integrating with other systems"
  value = {
    namespace        = var.namespace
    team_name        = var.team_name
    group_name       = var.kubernetes_group
    role_name        = kubernetes_role_v1.team_role.metadata[0].name
    binding_name     = kubernetes_role_binding_v1.team_role_binding.metadata[0].name
    permission_level = var.permission_level
    environment      = var.environment
  }
}

# Audit Information
output "audit_info" {
  description = "Audit information for compliance and tracking"
  value = {
    role_created_at         = kubernetes_role_v1.team_role.metadata[0].creation_timestamp
    binding_created_at      = kubernetes_role_binding_v1.team_role_binding.metadata[0].creation_timestamp
    role_resource_version   = kubernetes_role_v1.team_role.metadata[0].resource_version
    binding_resource_version = kubernetes_role_binding_v1.team_role_binding.metadata[0].resource_version
    audit_annotations       = var.enable_audit_annotations ? {
      contact = var.audit_contact
      team    = var.team_name
      env     = var.environment
    } : {}
  }
}

# Verification Commands
output "verification_commands" {
  description = "kubectl commands to verify RBAC setup"
  value = {
    check_role            = "kubectl get role ${kubernetes_role_v1.team_role.metadata[0].name} -n ${var.namespace}"
    check_rolebinding     = "kubectl get rolebinding ${kubernetes_role_binding_v1.team_role_binding.metadata[0].name} -n ${var.namespace}"
    describe_role         = "kubectl describe role ${kubernetes_role_v1.team_role.metadata[0].name} -n ${var.namespace}"
    describe_rolebinding  = "kubectl describe rolebinding ${kubernetes_role_binding_v1.team_role_binding.metadata[0].name} -n ${var.namespace}"
    test_access          = "kubectl auth can-i --list --as=${var.kubernetes_group} -n ${var.namespace}"
  }
}

# Troubleshooting Information
output "troubleshooting_info" {
  description = "Information for troubleshooting RBAC issues"
  value = {
    role_name         = kubernetes_role_v1.team_role.metadata[0].name
    binding_name      = kubernetes_role_binding_v1.team_role_binding.metadata[0].name
    namespace         = var.namespace
    kubernetes_group  = var.kubernetes_group
    permission_level  = var.permission_level
    
    # Common issues checklist
    checklist = {
      role_exists                = "kubectl get role ${kubernetes_role_v1.team_role.metadata[0].name} -n ${var.namespace}"
      binding_exists             = "kubectl get rolebinding ${kubernetes_role_binding_v1.team_role_binding.metadata[0].name} -n ${var.namespace}"
      check_group_membership     = "User must be mapped to '${var.kubernetes_group}' group via EKS Access Entry"
      verify_namespace_access    = "kubectl auth can-i get pods -n ${var.namespace} --as=system:serviceaccount:${var.namespace}:default"
    }
  }
}

# Resource Counts
output "resource_counts" {
  description = "Count of RBAC resources created"
  value = {
    roles                    = 1 + length(var.additional_roles)
    role_bindings            = 1 + length(var.service_account_bindings) + length(var.additional_roles)
    cluster_roles            = var.enable_cluster_readonly ? 1 : 0
    cluster_role_bindings    = var.enable_cluster_readonly ? 1 : 0
    total_subjects           = 1 + length(var.additional_subjects)
    service_account_bindings = length(var.service_account_bindings)
  }
}

# Permissions Matrix (for documentation)
output "permissions_matrix" {
  description = "Detailed permissions matrix for the role"
  value = {
    for rule in kubernetes_role_v1.team_role.rule : 
    join("/", rule.api_groups) => {
      resources = rule.resources
      verbs     = rule.verbs
    }
  }
}
