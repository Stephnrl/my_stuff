###############################################################################
# Job template selection
#
# Either pass `job_template_id` directly, or look it up by
# `job_template_name` + `job_template_organization`.
###############################################################################

variable "job_template_id" {
  description = "ID of the AAP job template to launch. Mutually exclusive with job_template_name."
  type        = number
  default     = null
}

variable "job_template_name" {
  description = "Name of the AAP job template. Used together with job_template_organization."
  type        = string
  default     = null
}

variable "job_template_organization" {
  description = "Organization name containing the job template. Required when using job_template_name."
  type        = string
  default     = null
}

###############################################################################
# Job inputs
###############################################################################

variable "inventory_id" {
  description = "Optional inventory ID. The job template must have inventory prompt-on-launch enabled to accept this."
  type        = number
  default     = null
}

variable "extra_vars" {
  description = "Non-sensitive extra variables passed to the job template. Encoded as JSON before being sent to AAP."
  type        = any
  default     = {}
}

variable "sensitive_extra_vars" {
  description = <<-EOT
    Sensitive extra variables passed to the job template. Merged with extra_vars at apply time.
    Marked sensitive so values are scrubbed from CLI output and plan diffs. NOTE: Terraform state
    still stores these in plaintext — prefer AAP credentials for true secrets and only use this
    for values that genuinely must come from Terraform.
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "wait_for_completion" {
  description = "Block `terraform apply` until the AAP job reaches a terminal state."
  type        = bool
  default     = true
}

variable "wait_for_completion_timeout_seconds" {
  description = "How long to wait for the job to finish before failing the apply."
  type        = number
  default     = 1800
}

###############################################################################
# Rerun controls
#
# Any change to the underlying `triggers` map causes Terraform to destroy the
# job resource from state and create a new one — i.e. launch the job again.
# These three knobs cover the common rerun strategies.
###############################################################################

variable "rerun_token" {
  description = <<-EOT
    Manual rerun knob. Change this string (timestamp, build ID, git SHA, version tag, etc.)
    on the next apply to force the job to launch again. Leave empty to disable.
  EOT
  type        = string
  default     = ""
}

variable "rerun_on_extra_vars_change" {
  description = "When true, a hash of extra_vars is mixed into triggers, so any change to extra_vars reruns the job."
  type        = bool
  default     = true
}

variable "extra_triggers" {
  description = "Additional trigger key/value pairs. Wire upstream resource attributes here (e.g. instance IDs) so changes upstream cause a rerun."
  type        = map(string)
  default     = {}
}
