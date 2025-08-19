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

# Data source to get the latest AL2023 EKS optimized AMI
data "aws_ssm_parameter" "eks_ami_al2023" {
  # For AL2023 standard AMI
  name = var.enable_fips ? "/aws/service/eks/optimized-ami/${var.kubernetes_version}/amazon-linux-2023/x86_64/standard/fips/enabled/image_id" : "/aws/service/eks/optimized-ami/${var.kubernetes_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

# Alternative: Get AMI using aws_ami data source for more control
data "aws_ami" "eks_al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = var.enable_fips ? 
      ["amazon-eks-node-al2023-x86_64-standard-${var.kubernetes_version}-*-fips-enabled"] : 
      ["amazon-eks-node-al2023-x86_64-standard-${var.kubernetes_version}-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = [var.node_architecture] # x86_64 or arm64
  }
}

locals {
  enabled = module.this.enabled

  # Use the SSM parameter or AMI data source
  eks_ami_id = var.custom_ami_id != "" ? var.custom_ami_id : data.aws_ssm_parameter.eks_ami_al2023.value

  # User data for AL2023 nodes
  userdata_al2023 = var.node_group_userdata_override != null ? var.node_group_userdata_override : base64encode(templatefile("${path.module}/userdata-al2023.sh.tpl", {
    cluster_name        = module.eks_cluster.eks_cluster_id
    cluster_endpoint    = module.eks_cluster.eks_cluster_endpoint
    cluster_ca          = module.eks_cluster.eks_cluster_certificate_authority_data
    enable_fips         = var.enable_fips
    bootstrap_arguments = var.bootstrap_arguments
  }))

  # Cluster tags for subnet discovery
  tags = { "kubernetes.io/cluster/${module.label.id}" = "shared" }

  # Required tags for AWS Load Balancer Controller
  public_subnets_additional_tags = {
    "kubernetes.io/role/elb" : 1
  }
  private_subnets_additional_tags = {
    "kubernetes.io/role/internal-elb" : 1
  }

  # Access control
  access_entry_map = {
    (data.aws_iam_session_context.current.issuer_arn) = {
      access_policy_associations = {
        ClusterAdmin = {}
      }
    }
  }

  # Core EKS Addons with Pod Identity support
  addons = [
    # Pod Identity Agent - REQUIRED for Pod Identity
    {
      addon_name                  = "eks-pod-identity-agent"
      addon_version               = var.pod_identity_agent_version
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    },
    # VPC CNI
    {
      addon_name                  = "vpc-cni"
      addon_version               = var.vpc_cni_version
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          ENABLE_POD_ENI           = "true"
          POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
        }
      })
    },
    # CoreDNS
    {
      addon_name                  = "coredns"
      addon_version               = var.coredns_version
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    },
    # Kube-proxy
    {
      addon_name                  = "kube-proxy"
      addon_version               = var.kube_proxy_version
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    },
    # EBS CSI Driver
    {
      addon_name                  = "aws-ebs-csi-driver"
      addon_version               = var.ebs_csi_driver_version
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      pod_identity_association = {
        "ebs-csi-controller-sa" = module.ebs_csi_driver_pod_identity_role.arn
      }
    },
    # EFS CSI Driver (optional but useful)
    {
      addon_name                  = "aws-efs-csi-driver"
      addon_version               = var.efs_csi_driver_version
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      pod_identity_association = {
        "efs-csi-controller-sa" = module.efs_csi_driver_pod_identity_role.arn
      }
    }
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
  max_nats                        = var.nat_gateway_count
  tags                            = local.tags
  public_subnets_additional_tags  = local.public_subnets_additional_tags
  private_subnets_additional_tags = local.private_subnets_additional_tags

  context = module.this.context
}

# EKS Cluster
module "eks_cluster" {
  source  = "cloudposse/eks-cluster/aws"
  version = "4.2.0"

  subnet_ids                   = concat(module.subnets.private_subnet_ids, module.subnets.public_subnet_ids)
  kubernetes_version           = var.kubernetes_version
  
  # DISABLE OIDC - We're using Pod Identity
  oidc_provider_enabled        = false
  
  # Logging
  enabled_cluster_log_types    = var.enabled_cluster_log_types
  cluster_log_retention_period = var.cluster_log_retention_period

  # Encryption
  cluster_encryption_config_enabled                         = true
  cluster_encryption_config_kms_key_enable_key_rotation     = true
  cluster_encryption_config_kms_key_deletion_window_in_days = 30
  cluster_encryption_config_resources                       = ["secrets"]

  # Addons
  addons             = local.addons
  addons_depends_on  = [module.eks_node_group_al2023]

  # Access configuration
  access_config = {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = false
  }
  access_entry_map = local.access_entry_map

  # Network configuration
  endpoint_private_access = true
  endpoint_public_access  = var.cluster_public_access_enabled
  public_access_cidrs    = var.cluster_public_access_cidrs

  context = module.this.context
  cluster_depends_on = [module.subnets]
}

# Node Group with AL2023 and optional FIPS
module "eks_node_group_al2023" {
  source  = "cloudposse/eks-node-group/aws"
  version = "3.2.0"

  cluster_name = module.eks_cluster.eks_cluster_id
  subnet_ids   = module.subnets.private_subnet_ids
  
  # AL2023 AMI configuration
  ami_type = "AL2023_x86_64_STANDARD"  # This tells EKS to use AL2023
  
  # For custom AMI (including FIPS), use ami_image_id instead
  # ami_image_id = local.eks_ami_id  # Uncomment to use custom/FIPS AMI
  
  # Instance configuration
  instance_types = var.node_group_instance_types
  
  # Capacity configuration  
  desired_size = var.node_group_desired_size
  min_size     = var.node_group_min_size
  max_size     = var.node_group_max_size
  
  # Disk configuration for AL2023
  disk_size = var.node_disk_size
  disk_type = var.node_disk_type  # gp3 recommended for AL2023
  
  # Labels and taints
  kubernetes_labels = merge(
    var.kubernetes_labels,
    {
      "os-distro" = "al2023"
      "fips-enabled" = tostring(var.enable_fips)
    }
  )
  kubernetes_taints = var.kubernetes_taints

  # Enable cluster autoscaler discovery
  cluster_autoscaler_enabled = true

  # Custom user data for AL2023 nodes
  userdata_override_base64 = local.userdata_al2023

  # AL2023 specific launch template settings
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # Security settings
  enable_monitoring = true

  context = module.this.context
}

# Alternative: Self-managed node group with more control over AL2023 AMI
resource "aws_launch_template" "al2023_fips" {
  count = var.create_self_managed_node_group ? 1 : 0

  name_prefix = "${module.label.id}-al2023-fips-"
  description = "Launch template for AL2023 FIPS-enabled EKS nodes"

  image_id      = local.eks_ami_id
  instance_type = var.node_group_instance_types[0]

  vpc_security_group_ids = [module.eks_cluster.eks_cluster_managed_security_group_id]

  iam_instance_profile {
    arn = module.eks_node_group_al2023.iam_instance_profile_arn
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = var.node_disk_type
      iops                  = var.node_disk_type == "gp3" ? var.node_disk_iops : null
      throughput            = var.node_disk_type == "gp3" ? var.node_disk_throughput : null
      encrypted             = true
      kms_key_id            = var.node_disk_encryption_kms_key_id
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  user_data = local.userdata_al2023

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      module.label.tags,
      {
        "Name" = "${module.label.id}-al2023-fips-node"
        "kubernetes.io/cluster/${module.eks_cluster.eks_cluster_id}" = "owned"
        "FIPS" = tostring(var.enable_fips)
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for self-managed nodes
resource "aws_autoscaling_group" "al2023_fips" {
  count = var.create_self_managed_node_group ? 1 : 0

  name                = "${module.label.id}-al2023-fips"
  vpc_zone_identifier = module.subnets.private_subnet_ids
  
  min_size         = var.node_group_min_size
  max_size         = var.node_group_max_size
  desired_capacity = var.node_group_desired_size

  launch_template {
    id      = aws_launch_template.al2023_fips[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${module.label.id}-al2023-fips-node"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${module.eks_cluster.eks_cluster_id}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${module.eks_cluster.eks_cluster_id}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# IAM Roles for Pod Identity (same as before)
module "ebs_csi_driver_pod_identity_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "2.2.0"

  service_account_name      = "ebs-csi-controller-sa"
  service_account_namespace = "kube-system"
  
  aws_iam_policy_document = data.aws_iam_policy_document.pod_identity_trust.json
  aws_managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]

  context = module.this.context
}

module "efs_csi_driver_pod_identity_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "2.2.0"

  service_account_name      = "efs-csi-controller-sa"
  service_account_namespace = "kube-system"
  
  aws_iam_policy_document = data.aws_iam_policy_document.pod_identity_trust.json
  aws_managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"]

  context = module.this.context
}

data "aws_iam_policy_document" "pod_identity_trust" {
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

output "eks_ami_id" {
  value       = local.eks_ami_id
  description = "AMI ID used for EKS nodes"
}

output "eks_ami_name" {
  value       = data.aws_ami.eks_al2023.name
  description = "AMI name used for EKS nodes"
}

output "fips_enabled" {
  value       = var.enable_fips
  description = "Whether FIPS mode is enabled"
}

output "node_group_al2023_id" {
  value       = module.eks_node_group_al2023.eks_node_group_id
  description = "EKS Node Group ID for AL2023 nodes"
}
