terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.75.1"
    }
  }
}

provider "aws" {
  region = var.region
}

# Data sources for existing resources
data "aws_caller_identity" "current" {}

# Replace these with your actual GitHub Actions role ARNs
variable "github_actions_role_arns" {
  description = "List of GitHub Actions role ARNs that need cluster access"
  type        = list(string)
  default = [
    # Example: "arn:aws:iam::123456789012:role/github-actions-deployment-role",
    # Example: "arn:aws:iam::123456789012:role/github-actions-ci-role"
  ]
}

# Replace these with your actual AWS SSO role ARNs from IAM Identity Center
variable "aws_sso_admin_role_arns" {
  description = "List of AWS SSO Admin role ARNs"
  type        = list(string)
  default = [
    # Example: "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_abc123def456"
  ]
}

variable "aws_sso_support_role_arns" {
  description = "List of AWS SSO Support role ARNs"
  type        = list(string)
  default = [
    # Example: "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_SupportUser_xyz789abc123"
  ]
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "my-private-eks-cluster"
}

locals {
  # Build access entry map for all roles
  access_entry_map = merge(
    # GitHub Actions roles - ClusterAdmin access for deployments
    {
      for role_arn in var.github_actions_role_arns :
      role_arn => {
        access_policy_associations = {
          ClusterAdmin = {}
        }
        # Use default user_name (includes role name and session name)
        user_name = null
      }
    },
    # AWS SSO Admin roles - ClusterAdmin access
    {
      for role_arn in var.aws_sso_admin_role_arns :
      role_arn => {
        access_policy_associations = {
          ClusterAdmin = {}
        }
        user_name = null
      }
    },
    # AWS SSO Support roles - View access only
    {
      for role_arn in var.aws_sso_support_role_arns :
      role_arn => {
        access_policy_associations = {
          View = {}
        }
        user_name = null
      }
    }
  )
}

# EKS Cluster
module "eks_cluster" {
  source = "cloudposse/eks-cluster/aws"
  version = "~> 4.0"

  # Basic cluster configuration
  name               = var.cluster_name
  kubernetes_version = "1.33"  # Use latest stable version
  
  # Network configuration - Private cluster
  subnet_ids              = var.private_subnet_ids
  endpoint_private_access = true
  endpoint_public_access  = false  # Completely private
  
  # If you need limited public access for management, you can use:
  # endpoint_public_access = true
  # public_access_cidrs    = ["YOUR_OFFICE_CIDR/32"]  # Replace with your IP/CIDR

  # Access configuration using new EKS Access Entries API
  access_config = {
    authentication_mode                         = "API"  # Use only the new API
    bootstrap_cluster_creator_admin_permissions = false  # Don't auto-add creator
  }

  # Access entries for your roles
  access_entry_map = local.access_entry_map

  # Pod Identity instead of OIDC + IRSA
  oidc_provider_enabled = false

  # Logging configuration
  enabled_cluster_log_types    = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_period = 30  # Days

  # Encryption at rest
  cluster_encryption_config_enabled = true
  
  # Official AWS addons only
  addons = [
    {
      addon_name                  = "vpc-cni"
      addon_version               = null  # Use latest
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      service_account_role_arn    = null
      # Pod Identity association for VPC CNI
      pod_identity_association = {
        "aws-node" = aws_iam_role.vpc_cni_pod_identity_role.arn
      }
    },
    {
      addon_name                  = "kube-proxy"
      addon_version               = null
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      service_account_role_arn    = null
    },
    {
      addon_name                  = "coredns"
      addon_version               = null
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      service_account_role_arn    = null
    },
    {
      addon_name                  = "eks-pod-identity-agent"
      addon_version               = null
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      service_account_role_arn    = null
    },
    {
      addon_name                  = "aws-ebs-csi-driver"
      addon_version               = null
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      service_account_role_arn    = null
      # Pod Identity association for EBS CSI Driver
      pod_identity_association = {
        "ebs-csi-controller-sa" = aws_iam_role.ebs_csi_pod_identity_role.arn
      }
    }
  ]

  # Security group configuration for private cluster
  managed_security_group_rules_enabled = true
  # Allow access from the VPC CIDR (adjust as needed)
  allowed_cidr_blocks = [data.aws_vpc.selected.cidr_block]

  tags = {
    Environment = "production"
    Team        = "platform"
    Purpose     = "private-eks-cluster"
  }
}

# Data source for VPC information
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# IAM role for VPC CNI Pod Identity
resource "aws_iam_role" "vpc_cni_pod_identity_role" {
  name = "${var.cluster_name}-vpc-cni-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-vpc-cni-pod-identity-role"
  }
}

# Attach AWS managed policy for VPC CNI
resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_pod_identity_role.name
}

# Additional policy for IPv6 support (if needed)
resource "aws_iam_role_policy" "vpc_cni_ipv6" {
  name = "${var.cluster_name}-vpc-cni-ipv6"
  role = aws_iam_role.vpc_cni_pod_identity_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AssignIpv6Addresses",
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstanceTypes"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*:*:network-interface/*"
      }
    ]
  })
}

# IAM role for EBS CSI Driver Pod Identity
resource "aws_iam_role" "ebs_csi_pod_identity_role" {
  name = "${var.cluster_name}-ebs-csi-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-ebs-csi-pod-identity-role"
  }
}

# Attach AWS managed policy for EBS CSI Driver
resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_pod_identity_role.name
}

# Pod Identity associations
resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = module.eks_cluster.eks_cluster_id
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni_pod_identity_role.arn

  tags = {
    Name = "${var.cluster_name}-vpc-cni-pod-identity"
  }
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks_cluster.eks_cluster_id
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_pod_identity_role.arn

  tags = {
    Name = "${var.cluster_name}-ebs-csi-pod-identity"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks_cluster.eks_cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks_cluster.eks_cluster_managed_security_group_id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks_cluster.eks_cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks_cluster.eks_cluster_certificate_authority_data
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = module.eks_cluster.eks_cluster_version
}
