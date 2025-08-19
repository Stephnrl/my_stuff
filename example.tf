provider "aws" {
  region = var.region
}

module "label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["cluster"]
  context    = module.this.context
}

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  enabled = module.this.enabled

  # Cluster tags for subnet discovery
  tags = { "kubernetes.io/cluster/${module.label.id}" = "shared" }

  # Required tags for AWS Load Balancer Controller
  public_subnets_additional_tags = {
    "kubernetes.io/role/elb" : 1
  }
  private_subnets_additional_tags = {
    "kubernetes.io/role/internal-elb" : 1
  }

  # Access control - replace with your actual IAM roles/users
  access_entry_map = {
    # Admin access for the current user (for initial setup)
    (data.aws_iam_session_context.current.issuer_arn) = {
      access_policy_associations = {
        ClusterAdmin = {}
      }
    }
    # Add your team's IAM roles here
    # "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/YourTeamRole" = {
    #   access_policy_associations = {
    #     AmazonEKSViewPolicy = {}
    #   }
    # }
  }

  # Core EKS Addons with Pod Identity support
  addons = [
    # Pod Identity Agent - REQUIRED for Pod Identity to work
    {
      addon_name                  = "eks-pod-identity-agent"
      addon_version               = var.pod_identity_agent_version # e.g., "v1.3.2-eksbuild.2"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    },
    # VPC CNI - Essential for networking
    {
      addon_name                  = "vpc-cni"
      addon_version               = var.vpc_cni_version # e.g., "v1.18.5-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      # If you have a Pod Identity association for VPC CNI
      # pod_identity_association = {
      #   "aws-node" = module.vpc_cni_pod_identity_role.arn
      # }
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          ENABLE_POD_ENI           = "true"
          POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
        }
      })
    },
    # CoreDNS - Essential for DNS resolution
    {
      addon_name                  = "coredns"
      addon_version               = var.coredns_version # e.g., "v1.11.3-eksbuild.2"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        computeType = "Fargate"  # or "EC2" based on your needs
        resources = {
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "70Mi"
          }
        }
      })
    },
    # Kube-proxy - Essential for service networking
    {
      addon_name                  = "kube-proxy"
      addon_version               = var.kube_proxy_version # e.g., "v1.30.6-eksbuild.3"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    },
    # EBS CSI Driver - For persistent volumes
    {
      addon_name                  = "aws-ebs-csi-driver"
      addon_version               = var.ebs_csi_driver_version # e.g., "v1.37.0-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      # Pod Identity association for EBS CSI Driver
      pod_identity_association = {
        "ebs-csi-controller-sa" = module.ebs_csi_driver_pod_identity_role.arn
      }
    },
    # EFS CSI Driver - For shared persistent volumes
    {
      addon_name                  = "aws-efs-csi-driver"
      addon_version               = var.efs_csi_driver_version # e.g., "v2.1.0-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      # Pod Identity association for EFS CSI Driver
      pod_identity_association = {
        "efs-csi-controller-sa" = module.efs_csi_driver_pod_identity_role.arn
      }
    },
    # Metrics Server - For HPA and resource metrics
    # Note: This is not an AWS managed addon, you'll need to install via Helm
    # Included here for completeness
  ]
}

# VPC Configuration
module "vpc" {
  source  = "cloudposse/vpc/aws"
  version = "2.2.0"

  ipv4_primary_cidr_block = var.vpc_cidr
  tags                    = local.tags

  context = module.this.context
}

# Subnet Configuration
module "subnets" {
  source  = "cloudposse/dynamic-subnets/aws"
  version = "2.4.2"

  availability_zones              = var.availability_zones
  vpc_id                          = module.vpc.vpc_id
  igw_id                          = [module.vpc.igw_id]
  ipv4_cidr_block                 = [module.vpc.vpc_cidr_block]
  nat_gateway_enabled             = true
  nat_instance_enabled            = false
  max_nats                        = var.nat_gateway_count # 1 for dev, 3 for prod
  tags                            = local.tags
  public_subnets_additional_tags  = local.public_subnets_additional_tags
  private_subnets_additional_tags = local.private_subnets_additional_tags

  context = module.this.context
}

# EKS Cluster
module "eks_cluster" {
  source = "cloudposse/eks-cluster/aws"
  version = "4.2.0" # Use latest version that supports Pod Identity

  subnet_ids                   = concat(module.subnets.private_subnet_ids, module.subnets.public_subnet_ids)
  kubernetes_version           = var.kubernetes_version
  
  # DISABLE OIDC - We're using Pod Identity instead
  oidc_provider_enabled        = false
  
  # Logging configuration
  enabled_cluster_log_types    = var.enabled_cluster_log_types
  cluster_log_retention_period = var.cluster_log_retention_period

  # Encryption configuration
  cluster_encryption_config_enabled                         = true
  cluster_encryption_config_kms_key_enable_key_rotation     = true
  cluster_encryption_config_kms_key_deletion_window_in_days = 30
  cluster_encryption_config_resources                       = ["secrets"]

  # Addons configuration
  addons             = local.addons
  addons_depends_on  = [module.eks_node_group]

  # Access configuration - Using AWS API instead of ConfigMap
  access_config = {
    authentication_mode                         = "API_AND_CONFIG_MAP" # or "API" only
    bootstrap_cluster_creator_admin_permissions = false
  }
  access_entry_map = local.access_entry_map

  # Network configuration
  endpoint_private_access = true
  endpoint_public_access  = var.cluster_public_access_enabled
  public_access_cidrs    = var.cluster_public_access_cidrs

  # Security Groups
  allowed_security_group_ids = var.allowed_security_group_ids
  allowed_cidr_blocks        = var.allowed_cidr_blocks

  context = module.this.context

  cluster_depends_on = [module.subnets]
}

# Node Group
module "eks_node_group" {
  source  = "cloudposse/eks-node-group/aws"
  version = "3.2.0"

  cluster_name      = module.eks_cluster.eks_cluster_id
  subnet_ids        = module.subnets.private_subnet_ids
  
  # Instance configuration
  ami_type          = var.node_group_ami_type
  instance_types    = var.node_group_instance_types
  
  # Scaling configuration
  desired_size      = var.node_group_desired_size
  min_size          = var.node_group_min_size
  max_size          = var.node_group_max_size
  
  # Labels and taints
  kubernetes_labels = var.kubernetes_labels
  kubernetes_taints = var.kubernetes_taints

  # Use cluster's Kubernetes version
  kubernetes_version = null

  # Enable cluster autoscaler discovery
  cluster_autoscaler_enabled = true

  # User data for additional node configuration
  userdata_override_base64 = var.node_group_userdata_override

  context = module.this.context
}

# IAM Role for EBS CSI Driver with Pod Identity
module "ebs_csi_driver_pod_identity_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "2.2.0"

  service_account_name      = "ebs-csi-controller-sa"
  service_account_namespace = "kube-system"
  
  # For Pod Identity, we use a different trust policy
  aws_iam_policy_document = data.aws_iam_policy_document.ebs_csi_driver_pod_identity_trust.json
  
  # Attach the AWS managed policy for EBS CSI Driver
  aws_managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]

  context = module.this.context
}

# Trust policy for Pod Identity (different from IRSA)
data "aws_iam_policy_document" "ebs_csi_driver_pod_identity_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

# IAM Role for EFS CSI Driver with Pod Identity
module "efs_csi_driver_pod_identity_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "2.2.0"

  service_account_name      = "efs-csi-controller-sa"
  service_account_namespace = "kube-system"
  
  aws_iam_policy_document = data.aws_iam_policy_document.efs_csi_driver_pod_identity_trust.json
  aws_managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"]

  context = module.this.context
}

data "aws_iam_policy_document" "efs_csi_driver_pod_identity_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

# Additional IAM role for your applications using Pod Identity
# Example: S3 access for an application
module "app_s3_pod_identity_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "2.2.0"

  service_account_name      = "app-s3-access"
  service_account_namespace = "default"
  
  aws_iam_policy_document = data.aws_iam_policy_document.app_pod_identity_trust.json
  
  # Custom inline policy for S3 access
  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::your-app-bucket/*",
          "arn:aws:s3:::your-app-bucket"
        ]
      }
    ]
  })

  context = module.this.context
}

data "aws_iam_policy_document" "app_pod_identity_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

# Outputs
output "eks_cluster_id" {
  value       = module.eks_cluster.eks_cluster_id
  description = "The name of the EKS cluster"
}

output "eks_cluster_arn" {
  value       = module.eks_cluster.eks_cluster_arn
  description = "The ARN of the EKS cluster"
}

output "eks_cluster_endpoint" {
  value       = module.eks_cluster.eks_cluster_endpoint
  description = "The endpoint for the EKS cluster API server"
}

output "eks_cluster_certificate_authority_data" {
  value       = module.eks_cluster.eks_cluster_certificate_authority_data
  description = "The base64 encoded certificate data required to communicate with the cluster"
  sensitive   = true
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "The ID of the VPC"
}

output "private_subnet_ids" {
  value       = module.subnets.private_subnet_ids
  description = "List of private subnet IDs"
}

output "pod_identity_enabled" {
  value       = true
  description = "Whether Pod Identity is enabled (OIDC is disabled)"
}
