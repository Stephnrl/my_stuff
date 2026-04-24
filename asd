variable "aws_region" {
  description = "AWS GovCloud region"
  type        = string
  default     = "us-gov-west-1"

  validation {
    condition     = can(regex("^us-gov-(west|east)-1$", var.aws_region))
    error_message = "Region must be a GovCloud region (us-gov-west-1 or us-gov-east-1)."
  }
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)"
  type        = string
}

variable "aap_controller_hostname" {
  description = "Fully-qualified hostname of the AAP controller (no scheme, no trailing slash). Example: aap.yourcompany.gov"
  type        = string

  validation {
    condition     = !can(regex("^https?://", var.aap_controller_hostname))
    error_message = "Hostname must not include https:// — just the FQDN."
  }
}

variable "aap_oidc_path" {
  description = "Path portion of the AAP OIDC issuer URL. Default matches AAP 2.5 controller."
  type        = string
  default     = "/api/controller/v2/oidc/"
}

variable "job_template_roles" {
  description = <<-EOT
    Map of IAM roles to create, one per AAP job template (or group of templates) that needs
    AWS access. The 'sub_pattern' pins which AAP job templates may assume the role via the
    OIDC 'sub' claim. Use specific patterns — avoid wildcards broader than org+template.

    Example sub_pattern values:
      "organization:prod-ops:job_template:deploy-web"          # single template
      "organization:prod-ops:job_template:deploy-*"            # all deploy-* templates in prod-ops
  EOT
  type = map(object({
    sub_pattern         = string
    secret_arns         = list(string)
    max_session_hours   = optional(number, 1)
    additional_policies = optional(list(string), [])
  }))
}
