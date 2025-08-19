variable "region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "nat_gateway_count" {
  type        = number
  description = "Number of NAT gateways to provision (use 1 for dev, 3 for prod)"
  default     = 1
}

# EKS Cluster Configuration
variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version to use for the EKS cluster"
  default     = "1.30"
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "List of control plane logging types to enable"
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_period" {
  type        = number
  description = "Number of days to retain cluster logs"
  default     = 30
}

variable "cluster_public_access_enabled" {
  type        = bool
  description = "Whether to enable public access to the cluster endpoint"
  default     = false
}

variable "cluster_public_access_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks that can access the public cluster endpoint"
  default     = ["0.0.0.0/0"]
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "List of Security Group IDs allowed to connect to the cluster"
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed to connect to the cluster"
  default     = []
}

# Node Group Configuration
variable "node_group_ami_type" {
  type        = string
  description = "AMI type for the node group instances"
  default     = "AL2023_x86_64_STANDARD"
  # Options: AL2_x86_64, AL2_x86_64_GPU, AL2_ARM_64, AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD, CUSTOM, BOTTLEROCKET_ARM_64, BOTTLEROCKET_x86_64
}

variable "node_group_instance_types" {
  type        = list(string)
  description = "Instance types for the node group"
  default     = ["t3.medium"]
}

variable "node_group_desired_size" {
  type        = number
  description = "Desired number of nodes"
  default     = 3
}

variable "node_group_min_size" {
  type        = number
  description = "Minimum number of nodes"
  default     = 1
}

variable "node_group_max_size" {
  type        = number
  description = "Maximum number of nodes"
  default     = 10
}

variable "kubernetes_labels" {
  type        = map(string)
  description = "Kubernetes labels to apply to the nodes"
  default     = {
    "node-type" = "general-purpose"
  }
}

variable "kubernetes_taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  description = "Kubernetes taints to apply to the nodes"
  default     = []
}

variable "node_group_userdata_override" {
  type        = string
  description = "Base64 encoded user data to override the default user data"
  default     = null
}

# Addon Versions
variable "pod_identity_agent_version" {
  type        = string
  description = "Version of the EKS Pod Identity Agent addon"
  default     = "v1.3.2-eksbuild.2"
}

variable "vpc_cni_version" {
  type        = string
  description = "Version of the VPC CNI addon"
  default     = "v1.18.5-eksbuild.1"
}

variable "coredns_version" {
  type        = string
  description = "Version of the CoreDNS addon"
  default     = "v1.11.3-eksbuild.2"
}

variable "kube_proxy_version" {
  type        = string
  description = "Version of the kube-proxy addon"
  default     = "v1.30.6-eksbuild.3"
}

variable "ebs_csi_driver_version" {
  type        = string
  description = "Version of the EBS CSI Driver addon"
  default     = "v1.37.0-eksbuild.1"
}

variable "efs_csi_driver_version" {
  type        = string
  description = "Version of the EFS CSI Driver addon"
  default     = "v2.1.0-eksbuild.1"
}

# Context variables (from null-label)
module "this" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  enabled     = true
  namespace   = "mycompany"
  environment = "dev"
  stage       = "test"
  name        = "eks"
  delimiter   = "-"
  
  tags = {
    "ManagedBy" = "Terraform"
    "Purpose"   = "EKS Cluster with Pod Identity"
  }
}
