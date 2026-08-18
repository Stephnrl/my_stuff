variable "name_prefix" {
  description = "Short prefix for all resource names."
  type        = string
  default     = "secgate"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,16}$", var.name_prefix))
    error_message = "name_prefix must be 3-16 lowercase alphanumeric characters or hyphens."
  }
}

variable "environment_suffix" {
  description = "Environment discriminator, e.g. prod / nonprod."
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure Government region."
  type        = string
  default     = "usgovvirginia"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- Identity ---------------------------------------------------------------

variable "gate_principal_id" {
  description = "Object ID of the workload identity (SPN/UAMI) the gate runs as."
  type        = string
}

variable "auditor_principal_ids" {
  description = "Object IDs granted read-only access to POA&M artifacts."
  type        = list(string)
  default     = []
}

# --- Storage ----------------------------------------------------------------

variable "storage_replication" {
  description = "LRS is usually sufficient; GRS if your SSP requires geo-redundancy for audit artifacts."
  type        = string
  default     = "GRS"
}

variable "soft_delete_days" {
  type    = number
  default = 30
}

variable "enable_immutability" {
  description = "Time-based immutability on the POA&M container. Strongly recommended for audit."
  type        = bool
  default     = true
}

variable "immutability_days" {
  description = "Retention period. A LOCKED policy can only be extended, never shortened - start unlocked."
  type        = number
  default     = 365
}

variable "raw_scan_retention_days" {
  description = "Raw Trivy JSON is bulky and reproducible from the POA&M; expire it sooner."
  type        = number
  default     = 180
}

variable "enable_private_endpoint" {
  type    = bool
  default = true
}

variable "private_endpoint_subnet_id" {
  type    = string
  default = ""
}

variable "private_dns_zone_id" {
  description = "Resource ID of privatelink.blob.core.usgovcloudapi.net zone."
  type        = string
  default     = ""
}

variable "runner_subnet_ids" {
  description = "Subnets hosting the self-hosted runners."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  type    = list(string)
  default = []
}

# --- Monitoring -------------------------------------------------------------

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "log_total_retention_days" {
  description = "Interactive + archive retention. Audit programs often want 12 months or more."
  type        = number
  default     = 730
}

variable "dce_public_access" {
  description = "Set false and use a private link scope once runner networking is settled."
  type        = bool
  default     = true
}

variable "security_email_receivers" {
  description = "map of name => email address"
  type        = map(string)
  default     = {}
}

variable "security_webhook_url" {
  description = "Teams/Slack incoming webhook for the security channel."
  type        = string
  default     = ""
  sensitive   = true
}

# --- Alert tuning -----------------------------------------------------------

variable "max_db_age_hours" {
  description = "Alert when scans run against a DB older than this."
  type        = number
  default     = 48
}

variable "overdue_alert_threshold" {
  description = "Alert when a component has more than this many overdue POA&M items."
  type        = number
  default     = 0
}

variable "enable_coverage_alert" {
  description = "Requires ACR diagnostics shipping ContainerRegistryRepositoryEvents to this workspace."
  type        = bool
  default     = true
}

variable "acr_id" {
  description = "Resource ID of the existing ACR. Only used to attach diagnostic settings."
  type        = string
  default     = ""
}

variable "component_quiet_days" {
  description = "Days without a scan before a previously-active component is flagged."
  type        = number
  default     = 30
}

variable "component_quiet_lookback_days" {
  type    = number
  default = 90
}
