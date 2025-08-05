# IAM Foundation Terraform Module

## Module Structure
```
modules/iam-foundation/
├── main.tf
├── variables.tf
├── outputs.tf
├── policies/
│   ├── team-base-policy.json
│   ├── team-developer-policy.json
│   ├── team-readonly-policy.json
│   ├── service-policies/
│   │   ├── ecs-task-policy.json
│   │   ├── lambda-execution-policy.json
│   │   └── ec2-instance-policy.json
│   └── permission-boundaries/
│       └── team-boundary-policy.json
├── data.tf
└── README.md
```

## Core Components

### 1. Data Sources for Bootstrap Resources
```hcl
# Reference existing bootstrap OIDC provider
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Reference existing CI/CD role from bootstrap
data "aws_iam_role" "cicd_role" {
  name = var.cicd_role_name  # Pass this from bootstrap outputs
}
```

### 2. Team Base Roles with Multiple Access Levels
```hcl
# Team Admin Roles - Full control within team resources
resource "aws_iam_role" "team_admin_roles" {
  for_each = var.teams
  
  name = "${each.key}-admin-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = [
            data.aws_iam_role.cicd_role.arn,
            # Add specific admin user ARNs
          ]
        }
      }
    ]
  })
  
  permissions_boundary = aws_iam_policy.team_permission_boundary[each.key].arn
  
  tags = merge(var.common_tags, {
    Team = each.key
    Role = "Admin"
  })
}

# Team Developer Roles - Limited access for development
resource "aws_iam_role" "team_developer_roles" {
  for_each = var.teams
  
  name = "${each.key}-developer-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = [
            data.aws_iam_role.cicd_role.arn,
            aws_iam_role.team_admin_roles[each.key].arn
          ]
        }
      }
    ]
  })
  
  permissions_boundary = aws_iam_policy.team_permission_boundary[each.key].arn
  
  tags = merge(var.common_tags, {
    Team = each.key
    Role = "Developer"
  })
}

# Team ReadOnly Roles - Read-only access for monitoring/debugging
resource "aws_iam_role" "team_readonly_roles" {
  for_each = var.teams
  
  name = "${each.key}-readonly-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = [
            data.aws_iam_role.cicd_role.arn,
            aws_iam_role.team_admin_roles[each.key].arn,
            aws_iam_role.team_developer_roles[each.key].arn
          ]
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Team = each.key
    Role = "ReadOnly"
  })
}
```

### 3. Permission Boundaries (Critical for Security)
```hcl
# Team permission boundaries to prevent privilege escalation
resource "aws_iam_policy" "team_permission_boundary" {
  for_each = var.teams
  
  name        = "${each.key}-permission-boundary"
  description = "Permission boundary for ${each.key} team"
  
  policy = templatefile("${path.module}/policies/permission-boundaries/team-boundary-policy.json", {
    team_name   = each.key
    vpc_id      = each.value.vpc_id
    account_id  = data.aws_caller_identity.current.account_id
    team_prefix = each.value.resource_prefix
    region      = data.aws_region.current.name
  })
  
  tags = merge(var.common_tags, {
    Team = each.key
  })
}
```

### 4. Team-Specific Policies

```hcl
# Admin policies - Full team resource control
resource "aws_iam_role_policy" "team_admin_policy" {
  for_each = var.teams
  
  name = "${each.key}-admin-policy"
  role = aws_iam_role.team_admin_roles[each.key].id
  
  policy = templatefile("${path.module}/policies/team-base-policy.json", {
    team_name    = each.key
    vpc_id       = each.value.vpc_id
    account_id   = data.aws_caller_identity.current.account_id
    team_prefix  = each.value.resource_prefix
    region       = data.aws_region.current.name
  })
}

# Developer policies - Limited access
resource "aws_iam_role_policy" "team_developer_policy" {
  for_each = var.teams
  
  name = "${each.key}-developer-policy"
  role = aws_iam_role.team_developer_roles[each.key].id
  
  policy = templatefile("${path.module}/policies/team-developer-policy.json", {
    team_name    = each.key
    vpc_id       = each.value.vpc_id
    account_id   = data.aws_caller_identity.current.account_id
    team_prefix  = each.value.resource_prefix
    region       = data.aws_region.current.name
  })
}

# ReadOnly policies
resource "aws_iam_role_policy" "team_readonly_policy" {
  for_each = var.teams
  
  name = "${each.key}-readonly-policy"
  role = aws_iam_role.team_readonly_roles[each.key].id
  
  policy = templatefile("${path.module}/policies/team-readonly-policy.json", {
    team_name    = each.key
    vpc_id       = each.value.vpc_id
    account_id   = data.aws_caller_identity.current.account_id
    team_prefix  = each.value.resource_prefix
    region       = data.aws_region.current.name
  })
}
```

### 5. Service Roles for Common AWS Services
```hcl
# ECS Task Execution Roles
resource "aws_iam_role" "ecs_task_execution_roles" {
  for_each = { for k, v in var.teams : k => v if v.enable_ecs }
  
  name = "${each.key}-ecs-task-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Team = each.key
    Service = "ECS"
  })
}

# ECS Task Roles
resource "aws_iam_role" "ecs_task_roles" {
  for_each = { for k, v in var.teams : k => v if v.enable_ecs }
  
  name = "${each.key}-ecs-task-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Team = each.key
    Service = "ECS"
  })
}

# Lambda Execution Roles
resource "aws_iam_role" "lambda_execution_roles" {
  for_each = { for k, v in var.teams : k => v if v.enable_lambda }
  
  name = "${each.key}-lambda-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Team = each.key
    Service = "Lambda"
  })
}

# EC2 Instance Profiles
resource "aws_iam_role" "ec2_instance_roles" {
  for_each = { for k, v in var.teams : k => v if v.enable_ec2 }
  
  name = "${each.key}-ec2-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Team = each.key
    Service = "EC2"
  })
}

resource "aws_iam_instance_profile" "ec2_instance_profiles" {
  for_each = { for k, v in var.teams : k => v if v.enable_ec2 }
  
  name = "${each.key}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_roles[each.key].name
  
  tags = merge(var.common_tags, {
    Team = each.key
    Service = "EC2"
  })
}
```

### 6. Service Policy Attachments
```hcl
# ECS Task Execution managed policies
resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  for_each = { for k, v in var.teams : k => v if v.enable_ecs }
  
  role       = aws_iam_role.ecs_task_execution_roles[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task custom policies
resource "aws_iam_role_policy" "ecs_task_policy" {
  for_each = { for k, v in var.teams : k => v if v.enable_ecs }
  
  name = "${each.key}-ecs-task-policy"
  role = aws_iam_role.ecs_task_roles[each.key].id
  
  policy = templatefile("${path.module}/policies/service-policies/ecs-task-policy.json", {
    team_name   = each.key
    vpc_id      = each.value.vpc_id
    account_id  = data.aws_caller_identity.current.account_id
    team_prefix = each.value.resource_prefix
    region      = data.aws_region.current.name
  })
}

# Lambda execution managed policies
resource "aws_iam_role_policy_attachment" "lambda_execution_managed" {
  for_each = { for k, v in var.teams : k => v if v.enable_lambda }
  
  role       = aws_iam_role.lambda_execution_roles[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Lambda custom policies
resource "aws_iam_role_policy" "lambda_execution_policy" {
  for_each = { for k, v in var.teams : k => v if v.enable_lambda }
  
  name = "${each.key}-lambda-execution-policy"
  role = aws_iam_role.lambda_execution_roles[each.key].id
  
  policy = templatefile("${path.module}/policies/service-policies/lambda-execution-policy.json", {
    team_name   = each.key
    vpc_id      = each.value.vpc_id
    account_id  = data.aws_caller_identity.current.account_id
    team_prefix = each.value.resource_prefix
    region      = data.aws_region.current.name
  })
}

# EC2 instance policies
resource "aws_iam_role_policy" "ec2_instance_policy" {
  for_each = { for k, v in var.teams : k => v if v.enable_ec2 }
  
  name = "${each.key}-ec2-instance-policy"
  role = aws_iam_role.ec2_instance_roles[each.key].id
  
  policy = templatefile("${path.module}/policies/service-policies/ec2-instance-policy.json", {
    team_name   = each.key
    vpc_id      = each.value.vpc_id
    account_id  = data.aws_caller_identity.current.account_id
    team_prefix = each.value.resource_prefix
    region      = data.aws_region.current.name
  })
}
```

### 7. IAM Groups for Human Users (Optional)
```hcl
# IAM Groups for human users if not using SSO
resource "aws_iam_group" "team_admin_groups" {
  for_each = { for k, v in var.teams : k => v if v.create_human_user_groups }
  
  name = "${each.key}-admins"
  path = "/teams/${each.key}/"
}

resource "aws_iam_group" "team_developer_groups" {
  for_each = { for k, v in var.teams : k => v if v.create_human_user_groups }
  
  name = "${each.key}-developers"
  path = "/teams/${each.key}/"
}

# Group policies that allow assuming team roles
resource "aws_iam_group_policy" "team_admin_group_policy" {
  for_each = { for k, v in var.teams : k => v if v.create_human_user_groups }
  
  name  = "${each.key}-admin-group-policy"
  group = aws_iam_group.team_admin_groups[each.key].name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          aws_iam_role.team_admin_roles[each.key].arn,
          aws_iam_role.team_developer_roles[each.key].arn,
          aws_iam_role.team_readonly_roles[each.key].arn
        ]
      }
    ]
  })
}

resource "aws_iam_group_policy" "team_developer_group_policy" {
  for_each = { for k, v in var.teams : k => v if v.create_human_user_groups }
  
  name  = "${each.key}-developer-group-policy"
  group = aws_iam_group.team_developer_groups[each.key].name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          aws_iam_role.team_developer_roles[each.key].arn,
          aws_iam_role.team_readonly_roles[each.key].arn
        ]
      }
    ]
  })
}
```

## Variables Structure
```hcl
variable "teams" {
  description = "Map of team configurations"
  type = map(object({
    vpc_id                     = string
    resource_prefix           = string
    allowed_regions          = list(string)
    cost_center              = string
    enable_ecs               = bool
    enable_lambda            = bool
    enable_ec2               = bool
    enable_rds               = bool
    create_human_user_groups = bool
  }))
}

variable "cicd_role_name" {
  description = "Name of the CI/CD role created in bootstrap module"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
```

## Outputs Structure
```hcl
# Team role outputs
output "team_admin_role_arns" {
  description = "ARNs of team admin roles"
  value       = { for k, v in aws_iam_role.team_admin_roles : k => v.arn }
}

output "team_developer_role_arns" {
  description = "ARNs of team developer roles"
  value       = { for k, v in aws_iam_role.team_developer_roles : k => v.arn }
}

output "team_readonly_role_arns" {
  description = "ARNs of team readonly roles"
  value       = { for k, v in aws_iam_role.team_readonly_roles : k => v.arn }
}

# Service role outputs
output "ecs_task_execution_role_arns" {
  description = "ARNs of ECS task execution roles"
  value       = { for k, v in aws_iam_role.ecs_task_execution_roles : k => v.arn }
}

output "ecs_task_role_arns" {
  description = "ARNs of ECS task roles"
  value       = { for k, v in aws_iam_role.ecs_task_roles : k => v.arn }
}

output "lambda_execution_role_arns" {
  description = "ARNs of Lambda execution roles"
  value       = { for k, v in aws_iam_role.lambda_execution_roles : k => v.arn }
}

output "ec2_instance_profile_names" {
  description = "Names of EC2 instance profiles"
  value       = { for k, v in aws_iam_instance_profile.ec2_instance_profiles : k => v.name }
}

# Group outputs (if created)
output "team_admin_group_names" {
  description = "Names of team admin groups"
  value       = { for k, v in aws_iam_group.team_admin_groups : k => v.name }
}

output "team_developer_group_names" {
  description = "Names of team developer groups"
  value       = { for k, v in aws_iam_group.team_developer_groups : k => v.name }
}
```

## Sample Policy Templates

### Team Base Policy (policies/team-base-policy.json)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2VPCAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:vpc": "${vpc_id}"
        }
      }
    },
    {
      "Sid": "ECSFullAccess",
      "Effect": "Allow",
      "Action": [
        "ecs:*",
        "ecr:*"
      ],
      "Resource": [
        "arn:aws:ecs:${region}:${account_id}:cluster/${team_prefix}-*",
        "arn:aws:ecs:${region}:${account_id}:service/${team_prefix}-*",
        "arn:aws:ecs:${region}:${account_id}:task/${team_prefix}-*",
        "arn:aws:ecs:${region}:${account_id}:task-definition/${team_prefix}-*",
        "arn:aws:ecr:${region}:${account_id}:repository/${team_prefix}-*"
      ]
    },
    {
      "Sid": "LogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:*"
      ],
      "Resource": [
        "arn:aws:logs:${region}:${account_id}:log-group:/aws/ecs/${team_prefix}-*",
        "arn:aws:logs:${region}:${account_id}:log-group:/aws/lambda/${team_prefix}-*"
      ]
    },
    {
      "Sid": "CloudWatchAccess",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:*",
        "application-autoscaling:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestedRegion": "${region}"
        }
      }
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": [
        "arn:aws:iam::${account_id}:role/${team_name}-*"
      ]
    },
    {
      "Sid": "S3TeamBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::${team_prefix}-*",
        "arn:aws:s3:::${team_prefix}-*/*"
      ]
    },
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:*"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${region}:${account_id}:secret:${team_prefix}-*"
      ]
    },
    {
      "Sid": "ParameterStoreAccess",
      "Effect": "Allow",
      "Action": [
        "ssm:*"
      ],
      "Resource": [
        "arn:aws:ssm:${region}:${account_id}:parameter/${team_prefix}/*"
      ]
    }
  ]
}
```

### Permission Boundary Policy (policies/permission-boundaries/team-boundary-policy.json)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyOutsideRegion",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["${region}"]
        },
        "ForAllValues:StringNotEquals": {
          "aws:RequestedRegion": ["${region}"]
        }
      }
    },
    {
      "Sid": "DenyIAMChanges",
      "Effect": "Deny",
      "Action": [
        "iam:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotLike": {
          "aws:PrincipalArn": [
            "arn:aws:iam::${account_id}:role/${team_name}-*",
            "arn:aws:iam::${account_id}:role/*-cicd-*"
          ]
        }
      }
    },
    {
      "Sid": "DenyNetworkChanges",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowWithinTeamResources",
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestedRegion": "${region}"
        }
      }
    }
  ]
}
```

## Usage Example
```hcl
module "iam_foundation" {
  source = "./modules/iam-foundation"
  
  cicd_role_name = module.bootstrap.cicd_role_name
  
  teams = {
    data-science = {
      vpc_id                     = module.networking.vpc_ids["data-science"]
      resource_prefix           = "ds"
      allowed_regions          = ["us-east-1"]
      cost_center              = "research"
      enable_ecs               = true
      enable_lambda            = true
      enable_ec2               = false
      enable_rds               = true
      create_human_user_groups = true
    }
    web-dev = {
      vpc_id                     = module.networking.vpc_ids["web-dev"]
      resource_prefix           = "webdev"
      allowed_regions          = ["us-east-1"]
      cost_center              = "engineering"
      enable_ecs               = true
      enable_lambda            = false
      enable_ec2               = true
      enable_rds               = false
      create_human_user_groups = false
    }
  }
  
  common_tags = {
    Environment = "sandbox"
    Project     = "landing-zone"
    ManagedBy   = "terraform"
  }
}
```
