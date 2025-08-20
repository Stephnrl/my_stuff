
# EKS Addons configuration with Pod Identity support - All in locals

locals {
  # Core networking addon
  vpc_cni_addon = {
    addon_name               = "vpc-cni"
    addon_version            = null # Uses latest
    resolve_conflicts        = "OVERWRITE"
    service_account_role_arn = one(module.vpc_cni_eks_iam_role[*].service_account_role_arn)
  }

  # Pod Identity agent - required for Pod Identity authentication
  pod_identity_addon = {
    addon_name        = "eks-pod-identity-agent"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
  }

  # Core DNS for cluster DNS resolution
  coredns_addon = {
    addon_name        = "coredns"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
  }

  # Kube-proxy for network proxy functionality
  kube_proxy_addon = {
    addon_name        = "kube-proxy"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
  }

  # EBS CSI driver for persistent volumes
  ebs_csi_addon = {
    addon_name        = "aws-ebs-csi-driver"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
    # Using Pod Identity instead of IRSA
    pod_identity_association = {
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKS_EBS_CSI_DriverRole"
      service_account = "ebs-csi-controller-sa"
    }
  }

  # EFS CSI driver for shared file systems
  efs_csi_addon = {
    addon_name        = "aws-efs-csi-driver"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
    pod_identity_association = {
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKS_EFS_CSI_DriverRole"
      service_account = "efs-csi-controller-sa"
    }
  }

  # AWS Load Balancer Controller for ALB/NLB integration
  aws_load_balancer_controller_addon = {
    addon_name        = "aws-load-balancer-controller"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
    pod_identity_association = {
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSLoadBalancerControllerRole"
      service_account = "aws-load-balancer-controller"
    }
  }

  # Fluent Bit for log forwarding to CloudWatch
  aws_for_fluent_bit_addon = {
    addon_name        = "aws-for-fluent-bit"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
    pod_identity_association = {
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSFluentBitRole"
      service_account = "fluent-bit"
    }
  }

  # ADOT (AWS Distro for OpenTelemetry) for observability
  adot_addon = {
    addon_name        = "adot"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
    pod_identity_association = {
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSADOTRole"
      service_account = "adot-collector"
    }
  }

  # Volume Snapshot Controller for EBS snapshot management
  snapshot_controller_addon = {
    addon_name        = "snapshot-controller"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
  }

  # GuardDuty agent for runtime security
  guardduty_addon = {
    addon_name        = "aws-guardduty-agent"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
  }

  # Mountpoint for S3 CSI driver (for S3 access as volumes)
  mountpoint_s3_addon = {
    addon_name        = "aws-mountpoint-s3-csi-driver"
    addon_version     = null
    resolve_conflicts = "OVERWRITE"
    pod_identity_association = {
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSMountpointS3Role"
      service_account = "s3-csi-driver-sa"
    }
  }

  # Essential addons for most production clusters
  essential_addons = [
    local.vpc_cni_addon,
    local.pod_identity_addon,
    local.coredns_addon,
    local.kube_proxy_addon,
    local.ebs_csi_addon,
  ]

  # Extended addons for full-featured clusters
  extended_addons = [
    local.efs_csi_addon,
    local.aws_load_balancer_controller_addon,
    local.snapshot_controller_addon,
  ]

  # Observability addons
  observability_addons = [
    local.aws_for_fluent_bit_addon,
    local.adot_addon,
  ]

  # Security addons
  security_addons = [
    local.guardduty_addon,
  ]

  # Storage addons
  storage_addons = [
    local.mountpoint_s3_addon,
  ]

  # Combine addons based on your needs
  # Option 1: Essential only (minimal setup)
  addons_minimal = local.essential_addons

  # Option 2: Production ready (recommended)
  addons_production = concat(
    local.essential_addons,
    local.extended_addons,
    local.observability_addons
  )

  # Option 3: Full featured (everything)
  addons_full = concat(
    local.essential_addons,
    local.extended_addons,
    local.observability_addons,
    local.security_addons,
    local.storage_addons
  )

  # Final addons list - choose one of the above
  addons = concat(
    local.addons_production,  # Change this to addons_minimal or addons_full as needed
    var.addons               # Still allow additional addons via variable
  )

  # Pod Identity Associations for the addons
  pod_identity_associations = {
    "ebs-csi-driver" = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKS_EBS_CSI_DriverRole"
      tags            = { "Purpose" = "EBS CSI Driver" }
    }

    "efs-csi-driver" = {
      namespace       = "kube-system"
      service_account = "efs-csi-controller-sa"
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKS_EFS_CSI_DriverRole"
      tags            = { "Purpose" = "EFS CSI Driver" }
    }

    "aws-load-balancer-controller" = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSLoadBalancerControllerRole"
      tags            = { "Purpose" = "Load Balancer Controller" }
    }

    "fluent-bit" = {
      namespace       = "amazon-cloudwatch"
      service_account = "fluent-bit"
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSFluentBitRole"
      tags            = { "Purpose" = "Fluent Bit Logging" }
    }

    "adot-collector" = {
      namespace       = "opentelemetry-operator-system"
      service_account = "adot-collector"
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSADOTRole"
      tags            = { "Purpose" = "ADOT Observability" }
    }

    "mountpoint-s3" = {
      namespace       = "kube-system"
      service_account = "s3-csi-driver-sa"
      role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSMountpointS3Role"
      tags            = { "Purpose" = "S3 Mountpoint CSI" }
    }
  }

  # IAM roles for Pod Identity (you'll need to create these)
  pod_identity_roles = {
    "AmazonEKS_EBS_CSI_DriverRole" = {
      policy_arns = [
        "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      ]
    }

    "AmazonEKS_EFS_CSI_DriverRole" = {
      policy_arns = [
        "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
      ]
    }

    "AmazonEKSLoadBalancerControllerRole" = {
      policy_arns = [
        # You'll need to create this policy or use the one from AWS Load Balancer Controller docs
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AWSLoadBalancerControllerIAMPolicy"
      ]
    }

    "AmazonEKSFluentBitRole" = {
      policy_arns = [
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      ]
    }

    "AmazonEKSADOTRole" = {
      policy_arns = [
        "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess",
        "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      ]
    }

    "AmazonEKSMountpointS3Role" = {
      policy_arns = [
        "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"  # Adjust based on your S3 access needs
      ]
    }
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Keep the variable for additional addons if needed later
variable "addons" {
  type = list(object({
    addon_name           = string
    addon_version        = optional(string, null)
    configuration_values = optional(string, null)
    resolve_conflicts           = optional(string, null)
    resolve_conflicts_on_create = optional(string, null)
    resolve_conflicts_on_update = optional(string, null)
    service_account_role_arn    = optional(string, null)
    pod_identity_association    = optional(map(string), {})
    create_timeout              = optional(string, null)
    update_timeout              = optional(string, null)
    delete_timeout              = optional(string, null)
    additional_tags             = optional(map(string), {})
  }))
  description = "Additional EKS addons to install beyond the default set"
  default     = []
}
