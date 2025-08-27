module "eks_pod_identity_common" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${local.eks_name}-common"

  # ==========================================================================
  # POLICIES - Enable what you need/want
  # ==========================================================================
  
  # Current addons you have
  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = [] # Add KMS key ARNs if you use encrypted EBS volumes
  
  attach_aws_vpc_cni_policy = true
  aws_vpc_cni_enable_ipv4   = true
  aws_vpc_cni_enable_ipv6   = false # Set to true if using IPv6

  # Common services you'll likely want
  attach_aws_lb_controller_policy = true
  
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [local.eks_name]
  
  # Backup solution
  attach_velero_policy       = true
  velero_s3_bucket_arns      = ["arn:aws:s3:::${local.eks_name}-velero-backups"]
  velero_s3_bucket_path_arns = ["arn:aws:s3:::${local.eks_name}-velero-backups/*"]
  
  # DNS management (if you want external DNS)
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [] # Add your Route53 hosted zone ARNs
  
  # Certificate management (if you want cert-manager)
  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = [] # Add your Route53 hosted zone ARNs for DNS validation

  # CloudWatch monitoring
  attach_aws_cloudwatch_observability_policy = true

  # ==========================================================================
  # POD IDENTITY ASSOCIATIONS - One per service
  # ==========================================================================
  
  association_defaults = {
    cluster_name = local.eks_name
  }

  associations = {
    # Current addons you have
    ebs_csi = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
    
    vpc_cni = {
      namespace       = "kube-system"
      service_account = "aws-node"
    }

    # Common services (install these when ready)
    aws_load_balancer_controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    
    cluster_autoscaler = {
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
    }

    # Backup solution
    velero = {
      namespace       = "velero"
      service_account = "velero"
    }

    # DNS management
    external_dns = {
      namespace       = "external-dns"
      service_account = "external-dns"
    }

    # Certificate management  
    cert_manager = {
      namespace       = "cert-manager"
      service_account = "cert-manager"
    }

    # CloudWatch monitoring
    cloudwatch_agent = {
      namespace       = "amazon-cloudwatch"
      service_account = "cloudwatch-agent"
    }
  }

  tags = local.tags
}

# ==========================================================================
# OPTIONAL: Create the Velero S3 bucket
# ==========================================================================

resource "aws_s3_bucket" "velero_backups" {
  bucket = "${local.eks_name}-velero-backups"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "velero_backups" {
  bucket = aws_s3_bucket.velero_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero_backups" {
  bucket = aws_s3_bucket.velero_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "velero_backups" {
  bucket = aws_s3_bucket.velero_backups.id

  rule {
    id     = "delete_old_backups"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
