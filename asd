##############################################################
# Per-job-template IAM role assumable via AAP OIDC federation.
##############################################################

data "aws_partition" "current" {}

# Trust policy: only the AAP OIDC provider may assume this role,
# and only when the 'sub' claim matches the job template pattern,
# and only with the correct audience.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_key}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${var.oidc_issuer_key}:sub"
      values   = [var.sub_pattern]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_hours * 3600

  tags = {
    Name = var.role_name
  }
}

# Least-privilege: only GetSecretValue + DescribeSecret on named ARNs.
data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid    = "ReadNamedSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = var.secret_arns
  }
}

resource "aws_iam_policy" "secrets_read" {
  name   = "${var.role_name}-secrets-read"
  policy = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each   = toset(var.additional_policies)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}
