################################################################################
# S3 bucket for GuardDuty findings export
#
# CMMC controls addressed:
#  - AU.L2-3.3.1/3.3.2: retain audit records (findings) beyond 90 days
#  - AU.L2-3.3.8       : protect audit info at rest (SSE-KMS w/ CMK) and
#                        optionally via Object Lock (WORM)
#  - SC.L2-3.13.8      : TLS-only bucket policy
#  - SC.L2-3.13.16     : encryption at rest
################################################################################

locals {
  resolved_bucket_name = coalesce(
    var.findings_bucket_name,
    "${var.name_prefix}-findings-${local.account_id}-${local.region}",
  )
}

resource "aws_s3_bucket" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  bucket              = local.resolved_bucket_name
  force_destroy       = false
  object_lock_enabled = var.enable_object_lock

  tags = merge(local.common_tags, {
    Name = local.resolved_bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.findings[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  bucket = aws_s3_bucket.findings[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  bucket = aws_s3_bucket.findings[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  bucket = aws_s3_bucket.findings[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.findings[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  bucket = aws_s3_bucket.findings[0].id

  # Current-version transitions + (optional) expiration
  rule {
    id     = "findings-current-versions"
    status = "Enabled"

    filter {}

    transition {
      days          = var.findings_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.findings_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    dynamic "expiration" {
      for_each = var.findings_retention_days > 0 ? [1] : []
      content {
        days = var.findings_retention_days
      }
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Clean up prior (non-current) versions after 90 days to control storage cost
  rule {
    id     = "findings-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.findings]
}

resource "aws_s3_bucket_object_lock_configuration" "findings" {
  count = var.create_findings_bucket && var.enable_object_lock ? 1 : 0

  bucket = aws_s3_bucket.findings[0].id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }
}

################################################################################
# Bucket policy
################################################################################

data "aws_iam_policy_document" "findings_bucket" {
  count = var.create_findings_bucket ? 1 : 0

  # GuardDuty service writes findings.
  statement {
    sid    = "AllowGuardDutyPutObject"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.findings[0].arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AllowGuardDutyGetBucketLocation"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }
    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.findings[0].arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Force KMS-encrypted writes only.
  statement {
    sid     = "DenyUnencryptedPuts"
    effect  = "Deny"
    actions = ["s3:PutObject"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.findings[0].arn}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  # Force the *correct* KMS key.
  statement {
    sid     = "DenyWrongKmsKey"
    effect  = "Deny"
    actions = ["s3:PutObject"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.findings[0].arn}/*"]
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.findings[0].arn]
    }
  }

  # Enforce TLS (CMMC SC.L2-3.13.8).
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [
      aws_s3_bucket.findings[0].arn,
      "${aws_s3_bucket.findings[0].arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "findings" {
  count = var.create_findings_bucket ? 1 : 0

  bucket = aws_s3_bucket.findings[0].id
  policy = data.aws_iam_policy_document.findings_bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.findings]
}
