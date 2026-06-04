resource "aws_ecr_repository" "this" {
  name         = var.name
  force_delete = var.force_delete

  image_tag_mutability = var.enable_tag_immutability
    ? (
        length(var.mutable_tag_exclusion_filters) > 0
        ? "IMMUTABLE_WITH_EXCLUSION"
        : "IMMUTABLE"
      )
    : (
        length(var.immutable_tag_exclusion_filters) > 0
        ? "MUTABLE_WITH_EXCLUSION"
        : "MUTABLE"
      )

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = var.enable_tag_immutability
      ? var.mutable_tag_exclusion_filters
      : var.immutable_tag_exclusion_filters

    content {
      filter      = image_tag_mutability_exclusion_filter.value
      filter_type = "WILDCARD"
    }
  }

  tags = var.tags
}
