terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.40"
      configuration_aliases = [aws]
    }
  }
}

# Org-scoped external access analyzer (free).
# type = "ORGANIZATION" requires the calling account to be the delegated
# administrator for IAM Access Analyzer (or the org management account).
resource "aws_accessanalyzer_analyzer" "external_access" {
  count = var.enable_external_access_analyzer ? 1 : 0

  analyzer_name = "${var.name_prefix}-external-access"
  type          = "ORGANIZATION"

  tags = var.tags
}

# Org-scoped unused access analyzer (billable per IAM role/user analyzed).
resource "aws_accessanalyzer_analyzer" "unused_access" {
  count = var.enable_unused_access_analyzer ? 1 : 0

  analyzer_name = "${var.name_prefix}-unused-access"
  type          = "ORGANIZATION_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = var.unused_access_age_days
    }
  }

  tags = var.tags
}



variable "name_prefix" {
  description = "Prefix for analyzer names. Final names will be '<prefix>-external-access' and '<prefix>-unused-access'."
  type        = string
  default     = "org"
}

variable "unused_access_age_days" {
  description = "Number of days since last use after which an IAM resource is considered unused."
  type        = number
  default     = 90

  validation {
    condition     = var.unused_access_age_days >= 1 && var.unused_access_age_days <= 365
    error_message = "unused_access_age_days must be between 1 and 365."
  }
}

variable "enable_external_access_analyzer" {
  description = "Whether to deploy the external access (free) analyzer."
  type        = bool
  default     = true
}

variable "enable_unused_access_analyzer" {
  description = "Whether to deploy the unused access (billable) analyzer."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all analyzers."
  type        = map(string)
  default     = {}
}




output "external_access_analyzer_arn" {
  description = "ARN of the external access analyzer (null if disabled)."
  value       = try(aws_accessanalyzer_analyzer.external_access[0].arn, null)
}

output "unused_access_analyzer_arn" {
  description = "ARN of the unused access analyzer (null if disabled)."
  value       = try(aws_accessanalyzer_analyzer.unused_access[0].arn, null)
}


