variable "role_name" {
  description = "IAM role name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider (the AAP controller)"
  type        = string
}

variable "oidc_issuer_key" {
  description = "Issuer key for condition matching (hostname + path, no scheme)"
  type        = string
}

variable "sub_pattern" {
  description = "Pattern matched against the OIDC 'sub' claim from AAP. Pins which job templates may assume this role."
  type        = string
}

variable "secret_arns" {
  description = "List of Secrets Manager secret ARNs this role may read"
  type        = list(string)
}

variable "max_session_hours" {
  description = "Max session duration in hours (1-12). Keep this as short as the longest job."
  type        = number
  default     = 1

  validation {
    condition     = var.max_session_hours >= 1 && var.max_session_hours <= 12
    error_message = "Session duration must be between 1 and 12 hours."
  }
}

variable "additional_policies" {
  description = "Additional IAM policy ARNs to attach (e.g., KMS decrypt for CMK-encrypted secrets)"
  type        = list(string)
  default     = []
}
