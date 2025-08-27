# terraform-module-aws-eks-landing-zone/modules/team-iam-role/main.tf

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Generate GitHub repo subject conditions based on input
  github_subjects = flatten([
    # Allow all repos matching pattern
    [for repo in var.github_repositories : "repo:${var.github_org}/${repo}:*"],
    
    # Allow environment-specific deployments if environments are specified
    var.github_environments != null ? flatten([
      for repo in var.github_repositories : [
        for env in var.github_environments : 
        "repo:${var.github_org}/${repo}:environment:${env}"
      ]
    ]) : []
  ])
}

# IAM Role with dual trust (GitHub OIDC + Console)
resource "aws_iam_role" "team_role" {
  name                 = "${var.team_name}-eks-namespace-role"
  description          = "EKS namespace access role for ${var.team_name} team"
  max_session_duration = var.max_session_duration
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # GitHub OIDC trust relationship
      [{
        Sid    = "GitHubActionsOIDC"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_subjects
          }
        }
      }],
      # AWS Console access (conditional)
      var.enable_console_access ? [{
        Sid    = "ConsoleAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = merge(
          # MFA requirement (conditional)
          var.require_mfa ? {
            Bool = {
              "aws:MultiFactorAuthPresent" = "true"
            }
          } : {},
          # Principal tag requirements (conditional)
          length(var.required_principal_tags) > 0 ? {
            StringEquals = {
              for key, value in var.required_principal_tags : 
              "aws:PrincipalTag/${key}" => value
            }
          } : {}
        )
      }] : []
    )
  })
  
  tags = merge(
    var.tags,
    {
      Name           = "${var.team_name}-eks-namespace-role"
      Team           = var.team_name
      Purpose        = "eks-namespace-access"
      GitHubOrg      = var.github_org
      GitHubRepos    = join(",", var.github_repositories)
      ConsoleAccess  = var.enable_console_access ? "enabled" : "disabled"
      MFARequired    = var.require_mfa ? "yes" : "no"
    }
  )
}

# Core EKS access policy
resource "aws_iam_role_policy" "eks_access" {
  name = "eks-cluster-access"
  role = aws_iam_role.team_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSClusterAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      },
      {
        Sid    = "EKSAPIAccess"
        Effect = "Allow"
        Action = [
          "eks:AccessKubernetesApi"
        ]
        Resource = var.cluster_arn != null ? var.cluster_arn : 
                  "arn:aws:eks:${local.region}:${local.account_id}:cluster/*"
      }
    ]
  })
}

# ECR access policy (conditional)
resource "aws_iam_role_policy" "ecr_access" {
  count = var.enable_ecr_access ? 1 : 0
  
  name = "ecr-access"
  role = aws_iam_role.team_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRTokenAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRepositoryAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = [
          for repo in var.ecr_repositories : 
          "arn:aws:ecr:${local.region}:${local.account_id}:repository/${repo}"
        ]
      }
    ]
  })
}

# S3 access policy (conditional)
resource "aws_iam_role_policy" "s3_access" {
  count = length(var.s3_buckets) > 0 ? 1 : 0
  
  name = "s3-access"
  role = aws_iam_role.team_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          for bucket in var.s3_buckets : 
          "arn:aws:s3:::${bucket}"
        ]
      },
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          for bucket in var.s3_buckets : 
          "arn:aws:s3:::${bucket}/*"
        ]
      }
    ]
  })
}

# Custom IAM policies (optional)
resource "aws_iam_role_policy" "custom_policies" {
  for_each = var.custom_policies
  
  name   = each.key
  role   = aws_iam_role.team_role.id
  policy = each.value
}

# Attach managed policies (optional)
resource "aws_iam_role_policy_attachment" "managed_policies" {
  for_each = toset(var.managed_policy_arns)
  
  role       = aws_iam_role.team_role.name
  policy_arn = each.value
}

# CloudWatch Logs access for troubleshooting (conditional)
resource "aws_iam_role_policy" "cloudwatch_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name = "cloudwatch-logs-access"
  role = aws_iam_role.team_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/eks/${var.team_name}/*"
      }
    ]
  })
}
