# terraform-module-aws-eks-landing-zone/modules/k8s-rbac/main.tf

locals {
  # Standard labels for all RBAC resources
  common_labels = merge(
    var.labels,
    {
      "app.kubernetes.io/managed-by"   = "terraform"
      "app.kubernetes.io/part-of"      = "eks-landing-zone"
      "app.kubernetes.io/component"    = "rbac"
      "platform.company.com/team"      = var.team_name
      "platform.company.com/env"       = var.environment
    }
  )
  
  # Permission level configurations
  permission_configs = {
    standard = {
      description = "Standard team access - full control within namespace (namespace-scoped only)"
      api_groups  = ["*"]
      resources   = ["*"]
      verbs       = ["*"]
    }
    readonly = {
      description = "Read-only access - can view resources but not modify"
      rules = [
        {
          api_groups = ["", "apps", "batch", "autoscaling", "networking.k8s.io"]
          resources  = ["*"]
          verbs      = ["get", "list", "watch"]
        },
        {
          api_groups = [""]
          resources  = ["pods/log"]
          verbs      = ["get", "list"]
        }
      ]
    }
    # Backward compatibility aliases
    normal = {
      description = "Alias for 'standard' - full control within namespace (namespace-scoped only)"
      api_groups  = ["*"]
      resources   = ["*"]
      verbs       = ["*"]
    }
    admin = {
      description = "Alias for 'standard' - full control within namespace (namespace-scoped only)"
      api_groups  = ["*"]
      resources   = ["*"]
      verbs       = ["*"]
    }
    reader = {
      description = "Alias for 'readonly' - read-only access to namespace resources"
      rules = [
        {
          api_groups = ["", "apps", "batch", "autoscaling", "networking.k8s.io"]
          resources  = ["*"]
          verbs      = ["get", "list", "watch"]
        },
        {
          api_groups = [""]
          resources  = ["pods/log"]
          verbs      = ["get", "list"]
        }
      ]
    }
    developer = {
      description = "Developer access - can create and manage most resources (deprecated: use 'standard' instead)"
      rules = [
        {
          api_groups = ["", "apps", "batch", "autoscaling"]
          resources  = ["deployments", "replicasets", "statefulsets", "daemonsets", "pods", "pods/log", "pods/exec", "pods/portforward", "services", "endpoints", "configmaps", "secrets", "jobs", "cronjobs", "horizontalpodautoscalers"]
          verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
        },
        {
          api_groups = ["networking.k8s.io"]
          resources  = ["ingresses", "networkpolicies"]
          verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
        },
        {
          api_groups = [""]
          resources  = ["persistentvolumeclaims"]
          verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
        }
      ]
    }
    deployer = {
      description = "CI/CD deployer - can update deployments and view resources (deprecated: use 'standard' instead)"
      rules = [
        {
          api_groups = ["apps"]
          resources  = ["deployments", "replicasets"]
          verbs      = ["get", "list", "watch", "update", "patch"]
        },
        {
          api_groups = [""]
          resources  = ["pods", "pods/log", "services", "endpoints"]
          verbs      = ["get", "list", "watch"]
        },
        {
          api_groups = [""]
          resources  = ["configmaps", "secrets"]
          verbs      = ["get", "list", "watch", "update", "patch"]
        }
      ]
    }
  }
  
  # Select the appropriate permission configuration
  selected_permission = lookup(local.permission_configs, var.permission_level, null)
  
  # Use custom rules if provided, otherwise use predefined permission level
  role_rules = var.custom_rules != null ? var.custom_rules : (
    contains(["standard", "normal", "admin"], var.permission_level) ? [
      {
        api_groups = [local.selected_permission.api_groups]
        resources  = [local.selected_permission.resources]
        verbs      = local.selected_permission.verbs
      }
    ] : local.selected_permission.rules
  )
  
  # Environment-specific rule adjustments
  environment_restrictions = {
    prod = {
      # In production, remove delete verbs for deployer role
      restricted_verbs = ["delete", "deletecollection"]
    }
    staging = {
      restricted_verbs = []
    }
    dev = {
      restricted_verbs = []
    }
  }
  
  # Apply environment restrictions
  final_role_rules = var.apply_environment_restrictions ? [
    for rule in local.role_rules : {
      api_groups     = rule.api_groups
      resources      = rule.resources
      resource_names = lookup(rule, "resource_names", null)
      verbs = var.environment == "prod" && contains(["deployer"], var.permission_level) ? [
        for verb in rule.verbs : verb if !contains(local.environment_restrictions.prod.restricted_verbs, verb)
      ] : rule.verbs
    }
  ] : local.role_rules
}

# Primary Role for the team in their namespace
resource "kubernetes_role_v1" "team_role" {
  metadata {
    name      = "${var.team_name}-${var.permission_level}"
    namespace = var.namespace
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"    = "${var.team_name}-${var.permission_level}"
        "rbac.company.com/role-type" = var.permission_level
      }
    )
    
    annotations = merge(
      var.annotations,
      {
        "platform.company.com/description"      = lookup(local.selected_permission, "description", var.custom_description)
        "platform.company.com/permission-level" = var.permission_level
        "platform.company.com/team"             = var.team_name
        "platform.company.com/environment"      = var.environment
      }
    )
  }
  
  dynamic "rule" {
    for_each = local.final_role_rules
    content {
      api_groups     = rule.value.api_groups
      resources      = rule.value.resources
      resource_names = lookup(rule.value, "resource_names", null)
      verbs          = rule.value.verbs
    }
  }
}

# RoleBinding to bind the Role to the team's Kubernetes group
resource "kubernetes_role_binding_v1" "team_role_binding" {
  metadata {
    name      = "${var.team_name}-${var.permission_level}-binding"
    namespace = var.namespace
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.team_name}-${var.permission_level}-binding"
        "rbac.company.com/binding-type" = "group"
      }
    )
    
    annotations = merge(
      var.annotations,
      {
        "platform.company.com/description" = "Binds ${var.permission_level} role to ${var.kubernetes_group} group"
        "platform.company.com/group"       = var.kubernetes_group
      }
    )
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.team_role.metadata[0].name
  }
  
  subject {
    kind      = "Group"
    name      = var.kubernetes_group
    api_group = "rbac.authorization.k8s.io"
  }
  
  # Additional subjects (users or service accounts)
  dynamic "subject" {
    for_each = var.additional_subjects
    content {
      kind      = subject.value.kind
      name      = subject.value.name
      namespace = subject.value.kind == "ServiceAccount" ? var.namespace : null
      api_group = subject.value.kind == "ServiceAccount" ? "" : "rbac.authorization.k8s.io"
    }
  }
}

# Additional RoleBindings for service accounts
resource "kubernetes_role_binding_v1" "service_account_bindings" {
  for_each = var.service_account_bindings
  
  metadata {
    name      = "${var.team_name}-${each.key}-binding"
    namespace = var.namespace
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"        = "${var.team_name}-${each.key}-binding"
        "rbac.company.com/binding-type" = "service-account"
      }
    )
    
    annotations = {
      "platform.company.com/description" = "Service account binding for ${each.key}"
      "platform.company.com/sa-name"     = each.key
    }
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = each.value.role_name != null ? each.value.role_name : kubernetes_role_v1.team_role.metadata[0].name
  }
  
  subject {
    kind      = "ServiceAccount"
    name      = each.key
    namespace = var.namespace
  }
}

# ClusterRole for cluster-wide read access (optional)
resource "kubernetes_cluster_role_v1" "team_cluster_readonly" {
  count = var.enable_cluster_readonly ? 1 : 0
  
  metadata {
    name = "${var.team_name}-cluster-readonly"
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"     = "${var.team_name}-cluster-readonly"
        "rbac.company.com/role-type" = "cluster-readonly"
      }
    )
    
    annotations = {
      "platform.company.com/description" = "Cluster-wide read-only access for ${var.team_name}"
      "platform.company.com/scope"       = "cluster"
    }
  }
  
  rule {
    api_groups = [""]
    resources  = ["namespaces", "nodes", "persistentvolumes"]
    verbs      = ["get", "list"]
  }
  
  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list"]
  }
}

# ClusterRoleBinding for cluster-wide read access
resource "kubernetes_cluster_role_binding_v1" "team_cluster_readonly_binding" {
  count = var.enable_cluster_readonly ? 1 : 0
  
  metadata {
    name = "${var.team_name}-cluster-readonly-binding"
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"        = "${var.team_name}-cluster-readonly-binding"
        "rbac.company.com/binding-type" = "cluster-group"
      }
    )
    
    annotations = {
      "platform.company.com/description" = "Binds cluster-readonly role to ${var.kubernetes_group}"
    }
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.team_cluster_readonly[0].metadata[0].name
  }
  
  subject {
    kind      = "Group"
    name      = var.kubernetes_group
    api_group = "rbac.authorization.k8s.io"
  }
}

# Additional custom roles
resource "kubernetes_role_v1" "custom_roles" {
  for_each = var.additional_roles
  
  metadata {
    name      = "${var.team_name}-${each.key}"
    namespace = var.namespace
    
    labels = merge(
      local.common_labels,
      each.value.labels,
      {
        "app.kubernetes.io/name"     = "${var.team_name}-${each.key}"
        "rbac.company.com/role-type" = "custom"
      }
    )
    
    annotations = merge(
      each.value.annotations,
      {
        "platform.company.com/custom-role" = each.key
      }
    )
  }
  
  dynamic "rule" {
    for_each = each.value.rules
    content {
      api_groups     = rule.value.api_groups
      resources      = rule.value.resources
      resource_names = lookup(rule.value, "resource_names", null)
      verbs          = rule.value.verbs
    }
  }
}

# Bindings for custom roles
resource "kubernetes_role_binding_v1" "custom_role_bindings" {
  for_each = var.additional_roles
  
  metadata {
    name      = "${var.team_name}-${each.key}-binding"
    namespace = var.namespace
    
    labels = merge(
      local.common_labels,
      each.value.labels,
      {
        "app.kubernetes.io/name"        = "${var.team_name}-${each.key}-binding"
        "rbac.company.com/binding-type" = "custom"
      }
    )
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.custom_roles[each.key].metadata[0].name
  }
  
  dynamic "subject" {
    for_each = each.value.subjects
    content {
      kind      = subject.value.kind
      name      = subject.value.name
      namespace = subject.value.kind == "ServiceAccount" ? var.namespace : null
      api_group = subject.value.kind == "ServiceAccount" ? "" : "rbac.authorization.k8s.io"
    }
  }
}
