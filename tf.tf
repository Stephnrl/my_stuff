################################################################################
# Variables
################################################################################

variable "create" {
  description = "Whether to create the IAM role and policies"
  type        = bool
  default     = true
}

variable "contractor_role_name" {
  description = "Name of the contractor IAM role"
  type        = string
  default     = "contractor-eks-deploy-role"
}

variable "use_name_prefix" {
  description = "Whether to use name_prefix instead of name"
  type        = bool
  default     = false
}

variable "path" {
  description = "Path for the IAM role"
  type        = string
  default     = "/contractors/"
}

variable "description" {
  description = "Description of the IAM role"
  type        = string
  default     = "IAM role for contractors deploying applications to EKS"
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds"
  type        = number
  default     = 14400 # 4 hours
}

variable "permissions_boundary" {
  description = "ARN of the permissions boundary policy to attach to the role"
  type        = string
  default     = null
}

variable "allowed_account_ids" {
  description = "List of AWS account IDs allowed to assume this role"
  type        = list(string)
  default     = []
}

variable "contractor_iam_users" {
  description = "List of contractor IAM user ARNs allowed to assume this role"
  type        = list(string)
  default     = []
}

variable "require_mfa" {
  description = "Whether to require MFA for role assumption"
  type        = bool
  default     = true
}

variable "external_id" {
  description = "External ID for additional security during role assumption"
  type        = string
  default     = null
}

variable "session_name_prefix" {
  description = "Required prefix for session names"
  type        = string
  default     = "contractor-session-"
}

variable "allowed_regions" {
  description = "List of allowed AWS regions for contractor operations"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1"]
}

variable "resource_prefix_allowlist" {
  description = "List of allowed resource name prefixes"
  type        = list(string)
  default     = ["contractor-", "dev-", "staging-"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Purpose     = "ContractorAccess"
    Environment = "Development"
  }
}

################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}

################################################################################
# Trust Policy Document
################################################################################

data "aws_iam_policy_document" "assume_role" {
  count = var.create ? 1 : 0

  # Allow specified IAM users to assume the role
  dynamic "statement" {
    for_each = length(var.contractor_iam_users) > 0 ? [1] : []

    content {
      sid     = "AllowContractorAssumeRole"
      effect  = "Allow"
      actions = ["sts:AssumeRole", "sts:TagSession"]

      principals {
        type        = "AWS"
        identifiers = var.contractor_iam_users
      }

      # Require MFA if enabled
      dynamic "condition" {
        for_each = var.require_mfa ? [1] : []

        content {
          test     = "Bool"
          variable = "aws:MultiFactorAuthPresent"
          values   = ["true"]
        }
      }

      # Require external ID if provided
      dynamic "condition" {
        for_each = var.external_id != null ? [1] : []

        content {
          test     = "StringEquals"
          variable = "sts:ExternalId"
          values   = [var.external_id]
        }
      }

      # Enforce session name prefix
      condition {
        test     = "StringLike"
        variable = "sts:RoleSessionName"
        values   = ["${var.session_name_prefix}*"]
      }
    }
  }

  # Allow cross-account access if specified
  dynamic "statement" {
    for_each = length(var.allowed_account_ids) > 0 ? [1] : []

    content {
      sid     = "AllowCrossAccountAssumeRole"
      effect  = "Allow"
      actions = ["sts:AssumeRole", "sts:TagSession"]

      principals {
        type        = "AWS"
        identifiers = [for account_id in var.allowed_account_ids : "arn:${local.partition}:iam::${account_id}:root"]
      }

      # Require external ID for cross-account
      dynamic "condition" {
        for_each = var.external_id != null ? [1] : []

        content {
          test     = "StringEquals"
          variable = "sts:ExternalId"
          values   = [var.external_id]
        }
      }
    }
  }
}

################################################################################
# Operational Policy Document (Allow)
################################################################################

data "aws_iam_policy_document" "operational" {
  count = var.create ? 1 : 0

  # EKS Read-Only Access (removed create/update/delete permissions)
  statement {
    sid    = "EKSReadOnlyAccess"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:ListClusters",
      "eks:DescribeNodegroup",
      "eks:ListNodegroups",
      "eks:DescribeAddon",
      "eks:ListAddons",
      "eks:DescribeAddonVersions",
      "eks:DescribeUpdate",
      "eks:ListUpdates",
      "eks:AccessKubernetesApi",
      "eks:ListFargateProfiles",
      "eks:DescribeFargateProfile"
    ]
    resources = ["*"]
  }

  # EC2 Network Read-Only
  statement {
    sid    = "EC2NetworkingRead"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:Get*"
    ]
    resources = ["*"]
  }

  # Security Groups Management (with name restrictions)
  statement {
    sid    = "SecurityGroupManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:ModifySecurityGroupRules"
    ]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "ec2:SecurityGroupName"
      values   = var.resource_prefix_allowlist
    }
  }

  # EC2 Tagging
  statement {
    sid    = "EC2Tagging"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]
    resources = [
      "arn:${local.partition}:ec2:*:${local.account_id}:security-group/*",
      "arn:${local.partition}:ec2:*:${local.account_id}:instance/*",
      "arn:${local.partition}:ec2:*:${local.account_id}:volume/*",
      "arn:${local.partition}:ec2:*:${local.account_id}:network-interface/*"
    ]
  }

  # IAM Service Roles (with prefix restrictions)
  statement {
    sid    = "IAMServiceRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags"
    ]
    resources = flatten([
      for prefix in var.resource_prefix_allowlist : [
        "arn:${local.partition}:iam::${local.account_id}:role/${prefix}*",
        "arn:${local.partition}:iam::${local.account_id}:role/eks-*"
      ]
    ])
  }

  # IAM Service Linked Roles
  statement {
    sid    = "IAMServiceLinkedRoles"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
      "iam:DeleteServiceLinkedRole",
      "iam:GetServiceLinkedRoleDeletionStatus"
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]
  }

  # IAM Policies (with prefix restrictions)
  statement {
    sid    = "IAMPolicyManagement"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:ListPolicyTags"
    ]
    resources = flatten([
      for prefix in var.resource_prefix_allowlist : [
        "arn:${local.partition}:iam::${local.account_id}:policy/${prefix}*",
        "arn:${local.partition}:iam::${local.account_id}:policy/eks-*"
      ]
    ])
  }

  # IAM Read Only
  statement {
    sid    = "IAMReadOnly"
    effect = "Allow"
    actions = [
      "iam:GetAccountAuthorizationDetails",
      "iam:GetAccountPasswordPolicy",
      "iam:GetAccountSummary",
      "iam:ListRoles",
      "iam:ListPolicies",
      "iam:ListInstanceProfiles",
      "iam:ListOpenIDConnectProviders",
      "iam:GetOpenIDConnectProvider"
    ]
    resources = ["*"]
  }

  # S3 Bucket Management (with prefix restrictions)
  statement {
    sid    = "S3BucketManagement"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketVersioning",
      "s3:PutBucketEncryption",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketPolicy",
      "s3:PutBucketTagging",
      "s3:GetBucketTagging",
      "s3:PutLifecycleConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutBucketLogging",
      "s3:GetBucketLogging",
      "s3:GetBucketVersioning",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketEncryption",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
      "s3:GetBucketAcl"
    ]
    resources = flatten([
      for prefix in var.resource_prefix_allowlist : [
        "arn:${local.partition}:s3:::${prefix}*",
        "arn:${local.partition}:s3:::eks-*"
      ]
    ])
  }

  # S3 Object Management
  statement {
    sid    = "S3ObjectManagement"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion",
      "s3:PutObjectTagging",
      "s3:GetObjectTagging"
    ]
    resources = flatten([
      for prefix in var.resource_prefix_allowlist : [
        "arn:${local.partition}:s3:::${prefix}*/*",
        "arn:${local.partition}:s3:::eks-*/*"
      ]
    ])
  }

  # S3 List All Buckets
  statement {
    sid       = "S3ListAllBuckets"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  # ECR Repository Management
  statement {
    sid    = "ECRManagement"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:GetAuthorizationToken",
      "ecr:GetRepositoryPolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy",
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:BatchDeleteImage"
    ]
    resources = ["*"]
  }

  # Internal Load Balancer Management
  statement {
    sid    = "InternalLoadBalancerManagement"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:SetSecurityGroups"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:Scheme"
      values   = ["internal"]
    }
  }

  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogsManagement"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:CreateLogStream",
      "logs:DeleteLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
      "logs:PutSubscriptionFilter",
      "logs:DeleteSubscriptionFilter",
      "logs:DescribeSubscriptionFilters"
    ]
    resources = flatten([
      "arn:${local.partition}:logs:*:${local.account_id}:log-group:/aws/eks/*",
      "arn:${local.partition}:logs:*:${local.account_id}:log-group:/aws/containerinsights/*",
      [for prefix in var.resource_prefix_allowlist : "arn:${local.partition}:logs:*:${local.account_id}:log-group:${prefix}*"]
    ])
  }

  # CloudWatch Metrics
  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmsForMetric"
    ]
    resources = ["*"]
  }

  # Secrets Manager (with path restrictions)
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:PutSecretValue",
      "secretsmanager:RotateSecret",
      "secretsmanager:RestoreSecret"
    ]
    resources = flatten([
      [for prefix in var.resource_prefix_allowlist : "arn:${local.partition}:secretsmanager:*:${local.account_id}:secret:${prefix}*"],
      "arn:${local.partition}:secretsmanager:*:${local.account_id}:secret:eks/*"
    ])
  }

  # Parameter Store (with path restrictions)
  statement {
    sid    = "ParameterStoreAccess"
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:DeleteParameter",
      "ssm:DescribeParameters",
      "ssm:GetParametersByPath",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource"
    ]
    resources = flatten([
      [for prefix in var.resource_prefix_allowlist : "arn:${local.partition}:ssm:*:${local.account_id}:parameter/${prefix}*"],
      "arn:${local.partition}:ssm:*:${local.account_id}:parameter/eks/*"
    ])
  }

  # KMS Key Usage (with alias restrictions)
  statement {
    sid    = "KMSKeyUsage"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListKeys",
      "kms:ListAliases",
      "kms:ListResourceTags",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:CreateGrant",
      "kms:RetireGrant",
      "kms:RevokeGrant",
      "kms:CreateAlias",
      "kms:UpdateAlias",
      "kms:DeleteAlias"
    ]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:AliasName"
      values = flatten([
        [for prefix in var.resource_prefix_allowlist : "alias/${prefix}*"],
        "alias/eks-*"
      ])
    }
  }

  # STS
  statement {
    sid    = "STSAccess"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
      "sts:AssumeRole"
    ]
    resources = ["*"]
  }

  # Resource Tagging
  statement {
    sid    = "ResourceTagging"
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:TagResources",
      "tag:UntagResources",
      "tag:GetTagKeys",
      "tag:GetTagValues"
    ]
    resources = ["*"]
  }

  # CloudFormation (with stack name restrictions)
  statement {
    sid    = "CloudFormationManagement"
    effect = "Allow"
    actions = [
      "cloudformation:CreateStack",
      "cloudformation:UpdateStack",
      "cloudformation:DeleteStack",
      "cloudformation:DescribeStacks",
      "cloudformation:DescribeStackEvents",
      "cloudformation:DescribeStackResources",
      "cloudformation:GetTemplate",
      "cloudformation:ValidateTemplate",
      "cloudformation:CreateChangeSet",
      "cloudformation:DeleteChangeSet",
      "cloudformation:DescribeChangeSet",
      "cloudformation:ExecuteChangeSet",
      "cloudformation:ListStacks",
      "cloudformation:ListStackResources",
      "cloudformation:GetStackPolicy",
      "cloudformation:SetStackPolicy"
    ]
    resources = flatten([
      [for prefix in var.resource_prefix_allowlist : "arn:${local.partition}:cloudformation:*:${local.account_id}:stack/${prefix}*/*"],
      "arn:${local.partition}:cloudformation:*:${local.account_id}:stack/eks-*/*"
    ])
  }

  # Service Discovery
  statement {
    sid    = "ServiceDiscovery"
    effect = "Allow"
    actions = [
      "servicediscovery:CreateService",
      "servicediscovery:DeleteService",
      "servicediscovery:GetService",
      "servicediscovery:UpdateService",
      "servicediscovery:ListServices",
      "servicediscovery:CreatePrivateDnsNamespace",
      "servicediscovery:DeleteNamespace",
      "servicediscovery:GetNamespace",
      "servicediscovery:ListNamespaces",
      "servicediscovery:RegisterInstance",
      "servicediscovery:DeregisterInstance",
      "servicediscovery:GetInstance",
      "servicediscovery:ListInstances",
      "servicediscovery:DiscoverInstances"
    ]
    resources = ["*"]
  }

  # Auto Scaling (for managed node groups)
  statement {
    sid    = "AutoScalingReadOnly"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags"
    ]
    resources = ["*"]
  }
}

################################################################################
# Security Baseline Policy Document (Deny)
################################################################################

data "aws_iam_policy_document" "security_baseline" {
  count = var.create ? 1 : 0

  # Network Creation Denials
  statement {
    sid    = "DenyVPCAndNetworkCreation"
    effect = "Deny"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateVpcPeeringConnection",
      "ec2:AcceptVpcPeeringConnection",
      "ec2:CreateInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:CreateEgressOnlyInternetGateway",
      "ec2:DeleteEgressOnlyInternetGateway",
      "ec2:CreateVpnGateway",
      "ec2:AttachVpnGateway",
      "ec2:CreateCustomerGateway",
      "ec2:CreateVpnConnection",
      "ec2:ModifyVpnConnection",
      "ec2:CreateTransitGateway",
      "ec2:CreateTransitGatewayAttachment",
      "ec2:CreateTransitGatewayPeeringAttachment",
      "ec2:ModifyTransitGateway",
      "ec2:DeleteTransitGateway"
    ]
    resources = ["*"]
  }

  # Public IP Denials
  statement {
    sid    = "DenyPublicIPAllocation"
    effect = "Deny"
    actions = [
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress"
    ]
    resources = ["*"]
  }

  # Deny EC2 with Public IP
  statement {
    sid    = "DenyEC2PublicIPOnLaunch"
    effect = "Deny"
    actions = ["ec2:RunInstances"]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "ec2:AssociatePublicIpAddress"
      values   = ["true"]
    }
  }

  # Subnet and Route Table Denials
  statement {
    sid    = "DenySubnetCreation"
    effect = "Deny"
    actions = [
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyRouteTableModification"
    effect = "Deny"
    actions = [
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation"
    ]
    resources = ["*"]
  }

  # Deny Public Load Balancers
  statement {
    sid    = "DenyPublicLoadBalancers"
    effect = "Deny"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:Scheme"
      values   = ["internet-facing"]
    }
  }

  # S3 Public Access Denials
  statement {
    sid    = "DenyS3PublicAccess"
    effect = "Deny"
    actions = [
      "s3:PutBucketAcl",
      "s3:PutObjectAcl",
      "s3:PutBucketPolicy",
      "s3:DeletePublicAccessBlock",
      "s3:PutAccountPublicAccessBlock",
      "s3:PutBucketWebsite",
      "s3:PutBucketCORS"
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-acl"
      values   = ["private"]
    }
  }

  # IAM User and Group Management Denials
  statement {
    sid    = "DenyIAMUserAndGroupManagement"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:UpdateUser",
      "iam:CreateGroup",
      "iam:DeleteGroup",
      "iam:UpdateGroup",
      "iam:AddUserToGroup",
      "iam:RemoveUserFromGroup",
      "iam:CreateLoginProfile",
      "iam:DeleteLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:UpdateAccessKey",
      "iam:ListAccessKeys",
      "iam:GetAccessKeyLastUsed"
    ]
    resources = ["*"]
  }

  # Password Policy Denials
  statement {
    sid    = "DenyIAMPasswordPolicyChanges"
    effect = "Deny"
    actions = [
      "iam:UpdateAccountPasswordPolicy",
      "iam:DeleteAccountPasswordPolicy"
    ]
    resources = ["*"]
  }

  # Organization and Billing Denials
  statement {
    sid    = "DenyOrganizationManagement"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyBillingAccess"
    effect = "Deny"
    actions = [
      "aws-portal:*",
      "billing:*",
      "budgets:*",
      "ce:*",
      "cur:*",
      "purchase-orders:*",
      "payments:*",
      "tax:*"
    ]
    resources = ["*"]
  }

  # Security Service Denials
  statement {
    sid    = "DenyCloudTrailModification"
    effect = "Deny"
    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyConfigModification"
    effect = "Deny"
    actions = [
      "config:DeleteConfigRule",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "config:StopConfigurationRecorder"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyGuardDutyDisable"
    effect = "Deny"
    actions = [
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "guardduty:StopMonitoringMembers",
      "guardduty:UpdateDetector"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenySecurityHubDisable"
    effect = "Deny"
    actions = [
      "securityhub:DisableSecurityHub",
      "securityhub:DeleteInsight",
      "securityhub:DisassociateFromMasterAccount",
      "securityhub:DisableImportFindingsForProduct"
    ]
    resources = ["*"]
  }

  # KMS Key Deletion Denial
  statement {
    sid    = "DenyKMSKeyDeletion"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DeleteAlias",
      "kms:DeleteImportedKeyMaterial",
      "kms:DisableKey"
    ]
    resources = ["*"]
  }

  # High Cost EC2 Instance Denials
  statement {
    sid    = "DenyHighCostEC2Instances"
    effect = "Deny"
    actions = ["ec2:RunInstances"]
    resources = ["arn:${local.partition}:ec2:*:*:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:InstanceType"
      values = [
        "p4d.24xlarge",
        "p4de.24xlarge",
        "p5.48xlarge",
        "x2gd.16xlarge",
        "x2gd.metal",
        "x2iedn.32xlarge",
        "x2iedn.metal",
        "u-6tb1.56xlarge",
        "u-6tb1.112xlarge",
        "u-9tb1.112xlarge",
        "u-12tb1.112xlarge",
        "u-18tb1.metal",
        "u-24tb1.metal"
      ]
    }
  }

  # Direct Connect and VPN Denials
  statement {
    sid    = "DenyDirectConnectAndVPN"
    effect = "Deny"
    actions = [
      "directconnect:*",
      "ec2:CreateVpnConnection",
      "ec2:DeleteVpnConnection",
      "ec2:ModifyVpnConnection",
      "ec2:CreateCustomerGateway",
      "ec2:DeleteCustomerGateway"
    ]
    resources = ["*"]
  }

  # Route53 Denials
  statement {
    sid    = "DenyRoute53HostedZoneCreation"
    effect = "Deny"
    actions = [
      "route53:CreateHostedZone",
      "route53:DeleteHostedZone",
      "route53:CreateReusableDelegationSet",
      "route53:ChangeResourceRecordSets"
    ]
    resources = ["*"]
  }

  # WAF Denials
  statement {
    sid    = "DenyWAFModification"
    effect = "Deny"
    actions = [
      "waf:*",
      "wafv2:*",
      "waf-regional:*"
    ]
    resources = ["*"]
  }

  # Support Case Denials
  statement {
    sid    = "DenySupportCaseCreation"
    effect = "Deny"
    actions = [
      "support:CreateCase",
      "support:AddCommunicationToCase"
    ]
    resources = ["*"]
  }

  # Production Resource Access Denial
  statement {
    sid    = "DenyProductionResourceAccess"
    effect = "Deny"
    actions = ["*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["production", "prod"]
    }
  }

  # Regional Restrictions
  statement {
    sid    = "RestrictToApprovedRegions"
    effect = "Deny"
    actions = ["*"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }

    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${local.partition}:iam::*:role/aws-service-role/*"]
    }
  }

  # Backup Deletion Denials
  statement {
    sid    = "DenyBackupDeletion"
    effect = "Deny"
    actions = [
      "backup:DeleteBackupPlan",
      "backup:DeleteBackupVault",
      "backup:DeleteRecoveryPoint",
      "ec2:DeleteSnapshot",
      "rds:DeleteDBSnapshot",
      "rds:DeleteDBClusterSnapshot"
    ]
    resources = ["*"]
  }

  # Critical Secrets Access Denial
  statement {
    sid    = "DenySecretsManagerCriticalSecrets"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DeleteSecret"
    ]
    resources = [
      "arn:${local.partition}:secretsmanager:*:${local.account_id}:secret:production/*",
      "arn:${local.partition}:secretsmanager:*:${local.account_id}:secret:prod/*",
      "arn:${local.partition}:secretsmanager:*:${local.account_id}:secret:master/*",
      "arn:${local.partition}:secretsmanager:*:${local.account_id}:secret:admin/*"
    ]
  }

  # Critical Parameters Access Denial
  statement {
    sid    = "DenyParameterStoreCriticalParams"
    effect = "Deny"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:PutParameter",
      "ssm:DeleteParameter"
    ]
    resources = [
      "arn:${local.partition}:ssm:*:${local.account_id}:parameter/production/*",
      "arn:${local.partition}:ssm:*:${local.account_id}:parameter/prod/*",
      "arn:${local.partition}:ssm:*:${local.account_id}:parameter/master/*",
      "arn:${local.partition}:ssm:*:${local.account_id}:parameter/admin/*"
    ]
  }

  # MFA Requirement for Deletions
  statement {
    sid    = "RequireMFAForDeletion"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:DeleteBucketWebsite",
      "s3:DeleteObjectVersion"
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

################################################################################
# IAM Role
################################################################################

resource "aws_iam_role" "contractor" {
  count = var.create ? 1 : 0

  name        = var.use_name_prefix ? null : var.contractor_role_name
  name_prefix = var.use_name_prefix ? "${var.contractor_role_name}-" : null
  path        = var.path
  description = var.description

  assume_role_policy    = data.aws_iam_policy_document.assume_role[0].json
  max_session_duration  = var.max_session_duration
  permissions_boundary  = var.permissions_boundary
  force_detach_policies = true

  tags = merge(
    var.tags,
    {
      Name = var.contractor_role_name
      Type = "ContractorRole"
    }
  )
}

################################################################################
# IAM Policies
################################################################################

resource "aws_iam_policy" "operational" {
  count = var.create ? 1 : 0

  name        = "${var.contractor_role_name}-operational-policy"
  path        = var.path
  description = "Operational permissions for contractor EKS deployment"
  policy      = data.aws_iam_policy_document.operational[0].json

  tags = merge(
    var.tags,
    {
      Name       = "${var.contractor_role_name}-operational-policy"
      PolicyType = "Allow"
    }
  )
}

resource "aws_iam_policy" "security_baseline" {
  count = var.create ? 1 : 0

  name        = "${var.contractor_role_name}-security-baseline-policy"
  path        = var.path
  description = "Security baseline restrictions for contractor access"
  policy      = data.aws_iam_policy_document.security_baseline[0].json

  tags = merge(
    var.tags,
    {
      Name       = "${var.contractor_role_name}-security-baseline-policy"
      PolicyType = "Deny"
    }
  )
}

################################################################################
# IAM Policy Attachments
################################################################################

resource "aws_iam_role_policy_attachment" "operational" {
  count = var.create ? 1 : 0

  policy_arn = aws_iam_policy.operational[0].arn
  role       = aws_iam_role.contractor[0].name
}

resource "aws_iam_role_policy_attachment" "security_baseline" {
  count = var.create ? 1 : 0

  policy_arn = aws_iam_policy.security_baseline[0].arn
  role       = aws_iam_role.contractor[0].name
}

################################################################################
# Outputs
################################################################################

output "role_arn" {
  description = "ARN of the contractor IAM role"
  value       = try(aws_iam_role.contractor[0].arn, null)
}

output "role_name" {
  description = "Name of the contractor IAM role"
  value       = try(aws_iam_role.contractor[0].name, null)
}

output "role_id" {
  description = "Unique ID of the contractor IAM role"
  value       = try(aws_iam_role.contractor[0].unique_id, null)
}

output "operational_policy_arn" {
  description = "ARN of the operational policy"
  value       = try(aws_iam_policy.operational[0].arn, null)
}

output "security_baseline_policy_arn" {
  description = "ARN of the security baseline policy"
  value       = try(aws_iam_policy.security_baseline[0].arn, null)
}

output "assume_role_command" {
  description = "AWS CLI command to assume the contractor role"
  value = var.create ? format(
    "aws sts assume-role --role-arn %s --role-session-name %s$(date +%%Y%%m%%d-%%H%%M%%S) %s",
    aws_iam_role.contractor[0].arn,
    var.session_name_prefix,
    var.external_id != null ? "--external-id ${var.external_id}" : ""
  ) : null
}
