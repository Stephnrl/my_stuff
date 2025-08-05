# Get OIDC provider ARN from SSM Parameter Store
data "aws_ssm_parameter" "oidc_provider_arn" {
  name = var.oidc_provider_arn_parameter
}

# Get permission boundary ARN from SSM if not provided directly
data "aws_ssm_parameter" "permission_boundary_arn" {
  count = var.permission_boundary_arn == null ? 1 : 0
  name  = "/landing-zone/permission-boundary-arn"
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Use provided permission boundary or fetch from SSM
  permission_boundary_arn = var.permission_boundary_arn != null ? var.permission_boundary_arn : (
    length(data.aws_ssm_parameter.permission_boundary_arn) > 0 ? data.aws_ssm_parameter.permission_boundary_arn[0].value : null
  )
  
  common_tags = merge(
    var.resource_tags,
    {
      Team        = var.team_name
      Module      = "iam-foundation"
      Environment = "landing-zone"
    }
  )

  # GitHub repository conditions for OIDC trust
  github_conditions = length(var.github_repos) > 0 ? [
    for repo in var.github_repos : "repo:${var.github_org}/${repo}:*"
  ] : ["repo:${var.github_org}/*"]
}

# Trust policy for GitHub OIDC
data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Federated"
      identifiers = [data.aws_ssm_parameter.oidc_provider_arn.value]
    }
    
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_conditions
    }
  }

  # Additional trusted entities (e.g., AWS services)
  dynamic "statement" {
    for_each = length(var.additional_trusted_entities) > 0 ? [1] : []
    content {
      effect = "Allow"
      
      principals {
        type        = "Service"
        identifiers = var.additional_trusted_entities
      }
      
      actions = ["sts:AssumeRole"]
    }
  }
}

# Team-specific IAM role
resource "aws_iam_role" "team_role" {
  name                 = "LandingZone-${var.team_name}-Role"
  assume_role_policy   = data.aws_iam_policy_document.github_oidc_trust.json
  max_session_duration = var.max_session_duration
  permissions_boundary = local.permission_boundary_arn
  
  tags = local.common_tags
}

# Security restrictions policy - Applied to all team types
data "aws_iam_policy_document" "security_restrictions" {
  # Deny VPC and networking infrastructure creation/modification
  statement {
    sid    = "DenyNetworkingInfrastructure"
    effect = "Deny"
    actions = [
      # VPC Management
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateDefaultVpc",
      
      # Internet and NAT Gateways
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      
      # Subnets (let platform team manage)
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      
      # Route Tables
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      
      # Network ACLs
      "ec2:CreateNetworkAcl",
      "ec2:DeleteNetworkAcl",
      "ec2:CreateNetworkAclEntry",
      "ec2:DeleteNetworkAclEntry",
      "ec2:ReplaceNetworkAclEntry",
      "ec2:ReplaceNetworkAclAssociation",
      
      # VPC Peering
      "ec2:CreateVpcPeeringConnection",
      "ec2:DeleteVpcPeeringConnection",
      "ec2:AcceptVpcPeeringConnection",
      "ec2:RejectVpcPeeringConnection",
      
      # Transit Gateway
      "ec2:CreateTransitGateway",
      "ec2:DeleteTransitGateway",
      "ec2:ModifyTransitGateway",
      "ec2:CreateTransitGatewayVpcAttachment",
      "ec2:DeleteTransitGatewayVpcAttachment",
      "ec2:CreateTransitGatewayRouteTable",
      "ec2:DeleteTransitGatewayRouteTable",
      
      # DHCP Options
      "ec2:CreateDhcpOptions",
      "ec2:DeleteDhcpOptions",
      "ec2:AssociateDhcpOptions",
      
      # VPN and Direct Connect
      "ec2:CreateVpnConnection",
      "ec2:DeleteVpnConnection",
      "ec2:CreateVpnGateway",
      "ec2:DeleteVpnGateway",
      "directconnect:*"
    ]
    resources = ["*"]
  }

  # Deny IAM role/policy/user creation and modification
  statement {
    sid    = "DenyIAMManagement"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:CreateGroup",
      "iam:DeleteGroup",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:AttachUserPolicy",
      "iam:DetachUserPolicy",
      "iam:AttachGroupPolicy",
      "iam:DetachGroupPolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutUserPolicy",
      "iam:DeleteUserPolicy",
      "iam:PutGroupPolicy",
      "iam:DeleteGroupPolicy",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      
      # OIDC Provider management
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      
      # SAML Provider management  
      "iam:CreateSAMLProvider",
      "iam:UpdateSAMLProvider",
      "iam:DeleteSAMLProvider"
    ]
    resources = ["*"]
  }

  # Deny organization and account management
  statement {
    sid    = "DenyOrganizationManagement"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
      "billing:*",
      "budgets:*",
      "ce:*",
      "cur:*"
    ]
    resources = ["*"]
  }

  # Deny cross-account resource sharing
  statement {
    sid    = "DenyCrossAccountSharing"
    effect = "Deny"
    actions = [
      "ram:*",
      "resource-groups:*"
    ]
    resources = ["*"]
  }

  # Deny security service bypass attempts
  statement {
    sid    = "DenySecurityBypass"
    effect = "Deny"
    actions = [
      # CloudTrail
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      
      # Config
      "config:DeleteConfigRule",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "config:StopConfigurationRecorder",
      
      # GuardDuty
      "guardduty:DeleteDetector",
      "guardduty:UpdateDetector",
      
      # Security Hub
      "securityhub:DisableSecurityHub",
      "securityhub:DeleteMembers",
      
      # Systems Manager Session Manager
      "ssm:UpdateDocumentDefaultVersion",
      "ssm:ModifyDocumentPermission"
    ]
    resources = ["*"]
  }

  # Require encryption for storage services
  statement {
    sid    = "RequireEncryption"
    effect = "Deny"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = ["*"]
    
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["AES256", "aws:kms"]
    }
  }

  # Deny unencrypted EBS volumes
  statement {
    sid    = "RequireEBSEncryption"
    effect = "Deny"
    actions = [
      "ec2:CreateVolume",
      "ec2:RunInstances"
    ]
    resources = [
      "arn:aws:ec2:*:*:volume/*",
      "arn:aws:ec2:*:*:instance/*"
    ]
    
    condition {
      test     = "Bool"
      variable = "ec2:Encrypted"
      values   = ["false"]
    }
  }
}

# Developer policy template
data "aws_iam_policy_document" "developer_policy" {
  count = var.team_policy_type == "developer" ? 1 : 0

  # Include security restrictions
  source_policy_documents = [data.aws_iam_policy_document.security_restrictions.json]

  # EC2 permissions scoped to team VPC
  statement {
    sid    = "EC2Management"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:RebootInstances",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeImages",
      "ec2:DescribeSnapshots",
      "ec2:DescribeVolumes",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeKeyPairs",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:ModifySecurityGroupRules",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume"
    ]
    resources = ["*"]
    
    dynamic "condition" {
      for_each = var.vpc_id != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "ec2:vpc"
        values   = [var.vpc_id]
      }
    }
  }

  # Restrict security group rules to reasonable ports
  statement {
    sid    = "RestrictSecurityGroupPorts"
    effect = "Deny"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress"
    ]
    resources = ["*"]
    
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "ec2:FromPort"
      values   = ["22", "3389"]  # SSH and RDP from anywhere
    }
    
    condition {
      test     = "StringEquals"
      variable = "ec2:SourceIp"
      values   = ["0.0.0.0/0"]
    }
  }

  # S3 permissions for team-specific bucket
  statement {
    sid    = "S3TeamBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:CreateBucket"
    ]
    resources = [
      "arn:aws:s3:::landing-zone-${var.team_name}",
      "arn:aws:s3:::landing-zone-${var.team_name}/*"
    ]
  }

  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/team/${var.team_name}*"
    ]
  }

  # ECS/Fargate permissions
  statement {
    sid    = "ECSManagement"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:DescribeClusters",
      "ecs:CreateService",
      "ecs:DeleteService",
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:RunTask",
      "ecs:StopTask"
    ]
    resources = ["*"]
    
    condition {
      test     = "StringLike"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # Lambda permissions with resource restrictions
  statement {
    sid    = "LambdaManagement"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:InvokeFunction",
      "lambda:GetFunction",
      "lambda:ListFunctions"
    ]
    resources = [
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${var.team_name}-*"
    ]
  }

  # Restrict instance types to cost-effective options
  statement {
    sid       = "RestrictInstanceTypes"
    effect    = var.enable_cost_controls ? "Deny" : "Allow"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]
    
    dynamic "condition" {
      for_each = var.enable_cost_controls ? [1] : []
      content {
        test     = "ForAnyValue:StringNotLike"
        variable = "ec2:InstanceType"
        values   = var.allowed_instance_types
      }
    }
  }

  # Restrict regions if specified
  dynamic "statement" {
    for_each = length(var.allowed_regions) > 0 ? [1] : []
    content {
      sid    = "RestrictRegions"
      effect = "Deny"
      actions = ["*"]
      resources = ["*"]
      
      condition {
        test     = "StringNotEquals"
        variable = "aws:RequestedRegion"
        values   = var.allowed_regions
      }
      
      # Allow global services
      condition {
        test     = "StringNotEquals"
        variable = "aws:Service"
        values   = [
          "iam",
          "cloudfront",
          "route53",
          "waf",
          "support",
          "trustedadvisor"
        ]
      }
    }
  }
}

# Data Scientist policy template
data "aws_iam_policy_document" "data_scientist_policy" {
  count = var.team_policy_type == "data-scientist" ? 1 : 0

  # Include security restrictions
  source_policy_documents = [
    data.aws_iam_policy_document.security_restrictions.json,
    data.aws_iam_policy_document.developer_policy[0].json
  ]

  # SageMaker permissions
  statement {
    sid    = "SageMakerManagement"
    effect = "Allow"
    actions = [
      "sagemaker:CreateNotebookInstance",
      "sagemaker:DeleteNotebookInstance",
      "sagemaker:DescribeNotebookInstance",
      "sagemaker:StartNotebookInstance",
      "sagemaker:StopNotebookInstance",
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:CreateModel",
      "sagemaker:DeleteModel",
      "sagemaker:DescribeModel",
      "sagemaker:CreateEndpoint",
      "sagemaker:DeleteEndpoint",
      "sagemaker:DescribeEndpoint"
    ]
    resources = ["*"]
    
    condition {
      test     = "StringLike"
      variable = "sagemaker:ResourceTag/Team"
      values   = [var.team_name]
    }
  }

  # Additional S3 permissions for ML data
  statement {
    sid    = "S3MLData"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::ml-data-${var.team_name}",
      "arn:aws:s3:::ml-data-${var.team_name}/*"
    ]
  }

  # Bedrock permissions for AI services (if needed)
  statement {
    sid    = "BedrockAccess"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:ListFoundationModels"
    ]
    resources = ["*"]
  }
}

# Admin policy template (very restricted)
data "aws_iam_policy_document" "admin_policy" {
  count = var.team_policy_type == "admin" ? 1 : 0

  # Include security restrictions even for admins if enabled
  source_policy_documents = var.deny_admin_access ? [data.aws_iam_policy_document.security_restrictions.json] : []

  # Admin access with VPC restriction
  statement {
    sid       = "AdminAccessRestricted"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
    
    # Restrict to specific VPC if provided
    dynamic "condition" {
      for_each = var.vpc_id != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "ec2:vpc"
        values   = [var.vpc_id]
      }
    }
  }
}

# Create team-specific policy
resource "aws_iam_policy" "team_policy" {
  count = var.team_policy_type != "custom" ? 1 : 0
  
  name        = "LandingZone-${var.team_name}-Policy"
  description = "Policy for ${var.team_name} team in landing zone"
  
  policy = var.team_policy_type == "developer" ? data.aws_iam_policy_document.developer_policy[0].json : (
    var.team_policy_type == "data-scientist" ? data.aws_iam_policy_document.data_scientist_policy[0].json : 
    data.aws_iam_policy_document.admin_policy[0].json
  )
  
  tags = local.common_tags
}

# Attach team policy to role
resource "aws_iam_role_policy_attachment" "team_policy_attachment" {
  count = var.team_policy_type != "custom" ? 1 : 0
  
  role       = aws_iam_role.team_role.name
  policy_arn = aws_iam_policy.team_policy[0].arn
}

# Attach custom policies if specified
resource "aws_iam_role_policy_attachment" "custom_policies" {
  count = var.team_policy_type == "custom" ? length(var.custom_policies) : 0
  
  role       = aws_iam_role.team_role.name
  policy_arn = var.custom_policies[count.index]
}

# Always attach ReadOnlyAccess for basic AWS resource visibility
resource "aws_iam_role_policy_attachment" "readonly_access" {
  role       = aws_iam_role.team_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
