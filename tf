# terraform-module-aws-eks-landing-zone/examples/sandbox-environment/main.tf

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Variables
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "sandbox-eks-cluster"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "your-org-name"
}

variable "team_name" {
  description = "Team name for the sandbox"
  type        = string
  default     = "sandbox-team"
}

variable "vpc_cidr" {
  description = "VPC CIDR for internal network"
  type        = string
  default     = "10.0.0.0/16"
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}
data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Provider configuration
provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# ==============================================================================
# GitHub OIDC Provider (one-time setup per account)
# ==============================================================================
module "github_oidc" {
  source = "../../modules/github-oidc"
}

# ==============================================================================
# Team IAM Role with GitHub OIDC and Console access
# ==============================================================================
module "sandbox_team_iam_role" {
  source = "../../modules/team-iam-role"
  
  team_name    = var.team_name
  github_org   = var.github_org
  cluster_name = var.cluster_name
  region       = var.region
  
  # GitHub repositories that can assume this role
  github_repositories = [
    "${var.github_org}/sandbox-*",
    "${var.github_org}/test-app"
  ]
  
  # Environments allowed for GitHub Actions
  github_environments = ["development", "sandbox"]
  
  # AWS Console access tags required
  console_access_tags = {
    Team       = var.team_name
    Department = "engineering"
    Access     = "sandbox"
  }
  
  # Additional AWS permissions for the team
  additional_policies = {
    ecr_access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload"
          ]
          Resource = [
            "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.team_name}-*"
          ]
        }
      ]
    })
    
    s3_access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject"
          ]
          Resource = [
            "arn:aws:s3:::${var.team_name}-*/*"
          ]
        }
      ]
    })
  }
}

# ==============================================================================
# EKS Access Configuration
# ==============================================================================
module "eks_access_entry" {
  source = "../../modules/eks-access-entry"
  
  cluster_name  = var.cluster_name
  principal_arn = module.sandbox_team_iam_role.role_arn
  
  # Kubernetes group for RBAC
  kubernetes_groups = ["${var.team_name}-users"]
  
  # Access policies for different environments
  access_policies = [
    {
      policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
      namespaces = ["${var.team_name}-dev", "${var.team_name}-sandbox"]
    },
    {
      policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
      namespaces = ["${var.team_name}-staging"]
    }
  ]
}

# ==============================================================================
# Kubernetes Namespaces with Resource Controls
# ==============================================================================

# Development namespace - relaxed limits for experimentation
module "namespace_dev" {
  source = "../../modules/k8s-namespace"
  
  namespace_name = "${var.team_name}-dev"
  team_name      = var.team_name
  environment    = "dev"
  description    = "Development namespace for ${var.team_name} - sandbox environment"
  
  # Security configuration
  pod_security_standard = "baseline"  # More relaxed for development
  prevent_destroy       = false       # Allow deletion in sandbox
  
  # Labels and annotations
  labels = {
    "cost-center" = "sandbox"
    "node-group"  = "sandbox"
  }
  
  annotations = {
    "platform.company.com/contact" = "sandbox-team@company.com"
    "platform.company.com/slack"   = "#sandbox-support"
  }
  
  # Service accounts
  create_default_service_account  = true
  service_account_role_arn       = module.sandbox_team_iam_role.role_arn
  automount_service_account_token = false
  
  # Resource quotas adjusted for t3.medium instances (2 nodes)
  # t3.medium: 2 vCPU, 4 GB RAM per node = Total: 4 vCPU, 8 GB RAM
  enable_resource_quota = true
  resource_quota_overrides = {
    # CPU: Reserve ~75% of cluster capacity for this namespace
    "requests.cpu"    = "3"      # 3 CPUs requested
    "limits.cpu"      = "3.5"    # 3.5 CPUs limit
    
    # Memory: Reserve ~75% of cluster capacity
    "requests.memory" = "6Gi"    # 6 GB requested
    "limits.memory"   = "7Gi"    # 7 GB limit
    
    # Object counts
    "pods"                     = "30"
    "services"                 = "10"
    "services.loadbalancers"   = "1"   # Limit LBs in sandbox
    "persistentvolumeclaims"   = "5"
    "secrets"                  = "15"
    "configmaps"               = "15"
  }
  
  # Storage quotas
  enable_storage_quota = true
  storage_quota_spec = {
    "requests.storage"           = "20Gi"  # Limited storage in sandbox
    "persistentvolumeclaims"     = "5"
    "requests.ephemeral-storage" = "10Gi"
    "limits.ephemeral-storage"   = "20Gi"
  }
  
  # Limit ranges for containers
  enable_limit_range = true
  limit_range_overrides = {
    container = {
      default_request = {
        cpu    = "50m"
        memory = "64Mi"
      }
      default = {
        cpu    = "200m"
        memory = "256Mi"
      }
      max = {
        cpu    = "1"      # Max 1 CPU per container
        memory = "2Gi"    # Max 2GB per container
      }
      min = {
        cpu    = "10m"
        memory = "32Mi"
      }
      max_limit_request_ratio = {
        cpu    = "10"
        memory = "10"
      }
    }
    pod = {
      max = {
        cpu    = "2"      # Max 2 CPUs per pod
        memory = "4Gi"    # Max 4GB per pod
      }
      min = {
        cpu    = "20m"
        memory = "64Mi"
      }
    }
  }
  
  # Network policies - IMPORTANT: Restrict egress to 10.0.0.0/8
  enable_network_policy     = true
  default_deny_all          = true  # Start with deny-all
  allow_ingress_controller  = true
  allow_intra_namespace     = true
  allow_dns                 = true
  allow_monitoring          = false  # Disable monitoring in sandbox
  allow_external_egress     = false  # Use custom egress rules
  
  # Custom external CIDR for 10.0.0.0/8 only
  allowed_external_cidrs = [
    {
      cidr = "10.0.0.0/8"
      ports = [
        {
          protocol = "TCP"
          port     = "443"
        },
        {
          protocol = "TCP"
          port     = "80"
        },
        {
          protocol = "TCP"
          port     = "3306"  # MySQL
        },
        {
          protocol = "TCP"
          port     = "5432"  # PostgreSQL
        }
      ]
    }
  ]
  
  # Application-specific network policies
  application_network_policies = {
    "web-app" = {
      pod_selector = {
        app = "web"
      }
      policy_types = ["Ingress", "Egress"]
      ingress_rules = [
        {
          from = [
            {
              namespace_selector = {
                match_labels = {
                  name = "ingress-nginx"
                }
              }
            }
          ]
          ports = [
            {
              protocol = "TCP"
              port     = "8080"
            }
          ]
        }
      ]
      egress_rules = [
        {
          to = [
            {
              ip_block = {
                cidr = "10.0.0.0/8"
              }
            }
          ]
          ports = [
            {
              protocol = "TCP"
              port     = "443"
            },
            {
              protocol = "TCP"
              port     = "3306"
            }
          ]
        }
      ]
    }
    
    "database-client" = {
      pod_selector = {
        app = "db-client"
      }
      policy_types = ["Egress"]
      egress_rules = [
        {
          to = [
            {
              ip_block = {
                cidr = "10.0.0.0/16"  # Even more restricted for DB clients
              }
            }
          ]
          ports = [
            {
              protocol = "TCP"
              port     = "3306"
            },
            {
              protocol = "TCP"
              port     = "5432"
            }
          ]
        }
      ]
    }
  }
  
  # Secrets and ConfigMaps
  secrets = {
    "app-secrets" = {
      type = "Opaque"
      data = {
        api_key = base64encode("sandbox-api-key")
      }
    }
  }
  
  config_maps = {
    "app-config" = {
      data = {
        environment = "sandbox"
        log_level   = "debug"
        api_url     = "http://api.sandbox.local"
      }
    }
  }
}

# Staging namespace - more restrictive
module "namespace_staging" {
  source = "../../modules/k8s-namespace"
  
  namespace_name = "${var.team_name}-staging"
  team_name      = var.team_name
  environment    = "staging"
  description    = "Staging namespace for ${var.team_name} - sandbox environment"
  
  pod_security_standard = "restricted"  # Stricter security
  prevent_destroy       = false
  
  # More limited resources for staging in sandbox
  enable_resource_quota = true
  resource_quota_overrides = {
    "requests.cpu"    = "1"
    "limits.cpu"      = "1.5"
    "requests.memory" = "2Gi"
    "limits.memory"   = "3Gi"
    "pods"            = "10"
    "services"        = "5"
  }
  
  # Stricter limit ranges
  enable_limit_range = true
  limit_range_overrides = {
    container = {
      default_request = {
        cpu    = "50m"
        memory = "128Mi"
      }
      default = {
        cpu    = "100m"
        memory = "256Mi"
      }
      max = {
        cpu    = "500m"
        memory = "1Gi"
      }
      min = {
        cpu    = "25m"
        memory = "64Mi"
      }
    }
  }
  
  # Same network restrictions
  enable_network_policy = true
  default_deny_all      = true
  allow_external_egress = false
  
  allowed_external_cidrs = [
    {
      cidr = "10.0.0.0/8"
      ports = [
        {
          protocol = "TCP"
          port     = "443"
        }
      ]
    }
  ]
}

# ==============================================================================
# RBAC Configuration
# ==============================================================================
module "k8s_rbac" {
  source = "../../modules/k8s-rbac"
  
  team_name         = var.team_name
  kubernetes_groups = ["${var.team_name}-users"]
  
  namespaces = {
    "${var.team_name}-dev" = {
      permissions = "edit"  # Full edit permissions in dev
      additional_rules = [
        {
          api_groups = [""]
          resources  = ["pods/exec", "pods/portforward"]
          verbs      = ["create", "get"]
        }
      ]
    }
    "${var.team_name}-staging" = {
      permissions = "view"  # Read-only in staging
    }
  }
}

# ==============================================================================
# Outputs
# ==============================================================================
output "iam_role_arn" {
  description = "IAM role ARN for the team"
  value       = module.sandbox_team_iam_role.role_arn
}

output "namespaces" {
  description = "Created namespaces"
  value = {
    dev = {
      name                = module.namespace_dev.namespace_name
      resource_quota      = module.namespace_dev.resource_quota_spec
      network_policies    = module.namespace_dev.network_policies_created
      security_config     = module.namespace_dev.security_configuration
    }
    staging = {
      name = module.namespace_staging.namespace_name
    }
  }
}

output "github_actions_config" {
  description = "Configuration for GitHub Actions"
  value = {
    role_arn     = module.sandbox_team_iam_role.role_arn
    cluster_name = var.cluster_name
    region       = var.region
    namespaces = {
      dev     = module.namespace_dev.namespace_name
      staging = module.namespace_staging.namespace_name
    }
  }
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name} --role-arn ${module.sandbox_team_iam_role.role_arn}"
}

output "test_commands" {
  description = "Commands to test the setup"
  value = {
    assume_role = "aws sts assume-role --role-arn ${module.sandbox_team_iam_role.role_arn} --role-session-name sandbox-test"
    test_access = "kubectl get pods -n ${module.namespace_dev.namespace_name}"
    test_denied = "kubectl get pods -n kube-system  # This should fail"
  }
}
