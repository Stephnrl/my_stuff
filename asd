1. Designate the delegated admin (you likely have this already):
hclresource "aws_securityhub_organization_admin_account" "this" {
  admin_account_id = var.security_account_id
}
2. Create the Organizations resource-based delegation policy (this is what's missing):
This is the piece that grants your security account permission to manage Security Hub policies via Organizations APIs. It uses aws_organizations_resource_policy, which is an org-wide singleton — only one can exist per organization.
hcldata "aws_organizations_organization" "this" {}

data "aws_caller_identity" "management" {}

resource "aws_organizations_resource_policy" "securityhub_delegation" {
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecurityServicesDelegatingDescribeOrganization"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action   = "organizations:DescribeOrganization"
        Resource = "*"
      },
      {
        Sid    = "SecurityServicesDelegatingListAPIs"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action = [
          "organizations:ListAccounts",
          "organizations:ListRoots",
          "organizations:ListOrganizationalUnitsForParent",
          "organizations:ListAccountsForParent",
          "organizations:ListDelegatedAdministrators",
          "organizations:ListAWSServiceAccessForOrganization",
        ]
        Resource = "*"
      },
      {
        Sid    = "SecurityServicesDelegatingDescribeAPIs"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action = [
          "organizations:DescribeOrganizationalUnit",
          "organizations:DescribeAccount",
        ]
        Resource = [
          "arn:aws:organizations::${data.aws_caller_identity.management.account_id}:ou/${data.aws_organizations_organization.this.id}/*",
          "arn:aws:organizations::${data.aws_caller_identity.management.account_id}:account/${data.aws_organizations_organization.this.id}/*",
        ]
      },
      {
        Sid    = "SecurityServicesDelegatingDescribePolicy"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action   = "organizations:DescribePolicy"
        Resource = "arn:aws:organizations::${data.aws_caller_identity.management.account_id}:policy/${data.aws_organizations_organization.this.id}/*"
      },
      {
        Sid    = "SecurityServicesDelegatingDescribeEffectivePolicy"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action   = "organizations:DescribeEffectivePolicy"
        Resource = [
          "arn:aws:organizations::${data.aws_caller_identity.management.account_id}:account/${data.aws_organizations_organization.this.id}/*",
        ]
      },
      {
        Sid    = "SecurityServicesDelegatingPolicyManagement"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action = [
          "organizations:CreatePolicy",
          "organizations:UpdatePolicy",
          "organizations:DeletePolicy",
          "organizations:AttachPolicy",
          "organizations:DetachPolicy",
          "organizations:EnablePolicyType",
          "organizations:DisablePolicyType",
        ]
        Resource = "*"
        Condition = {
          StringLikeIfExists = {
            "organizations:PolicyType" = [
              "SERVICE_CONTROL_POLICY",
            ]
          }
        }
      },
      {
        Sid    = "SecurityServicesDelegatingRegisterDeregister"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action = [
          "organizations:RegisterDelegatedAdministrator",
          "organizations:DeregisterDelegatedAdministrator",
        ]
        Resource = "arn:aws:organizations::${data.aws_caller_identity.management.account_id}:account/${data.aws_organizations_organization.this.id}/*"
      },
      {
        Sid    = "SecurityServicesDelegatingServiceAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action = [
          "organizations:EnableAWSServiceAccess",
          "organizations:DisableAWSServiceAccess",
        ]
        Resource = "*"
      },
    ]
  })
}
Two important things to be aware of:
aws_organizations_resource_policy is an organization-wide singleton. Only one can exist per organization. If other services need delegation policies, their statements must be combined into a single policy. GitHub So if you're already using this resource for something like AWS Backup or Inspector delegation, you'll need to merge the statements rather than creating a second one.
Also, the exact policy statements AWS expects can vary — AWS expects exactly 8 policy statements, including SecurityServicesDelegating* statements with resource ARNs scoped to the organization ID. GitHub If you want to be safe and not hand-craft these, you could apply the delegated admin resource via Terraform, then create the policy once through the console (the "Create policy" button auto-generates the correct statements), and then terraform import the aws_organizations_resource_policy into state to manage it going forward.
Once this policy is applied from the management account, that permission error on the security account will go away.
