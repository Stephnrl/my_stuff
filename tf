# terraform-module-aws-eks-landing-zone/modules/k8s-namespace/network-policy.tf

# Default deny-all NetworkPolicy for namespace isolation
resource "kubernetes_network_policy_v1" "default_deny_all" {
  count = var.enable_network_policy && var.default_deny_all ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-default-deny-all"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-default-deny-all"
        "app.kubernetes.io/component" = "network-policy"
        "policy-type"                 = "deny-all"
      }
    )
    
    annotations = {
      "platform.company.com/policy-type" = "default-deny-all"
      "platform.company.com/description" = "Denies all ingress and egress traffic by default"
    }
  }
  
  spec {
    # Apply to all pods in the namespace
    pod_selector {}
    
    # Block both ingress and egress by default
    policy_types = ["Ingress", "Egress"]
    
    # Empty ingress/egress blocks = deny all
    # Specific allow rules are defined in separate policies below
  }
}

# Allow ingress from ingress controllers
resource "kubernetes_network_policy_v1" "allow_ingress_controller" {
  count = var.enable_network_policy && var.allow_ingress_controller ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-allow-ingress-controller"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-allow-ingress-controller"
        "app.kubernetes.io/component" = "network-policy"
        "policy-type"                 = "allow-ingress"
      }
    )
    
    annotations = {
      "platform.company.com/policy-type" = "ingress-controller"
      "platform.company.com/description" = "Allows traffic from ingress controllers"
    }
  }
  
  spec {
    pod_selector {}
    
    policy_types = ["Ingress"]
    
    # Allow traffic from ingress controller namespaces
    dynamic "ingress" {
      for_each = var.ingress_controller_namespaces
      content {
        from {
          namespace_selector {
            match_labels = {
              name = ingress.value
            }
          }
        }
      }
    }
    
    # Allow traffic from pods with specific labels (like ALB ingress controller)
    dynamic "ingress" {
      for_each = var.ingress_controller_selectors
      content {
        from {
          pod_selector {
            match_labels = ingress.value
          }
        }
      }
    }
  }
}

# Allow intra-namespace communication
resource "kubernetes_network_policy_v1" "allow_intra_namespace" {
  count = var.enable_network_policy && var.allow_intra_namespace ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-allow-intra-namespace"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-allow-intra-namespace"
        "app.kubernetes.io/component" = "network-policy"
        "policy-type"                 = "allow-internal"
      }
    )
    
    annotations = {
      "platform.company.com/policy-type" = "intra-namespace"
      "platform.company.com/description" = "Allows communication within the namespace"
    }
  }
  
  spec {
    pod_selector {}
    
    policy_types = ["Ingress", "Egress"]
    
    # Allow ingress from same namespace
    ingress {
      from {
        pod_selector {}
      }
    }
    
    # Allow egress to same namespace
    egress {
      to {
        pod_selector {}
      }
    }
  }
}

# Allow DNS resolution
resource "kubernetes_network_policy_v1" "allow_dns" {
  count = var.enable_network_policy && var.allow_dns ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-allow-dns"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-allow-dns"
        "app.kubernetes.io/component" = "network-policy"
        "policy-type"                 = "allow-dns"
      }
    )
    
    annotations = {
      "platform.company.com/policy-type" = "dns"
      "platform.company.com/description" = "Allows DNS resolution"
    }
  }
  
  spec {
    pod_selector {}
    
    policy_types = ["Egress"]
    
    # Allow DNS queries to kube-system namespace
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      
      ports {
        protocol = "TCP"
        port     = "53"
      }
      
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
    
    # Allow DNS queries to system pods
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
        
        pod_selector {
          match_labels = {
            k8s-app = "kube-dns"
          }
        }
      }
      
      ports {
        protocol = "TCP"
        port     = "53"
      }
      
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
  }
}

# Allow monitoring (Prometheus, metrics collection)
resource "kubernetes_network_policy_v1" "allow_monitoring" {
  count = var.enable_network_policy && var.allow_monitoring ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-allow-monitoring"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-allow-monitoring"
        "app.kubernetes.io/component" = "network-policy"
        "policy-type"                 = "allow-monitoring"
      }
    )
    
    annotations = {
      "platform.company.com/policy-type" = "monitoring"
      "platform.company.com/description" = "Allows monitoring systems to scrape metrics"
    }
  }
  
  spec {
    pod_selector {}
    
    policy_types = ["Ingress"]
    
    # Allow monitoring from specific namespaces
    dynamic "ingress" {
      for_each = var.monitoring_namespaces
      content {
        from {
          namespace_selector {
            match_labels = {
              name = ingress.value
            }
          }
        }
        
        ports {
          protocol = "TCP"
          port     = "8080"  # Common metrics port
        }
        
        ports {
          protocol = "TCP" 
          port     = "9090"  # Prometheus metrics
        }
        
        ports {
          protocol = "TCP"
          port     = "3000"  # Grafana
        }
      }
    }
    
    # Allow monitoring from pods with specific labels
    dynamic "ingress" {
      for_each = var.monitoring_selectors
      content {
        from {
          pod_selector {
            match_labels = ingress.value
          }
        }
        
        ports {
          protocol = "TCP"
          port     = "8080"
        }
        
        ports {
          protocol = "TCP"
          port     = "9090"
        }
      }
    }
  }
}

# Allow egress to external services
resource "kubernetes_network_policy_v1" "allow_external_egress" {
  count = var.enable_network_policy && var.allow_external_egress ? 1 : 0
  
  metadata {
    name      = "${var.namespace_name}-allow-external-egress"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-allow-external-egress"
        "app.kubernetes.io/component" = "network-policy"
        "policy-type"                 = "allow-external"
      }
    )
    
    annotations = {
      "platform.company.com/policy-type" = "external-egress"
      "platform.company.com/description" = "Allows egress to external services and APIs"
    }
  }
  
  spec {
    pod_selector {}
    
    policy_types = ["Egress"]
    
    # Allow HTTPS traffic to external services
    egress {
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }
    
    # Allow HTTP traffic to external services (if enabled)
    dynamic "egress" {
      for_each = var.allow_http_egress ? [1] : []
      content {
        ports {
          protocol = "TCP"
          port     = "80"
        }
      }
    }
    
    # Allow specific external IP ranges
    dynamic "egress" {
      for_each = var.allowed_external_cidrs
      content {
        to {
          ip_block {
            cidr   = egress.value.cidr
            except = lookup(egress.value, "except", [])
          }
        }
        
        dynamic "ports" {
          for_each = lookup(egress.value, "ports", [])
          content {
            protocol = ports.value.protocol
            port     = ports.value.port
          }
        }
      }
    }
  }
}

# Allow communication with specific namespaces (cross-namespace)
resource "kubernetes_network_policy_v1" "allow_cross_namespace" {
  for_each = var.allowed_namespaces
  
  metadata {
    name      = "${var.namespace_name}-allow-${each.key}"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-allow-${each.key}"
        "app.kubernetes.io/component" = "network-policy"
        "policy-type"                 = "cross-namespace"
        "target-namespace"            = each.key
      }
    )
    
    annotations = {
      "platform.company.com/policy-type" = "cross-namespace"
      "platform.company.com/target-namespace" = each.key
      "platform.company.com/description" = "Allows communication with ${each.key} namespace"
    }
  }
  
  spec {
    pod_selector {}
    
    policy_types = each.value.direction == "both" ? ["Ingress", "Egress"] : [title(each.value.direction)]
    
    # Configure ingress rules
    dynamic "ingress" {
      for_each = contains(["ingress", "both"], each.value.direction) ? [1] : []
      content {
        from {
          namespace_selector {
            match_labels = {
              name = each.key
            }
          }
        }
        
        dynamic "ports" {
          for_each = each.value.ports
          content {
            protocol = ports.value.protocol
            port     = ports.value.port
          }
        }
      }
    }
    
    # Configure egress rules
    dynamic "egress" {
      for_each = contains(["egress", "both"], each.value.direction) ? [1] : []
      content {
        to {
          namespace_selector {
            match_labels = {
              name = each.key
            }
          }
        }
        
        dynamic "ports" {
          for_each = each.value.ports
          content {
            protocol = ports.value.protocol
            port     = ports.value.port
          }
        }
      }
    }
  }
}

# Application-specific network policies
resource "kubernetes_network_policy_v1" "application_specific" {
  for_each = var.application_network_policies
  
  metadata {
    name      = "${var.namespace_name}-${each.key}"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    
    labels = merge(
      local.common_labels,
      each.value.labels,
      {
        "app.kubernetes.io/name"      = "${var.namespace_name}-${each.key}"
        "app.kubernetes.io/component" = "network-policy"
        "policy-type"                 = "application-specific"
        "application"                 = each.key
      }
    )
    
    annotations = merge(
      each.value.annotations,
      {
        "platform.company.com/policy-type" = "application-specific"
        "platform.company.com/application" = each.key
      }
    )
  }
  
  spec {
    pod_selector {
      match_labels = each.value.pod_selector
    }
    
    policy_types = each.value.policy_types
    
    # Dynamic ingress rules
    dynamic "ingress" {
      for_each = each.value.ingress_rules
      content {
        dynamic "from" {
          for_each = ingress.value.from
          content {
            dynamic "namespace_selector" {
              for_each = lookup(from.value, "namespace_selector", null) != null ? [from.value.namespace_selector] : []
              content {
                match_labels = namespace_selector.value.match_labels
              }
            }
            
            dynamic "pod_selector" {
              for_each = lookup(from.value, "pod_selector", null) != null ? [from.value.pod_selector] : []
              content {
                match_labels = pod_selector.value.match_labels
              }
            }
            
            dynamic "ip_block" {
              for_each = lookup(from.value, "ip_block", null) != null ? [from.value.ip_block] : []
              content {
                cidr   = ip_block.value.cidr
                except = lookup(ip_block.value, "except", [])
              }
            }
          }
        }
        
        dynamic "ports" {
          for_each = ingress.value.ports
          content {
            protocol = ports.value.protocol
            port     = ports.value.port
          }
        }
      }
    }
    
    # Dynamic egress rules
    dynamic "egress" {
      for_each = each.value.egress_rules
      content {
        dynamic "to" {
          for_each = egress.value.to
          content {
            dynamic "namespace_selector" {
              for_each = lookup(to.value, "namespace_selector", null) != null ? [to.value.namespace_selector] : []
              content {
                match_labels = namespace_selector.value.match_labels
              }
            }
            
            dynamic "pod_selector" {
              for_each = lookup(to.value, "pod_selector", null) != null ? [to.value.pod_selector] : []
              content {
                match_labels = pod_selector.value.match_labels
              }
            }
            
            dynamic "ip_block" {
              for_each = lookup(to.value, "ip_block", null) != null ? [to.value.ip_block] : []
              content {
                cidr   = ip_block.value.cidr
                except = lookup(ip_block.value, "except", [])
              }
            }
          }
        }
        
        dynamic "ports" {
          for_each = egress.value.ports
          content {
            protocol = ports.value.protocol
            port     = ports.value.port
          }
        }
      }
    }
  }
}
