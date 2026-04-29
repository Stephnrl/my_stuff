################################################################################
# Customer-managed KMS key for findings export
#
# CMMC SC.L2-3.13.11 (cryptographic protection of CUI) and SC.L2-3.13.16
# (confidentiality of CUI at rest). AWS KMS uses FIPS 140-2/140-3 validated
# HSMs; in GovCloud and FIPS regions the FIPS endpoints are used by default.
################################################################################

resource "aws_kms_key" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  description             = "CMK for GuardDuty findings export (${var.name_prefix})"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true
  multi_region            = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-findings"
  })
}

resource "aws_kms_alias" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  name          = "alias/${var.name_prefix}-findings"
  target_key_id = aws_kms_key.findings[0].key_id
}

data "aws_iam_policy_document" "findings_kms" {
  count = var.create_findings_bucket ? 1 : 0

  # Root account administrative access (standard AWS pattern).
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow GuardDuty to encrypt findings written to S3.
  statement {
    sid    = "AllowGuardDutyUseOfKey"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Deny anything outside TLS 1.2+
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_kms_key_policy" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  key_id = aws_kms_key.findings[0].id
  policy = data.aws_iam_policy_document.findings_kms[0].json
}
